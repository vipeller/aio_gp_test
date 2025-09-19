#!/usr/bin/env bash
set -euo pipefail

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [SUCC] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# -------- inputs --------
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"     # AIO instance name
: "${TEMPLATE_NAME:?set TEMPLATE_NAME}"     # Akri Connector Template name
: "${CONNECTOR_NAME:?set CONNECTOR_NAME}"   # Akri Connector (instance) name
API="2025-07-01-preview"

log "Inputs:"
log "  SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
log "  RESOURCE_GROUP  = $RESOURCE_GROUP"
log "  INSTANCE_NAME   = $INSTANCE_NAME"
log "  TEMPLATE_NAME   = $TEMPLATE_NAME"
log "  CONNECTOR_NAME  = $CONNECTOR_NAME"

# -------- tools & az extension --------
command -v az >/dev/null || { err "Azure CLI 'az' is required"; exit 1; }
command -v jq >/dev/null || { err "'jq' is required"; exit 1; }

# ensure azure-iot-ops extension is present (no prompts)
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  log "Installing Azure IoT Operations CLI extension…"
  az extension add -n azure-iot-ops --yes >/dev/null
else
  # keep it fresh but don't fail the script if update errors
  az extension update -n azure-iot-ops --yes >/dev/null || true
fi
ok "IoT Ops CLI extension ready"

# -------- login & subscription --------
if ! az account show >/dev/null 2>&1; then
  log "Azure login required…"
  az login --only-show-errors >/dev/null
  ok "Logged in"
fi
az account set --subscription "$SUBSCRIPTION_ID"
ok "Using subscription $SUBSCRIPTION_ID"

# -------- discover extendedLocation from AIO --------
log "Resolving extendedLocation from AIO instance '$INSTANCE_NAME'…"
EXT_JSON="$(az iot ops show -g "$RESOURCE_GROUP" -n "$INSTANCE_NAME" -o json --only-show-errors)"
EXT_NAME="$(jq -r '.extendedLocation.name // empty' <<<"$EXT_JSON")"
if [[ -z "$EXT_NAME" ]]; then
  err "Could not resolve extendedLocation from instance '$INSTANCE_NAME'."
  exit 1
fi
ok "extendedLocation.name = $EXT_NAME"

# -------- build request --------
BASE="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.IoTOperations/instances/$INSTANCE_NAME"
URI="$BASE/akriConnectorTemplates/$TEMPLATE_NAME/connectors/$CONNECTOR_NAME?api-version=$API"
BODY="$(jq -n --arg n "$EXT_NAME" '{extendedLocation:{name:$n,type:"CustomLocation"}}')"

# -------- create or update connector --------
log "Creating/updating Akri Connector instance '$CONNECTOR_NAME' from template '$TEMPLATE_NAME'…"
az rest --method put --url "$URI" --body "$BODY" --only-show-errors >/dev/null
ok "PUT accepted by ARM"

# -------- poll provisioning state --------
log "Waiting for provisioning to complete…"
for i in {1..60}; do
  state="$(az rest --method get --url "$URI" --only-show-errors \
           | jq -r '.properties.provisioningState // .properties.status // empty')"

  if [[ "$state" == "Succeeded" ]]; then
    ok "Provisioning Succeeded"
    exit 0
  fi
  if [[ "$state" == "Failed" || "$state" == "Canceled" ]]; then
    err "Provisioning $state"
    # dump current resource for troubleshooting (to stderr)
    az rest --method get --url "$URI" --only-show-errors | jq . >&2 || true
    exit 1
  fi

  log "Provisioning state: ${state:-<unknown>} (retry $i/60)…"
  sleep 5
done

err "Timed out waiting for provisioning"
exit 1
