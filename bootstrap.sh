#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/vipeller/aio_gp_test/main/aio-tools"

SCRIPTS=(
  discover_env.sh
  deploy_opc_publisher_template.sh
)

echo "Fetching scripts from $REPO_URL …"
mkdir -p ./aio-tools
cd ./aio-tools

for s in "${SCRIPTS[@]}"; do
  echo "Downloading $s"
  curl -sSL -o "$s" "$REPO_URL/$s"
  chmod +x "$s"
done

echo
echo "Scripts installed into ./aio-tools/"
echo "   Available:"
for s in "${SCRIPTS[@]}"; do
  echo "   - $s"
done

echo
echo "Next steps:"
echo "  1. cd aio-tools/"
echo "  2. Run ./discover_env.sh <resource-group> <subscription-id>"
echo "     (this will print export commands for you)"
echo "  3. Source the exports: eval \$(./discover_env.sh …)"
echo "  4. Use the other scripts as needed"
