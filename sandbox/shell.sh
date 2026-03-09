#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"

if ! docker sandbox ls 2>/dev/null | grep -q "$SANDBOX_NAME"; then
  echo "ERROR: Sandbox '$SANDBOX_NAME' is not running."
  echo "Start it first: bash sandbox/start.sh"
  exit 1
fi

docker sandbox exec -it "$SANDBOX_NAME" bash
