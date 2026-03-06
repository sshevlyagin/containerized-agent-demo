#!/usr/bin/env bash
set -euo pipefail

docker exec -it -u agent -w /workspace claude-docker-agent bash --login
