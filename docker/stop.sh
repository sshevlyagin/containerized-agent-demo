#!/usr/bin/env bash
set -euo pipefail

docker stop claude-docker-agent
echo "Container stopped. Run 'bash docker/start.sh' to restart."
