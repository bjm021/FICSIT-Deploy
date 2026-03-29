#!/bin/sh
# Source this file before running tofu commands:
#   source ./env.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found in $SCRIPT_DIR" >&2
  return 1
fi

# Export every variable defined in .env
set -a
# shellcheck disable=SC1091
. "$SCRIPT_DIR/.env"
set +a

# GitLab HTTP state backend credentials (only used when STATE_BACKEND=gitlab)
if [ "${STATE_BACKEND:-gitlab}" = "gitlab" ]; then
  export TF_HTTP_PASSWORD="$GITLAB_PROJECT_ACCESS_TOKEN"
fi

# Pass sensitive vars to OpenTofu without putting them in terraform.tfvars
export TF_VAR_sf_admin_password="$SF_ADMIN_PASSWORD"
export TF_VAR_r2_account_id="$R2_ACCOUNT_ID"
export TF_VAR_r2_access_key_id="$R2_ACCESS_KEY_ID"
export TF_VAR_r2_secret_access_key="$R2_SECRET_ACCESS_KEY"
export TF_VAR_r2_jurisdiction="${R2_JURISDICTION:-}"

BACKEND_INFO="${STATE_BACKEND:-gitlab}"
if [ "$BACKEND_INFO" = "gitlab" ]; then
  BACKEND_INFO="gitlab (${GITLAB_PROJECT_URL})"
fi
echo "Environment loaded: OpenStack=${OS_AUTH_URL}, state backend=${BACKEND_INFO}"
