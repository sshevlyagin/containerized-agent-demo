#!/usr/bin/env bash
#
# Runs the full integration test inside the Docker sandbox.
#
# 1. Copies the sandbox proxy CA cert into the build context
# 2. Creates a compose override with build proxy args + cleared runtime proxy vars
# 3. Runs docker compose up --build --abort-on-container-exit
# 4. Cleans up
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

cleanup() {
  echo ""
  echo "Cleaning up ..."
  # Restore empty proxy cert placeholders
  : > proxy-ca.crt
  : > test/proxy-ca.crt
  # Remove the sandbox compose override
  rm -f docker-compose.override.yml
  docker compose down -v 2>/dev/null || true
}
trap cleanup EXIT

# --- Proxy setup for Docker-in-Docker builds ---
# The sandbox VM routes traffic through a MITM proxy. Build containers
# need proxy env vars to reach the internet (HTTP_PROXY/HTTPS_PROXY as
# build args). Running containers communicate on the Docker compose
# network and must NOT be proxied (cleared via environment).
PROXY_CERT="/usr/local/share/ca-certificates/proxy-ca.crt"
if [ -f "$PROXY_CERT" ] && [ -s "$PROXY_CERT" ]; then
  cp "$PROXY_CERT" proxy-ca.crt
  cp "$PROXY_CERT" test/proxy-ca.crt

  cat > docker-compose.override.yml <<'OVERRIDE'
services:
  order-service:
    build:
      args:
        HTTP_PROXY: http://host.docker.internal:3128
        HTTPS_PROXY: http://host.docker.internal:3128
    environment:
      HTTP_PROXY: ""
      HTTPS_PROXY: ""
      http_proxy: ""
      https_proxy: ""
  test-executor:
    build:
      args:
        HTTP_PROXY: http://host.docker.internal:3128
        HTTPS_PROXY: http://host.docker.internal:3128
    environment:
      HTTP_PROXY: ""
      HTTPS_PROXY: ""
      http_proxy: ""
      https_proxy: ""
OVERRIDE

  echo "Configured proxy CA cert and compose override for Docker builds"
else
  echo "WARNING: No proxy CA cert found at $PROXY_CERT — builds may fail if behind MITM proxy"
fi

# --- Build and run ---
echo "Building and starting all services ..."
docker compose up --build --abort-on-container-exit --exit-code-from test-executor
