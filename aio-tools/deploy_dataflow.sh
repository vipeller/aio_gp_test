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
SOURCE_TOPIC="${SOURCE_TOPIC:-fullmachine/telemetry}"

# -------- Logging helpers --------
log(){ printf '[INFO] %s\n' "$*" >&2; }
ok(){  printf '[OK]   %s\n' "$*" >&2; }
warn(){printf '[WARN] %s\n' "$*" >&2; }
err(){ printf '[ERR]  %s\n' "$*" >&2; }

command -v az >/dev/null || { err "Azure CLI not found"; exit 1; }
command -v jq >/dev/null || { err "jq not found"; exit 1; }
command -v kubectl >/dev/null || { err "kubectl not found"; exit 1; }

# -------- Ensure az logged in & subscription targeted --------
az account show >/dev/null 2>&1 || az login --only-show-errors >/dev/null
az account set --subscription "$SUBSCRIPTION_ID"

# -------- Ensure 'azure-iot-ops' CLI extension is installed --------
if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  log "Installing Azure CLI extension 'azure-iot-ops'…"
  az extension add -n azure-iot-ops -y --only-show-errors >/dev/null
  ok "'azure-iot-ops' extension installed."
else
  ok "'azure-iot-ops' extension present."
fi

# -------- Resolve extendedLocation & host cluster info --------
log "Getting AIO instance and its Custom Location…"
AIO_JSON="$(az iot ops show -g "$RESOURCE_GROUP" -n "$INSTANCE_NAME" -o json --only-show-errors)"
EXT_NAME="$(jq -r '.extendedLocation.name // empty' <<<"$AIO_JSON")"
[[ -z "$EXT_NAME" || "$EXT_NAME" == "null" ]] && { err "Instance has no extendedLocation.name"; exit 1; }

# The Custom Location resource lives in the same RG as the AIO instance
CL_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ExtendedLocation/customLocations/${EXT_NAME}"
CL_JSON="$(az rest --method get --url "https://management.azure.com${CL_ID}?api-version=2021-08-31" --only-show-errors)"
HOST_ID="$(jq -r '.properties.hostResourceId // empty' <<<"$CL_JSON")"
if [[ -z "$HOST_ID" ]]; then
  warn "Could not determine hostResourceId from Custom Location. Kubernetes connectivity check may be limited."
fi

# -------- Ensure kubectl can talk to the target cluster --------
need_k8s=0
if ! kubectl get ns azure-iot-operations >/dev/null 2>&1; then
  need_k8s=1
fi

if [[ "$need_k8s" -eq 1 ]]; then
  log "kubectl is not connected to the target cluster. Attempting to connect…"

  if [[ -n "$HOST_ID" && "$HOST_ID" == */managedClusters/* ]]; then
    # AKS cluster
    AKS_RG="$(sed -E 's#.*/resourceGroups/([^/]+).*#\1#' <<<"$HOST_ID")"
    AKS_NAME="$(sed -E 's#.*/managedClusters/([^/]+).*#\1#' <<<"$HOST_ID")"
    if [[ -n "$AKS_RG" && -n "$AKS_NAME" ]]; then
      log "Detected AKS host: $AKS_NAME (RG: $AKS_RG). Fetching credentials…"
      az aks get-credentials -g "$AKS_RG" -n "$AKS_NAME" --overwrite-existing --only-show-errors >/dev/null
      ok "kubectl configured for AKS."
    else
      err "Could not parse AKS name/RG from hostResourceId: $HOST_ID"
      exit 1
    fi
  elif [[ -n "$HOST_ID" && "$HOST_ID" == */connectedClusters/* ]]; then
    # Arc-enabled Kubernetes (on-prem/edge).
    ARC_RG="$(sed -E 's#.*/resourceGroups/([^/]+).*#\1#' <<<"$HOST_ID")"
    ARC_NAME="$(sed -E 's#.*/connectedClusters/([^/]+).*#\1#' <<<"$HOST_ID")"
    warn "Detected Arc-enabled Kubernetes host: $ARC_NAME (RG: $ARC_RG)."
    warn "This script cannot auto-launch the interactive 'az connectedk8s proxy'."
    cat >&2 <<EOT
Next steps:
  1) In a separate terminal, run:
     az connectedk8s proxy -g "$ARC_RG" -n "$ARC_NAME" --context "$ARC_NAME"

  2) Ensure 'kubectl get ns' succeeds against that context, then re-run this script.

EOT
    exit 1
  else
    err "Unknown host cluster type (hostResourceId: $HOST_ID). Configure kubectl to the target cluster and retry."
    exit 1
  fi

  # Re-check after attempting to connect
  if ! kubectl get ns azure-iot-operations >/dev/null 2>&1; then
    err "kubectl still cannot reach namespace 'azure-iot-operations'. Fix connectivity and retry."
    exit 1
  fi
else
  ok "kubectl connectivity OK (namespace 'azure-iot-operations' reachable)."
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
  --only-show-errors >/dev/null
ok "Kafka endpoint ensured."

# -------- Build the Dataflow (mode + operations: Source → Destination) --------
DF_CFG="$tmpdir/dataflow.json"
cat >"$DF_CFG" <<JSON
{
  "profileName": "$PROFILE_NAME",
  "dataflowName": "$DATAFLOW_NAME",
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
  --resource-group "$RESOURCE_GROUP" \
  --instance "$INSTANCE_NAME" \
  --config-file "$DF_CFG" \
  --only-show-errors >/dev/null

ok "Dataflow applied."
echo "Profile:    $PROFILE_NAME"
echo "Dataflow:   $DATAFLOW_NAME"
echo "Source:     endpoint '$MQTT_ENDPOINT_NAME' topic '$SOURCE_TOPIC'"
echo "Destination:endpoint '$KAFKA_ENDPOINT_NAME' topic '$DEST_TOPIC' (Event Hubs–Kafka)"
