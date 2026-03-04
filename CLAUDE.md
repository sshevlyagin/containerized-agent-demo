# Order Service

## Stack
- Node 22, TypeScript 5, Express 5
- Postgres 18 (via Prisma)
- SQS (LocalStack)
- pnpm

## Running with Docker Compose

```bash
docker compose up --build
```

This starts 4 services:
- **postgres** — database on port 5432
- **localstack** — SQS mock on port 4566
- **order-service** — app on port 3000 (waits for postgres + localstack healthy)
- **test-executor** — runs integration tests then exits

Watch test-executor logs for `ALL TESTS PASSED`.

## Teardown

```bash
docker compose down -v
```

## Local Development

```bash
nvm use
pnpm install
pnpm dev
```

Requires a running Postgres and LocalStack (see `.env` for connection defaults).

## Key Commands

- `pnpm build` — compile TypeScript
- `pnpm start` — run compiled app
- `pnpm migrate:deploy` — apply Prisma migrations
- `pnpm prisma generate` — regenerate Prisma client
