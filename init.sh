#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TF=tofu

# ---------------------------------------------------------------------------
# Load credentials and environment
# ---------------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found. Copy .env.example and fill in your values." >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/terraform.tfvars" ]; then
  echo "ERROR: terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values." >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$SCRIPT_DIR/env.sh"

# ---------------------------------------------------------------------------
# Generate backend.hcl from .env values (never committed — in .gitignore)
# ---------------------------------------------------------------------------
# Extract the project path from the URL (e.g. "stbemeyer/factorygameserver")
# and URL-encode the slash for the GitLab API.
PROJECT_PATH="${GITLAB_PROJECT_URL#https://*/}"
PROJECT_PATH_ENCODED="${PROJECT_PATH/\//\%2F}"
GITLAB_HOST="${GITLAB_PROJECT_URL%%/${PROJECT_PATH}}"
STATE_BASE="${GITLAB_HOST}/api/v4/projects/${PROJECT_PATH_ENCODED}/terraform/state/${TF_STATE_NAME}"

cat > "$SCRIPT_DIR/backend.hcl" <<EOF
address        = "${STATE_BASE}"
lock_address   = "${STATE_BASE}/lock"
unlock_address = "${STATE_BASE}/lock"
lock_method    = "POST"
unlock_method  = "DELETE"
retry_wait_min = 5
headers        = { "PRIVATE-TOKEN" = "${GITLAB_PROJECT_ACCESS_TOKEN}" }
EOF

# ---------------------------------------------------------------------------
# Terraform init → plan → apply
# ---------------------------------------------------------------------------
echo ""
echo "=== $TF init ==="
$TF init -reconfigure -backend-config=backend.hcl

echo ""
echo "=== $TF plan ==="
$TF plan -out=tfplan

echo ""
read -rp "Apply the plan? [y/N] " confirm
if [ "${confirm,,}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== $TF apply ==="
$TF apply tfplan
rm -f tfplan

echo ""
echo "=== Done ==="
$TF output

# ---------------------------------------------------------------------------
# Stream installation logs from the new instance
# ---------------------------------------------------------------------------
FLOATING_IP="$($TF output -raw floating_ip)"

echo ""
echo "=== Waiting for SSH on ${FLOATING_IP} ==="
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
until ssh $SSH_OPTS "ubuntu@${FLOATING_IP}" true 2>/dev/null; do
  printf "."
  sleep 5
done
echo " ready."

echo ""
echo "=== Installation log (Ctrl+C to stop following) ==="
# Follow the log until the bootstrap complete marker appears, then exit
ssh $SSH_OPTS "ubuntu@${FLOATING_IP}" \
  "tail -n +1 -f /var/log/satisfactory-setup.log | { sed '/Bootstrap complete/q'; }"
