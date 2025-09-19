#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="vipeller"
GITHUB_REPO="aio_gp_test"
GITHUB_BRANCH="main"

# Where to place downloaded assets
TARGET_DIR="${TARGET_DIR:-$PWD/aio-tools}"
SCRIPTS_DIR="$TARGET_DIR"
SCHEMAS_DIR="$TARGET_DIR/iotops"

SCRIPTS=(
  "discover_env.sh"
  "deploy_opc_publisher_template.sh"
  "deploy_opc_publisher_instance.sh"
)

SCHEMA_FILES=(
  "opc-publisher-connector-metadata.json"
  "opc-publisher-dataset-datapoint-schema.json"
  "opc-publisher-dataset-schema.json"
  "opc-publisher-endpoint-schema.json"
  "opc-publisher-event-schema.json"
)

# ---------- logging helpers (stderr only) ----------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [SUCC] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---------- helpers ----------
raw_url() {
  # $1 = path within repo (e.g., scripts/foo.sh or iotops/bar.json)
  printf 'https://raw.githubusercontent.com/%s/%s/%s/%s' \
    "$GITHUB_ORG" "$GITHUB_REPO" "$GITHUB_BRANCH" "$1"
}

fetch() {
  # $1 = remote path; $2 = local path
  local remote="$1" local_path="$2"
  mkdir -p "$(dirname "$local_path")"
  # -f fail on HTTP errors, -L follow redirects, -sSL quiet but still follow redirects
  if curl -fsSL "$(raw_url "$remote")" -o "$local_path"; then
    ok "Fetched $remote → $local_path"
  else
    err "Failed to fetch $remote"
    return 1
  fi
}

# ---------- start ----------
log "Bootstrap from GitHub: $GITHUB_ORG/$GITHUB_REPO@$GITHUB_BRANCH"
log "Target directory: $TARGET_DIR"
mkdir -p "$SCRIPTS_DIR" "$SCHEMAS_DIR"

# Fetch scripts
log "Downloading scripts…"
for f in "${SCRIPTS[@]}"; do
  fetch "aio-tools/$f" "$SCRIPTS_DIR/$f"
done

# Make scripts executable
log "Marking scripts executable…"
chmod +x "$SCRIPTS_DIR"/*.sh || true
ok "Scripts ready in $SCRIPTS_DIR"

# Fetch schema files
if ((${#SCHEMA_FILES[@]})); then
  log "Downloading iotops schema files…"
  for f in "${SCHEMA_FILES[@]}"; do
    fetch "aio-tools/iotops/$f" "$SCHEMAS_DIR/$f" || warn "Skipped schema $f (not found?)"
  done
  ok "Schemas ready in $SCHEMAS_DIR"
else
  warn "No schema files listed in SCHEMA_FILES; nothing to fetch."
fi

log "Done. Next:"
log "  cd \"$TARGET_DIR\""
log "  # discover env (prints exports) → eval them in your shell"
log "  # eval \"\$(./discover_env.sh <resource-group> <subscription-id>)\""
