#!/bin/bash
set -euo pipefail

INSTANCE_NAME="claude-agent"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if Claude is authenticated (login data persists in lima/.claude-data/)
if ! limactl shell "$INSTANCE_NAME" bash -c 'test -f "$HOME/.claude/credentials.json"' 2>/dev/null &&
   ! limactl shell "$INSTANCE_NAME" bash -c 'test -f "$HOME/.claude/.credentials.json"' 2>/dev/null &&
   ! limactl shell "$INSTANCE_NAME" bash -c 'test -d "$HOME/.claude/.credentials"' 2>/dev/null &&
   ! limactl shell "$INSTANCE_NAME" bash -c 'test -n "${ANTHROPIC_API_KEY:-}"' 2>/dev/null; then
  echo "No Claude login found. Run 'claude login' first:"
  echo "  bash lima/shell.sh"
  echo "  claude login"
  echo ""
  echo "Your login will persist in lima/.claude-data/ across VM restarts."
  echo ""
fi

if [ $# -eq 0 ]; then
  # Interactive mode — no streaming
  echo "Starting interactive Claude session..."
  limactl shell "$INSTANCE_NAME" bash -c "cd '$PROJECT_DIR' && exec claude"
else
  # Headless mode with session logging
  # Lima mounts host dirs at the same path, so WORKSPACE_DISPLAY_PREFIX = project dir
  WORKSPACE_DISPLAY_PREFIX="$PROJECT_DIR/"
  source "$PROJECT_DIR/common/stream-claude.sh"

  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  CLAUDE_RAW_JSONL="$SESSIONS_DIR/raw-${TIMESTAMP}.jsonl"

  echo "Running Claude in headless mode..."
  echo "📂 Session log: $CLAUDE_RAW_JSONL"
  echo ""

  set +e
  limactl shell "$INSTANCE_NAME" bash -c \
    'cd "$1" && exec claude --dangerously-skip-permissions --output-format stream-json --verbose -p "$2"' \
    -- "$PROJECT_DIR" "$*" 2>&1 | tee "$CLAUDE_RAW_JSONL" | _parse_stream
  CLAUDE_EXIT_CODE=${PIPESTATUS[0]}
  set -e

  echo ""
  generate_session_summary "$CLAUDE_RAW_JSONL"
  exit "${CLAUDE_EXIT_CODE}"
fi
