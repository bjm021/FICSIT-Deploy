#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Load credentials and environment
# ---------------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found. Copy .env.example and fill in your values." >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/secure.yaml" ]; then
  echo "ERROR: secure.yaml not found. Add your OpenStack application credentials." >&2
  exit 1
fi
if [ ! -f "$SCRIPT_DIR/terraform.tfvars" ]; then
  echo "ERROR: terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values." >&2
  exit 1
fi

# shellcheck disable=SC1091
. "$SCRIPT_DIR/env.sh"

# ---------------------------------------------------------------------------
# Terraform init → plan → apply
# ---------------------------------------------------------------------------
echo ""
echo "=== terraform init ==="
terraform init -reconfigure

echo ""
echo "=== terraform plan ==="
terraform plan -out=tfplan

echo ""
read -rp "Apply the plan? [y/N] " confirm
if [ "${confirm,,}" != "y" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "=== terraform apply ==="
terraform apply tfplan
rm -f tfplan

echo ""
echo "=== Done ==="
terraform output
