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

## Container Isolation Approaches

Three approaches for running Claude Code in isolated environments with network restrictions:

- **[Docker-in-Docker](docker/README.md)** — Privileged container with iptables firewall. Full `docker compose up --build` works inside.
- **[Lima VM](lima/README.md)** — macOS hypervisor VM with iptables firewall. Strongest isolation, includes status monitoring server.
- **[Docker Sandbox](sandbox/README.md)** — Docker Desktop AI Sandbox with MITM proxy. Simplest setup, but Docker builds can't make outbound connections.

See the [root README](README.md) for a full comparison table and trade-offs.
