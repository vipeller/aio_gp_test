#!/usr/bin/env bash
set -euo pipefail

# --- Parameters or environment ---
SUBSCRIPTION_ID="${2:-${SUBSCRIPTION_ID:-}}"
RESOURCE_GROUP="${1:-${RESOURCE_GROUP:-}}"

if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" ]]; then
  echo "Usage: $0 <subscription-id> <resource-group>"
  echo "Or set SUBSCRIPTION_ID and RESOURCE_GROUP environment variables."
  exit 1
fi

API="2025-07-01-preview"

echo "[INFO] Discovering Azure IoT Operations resources in RG=$RESOURCE_GROUP, SUB=$SUBSCRIPTION_ID..."

# --- AIO instance(s) ---
echo "[INFO] Looking up IoT Operations instances..."
AIO_LIST="$(az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.IoTOperations/instances?api-version=$API" \
  -o json --only-show-errors)"

AIO_COUNT="$(jq -r '.value | length' <<<"$AIO_LIST")"
if [[ "$AIO_COUNT" -eq 0 ]]; then
  echo "ERROR: No Microsoft.IoTOperations/instances found in RG $RESOURCE_GROUP" >&2
  exit 1
fi

INSTANCE_NAME="$(
  jq -r '
    .value
    | sort_by(.systemData.createdAt // "1970-01-01T00:00:00Z")
    | last
    | .name' <<<"$AIO_LIST"
)"
LOCATION="$(jq -r ".value[] | select(.name==\"$INSTANCE_NAME\") | .location" <<<"$AIO_LIST")"
echo "[OK] Found AIO instance: $INSTANCE_NAME (location=$LOCATION)"

# --- ADR namespace(s) ---
echo "[INFO] Looking up Device Registry namespaces..."
ADR_LIST="$(az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DeviceRegistry/namespaces?api-version=$API" \
  -o json --only-show-errors)"
ADR_COUNT="$(jq -r '.value | length' <<<"$ADR_LIST")"
[[ "$ADR_COUNT" -eq 0 ]] && { echo "ERROR: No ADR namespaces found in RG $RESOURCE_GROUP" >&2; exit 1; }
ADR_NAMESPACE_NAME="$(jq -r '.value | sort_by(.systemData.createdAt // "1970-01-01T00:00:00Z") | last | .name' <<<"$ADR_LIST")"
echo "[OK] Found ADR namespace: $ADR_NAMESPACE_NAME"

# --- Schema Registry(ies) ---
echo "[INFO] Looking up Schema Registries..."
SR_LIST="$(az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DeviceRegistry/schemaRegistries?api-version=$API" \
  -o json --only-show-errors)"
SR_COUNT="$(jq -r '.value | length' <<<"$SR_LIST")"
[[ "$SR_COUNT" -eq 0 ]] && { echo "ERROR: No schema registries found in RG $RESOURCE_GROUP" >&2; exit 1; }
SCHEMA_REGISTRY_NAME="$(jq -r '.value | sort_by(.systemData.createdAt // "1970-01-01T00:00:00Z") | last | .name' <<<"$SR_LIST")"
echo "[OK] Found Schema Registry: $SCHEMA_REGISTRY_NAME"

# --- Print env exports ---
TEMPLATE_NAME="${TEMPLATE_NAME:-opc-publisher-gp}"
CONNECTOR_NAME="${CONNECTOR_NAME:-opc-publisher-gp}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-gp}"
NAMESPACE="${NAMESPACE:-azure-iot-operations}"

echo
echo "Environment setup complete. Use these exports (or adjust accordingly):"
cat <<EOF
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export RESOURCE_GROUP="$RESOURCE_GROUP"
export INSTANCE_NAME="$INSTANCE_NAME"
export SCHEMA_REGISTRY_NAME="$SCHEMA_REGISTRY_NAME"
export TEMPLATE_NAME="$TEMPLATE_NAME"
export CONNECTOR_NAME="$CONNECTOR_NAME"
export LOCATION="$LOCATION"

export DEPLOYMENT_NAME="$DEPLOYMENT_NAME"
export ADR_NAMESPACE_NAME="$ADR_NAMESPACE_NAME"
export NAMESPACE="$NAMESPACE"
EOF
