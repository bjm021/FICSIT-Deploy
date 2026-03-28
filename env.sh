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

# GitLab HTTP state backend credentials
export TF_HTTP_USERNAME="oauth2"
export TF_HTTP_PASSWORD="$GITLAB_PROJECT_ACCESS_TOKEN"

echo "Environment loaded: OpenStack=${OS_AUTH_URL}, state backend=${GITLAB_PROJECT_URL}"
