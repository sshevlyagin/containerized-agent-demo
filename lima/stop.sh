#!/bin/bash
set -euo pipefail

INSTANCE_NAME="claude-agent"

if ! limactl list --json 2>/dev/null | jq -e ".[] | select(.name == \"$INSTANCE_NAME\")" &>/dev/null; then
  echo "Instance '$INSTANCE_NAME' does not exist."
  exit 0
fi

echo "Stopping instance '$INSTANCE_NAME'..."
limactl stop "$INSTANCE_NAME"
echo "Instance '$INSTANCE_NAME' stopped."
