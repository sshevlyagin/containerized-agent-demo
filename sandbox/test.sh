#!/usr/bin/env bash
#
# Runs the full integration test inside the Docker sandbox.
#
# Uses docker compose up --build with proxy CA cert handling.
# The sandbox's MITM proxy intercepts HTTPS, so Docker build steps
# need the proxy's CA cert to validate connections.
#
# 1. Copies the proxy CA cert into the build context
# 2. Creates a compose override to clear proxy env vars for running containers
# 3. Runs docker compose up --build --abort-on-container-exit
# 4. Cleans up
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

cleanup() {
  echo ""
  echo "Cleaning up ..."
  docker compose down -v 2>/dev/null || true
  # Restore empty placeholder certs
  : > "$PROJECT_DIR/proxy-ca.crt"
  : > "$PROJECT_DIR/test/proxy-ca.crt"
  # Remove compose override
  rm -f "$PROJECT_DIR/docker-compose.override.yml"
}
trap cleanup EXIT

# --- Copy real proxy CA cert into build context ---
PROXY_CA="/usr/local/share/ca-certificates/proxy-ca.crt"
if [ -f "$PROXY_CA" ] && [ -s "$PROXY_CA" ]; then
  echo "Copying proxy CA cert into build context ..."
  cp "$PROXY_CA" "$PROJECT_DIR/proxy-ca.crt"
  cp "$PROXY_CA" "$PROJECT_DIR/test/proxy-ca.crt"
else
  echo "WARNING: No proxy CA cert found at $PROXY_CA — builds may fail if behind MITM proxy"
fi

# --- Create compose override to clear proxy env for running containers ---
# Inter-container traffic goes over the Docker bridge, not through the proxy.
cat > "$PROJECT_DIR/docker-compose.override.yml" <<'EOF'
services:
  order-service:
    environment:
      - http_proxy=
      - https_proxy=
      - HTTP_PROXY=
      - HTTPS_PROXY=
  test-executor:
    environment:
      - http_proxy=
      - https_proxy=
      - HTTP_PROXY=
      - HTTPS_PROXY=
EOF

echo "Running docker compose up --build ..."
docker compose up --build --abort-on-container-exit --exit-code-from test-executor
