#!/bin/bash
set -euo pipefail

INSTANCE_NAME="claude-agent"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

limactl shell "$INSTANCE_NAME" bash -c "cd '$PROJECT_DIR' && exec bash --login"
