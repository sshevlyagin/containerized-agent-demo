#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"

echo "Applying deny-by-default network policy to sandbox '$SANDBOX_NAME' ..."
echo ""

docker sandbox network proxy "$SANDBOX_NAME" \
  --policy deny \
  --allow-host "*.anthropic.com" \
  --allow-host "platform.claude.com" \
  --allow-host "*.npmjs.org" \
  --allow-host "*.nodesource.com" \
  --allow-host "*.docker.io" \
  --allow-host "*.docker.com" \
  --allow-host "*.cloudflarestorage.com" \
  --allow-host "github.com" \
  --allow-host "*.github.com" \
  --allow-host "*.githubusercontent.com"

echo ""
echo "Network policy applied. Only the following hosts are allowed:"
echo "  *.anthropic.com, platform.claude.com   — Claude API"
echo "  *.npmjs.org                            — npm registry"
echo "  *.nodesource.com                       — Node.js packages"
echo "  *.docker.io, *.docker.com,             — Docker Hub"
echo "  *.cloudflarestorage.com"
echo "  github.com, *.github.com,              — Git operations"
echo "  *.githubusercontent.com"
echo ""
echo "View network logs: docker sandbox network log $SANDBOX_NAME"
