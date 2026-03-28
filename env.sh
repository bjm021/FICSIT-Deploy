#!/bin/sh
# Source this file before running terraform commands:
#   source ./env.sh
#
# Points the OpenStack provider at the clouds.yaml in this directory.
# secure.yaml is automatically merged from the same directory.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export OS_CLIENT_CONFIG_FILE="$SCRIPT_DIR/clouds.yaml"
export OS_CLOUD="openstack"

echo "OpenStack env set: cloud=openstack, config=$SCRIPT_DIR/clouds.yaml"
