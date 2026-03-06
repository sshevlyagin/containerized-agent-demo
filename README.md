# Containerized Claude Code Agent Demo

Three approaches to running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) in isolated containers with network restrictions, each with different trade-offs for security, portability, and capability.

## The Demo Workload

A Node.js/TypeScript **order service** — Express 5 REST API backed by Postgres and SQS (via LocalStack). The full stack runs via Docker Compose with automated integration tests. Claude works inside the container to edit code, run builds, execute tests, and iterate — all within a network-restricted environment.

```bash
docker compose up --build    # start full stack
# Watch for "ALL TESTS PASSED" in test-executor logs
docker compose down -v       # teardown
```

## Three Isolation Approaches

### 1. [Docker-in-Docker](docker/) — Privileged container with iptables firewall

Claude runs inside a privileged Docker container that has its own Docker daemon. The full `docker compose up --build` workflow works inside the container. Network is locked down via iptables + ipset allowlisting individual domain IPs.

```bash
bash docker/start.sh          # build + start
bash docker/run-claude.sh     # interactive Claude
bash docker/stop.sh           # stop
```

### 2. [Lima VM](lima/) — Full VM with iptables firewall

Claude runs inside a Lima VM (macOS hypervisor). Like Docker-in-Docker, but with stronger isolation through a full VM boundary. Includes a status monitoring HTTP server for headless operation.

```bash
bash lima/start.sh             # create/start VM (~5 min first time)
bash lima/run-claude.sh        # interactive Claude
bash lima/stop.sh              # stop
```

### 3. [Docker Sandbox](sandbox/) — Docker Desktop AI Sandbox with MITM proxy

Claude runs inside a Docker Desktop AI Sandbox — a lightweight microVM managed by Docker Desktop. Network is controlled via a MITM proxy with hostname-based rules. Docker builds work via a proxy workaround that injects the MITM CA cert into the build context.

```bash
./sandbox/run.sh               # create + launch sandbox
./sandbox/network-policy.sh    # apply network restrictions (separate terminal)
```

## Comparison

| Aspect | Docker-in-Docker | Lima VM | Docker Sandbox |
|--------|-----------------|---------|----------------|
| Isolation | Privileged container | Full VM (hypervisor) | MicroVM (Docker Desktop) |
| Network control | iptables + ipset | iptables + ipset | MITM proxy |
| Docker builds inside | Yes | Yes | Yes (proxy workaround) |
| Auth persistence | Volume mount `docker/.claude-data/` | Symlink `lima/.claude-data/` | Inside sandbox VM |
| Status monitoring | None | HTTP server (port 8080) | None |
| Host requirements | Docker (any OS) | macOS + Lima | Docker Desktop 4.58+ |
| License | Open source | Open source (CNCF) | Docker Desktop license |
| Security model | `--privileged` + firewall | VM boundary + firewall | VM boundary + proxy |
| Headless flag | `--dangerously-skip-permissions` | `--allowedTools` | `--dangerously-skip-permissions` |
| Git worktrees | Yes (auto-detected) | Yes (auto-detected) | Yes (auto-detected) |
| Allowed domains | 21 (individual) | 18 (individual) | 14 (wildcard patterns) |

## Trade-offs

**Docker-in-Docker** is the most portable (runs anywhere Docker runs) and the most capable (full `docker compose up --build` works). The trade-off is security: `--privileged` gives the container full host capabilities, so the iptables firewall is the only barrier. Best for trusted environments where you want full Docker functionality.

**Lima VM** provides the strongest isolation via a real hypervisor boundary *and* an iptables firewall inside the VM. The trade-off is macOS-only and slower startup (~5 min first boot). The status server is unique to this approach and useful for monitoring headless Claude sessions. Best for macOS users who want defense-in-depth.

**Docker Sandbox** offers the simplest setup (one command) and a managed security model via Docker Desktop's MITM proxy. Docker builds work via a proxy workaround: `sandbox/test.sh` injects the MITM proxy's CA cert into the build context so HTTPS connections in `RUN` steps succeed. Best for teams already using Docker Desktop who want managed isolation with minimal configuration.

## Shared Infrastructure

All approaches use the same underlying order-service application and can share:

- **`docker-compose.infra.yml`** — Postgres + LocalStack only (no app container), for local development or sandbox use
- **`scripts/create-queue.sh`** — Create the SQS queue in LocalStack
- **`scripts/seed-messages.sh`** — Send sample order messages to the queue
- **`.env.example`** — Default environment variable template

```bash
# Start just the infrastructure
docker compose -f docker-compose.infra.yml up -d --wait
./scripts/create-queue.sh

# Run the app natively
cp .env.example .env
pnpm install
pnpm prisma generate
pnpm migrate:deploy
pnpm dev
```
