#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="claude-docker-agent"

# Check container is running
if ! docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null | grep -q running; then
  echo "ERROR: Container '$CONTAINER_NAME' is not running."
  echo "Start it first: bash docker/start.sh"
  exit 1
fi

# Check for Claude auth credentials
if ! docker exec -u agent "$CONTAINER_NAME" sh -c \
    'test -f /home/agent/.claude/credentials.json || test -d /home/agent/.claude/.credentials'; then
  echo "WARNING: No Claude credentials found."
  echo "Run 'bash docker/shell.sh' then 'claude login' to authenticate."
  exit 1
fi

if [ $# -eq 0 ]; then
  # Headed mode (interactive)
  docker exec -it -u agent -w /workspace "$CONTAINER_NAME" claude
else
  # Headless mode
  docker exec -it -u agent -w /workspace "$CONTAINER_NAME" claude --dangerously-skip-permissions -p "$@"
fi
