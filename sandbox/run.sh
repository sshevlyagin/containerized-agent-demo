#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"
IMAGE_NAME="order-service-sandbox:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REBUILD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild) REBUILD=true; shift ;;
    --help|-h)
      echo "Usage: $0 [--rebuild]"
      echo "  --rebuild  Remove existing sandbox and recreate from scratch"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Prerequisites ---

if ! command -v docker &>/dev/null; then
  echo "Error: docker CLI not found. Install Docker Desktop 4.58+." >&2
  exit 1
fi

if ! docker sandbox --help &>/dev/null 2>&1; then
  echo "Error: 'docker sandbox' command not available." >&2
  echo "Upgrade to Docker Desktop 4.58+ and enable the Docker AI Sandboxes feature." >&2
  exit 1
fi

# --- Build custom template ---

echo "Building sandbox template image: $IMAGE_NAME ..."
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"

# --- Handle existing sandbox ---

if docker sandbox ls 2>/dev/null | grep -q "$SANDBOX_NAME"; then
  if [[ "$REBUILD" == true ]]; then
    echo "Removing sandbox '$SANDBOX_NAME' for rebuild ..."
    docker sandbox rm "$SANDBOX_NAME" 2>/dev/null || true
  else
    echo "Re-launching existing sandbox '$SANDBOX_NAME' (auth is preserved) ..."
    echo ""
    echo "NOTE: Apply network policy from a separate terminal:"
    echo "  ./sandbox/network-policy.sh"
    echo ""
    docker sandbox run "$SANDBOX_NAME"
    exit 0
  fi
fi

# --- Launch new sandbox ---

echo ""
echo "Creating sandbox '$SANDBOX_NAME' ..."
echo "Project directory: $PROJECT_DIR"
echo ""
echo "First run will walk you through Claude login/onboarding."
echo ""
echo "NOTE: Apply network policy from a separate terminal:"
echo "  ./sandbox/network-policy.sh"
echo ""

docker sandbox run \
  -t "$IMAGE_NAME" \
  --name "$SANDBOX_NAME" \
  claude "$PROJECT_DIR"
