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
# Configure backend
# ---------------------------------------------------------------------------
BACKEND_ARGS=""
if [ "${STATE_BACKEND:-gitlab}" = "gitlab" ]; then
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
  BACKEND_ARGS="-backend-config=backend.hcl"
  echo "Using GitLab remote state backend"
else
  echo "Using local state backend (terraform.tfstate)"
fi

# ---------------------------------------------------------------------------
# Init and destroy
# ---------------------------------------------------------------------------
echo ""
echo "=== $TF init ==="
# shellcheck disable=SC2086
$TF init -reconfigure $BACKEND_ARGS

echo ""
echo "=== $TF plan -destroy ==="
$TF plan -destroy -out=tfdestroyplan

echo ""
read -rp "Destroy all resources? This cannot be undone. [y/N] " confirm
if [ "${confirm,,}" != "y" ]; then
  echo "Aborted."
  rm -f tfdestroyplan
  exit 0
fi

echo ""
echo "=== $TF apply ==="
$TF apply tfdestroyplan
rm -f tfdestroyplan

echo ""
echo "=== Done — all resources destroyed ==="
