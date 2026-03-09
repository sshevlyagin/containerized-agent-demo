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
  # Interactive mode — re-attach to sandbox (no streaming)
  docker sandbox run "$SANDBOX_NAME"
else
  # Headless mode with session logging
  WORKSPACE_DISPLAY_PREFIX="$PROJECT_DIR/"
  source "$PROJECT_DIR/common/stream-claude.sh"

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  CLAUDE_RAW_JSONL="$SESSIONS_DIR/raw-${TIMESTAMP}.jsonl"

  echo "Running Claude in headless mode..."
  echo "📂 Session log: $CLAUDE_RAW_JSONL"
  echo ""

  set +e
  docker sandbox exec -w "$PROJECT_DIR" "$SANDBOX_NAME" \
    claude --dangerously-skip-permissions \
    --output-format stream-json --verbose \
    -p "$@" 2>&1 | tee "$CLAUDE_RAW_JSONL" | _parse_stream
  CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
  set -e

  echo ""
  generate_session_summary "$CLAUDE_RAW_JSONL"
  exit "${CLAUDE_EXIT_CODE}"
fi
