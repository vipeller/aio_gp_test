#!/usr/bin/env bash
set -euo pipefail

# -------- Config & required inputs -------- 
: "${FABRIC_WORKSPACE_ID:?Set FABRIC_WORKSPACE_ID (GUID)}"

# ---- Names (centralized) ----
DISPLAY_NAME="${DISPLAY_NAME:-DTB-GP-Test}"
SOURCE_NAME="${SOURCE_NAME:-DataflowSource}"
DEST_NAME="${DEST_NAME:-DTBSink}"
STREAM_NAME="${STREAM_NAME:-Staging}"
DESCRIPTION="${DESCRIPTION:-Dataflow staging pipeline for DTB GP Test}"

# -------- logging (stderr only) --------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }


# -------- Utilities -------- 
b64() { printf '%s' "$1" | base64 | tr -d '\r\n'; }

# -------- Getting authentication token -------- 
log "Getting Fabric access token…"

AUTH_TOKEN="$(az account get-access-token \
  --scope https://api.fabric.microsoft.com/.default \
  --query accessToken -o tsv 2>/dev/null || true)"
if [[ -z "$AUTH_TOKEN" ]]; then
  echo "ERROR: Failed to obtain Fabric access token (check az login / tenant access)." >&2
  exit 1
fi

# -------- Build eventstream payload -------- 
log "Building eventstream definition (source=$SOURCE_NAME, dest=$DEST_NAME, stream=$STREAM_NAME)…"

EVENTSTREAM_JSON=$(
  jq -n \
    --arg src "$SOURCE_NAME" \
    --arg dest "$DEST_NAME" \
    --arg stream "$STREAM_NAME" '
{
  sources: [
    { name: $src, type: "CustomEndpoint", properties: {} }
  ],
  destinations: [
    {
      name: $dest,
      type: "CustomEndpoint",
      properties: {},
      inputNodes: [ { name: $stream } ]      
    }
  ],
  streams: [
    {
      name: $stream,
      type: "DefaultStream",
      properties: {},
      inputNodes: [ { name: $src } ]
    }
  ],
  operators: [],
  compatibilityLevel: "1.0"
}'
)

PLATFORM_JSON=$(
  jq -n --arg dn "$DISPLAY_NAME" '
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/gitIntegration/platformProperties/2.0.0/schema.json",
  "metadata": { "type": "Eventstream", "displayName": $dn },
  "config":   { "version": "2.0", "logicalId": "00000000-0000-0000-0000-000000000000" }
}'
)

DEF_JSON=$(
  jq -n \
    --arg es "$(b64 "$EVENTSTREAM_JSON")" \
    --arg plat "$(b64 "$PLATFORM_JSON")" '
{
  parts: [
    { path: "eventstream.json", payload: $es,   payloadType: "InlineBase64" },
    { path: ".platform",        payload: $plat, payloadType: "InlineBase64" }
  ]
}'
)

BODY=$(
  jq -n \
    --arg dn "$DISPLAY_NAME" \
    --arg desc "$DESCRIPTION" \
    --argjson defin "$DEF_JSON" '
{
  displayName: $dn,
  type: "Eventstream",
  description: $desc,
  definition: $defin
}'
)

ok "Definition built."

# -------- Create the Eventstream -------- 
CREATE_URL="https://api.fabric.microsoft.com/v1/workspaces/$FABRIC_WORKSPACE_ID/items"

tmpdir="$(mktemp -d)"; trap 'rm -rf "$tmpdir"' EXIT
headers="$tmpdir/headers.txt"
resp="$tmpdir/body.json"

log "Creating Eventstream in workspace: $FABRIC_WORKSPACE_ID"
HTTP_CODE=$(
  curl -sS -D "$headers" -o "$resp" -w '%{http_code}' \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST "$CREATE_URL" -d "$BODY"
)

eventstream_id=""
case "$HTTP_CODE" in
  201)
    eventstream_id="$(jq -r '.id' "$resp")"
    ;;
  202)
    op_url="$(awk -F': ' 'tolower($1)=="location"{print $2}' "$headers" | tr -d '\r')"
    retry_after="$(awk -F': ' 'tolower($1)=="retry-after"{print $2}' "$headers" | tr -d '\r')"
    [[ -z "${retry_after:-}" ]] && retry_after=5

    log "Accepted (202). Polling operation…"
    while :; do
      state="$(curl -sS -H "Authorization: Bearer $AUTH_TOKEN" "$op_url")"
      status="$(jq -r '.status // empty' <<<"$state")"
      [[ "$status" == "Succeeded" ]] && break
      if [[ "$status" == "Failed" || "$status" == "Canceled" ]]; then
        err "Provisioning failed."; echo "$state" | jq . >&2; exit 1
      fi
      sleep "$retry_after"
    done

    base="${op_url%/state}"
    result="$(curl -sS -H "Authorization: Bearer $AUTH_TOKEN" "$base/result")"
    eventstream_id="$(jq -r '.id' <<<"$result")"
    ;;
  *)
    err "Unexpected HTTP $HTTP_CODE from create call:"
    cat "$resp" >&2
    exit 1
    ;;
esac

[[ -z "$eventstream_id" || "$eventstream_id" == "null" ]] && { err "No Eventstream ID returned."; exit 1; }
ok "Created Eventstream: $eventstream_id"

# -------- Resolve sourceId & print connection -------- 
log "Fetching topology to resolve source id for \"$SOURCE_NAME\"…"
TOPOLOGY="$(curl -sS -H "Authorization: Bearer $AUTH_TOKEN" \
  "https://api.fabric.microsoft.com/v1/workspaces/$FABRIC_WORKSPACE_ID/eventstreams/$eventstream_id/topology")"

source_id="$(jq -r --arg n "$SOURCE_NAME" '.sources[]? | select(.name==$n) | .id' <<<"$TOPOLOGY")"
if [[ -z "$source_id" || "$source_id" == "null" ]]; then
  err "Could not find source \"$SOURCE_NAME\" in topology. Available sources:"
  jq -r '.sources[]? | "\(.name)\t\(.id)"' <<<"$TOPOLOGY" >&2
  exit 1
fi
ok "Resolved source id: $source_id"

log "Fetching source connection credentials…"
CONN="$(curl -sS -H "Authorization: Bearer $AUTH_TOKEN" \
  "https://api.fabric.microsoft.com/v1/workspaces/$FABRIC_WORKSPACE_ID/eventstreams/$eventstream_id/sources/$source_id/connection")"

# Save to ./creds/dtb_hub_cred.json (pretty-printed), creating the dir if needed
OUT_DIR="./creds"
OUT_FILE="$OUT_DIR/dtb_hub_cred.json"
mkdir -p "$OUT_DIR"
printf '%s\n' "$CONN" | jq . > "$OUT_FILE"
chmod 600 "$OUT_FILE" 2>/dev/null || true

ok "Credentials saved to: $OUT_FILE"

echo
echo "================================================================"
echo "⚠️  SECURITY WARNING"
echo "The source connection credentials were written to:"
echo "    $OUT_FILE"
echo
echo "Treat this file as a secret. Remove it as soon as your deployment"
echo "has consumed the credentials (e.g., after you’ve configured the sender)."
echo "Example cleanup:"
echo "    rm -f \"$OUT_FILE\""
echo "================================================================"

