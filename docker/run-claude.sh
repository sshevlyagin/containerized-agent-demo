#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="claude-docker-agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check container is running
if ! docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null | grep -q running; then
  echo "ERROR: Container '$CONTAINER_NAME' is not running."
  echo "Start it first: bash docker/start.sh"
  exit 1
fi

# Check for Claude auth credentials
if ! docker exec -u agent "$CONTAINER_NAME" sh -c \
    'test -f /home/agent/.claude/credentials.json || test -f /home/agent/.claude/.credentials.json || test -d /home/agent/.claude/.credentials || test -n "${ANTHROPIC_API_KEY:-}"'; then
  echo "WARNING: No Claude credentials found."
  echo "Run 'bash docker/shell.sh' then 'claude login' to authenticate."
  exit 1
fi

if [ $# -eq 0 ]; then
  # Headed mode (interactive TUI) — no streaming
  docker exec -it -u agent -w /workspace "$CONTAINER_NAME" claude
else
  # Headless mode with session logging
  WORKSPACE_DISPLAY_PREFIX="/workspace/"
  source "$PROJECT_DIR/common/stream-claude.sh"

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  CLAUDE_RAW_JSONL="$SESSIONS_DIR/raw-${TIMESTAMP}.jsonl"

  echo "📂 Session log: $CLAUDE_RAW_JSONL"
  echo ""

  set +e
  docker exec -u agent -w /workspace "$CONTAINER_NAME" \
    claude --dangerously-skip-permissions \
    --output-format stream-json --verbose \
    -p "$@" 2>&1 | tee "$CLAUDE_RAW_JSONL" | _parse_stream
  CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
  set -e

  echo ""
  generate_session_summary "$CLAUDE_RAW_JSONL"
  exit "${CLAUDE_EXIT_CODE}"
fi
