#!/usr/bin/env bash
set -euo pipefail

# --- Parameters or environment ---
SUBSCRIPTION_ID="${1:-${SUBSCRIPTION_ID:-}}"
RESOURCE_GROUP="${2:-${RESOURCE_GROUP:-}}"

if [[ -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" ]]; then
  echo "Usage: $0 <subscription-id> <resource-group>" >&2
  echo "Or set SUBSCRIPTION_ID and RESOURCE_GROUP environment variables." >&2
  exit 1
fi

API="2025-10-01"

echo "[INFO] Discovering Azure IoT Operations resources in RG=$RESOURCE_GROUP, SUB=$SUBSCRIPTION_ID..." >&2

# --- AIO instance(s) ---
echo "[INFO] Looking up IoT Operations instances..." >&2
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
echo "[OK] Found AIO instance: $INSTANCE_NAME (location=$LOCATION)" >&2

# --- ADR namespace(s) ---
echo "[INFO] Looking up Device Registry namespaces..." >&2
ADR_LIST="$(az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DeviceRegistry/namespaces?api-version=$API" \
  -o json --only-show-errors)"
ADR_COUNT="$(jq -r '.value | length' <<<"$ADR_LIST")"
[[ "$ADR_COUNT" -eq 0 ]] && { echo "ERROR: No ADR namespaces found in RG $RESOURCE_GROUP" >&2; exit 1; }
ADR_NAMESPACE_NAME="$(jq -r '.value | sort_by(.systemData.createdAt // "1970-01-01T00:00:00Z") | last | .name' <<<"$ADR_LIST")"
echo "[OK] Found ADR namespace: $ADR_NAMESPACE_NAME" >&2

# --- Schema Registry(ies) ---
echo "[INFO] Looking up Schema Registries..." >&2
SR_LIST="$(az rest --method get \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DeviceRegistry/schemaRegistries?api-version=$API" \
  -o json --only-show-errors)"
SR_COUNT="$(jq -r '.value | length' <<<"$SR_LIST")"
[[ "$SR_COUNT" -eq 0 ]] && { echo "ERROR: No schema registries found in RG $RESOURCE_GROUP" >&2; exit 1; }
SCHEMA_REGISTRY_NAME="$(jq -r '.value | sort_by(.systemData.createdAt // "1970-01-01T00:00:00Z") | last | .name' <<<"$SR_LIST")"
echo "[OK] Found Schema Registry: $SCHEMA_REGISTRY_NAME" >&2

# --- Fabric 'My workspace' discovery ---
echo "[INFO] Getting Fabric access token…" >&2
TOK="$(az account get-access-token \
  --scope https://api.fabric.microsoft.com/.default \
  --query accessToken -o tsv 2>/dev/null || true)"
if [[ -z "$TOK" ]]; then
  echo "ERROR: Failed to obtain Fabric access token (check az login / tenant access)." >&2
  exit 1
fi

echo "[INFO] Querying Fabric workspaces (tenant-scoped)..." >&2
FABRIC_WS_JSON="$(curl -sSsf \
  -H "Authorization: Bearer $TOK" \
  -H "Content-Type: application/json" \
  "https://api.fabric.microsoft.com/v1/workspaces")"

# Prefer type == Personal; also fallback to displayName == 'My workspace' (case-insensitive)
FABRIC_WORKSPACE_ID="$(
  jq -r '
    .value
    | map(select(.type=="Personal" or ((.displayName // "") | ascii_downcase)=="my workspace"))
    | .[0].id // empty
  ' <<<"$FABRIC_WS_JSON"
)"
FABRIC_CAPACITY_ID="$(
  jq -r '
    .value
    | map(select(.type=="Personal" or ((.displayName // "") | ascii_downcase)=="my workspace"))
    | .[0].capacityId // empty
  ' <<<"$FABRIC_WS_JSON"
)"

if [[ -z "$FABRIC_WORKSPACE_ID" ]]; then
  echo "WARN: Could not find a Fabric 'My workspace' in this tenant for the current principal." >&2
else
  echo "[OK] Found Fabric 'My workspace': id=$FABRIC_WORKSPACE_ID capacityId=${FABRIC_CAPACITY_ID:-<none>}" >&2
fi

# --- Print env exports ---
TEMPLATE_NAME="${TEMPLATE_NAME:-opc-publisher-gp}"
CONNECTOR_NAME="${CONNECTOR_NAME:-opc-publisher-gp}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-gp}"
NAMESPACE="${NAMESPACE:-azure-iot-operations}"

echo >&2
echo "Environment setup complete. Use these exports (or adjust accordingly):" >&2
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

export FABRIC_WORKSPACE_ID="$FABRIC_WORKSPACE_ID"
export FABRIC_CAPACITY_ID="${FABRIC_CAPACITY_ID:-}"
EOF
