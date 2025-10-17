#!/usr/bin/env bash
set -euo pipefail

GITHUB_ORG="vipeller"
GITHUB_REPO="aio_gp_test"
GITHUB_BRANCH="main"

# Where to place downloaded assets
TARGET_DIR="${TARGET_DIR:-$PWD/aio-tools}"
SCRIPTS_DIR="$TARGET_DIR"

SCRIPTS=(
  "discover_env.sh"
  "deploy_opc_publisher_template.sh"
  "deploy_umati.sh"
  "register_umati_device.sh"
  "onboard_fullmachine.sh"
  "deploy_eventstream.sh"
  "deploy_dataflow.sh"
)

# ---------- logging helpers (stderr only) ----------
log()  { printf '[%s] [INFO] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
ok()   { printf '[%s] [ OK ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
warn() { printf '[%s] [WARN]  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
err()  { printf '[%s] [ERR ] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---------- helpers ----------
raw_url() {
  # $1 = path within repo (e.g., scripts/foo.sh)
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
mkdir -p "$SCRIPTS_DIR"

# Fetch scripts
log "Downloading scripts…"
for f in "${SCRIPTS[@]}"; do
  fetch "aio-tools/$f" "$SCRIPTS_DIR/$f"
done

# Make scripts executable
log "Marking scripts executable…"
chmod +x "$SCRIPTS_DIR"/*.sh || true
ok "Scripts ready in $SCRIPTS_DIR"

log "Done. Next:"
log "  cd \"$TARGET_DIR\""
log "  # discover env (prints exports) → eval them in your shell"
log "  # eval \"\$(./discover_env.sh <subscription-id> <resource-group>)\""
