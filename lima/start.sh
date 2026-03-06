#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTANCE_NAME="claude-agent"

# Check if Lima is installed
if ! command -v limactl &>/dev/null; then
  echo "Error: limactl is not installed. Install Lima first: brew install lima" >&2
  exit 1
fi

# Ensure persistent Claude data directory exists on host
mkdir -p "$SCRIPT_DIR/.claude-data"

# Build mount flags — always mount project dir writable
MOUNT_FLAGS=("--mount=${PROJECT_DIR}:w")

# If this is a git worktree, also mount the parent .git dir so git works inside the VM
if [ -f "$PROJECT_DIR/.git" ]; then
  GIT_DIR=$(sed 's/^gitdir: //' "$PROJECT_DIR/.git")
  # Resolve to the top-level .git directory (strip /worktrees/<name>)
  GIT_COMMON_DIR=$(cd "$GIT_DIR" && git rev-parse --git-common-dir 2>/dev/null) || true
  if [ -n "$GIT_COMMON_DIR" ] && [ -d "$GIT_COMMON_DIR" ]; then
    GIT_COMMON_DIR=$(cd "$GIT_DIR" && cd "$GIT_COMMON_DIR" && pwd)
    echo "Detected git worktree, mounting $GIT_COMMON_DIR (read-only)"
    MOUNT_FLAGS+=("--mount=${GIT_COMMON_DIR}:ro")
  fi
fi

# Check if instance already exists by looking for its directory
if [ -d "$HOME/.lima/$INSTANCE_NAME" ]; then
  STATUS=$(limactl list --json 2>/dev/null | jq -r --arg name "$INSTANCE_NAME" '.[] | select(.name == $name) | .status // empty' 2>/dev/null || echo "")
  if [ "$STATUS" = "Running" ]; then
    echo "Instance '$INSTANCE_NAME' is already running."
    exit 0
  fi
  echo "Starting existing instance '$INSTANCE_NAME'..."
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    limactl start "$INSTANCE_NAME" --set ".env.ANTHROPIC_API_KEY = \"$ANTHROPIC_API_KEY\""
  else
    limactl start "$INSTANCE_NAME"
  fi
else
  echo "Creating and starting instance '$INSTANCE_NAME'..."
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    limactl create "$SCRIPT_DIR/claude-agent.yaml" \
      --name="$INSTANCE_NAME" \
      "${MOUNT_FLAGS[@]}" \
      --set ".env.ANTHROPIC_API_KEY = \"$ANTHROPIC_API_KEY\""
  else
    limactl create "$SCRIPT_DIR/claude-agent.yaml" \
      --name="$INSTANCE_NAME" \
      "${MOUNT_FLAGS[@]}"
  fi
  limactl start "$INSTANCE_NAME"
fi

echo ""
echo "Instance '$INSTANCE_NAME' is ready."
echo "  Shell:  bash lima/shell.sh"
echo "  Claude: bash lima/run-claude.sh"
echo "  Stop:   bash lima/stop.sh"
