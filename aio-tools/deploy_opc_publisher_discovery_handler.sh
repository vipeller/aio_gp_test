#!/usr/bin/env bash
set -euo pipefail

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# -------- inputs --------
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"
API="${API:-2025-07-01-preview}"
DH_NAME="${DH_NAME:-opc-publisher}"     # discovery handler resource name

log "Inputs:"
log "  SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
log "  RESOURCE_GROUP  = $RESOURCE_GROUP"
log "  INSTANCE_NAME   = $INSTANCE_NAME"
log "  DH_NAME         = $DH_NAME"
log "  API             = $API"

# -------- tools & az extension --------
command -v az >/dev/null || { err "Azure CLI 'az' is required"; exit 1; }
command -v jq >/dev/null || { err "'jq' is required"; exit 1; }

# No prompts for extensions
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  log "Installing Azure IoT Operations CLI extension…"
  az extension add -n azure-iot-ops -y --only-show-errors >/dev/null
else
  az extension update -n azure-iot-ops --only-show-errors >/dev/null || true
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

# -------- resolve Custom Location from AIO instance --------
log "Resolving extendedLocation from AIO instance '$INSTANCE_NAME'…"
EXT_NAME="$(az iot ops show -g "$RESOURCE_GROUP" -n "$INSTANCE_NAME" \
  -o tsv --query extendedLocation.name --only-show-errors || true)"
if [[ -z "$EXT_NAME" || "$EXT_NAME" == "null" ]]; then
  err "Could not resolve extendedLocation.name from AIO instance."
  exit 1
fi
ok "extendedLocation.name = $EXT_NAME"

# -------- build ARM URI & body --------
BASE="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.IoTOperations/instances/$INSTANCE_NAME"
URI="$BASE/akriDiscoveryHandlers/$DH_NAME?api-version=$API"

log "Composing discovery handler payload…"
BODY="$(jq -n --arg ext "$EXT_NAME" '
{
  extendedLocation: { name: $ext, type: "CustomLocation" },
  properties: {
    aioMetadata: { aioMinVersion: "1.2.*", aioMaxVersion: "1.*.*" },
    imageConfiguration: {
      imageName: "iotedge/opc-publisher",
      imagePullPolicy: "Always",
      registrySettings: {
        registrySettingsType: "ContainerRegistry",
        containerRegistrySettings: { registry: "mcr.microsoft.com" }
      },
      tagDigestSettings: { tagDigestType: "Tag", tag: "2.9.15" }
    },
    mode: "Enabled",
    schedule: { scheduleType: "Cron", cron: "*/10 * * * *" },
    additionalConfiguration: {
      AioNetworkDiscoveryMode: "Fast",
      EnableMetrics: "True",
      LogFormat: "syslog"
    },
    discoverableDeviceEndpointTypes: [
      { endpointType: "Microsoft.OpcPublisher", version: "2.9" }
    ],
    secrets: [],
    diagnostics: { logs: { level: "info" } },
    mqttConnectionConfiguration: {
      host: "aio-broker:18883",
      authentication: { method: "ServiceAccountToken", serviceAccountTokenSettings: { audience: "aio-internal" } },
      tls: { mode: "Enabled", trustedCaCertificateConfigMapRef: "azure-iot-operations-aio-ca-trust-bundle" }
    }
  }
}
')"

# -------- create or update & poll provisioning --------
log "Deploying discovery handler '$DH_NAME'…"
az rest --method put --url "$URI" --body "$BODY" --only-show-errors >/dev/null
ok "PUT accepted by ARM"

log "Waiting for discovery handler provisioning…"
for i in {1..60}; do
  state="$(az rest --method get --url "$URI" --only-show-errors \
           | jq -r '.properties.provisioningState // empty')"

  if [[ "$state" == "Succeeded" ]]; then
    ok "Provisioning Succeeded"
    exit 0
  fi
  if [[ "$state" == "Failed" || "$state" == "Canceled" ]]; then
    err "Provisioning $state"
    az rest --method get --url "$URI" --only-show-errors | jq . >&2 || true
    exit 1
  fi

  log "Provisioning state: ${state:-<unknown>} (retry $i/60)…"
  sleep 5
done

err "Timed out waiting for provisioning"
exit 1
