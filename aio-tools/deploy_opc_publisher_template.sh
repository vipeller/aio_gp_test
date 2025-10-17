#!/usr/bin/env bash
set -euo pipefail

# -------- logging helpers (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# -------- inputs --------
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${INSTANCE_NAME:?set INSTANCE_NAME}"
: "${SCHEMA_REGISTRY_NAME:?set SCHEMA_REGISTRY_NAME}"
SCHEMA_DIR="${SCHEMA_DIR:-./iotops}"
TEMPLATE_NAME="${TEMPLATE_NAME:-opc-publisher}"
API_VER="2025-10-01"

IMAGE_NAME="iotedge/opc-publisher"
IMAGE_REGISTRY="mcr.microsoft.com"
IMAGE_TAG="2.9.15"
IMAGE_PULL_POLICY="Always"

# -------- tools check --------
command -v az >/dev/null || { err "Azure CLI 'az' is required"; exit 1; }
command -v jq >/dev/null || { err "'jq' is required"; exit 1; }

# --- Ensure azure-iot-ops extension is installed (no prompts) ---
az config set extension.use_dynamic_install=yes_without_prompt >/dev/null

if ! az extension show -n azure-iot-ops >/dev/null 2>&1; then
  echo "[setup] Installing Azure IoT Operations CLI extension…" >&2
  az extension add -n azure-iot-ops -y --only-show-errors >/dev/null
else
  az extension update -n azure-iot-ops --only-show-errors >/dev/null || true
fi

# -------- context summary --------
log "Subscription:  $SUBSCRIPTION_ID"
log "ResourceGroup: $RESOURCE_GROUP"
log "Instance:      $INSTANCE_NAME"
log "SchemaRegistry:$SCHEMA_REGISTRY_NAME"
log "Schema dir:    $SCHEMA_DIR"
log "Template:      $TEMPLATE_NAME"
log "Image:         $IMAGE_REGISTRY/$IMAGE_NAME:$IMAGE_TAG (pull=$IMAGE_PULL_POLICY)"

# -------- ensure az is logged in & set sub --------
if ! az account show >/dev/null 2>&1; then
  log "Azure login required…"
  az login --only-show-errors >/dev/null
  ok "Logged in"
fi
az account set --subscription "$SUBSCRIPTION_ID"
ok "Using subscription $SUBSCRIPTION_ID"

# -------- discover extendedLocation from AIO --------
log "Fetching AIO instance to resolve extendedLocation…"
IOTOPS_JSON="$(az iot ops show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$INSTANCE_NAME" \
  --only-show-errors -o json)"

EXT_LOC_NAME="$(jq -r '.extendedLocation.name // empty' <<<"$IOTOPS_JSON")"
EXT_LOC_TYPE="$(jq -r '.extendedLocation.type // empty' <<<"$IOTOPS_JSON")"
if [[ -z "$EXT_LOC_NAME" ]]; then
  err "Could not resolve extendedLocation from instance '$INSTANCE_NAME'."
  exit 1
fi
EXT_LOC_TYPE="${EXT_LOC_TYPE:-CustomLocation}"
ok "extendedLocation: name=$EXT_LOC_NAME type=$EXT_LOC_TYPE"

CONNECTOR_METADATA_REF="${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}-metadata"

# -------- build connector template body --------
log "Composing Akri Connector Template body…"
BODY="$(jq -n \
  --arg extName "$EXT_LOC_NAME" \
  --arg extType "$EXT_LOC_TYPE" \
  --arg imageName "$IMAGE_NAME" \
  --arg registry "$IMAGE_REGISTRY" \
  --arg connectorMetadataRef "$CONNECTOR_METADATA_REF" \
  --arg tag "$IMAGE_TAG" \
  --arg pull "$IMAGE_PULL_POLICY" \
  '{
    extendedLocation: { name: $extName, type: $extType },
    properties: {
      aioMetadata: { aioMinVersion: "1.2.*", aioMaxVersion: "1.*.*" },
      runtimeConfiguration: {
        runtimeConfigurationType: "ManagedConfiguration",
        managedConfigurationSettings: {
          managedConfigurationType: "ImageConfiguration",
          imageConfigurationSettings: {
            imageName: $imageName,
            imagePullPolicy: $pull,
            replicas: 1,
            registrySettings: {
              registrySettingsType: "ContainerRegistry",
              containerRegistrySettings: { registry: $registry }
            },
            tagDigestSettings: { tagDigestType: "Tag", tag: $tag }
          },
          additionalConfiguration: {
            EnableMetrics: "True",
            UseFileChangePolling: "True",
            AioNetworkDiscoveryMode: null,
            AioNetworkDiscoveryInterval: null,
            DisableDataSetMetaData: "True",
            LogFormat: "syslog",
            PkiRootPath: "/var/tmp/pki",
            PublishedNodesFile: "/var/tmp/pn.json",
            CreatePublishFileIfNotExist: "True"
          },
          allocation: { policy: "Bucketized", bucketSize: 1 }
        }
      },
      deviceInboundEndpointTypes: [
        {
          endpointType: "Microsoft.OpcPublisher",
          version: "2.9",
          displayName: "OPC Publisher"
        }
      ],
      diagnostics: { logs: { level: "info" } },
      connectorMetadataRef: $connectorMetadataRef,
      mqttConnectionConfiguration: {
        host: "aio-broker:18883",
        authentication: {
          method: "ServiceAccountToken",
          serviceAccountTokenSettings: { audience: "aio-internal" }
        },
        tls: { mode: "Enabled", trustedCaCertificateConfigMapRef: "azure-iot-operations-aio-ca-trust-bundle" }
      }
    }
  }')"

# -------- PUT the template (idempotent) --------
URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.IoTOperations/instances/${INSTANCE_NAME}/akriConnectorTemplates/${TEMPLATE_NAME}?api-version=${API_VER}"

log "Creating/updating connector template '$TEMPLATE_NAME' in '$RESOURCE_GROUP/$INSTANCE_NAME'…"
az rest --method put --url "$URI" --headers "Content-Type=application/json" --body "$BODY" --only-show-errors >/dev/null
ok "PUT accepted"

# -------- poll provisioning state --------
log "Waiting for provisioning to complete…"
for i in {1..30}; do
  state="$(az rest --method get --url "$URI" --only-show-errors | jq -r '.properties.provisioningState // empty')"
  if [[ "$state" == "Succeeded" ]]; then
    ok "Provisioning Succeeded"
    break
  fi
  if [[ "$state" == "Failed" || "$state" == "Canceled" ]]; then
    err "Provisioning $state"
    exit 1
  fi
  log "Provisioning state: ${state:-<unknown>} (retry $i/30)…"
  sleep 5
done
