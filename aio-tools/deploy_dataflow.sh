#!/usr/bin/env bash
set -euo pipefail

# ========= Inputs =========
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"
: "${LOCATION:?set LOCATION}"

CREDS_FILE="${CREDS_FILE:-./creds/dtb_hub_cred.json}"  # produced by the eventstream script

DATAFLOW_NAME="${DATAFLOW_NAME:-fullmachine-to-es}"
PROFILE_NAME="${PROFILE_NAME:-default}"

# source / destination endpoint names
MQTT_ENDPOINT_NAME="${MQTT_ENDPOINT_NAME:-default}"          # built-in MQTT endpoint to the local broker
KAFKA_ENDPOINT_NAME="${KAFKA_ENDPOINT_NAME:-fabric-es-kafka}"# we’ll have created this earlier

# MQTT source topic (override if needed)
SOURCE_TOPIC="${SOURCE_TOPIC:-fullmachine/telemetry}"

# ========= Logging helpers =========
log(){ printf '[INFO] %s\n' "$*" >&2; }
ok(){  printf '[ OK ]   %s\n' "$*" >&2; }
err(){ printf '[ERR]  %s\n' "$*" >&2; }

command -v az >/dev/null || { err "Azure CLI not found"; exit 1; }
command -v jq >/dev/null || { err "jq not found"; exit 1; }

# ========= Parse Fabric creds to get EH namespace & event hub name =========
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

# ========= Ensure the Kafka endpoint exists (SASL/PLAIN with $ConnectionString) =========
# (Safe to re-apply; if you already created it earlier, this will just update/ensure)
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

# ========= Build the Dataflow (mode + operations: Source → Destination) =========
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
echo "Destination:endpoint '$KAFKA_ENDPOINT_NAME' topic '$DEST_TOPIC' (EH-compatible Kafka)"
