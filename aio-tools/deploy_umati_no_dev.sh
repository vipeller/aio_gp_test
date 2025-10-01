#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="vipeller"
GITHUB_REPO="aio_gp_test"
GITHUB_BRANCH="main"

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# -------- required inputs (ENV) --------
: "${DEPLOYMENT_NAME:?set DEPLOYMENT_NAME}"      # Helm release name
: "${INSTANCE_NAME:?set INSTANCE_NAME}"          # AIO instance name (for sanity checks)
: "${RESOURCE_GROUP:?set RESOURCE_GROUP}"
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID}"
: "${ADR_NAMESPACE_NAME:?set ADR_NAMESPACE_NAME}" 
: "${NAMESPACE:?set NAMESPACE}"                   # Kubernetes namespace to deploy into

# -------- optional inputs (ENV) --------
CHART_PATH_IN_REPO="${CHART_PATH_IN_REPO:-aio-tools/charts/umati-sample-server-1.0-alpha.1.tgz}"

# To use a local chart file, set HELM_CHART_PATH.
HELM_CHART_PATH="${HELM_CHART_PATH:-}"

COUNT="${COUNT:-1}"                              # number of simulator instances
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"        # helm/kubectl wait budget (seconds)
API="${API:-2025-07-01-preview}"

log "Inputs:"
log "  SUBSCRIPTION_ID   = $SUBSCRIPTION_ID"
log "  RESOURCE_GROUP    = $RESOURCE_GROUP"
log "  INSTANCE_NAME     = $INSTANCE_NAME"
log "  ADR_NAMESPACE_NAME= $ADR_NAMESPACE_NAME"
log "  NAMESPACE         = $NAMESPACE"
log "  COUNT             = $COUNT"
log "  HELM_CHART_PATH   = ${HELM_CHART_PATH:-<unset>}"
log "  CHART_PATH_IN_REPO   = $CHART_PATH_IN_REPO"
log "  TIMEOUT_SECONDS   = $TIMEOUT_SECONDS"

# -------- tools --------
command -v az >/dev/null       || { err "Azure CLI 'az' is required"; exit 1; }
command -v jq >/dev/null       || { err "'jq' is required"; exit 1; }
command -v kubectl >/dev/null  || { err "'kubectl' is required"; exit 1; }
command -v helm >/dev/null     || { err "'helm' is required"; exit 1; }

# -------- login & subscription --------
if ! az account show >/dev/null 2>&1; then
  log "Azure login required…"
  az login --only-show-errors >/dev/null
  ok "Logged in"
fi
az account set --subscription "$SUBSCRIPTION_ID"
ok "Using subscription $SUBSCRIPTION_ID"

# -------- Validate ADR namespace --------
ADR_URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DeviceRegistry/namespaces/${ADR_NAMESPACE_NAME}?api-version=$API"
ADR_JSON="$(az rest --method get --url "$ADR_URI" --only-show-errors 2>/dev/null || true)"
ADR_ID="$(echo "${ADR_JSON:-}" | jq -r '.id // empty')"
if [[ -z "$ADR_ID" ]]; then
  err "ADR namespace not found: $ADR_NAMESPACE_NAME (RG: $RESOURCE_GROUP)"
  exit 1
fi
ok "ADR namespace id: $ADR_ID"

# -------- AIO instance + extendedLocation (sanity) --------
AIO_JSON="$(az iot ops show -g "$RESOURCE_GROUP" -n "$INSTANCE_NAME" --only-show-errors -o json 2>/dev/null || true)"
AIO_NAME="$(echo "$AIO_JSON" | jq -r '.name // empty')"
EXT_LOC_JSON="$(echo "$AIO_JSON" | jq -c '.extendedLocation // empty')"
if [[ -z "$AIO_NAME" || "$AIO_NAME" == "null" ]]; then
  err "AIO instance not found: $INSTANCE_NAME"
  exit 1
fi
if [[ -z "$EXT_LOC_JSON" || "$EXT_LOC_JSON" == "null" ]]; then
  err "AIO instance missing extendedLocation; check installation."
  exit 1
fi
ok "AIO extendedLocation: $EXT_LOC_JSON"

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

# -------- determine chart source (GitHub raw by default) --------
if [[ -n "$HELM_CHART_PATH" ]]; then
  [[ -f "$HELM_CHART_PATH" ]] || { err "Local chart not found at $HELM_CHART_PATH"; exit 1; }
  CHART_SRC="$HELM_CHART_PATH"
  log "Using local chart: $CHART_SRC"
else
  CHART_SRC="https://raw.githubusercontent.com/${GITHUB_ORG}/${GITHUB_REPO}/${GITHUB_BRANCH}/${CHART_PATH_IN_REPO}"
  log "Using chart from GitHub: $CHART_SRC"
fi

# -------- helm deploy --------
log "Deploying Helm release '$DEPLOYMENT_NAME' to namespace '$NAMESPACE'…"
log "  simulations = $COUNT"
helm upgrade -i "$DEPLOYMENT_NAME" "$CHART_SRC" \
  --namespace "$NAMESPACE" --create-namespace \
  --set "simulations=$COUNT" \
  --set "deployDefaultIssuerCA=false" \
  --wait --timeout "${TIMEOUT_SECONDS}s"
ok "Helm release applied"

# -------- Wait for readiness --------
label="app.kubernetes.io/instance=${DEPLOYMENT_NAME}"
log "Waiting for resources with label '$label' in namespace '$NAMESPACE' to become Ready…"

deps="$(kubectl -n "$NAMESPACE" get deploy -l "$label" -o name 2>/dev/null || true)"
if [[ -n "$deps" ]]; then
  while read -r d; do
    [[ -z "$d" ]] && continue
    log "  -> rollout $d"
    kubectl -n "$NAMESPACE" rollout status "$d" --timeout="${TIMEOUT_SECONDS}s"
  done <<< "$deps"
  ok "All deployments for $DEPLOYMENT_NAME are ready"
else
  # Fallback to pods if there are no Deployments
  for i in {1..60}; do
    total="$(kubectl -n "$NAMESPACE" get pods -l "$label" -o json | jq '.items | length')"
    notReady="$(kubectl -n "$NAMESPACE" get pods -l "$label" -o json \
      | jq '[.items[] | select(.status.phase!="Running" or ([.status.containerStatuses[]? | select(.ready!=true)]|length)>0)] | length')"
    if [[ "$total" -gt 0 && "$notReady" -eq 0 ]]; then
      ok "All $total pods Ready."
      break
    fi
    if [[ $i -eq 60 ]]; then
      err "Timed out waiting for pods to become Ready"
      exit 1
    fi
    log "Pods not ready yet (retry $i/60)…"
    sleep 5
  done
fi

# -------- Create ADR namespaced devices for "umati" --------
log "Creating ADR devices for simulation 'umati'…"

# AssetTypes for umati
assetTypes=( "nsu=http://opcfoundation.org/UA/MachineTool/;i=13" ) # machine tool

# Base ADR resource
ADR_RESOURCE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DeviceRegistry/namespaces/${ADR_NAMESPACE_NAME}"

# Loop over simulator instances
for ((i=0; i<COUNT; i++)); do
  suffix=$(printf "%06d" "$i")
  deviceName="umati-${suffix}"
  deviceResource="${ADR_RESOURCE}/devices/${deviceName}"

  log "Checking if device '$deviceName' exists…"
  if ! device_json="$(az rest --method get \
        --url "${deviceResource}?api-version=${API}" \
        --headers "Content-Type=application/json" \
        --only-show-errors 2>/dev/null || true)"; then
    device_json=""
  fi

  device_id="$(jq -r '.id // empty' <<<"$device_json")"
  if [[ -n "$device_id" ]]; then
    ok "Device $device_id already exists"
    continue
  fi

  # Build OPC UA endpoint address inside K8s cluster
  address="umati-${DEPLOYMENT_NAME}-${suffix}.${NAMESPACE}.svc.cluster.local"
  address="opc.tcp://${address}:4840"

  # Compose body
  BODY="$(jq -n \
    --arg ext "$(jq -c '.extendedLocation' <<<"$AIO_JSON")" \
    --arg loc "$LOCATION" \
    --arg addr "$address" \
    --argjson ats "$(printf '%s\n' "${assetTypes[@]}" | jq -R . | jq -s .)" '
  {
    extendedLocation: ($ext | fromjson),
    location: $loc,
    properties: {
      enabled: true,
      attributes: { deviceType: "LDS" },
      endpoints: {
        inbound: {
          none: {
            address: $addr,
            endpointType: "Microsoft.OpcPublisher",
            version: "2.9",
            authentication: { method: "Anonymous" },
            additionalConfiguration: {
              EndpointSecurityMode: "None",
              EndpointSecurityPolicy: "None",
              RunAssetDiscovery: true,
              AssetTypes: $ats
            } | tostring
          }
        }
      }
    }
  }')"

  # Create device
  log "Creating ADR namespaced device $deviceName…"
  if new_device="$(az rest --method put \
        --url "${deviceResource}?api-version=${API}" \
        --headers "Content-Type=application/json" \
        --body "$BODY" --only-show-errors)"; then
    ok "ADR namespaced device $(jq -r '.id' <<<"$new_device") created."
  else
    err "Failed to create device $deviceName"
    exit 1
  fi
done
