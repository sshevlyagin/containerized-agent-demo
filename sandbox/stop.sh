#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"

if docker sandbox ls 2>/dev/null | grep -q "$SANDBOX_NAME"; then
  echo "Removing sandbox '$SANDBOX_NAME' ..."
  docker sandbox rm "$SANDBOX_NAME"
  echo "Done."
else
  echo "No sandbox named '$SANDBOX_NAME' found."
fi
