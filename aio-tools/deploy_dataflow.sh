#!/usr/bin/env bash
set -euo pipefail

# -------- Inputs --------
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"
: "${LOCATION:?set LOCATION}"

CREDS_FILE="${CREDS_FILE:-./creds/dtb_hub_cred.json}"  # produced by the eventstream script

DATAFLOW_NAME="${DATAFLOW_NAME:-fullmachine-to-es}"
PROFILE_NAME="${PROFILE_NAME:-default}"

# source / destination endpoint names
MQTT_ENDPOINT_NAME="${MQTT_ENDPOINT_NAME:-default}"            # built-in MQTT endpoint to local broker
KAFKA_ENDPOINT_NAME="${KAFKA_ENDPOINT_NAME:-fabric-es-kafka}"  # we’ll ensure/create this

# MQTT source topic (override if needed)
SOURCE_TOPIC="${SOURCE_TOPIC:-azure-iot-operations/umati-000000/messages/FullMachineTool}"

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

command -v az >/dev/null || { err "Azure CLI not found"; exit 1; }
command -v jq >/dev/null || { err "jq not found"; exit 1; }
command -v kubectl >/dev/null || { err "kubectl not found"; exit 1; }

# -------- Ensure az logged in & subscription targeted --------
az account show >/dev/null 2>&1 || az login --only-show-errors >/dev/null
az account set --subscription "$SUBSCRIPTION_ID"

# -------- Ensure 'azure-iot-ops' CLI extension is installed --------
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  log "Installing Azure IoT Operations CLI extension…"
  az extension add -n azure-iot-ops -y --only-show-errors >/dev/null
else  
  az extension update -n azure-iot-ops --only-show-errors >/dev/null || true
fi
ok "IoT Ops CLI extension ready"

# -------- Optional: try to auto-connect to AKS --------
# If there's exactly one AKS cluster in the RG, attempt to get credentials.
# Otherwise, tell the user how to connect.
log "Checking for AKS clusters in resource group '$RESOURCE_GROUP'…"
AKS_LIST="$(az aks list -g "$RESOURCE_GROUP" -o json 2>/dev/null || echo '[]')"
AKS_COUNT="$(jq 'length' <<<"$AKS_LIST")"
if [[ "$AKS_COUNT" -eq 1 ]]; then
  AKS_NAME="$(jq -r '.[0].name' <<<"$AKS_LIST")"
  log "Found single AKS cluster: $AKS_NAME — fetching credentials…"
  # --overwrite-existing avoids prompt if kubeconfig already has an entry
  if az aks get-credentials -g "$RESOURCE_GROUP" -n "$AKS_NAME" --overwrite-existing >/dev/null 2>&1; then
    ok "kubectl context configured for AKS cluster '$AKS_NAME'"
  else
    warn "Failed to get AKS credentials automatically. Please configure kubectl context manually."
  fi
elif [[ "$AKS_COUNT" -gt 1 ]]; then
  warn "Multiple AKS clusters found in RG '$RESOURCE_GROUP'."
  warn "Run: az aks get-credentials -g \"$RESOURCE_GROUP\" -n <cluster-name>"
else
  warn "No AKS clusters found in RG '$RESOURCE_GROUP'. If you're using Arc-enabled K8s, ensure your kubectl context is already set."
  warn "For Arc clusters, you can use: az connectedk8s proxy -g \"$RESOURCE_GROUP\" -n <arc-cluster>  (then point kubectl to the proxy kubeconfig)"
fi

# -------- Parse Fabric creds to get EH namespace & event hub name --------
[[ -s "$CREDS_FILE" ]] || { err "Missing creds file: $CREDS_FILE"; exit 1; }

FQDN="$(jq -r '.fullyQualifiedNamespace // empty' "$CREDS_FILE")"
EH_NAME="$(jq -r '.eventHubName // empty' "$CREDS_FILE")"
CONN_STR="$(jq -r '.accessKeys.primaryConnectionString // empty' "$CREDS_FILE")"
if [[ -z "$FQDN" || -z "$EH_NAME" || -z "$CONN_STR" ]]; then
  err "Creds file is missing required fields (fullyQualifiedNamespace, eventHubName, accessKeys.primaryConnectionString)."
  exit 1
fi
DEST_TOPIC="$EH_NAME"

log "Using Event Hubs namespace: $FQDN ; event hub (Kafka topic): $DEST_TOPIC"

# -------- Ensure the Kafka endpoint exists (SASL/PLAIN with $ConnectionString) --------
tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
EP_CFG="$tmpdir/kafka-endpoint.json"
SECRET_NAME="${KAFKA_ENDPOINT_NAME}-sasl"

log "Ensuring Kubernetes secret '$SECRET_NAME' exists (username=\$ConnectionString)…"
kubectl -n azure-iot-operations delete secret "$SECRET_NAME" >/dev/null 2>&1 || true
kubectl -n azure-iot-operations create secret generic "$SECRET_NAME" \
  --from-literal=username='$ConnectionString' \
  --from-literal=password="$CONN_STR" >/dev/null
ok "Secret ensured."

BOOTSTRAP="${FQDN}:9093"
cat >"$EP_CFG" <<JSON
{
  "endpointType": "Kafka",
  "kafkaSettings": {
    "host": "$BOOTSTRAP",
    "authentication": {
      "method": "Sasl",
      "saslSettings": {
        "saslType": "Plain",
        "secretRef": "$SECRET_NAME"
      }
    },
    "copyMqttProperties": "Enabled",
    "tls": { "mode": "Enabled" }
  }
}
JSON

log "Applying Kafka endpoint '$KAFKA_ENDPOINT_NAME'…"
az iot ops dataflow endpoint apply \
  --resource-group "$RESOURCE_GROUP" \
  --instance "$INSTANCE_NAME" \
  --name "$KAFKA_ENDPOINT_NAME" \
  --config-file "$EP_CFG" \
  --only-show-errors
ok "Kafka endpoint ensured."

# -------- Build the Dataflow (mode + operations: Source → Destination) --------
DF_CFG="$tmpdir/dataflow.json"
cat >"$DF_CFG" <<JSON
{
  "mode": "Enabled",
  "operations": [
    {
      "operationType": "Source",
      "sourceSettings": {
        "endpointRef": "$MQTT_ENDPOINT_NAME",
        "assetRef": "",
        "serializationFormat": "Json",
        "schemaRef": "",
        "dataSources": [ "$SOURCE_TOPIC" ]
      }
    },
    {
      "operationType": "Destination",
      "destinationSettings": {
        "endpointRef": "$KAFKA_ENDPOINT_NAME",
        "dataDestination": "$DEST_TOPIC"
      }
    }
  ]
}
JSON

log "Applying dataflow '$DATAFLOW_NAME' (source mqtt:'$SOURCE_TOPIC' → kafka:'$DEST_TOPIC')…"
az iot ops dataflow apply \
  -g "$RESOURCE_GROUP" \
  --instance "$INSTANCE_NAME" \
  -n "$DATAFLOW_NAME" \
  -p "$PROFILE_NAME" \
  --config-file "$DF_CFG" \
  --only-show-errors

ok "Dataflow applied."
echo "Profile:    $PROFILE_NAME"
echo "Dataflow:   $DATAFLOW_NAME"
echo "Source:     endpoint '$MQTT_ENDPOINT_NAME' topic '$SOURCE_TOPIC'"
echo "Destination:endpoint '$KAFKA_ENDPOINT_NAME' topic '$DEST_TOPIC' (Event Hubs–Kafka)"
