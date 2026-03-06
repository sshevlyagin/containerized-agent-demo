#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="claude-docker-agent"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$PROJECT_DIR/docker/.claude-data"

# Detect git worktree — if .git is a file, resolve the common git dir and mount it
EXTRA_MOUNTS=()
if [ -f "$PROJECT_DIR/.git" ]; then
  GIT_DIR=$(sed 's/^gitdir: //' "$PROJECT_DIR/.git")
  GIT_COMMON_DIR=$(cd "$GIT_DIR" && git rev-parse --git-common-dir 2>/dev/null) || true
  if [ -n "$GIT_COMMON_DIR" ] && [ -d "$GIT_COMMON_DIR" ]; then
    GIT_COMMON_DIR=$(cd "$GIT_DIR" && cd "$GIT_COMMON_DIR" && pwd)
    echo "Detected git worktree, mounting $GIT_COMMON_DIR (read-only)"
    EXTRA_MOUNTS+=(-v "$GIT_COMMON_DIR:$GIT_COMMON_DIR:ro")
  fi
fi

# Check if container already exists
if docker container inspect "$CONTAINER_NAME" &>/dev/null; then
  STATE=$(docker container inspect -f '{{.State.Status}}' "$CONTAINER_NAME")
  if [ "$STATE" = "running" ]; then
    echo "Container '$CONTAINER_NAME' is already running."
    echo "Use docker/shell.sh to get a shell, or docker/run-claude.sh to start Claude."
    exit 0
  else
    echo "Container '$CONTAINER_NAME' exists but is stopped. Restarting..."
    docker start "$CONTAINER_NAME"
  fi
else
  echo "==> Building Docker image..."
  docker build -t claude-docker-agent "$PROJECT_DIR/docker"

  echo "==> Starting container..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    --privileged \
    -v "$PROJECT_DIR:/workspace" \
    -v "$PROJECT_DIR/docker/.claude-data:/home/agent/.claude" \
    -v claude-docker-agent-dind:/var/lib/docker \
    ${EXTRA_MOUNTS[@]+"${EXTRA_MOUNTS[@]}"} \
    ${ANTHROPIC_API_KEY:+-e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"} \
    claude-docker-agent
fi

# Wait for inner dockerd to be ready (up to 60s)
echo "==> Waiting for inner dockerd..."
timeout=60
elapsed=0
while ! docker exec "$CONTAINER_NAME" docker info &>/dev/null; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "ERROR: Inner dockerd failed to start within ${timeout}s"
    docker logs "$CONTAINER_NAME"
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
echo "==> Inner dockerd ready (${elapsed}s)"

echo ""
echo "============================================"
echo " Claude Docker Agent is running!"
echo "============================================"
echo ""
echo "  Shell:          bash docker/shell.sh"
echo "  Claude (headed): bash docker/run-claude.sh"
echo "  Claude (headless): bash docker/run-claude.sh \"your prompt here\""
echo "  Stop:           bash docker/stop.sh"
echo ""
