#!/usr/bin/env bash
set -euo pipefail

SANDBOX_NAME="claude-order-service"

echo "Applying deny-by-default network policy to sandbox '$SANDBOX_NAME' ..."
echo ""

docker sandbox network proxy "$SANDBOX_NAME" \
  --policy deny \
  --allow-host "*.anthropic.com" \
  --allow-host "platform.claude.com" \
  --allow-host "claude.ai" \
  --allow-host "sentry.io" \
  --allow-host "*.npmjs.org" \
  --allow-host "*.nodesource.com" \
  --allow-host "*.docker.io" \
  --allow-host "*.docker.com" \
  --allow-host "*.cloudflarestorage.com" \
  --allow-host "github.com" \
  --allow-host "*.github.com" \
  --allow-host "*.githubusercontent.com" \
  --allow-host "storage.googleapis.com" \
  --allow-host "deb.debian.org" \
  --allow-host "cdn.amazonlinux.com" \
  --allow-host "host.docker.internal" \
  --allow-host "*.prisma.sh"

echo ""
echo "Network policy applied. Only the following hosts are allowed:"
echo "  *.anthropic.com, platform.claude.com,  — Claude API + auth"
echo "  claude.ai, sentry.io"
echo "  *.npmjs.org                            — npm registry"
echo "  *.nodesource.com                       — Node.js packages"
echo "  *.docker.io, *.docker.com,             — Docker Hub"
echo "  *.cloudflarestorage.com"
echo "  github.com, *.github.com,              — Git operations"
echo "  *.githubusercontent.com"
echo "  storage.googleapis.com                 — Cloud storage"
echo "  deb.debian.org                         — Debian packages (Docker builds)"
echo "  cdn.amazonlinux.com                    — Amazon Linux packages (Docker builds)"
echo "  host.docker.internal                   — Docker proxy for builds"
echo "  *.prisma.sh                            — Prisma engine binaries"
echo ""
echo "View network logs: docker sandbox network log $SANDBOX_NAME"
