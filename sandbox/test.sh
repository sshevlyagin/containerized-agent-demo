#!/usr/bin/env bash
#
# Runs the full integration test inside the Docker sandbox.
#
# Because Docker build RUN steps have no outbound network inside
# AI Sandboxes (see BUG-REPORT.md), this script runs the app
# natively on the sandbox VM and uses Docker only for infrastructure.
#
# 1. Starts postgres + localstack via docker compose
# 2. Installs deps, builds, migrates, and starts the app on the host
# 3. Runs the integration test script
# 4. Cleans up
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

APP_PID=""
cleanup() {
  echo ""
  echo "Cleaning up ..."
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true
  docker compose -f docker-compose.infra.yml down -v 2>/dev/null || true
}
trap cleanup EXIT

# --- Start infrastructure ---

echo "Starting postgres and localstack ..."
docker compose -f docker-compose.infra.yml up -d --wait

# --- Environment ---

export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/orders"
export SQS_ENDPOINT="http://localhost:4566"
export SQS_QUEUE_URL="http://localhost:4566/000000000000/orders"
export AWS_REGION="us-east-1"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export PORT="3000"

# --- Install, build, migrate ---

rm -rf node_modules
pnpm install
pnpm prisma generate
pnpm build

# Apply migrations directly via psql inside the postgres container
POSTGRES_CONTAINER=$(docker compose -f docker-compose.infra.yml ps -q postgres | head -1)
echo "Applying database migrations via psql ..."
for migration_sql in prisma/migrations/*/migration.sql; do
  echo "  -> $migration_sql"
  docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -d orders < "$migration_sql"
done

node dist/index.js &
APP_PID=$!

# --- Run tests ---

ORDER_SERVICE_URL="http://localhost:3000" \
SQS_ENDPOINT="http://localhost:4566" \
  bash test/test-executor.sh
