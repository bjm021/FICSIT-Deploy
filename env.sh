#!/bin/sh
# Source this file before running terraform commands:
#   source ./env.sh
#
# Loads credentials from .env and sets all required environment variables
# for the OpenStack provider and GitLab HTTP state backend.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found in $SCRIPT_DIR" >&2
  return 1
fi
# shellcheck disable=SC1091
. "$SCRIPT_DIR/.env"

# --- OpenStack provider ---
export OS_CLIENT_CONFIG_FILE="$SCRIPT_DIR/clouds.yaml"
export OS_CLOUD="openstack"

# --- GitLab HTTP state backend ---
# TF_HTTP_USERNAME can be any non-empty string when using an access token
export TF_HTTP_USERNAME="terraform"
export TF_HTTP_PASSWORD="$GITLAB_PROJECT_ACCESS_TOKEN"

echo "Environment loaded: cloud=openstack, state backend=GitLab (${GITLAB_PROJECT_URL})"
