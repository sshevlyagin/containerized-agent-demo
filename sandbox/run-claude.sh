#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! docker sandbox ls 2>/dev/null | grep -q "$SANDBOX_NAME"; then
  echo "ERROR: Sandbox '$SANDBOX_NAME' is not running."
  echo "Start it first: bash sandbox/start.sh"
  exit 1
fi

if [ $# -eq 0 ]; then
  # Interactive mode — re-attach to sandbox
  docker sandbox run "$SANDBOX_NAME"
else
  # Headless mode
  echo "Running Claude in headless mode..."
  docker sandbox exec -w "$PROJECT_DIR" "$SANDBOX_NAME" claude --dangerously-skip-permissions -p "$@"
fi
