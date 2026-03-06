#!/usr/bin/env bash
set -euo pipefail

echo "==> Starting dockerd..."
dockerd &>/var/log/dockerd.log &

# Wait for Docker to be ready (up to 30s)
timeout=30
elapsed=0
while ! docker info &>/dev/null; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "ERROR: dockerd failed to start within ${timeout}s"
    cat /var/log/dockerd.log
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
echo "==> dockerd ready (${elapsed}s)"

# Set up firewall after dockerd so Docker's iptables chains exist first
echo "==> Setting up firewall..."
/usr/local/bin/setup-firewall.sh

# Start cron for IP refresh
echo "==> Starting cron..."
cron

# Fix ownership so agent user can access workspace and Claude data
# Mark /workspace as safe for git (ownership differs in container)
git config --global --add safe.directory /workspace

echo "==> Setting up agent user permissions..."
chown -R agent:agent /home/agent/.claude 2>/dev/null || true
chown agent:agent /workspace 2>/dev/null || true

echo "==> Container ready. Use docker/shell.sh or docker/run-claude.sh to interact."
exec sleep infinity
