#!/bin/bash
set -euo pipefail

INSTANCE_NAME="claude-agent"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if Claude is authenticated (login data persists in lima/.claude-data/)
if ! limactl shell "$INSTANCE_NAME" test -f "\$HOME/.claude/credentials.json" 2>/dev/null &&
   ! limactl shell "$INSTANCE_NAME" test -d "\$HOME/.claude/.credentials" 2>/dev/null; then
  echo "No Claude login found. Run 'claude login' first:"
  echo "  bash lima/shell.sh"
  echo "  claude login"
  echo ""
  echo "Your login will persist in lima/.claude-data/ across VM restarts."
  echo ""
fi

if [ $# -eq 0 ]; then
  # Interactive mode
  echo "Starting interactive Claude session..."
  limactl shell "$INSTANCE_NAME" bash -c "cd '$PROJECT_DIR' && exec claude"
else
  # Headless mode — pass all arguments as a prompt
  echo "Running Claude in headless mode..."
  limactl shell "$INSTANCE_NAME" bash -c 'cd "$1" && exec claude -p "$2"' -- "$PROJECT_DIR" "$*"
fi
