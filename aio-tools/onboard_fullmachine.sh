#!/usr/bin/env bash
set -euo pipefail

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# -------- required env --------
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${ADR_NAMESPACE_NAME:?set ADR_NAMESPACE_NAME}"
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${LOCATION:?set LOCATION}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"

# -------- tunables --------
API="${API:-2025-10-01}"
PREFIX="${PREFIX:-fullmachinetool-}"
WAIT_INTERVAL_SEC="${WAIT_INTERVAL_SEC:-10}"
WAIT_TIMEOUT_SEC="${WAIT_TIMEOUT_SEC:-900}"   # 15 min default

log "Inputs:"
log "  SUBSCRIPTION_ID   = $SUBSCRIPTION_ID"
log "  RESOURCE_GROUP    = $RESOURCE_GROUP"
log "  ADR_NAMESPACE_NAME= $ADR_NAMESPACE_NAME"
log "  INSTANCE_NAME     = $INSTANCE_NAME"
log "  LOCATION          = $LOCATION"
log "  PREFIX            = $PREFIX"
log "  TIMEOUT/INTERVAL  = ${WAIT_TIMEOUT_SEC}s / ${WAIT_INTERVAL_SEC}s"

# -------- tools --------
command -v az >/dev/null  || { err "Azure CLI 'az' is required"; exit 1; }
command -v jq >/dev/null  || { err "'jq' is required"; exit 1; }

# ensure azure-iot-ops extension is present (no prompts)
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null
if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  log "Installing Azure IoT Operations CLI extension…"
  az extension add -n azure-iot-ops -y --only-show-errors >/dev/null
else
  # keep it fresh but don't fail the script if update errors
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

# -------- Resolve ADR resource id --------
ADR_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DeviceRegistry/namespaces/${ADR_NAMESPACE_NAME}"
# sanity check it exists
az rest --method get \
  --url "https://management.azure.com${ADR_RESOURCE_ID}?api-version=${API}" \
  --only-show-errors >/dev/null
ok "ADR namespace found: $ADR_NAMESPACE_NAME"

# -------- Resolve extendedLocation from AIO instance --------
log "Resolving extendedLocation from AIO instance '$INSTANCE_NAME'…"
AIO_JSON="$(az iot ops show -g "$RESOURCE_GROUP" -n "$INSTANCE_NAME" -o json --only-show-errors)"
EXT_NAME="$(jq -r '.extendedLocation.name // empty' <<<"$AIO_JSON")"
EXT_TYPE="$(jq -r '.extendedLocation.type // "CustomLocation"' <<<"$AIO_JSON")"
[[ -z "$EXT_NAME" ]] && { err "AIO instance missing extendedLocation.name"; exit 1; }
EXT_LOC="$(jq -c -n --arg n "$EXT_NAME" --arg t "$EXT_TYPE" '{name:$n,type:$t}')"
ok "extendedLocation: $EXT_LOC"

# -------- Wait for discovered asset to appear --------
log "Waiting for discovered asset with name starting with '$PREFIX'…"
deadline=$(( $(date +%s) + WAIT_TIMEOUT_SEC ))
ASSET_NAME=""

while :; do
  DISCOVERED_JSON="$(az rest --method get \
    --url "https://management.azure.com${ADR_RESOURCE_ID}/discoveredAssets?api-version=${API}" \
    --only-show-errors)"

  # pick the first match
  ASSET_NAME="$(jq -r --arg p "$PREFIX" '.value[]?.name | select(startswith($p))' <<<"$DISCOVERED_JSON" | head -n1 || true)"

  if [[ -n "$ASSET_NAME" ]]; then
    ok "Found discovered asset: $ASSET_NAME"
    break
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    err "Timed out after ${WAIT_TIMEOUT_SEC}s waiting for a discovered asset starting with '$PREFIX'."
    exit 1
  fi

  log "Still waiting… (next check in ${WAIT_INTERVAL_SEC}s)"
  sleep "$WAIT_INTERVAL_SEC"
done

# -------- Fetch discovered asset details --------
log "Fetching discovered asset details for '$ASSET_NAME'…"
DASSET="$(az rest --method get \
  --url "https://management.azure.com${ADR_RESOURCE_ID}/discoveredAssets/${ASSET_NAME}?api-version=${API}" \
  --only-show-errors)"

# Remove unsupported properties (e.g. lastUpdatedOn)
PROPS="$(jq 'del(.properties.lastUpdatedOn)' <<<"$DASSET" | jq -c '.properties')"

# Choose displayName fallback
DISPLAY_NAME="$(jq -r '.properties.displayName // .properties.model // "Asset"' <<<"$DASSET")"
DESC_VAL="$(jq -r '.properties.description // ""' <<<"$DASSET")"

# -------- Build onboarded asset body --------
log "Building onboarding payload…"
BODY="$(jq -c -n \
  --argjson ext "$EXT_LOC" \
  --arg loc "$LOCATION" \
  --arg dn "$DISPLAY_NAME" \
  --arg desc "$DESC_VAL" \
  --argjson props "$PROPS" \
  '{
    extendedLocation: $ext,
    location: $loc,
    properties: {
      externalAssetId: $props.externalAssetId,
      enabled: true,
      displayName: $dn,
      description: $desc,
      manufacturer: $props.manufacturer,
      model: $props.model,
      productCode: $props.productCode,
      hardwareRevision: $props.hardwareRevision,
      softwareRevision: $props.softwareRevision,
      documentationUri: $props.documentationUri,
      serialNumber: $props.serialNumber,
      defaultDatasetsDestinations: $props.defaultDatasetsDestinations,
      defaultEventsDestinations: $props.defaultEventsDestinations,
      defaultStreamsDestinations: $props.defaultStreamsDestinations,
      defaultDatasetsConfiguration: $props.defaultDatasetsConfiguration,
      defaultEventsConfiguration: $props.defaultEventsConfiguration,
      defaultStreamsConfiguration: $props.defaultStreamsConfiguration,
      defaultManagementGroupsConfiguration: $props.defaultManagementGroupsConfiguration,
      deviceRef: $props.deviceRef,
      discoveredAssetRefs: [$props.discoveryId],
      assetTypeRefs: $props.assetTypeRefs,
      datasets: $props.datasets,
      eventGroups: $props.eventGroups,
      streams: $props.streams,
      managementGroups: $props.managementGroups
    }
  }')"

# -------- Create (or update) the onboarded asset --------
PUT_URL="https://management.azure.com${ADR_RESOURCE_ID}/assets/${ASSET_NAME}?api-version=${API}"
log "Onboarding asset '$ASSET_NAME'…"
az rest --method put \
  --url "$PUT_URL" \
  --body "$BODY" \
  --only-show-errors \
  | jq -C . >&2

ok "Asset '$ASSET_NAME' onboarded."
