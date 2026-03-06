# Docker Sandbox Isolation

Runs Claude Code inside a **Docker Desktop AI Sandbox** — a lightweight microVM managed by Docker Desktop with built-in MITM proxy for network control.

## How It Works

1. Docker Desktop creates a microVM (AI Sandbox) from a custom template image
2. The host project directory is synced into the sandbox via virtiofs
3. Network is restricted via a MITM proxy with hostname-based allowlisting
4. Claude Code runs inside the sandbox VM and can edit files, run native tools, and use Docker for infrastructure
5. Auth persists inside the sandbox VM across runs

## Prerequisites

- Docker Desktop 4.58+ with [Docker AI Sandboxes](https://docs.docker.com/ai/sandboxes/) enabled
- Claude Enterprise account (auth via `claude login`)

## Quick Start

```bash
# Terminal 1 — launch the sandbox (interactive, blocks)
# First run will walk you through Claude login/onboarding
bash sandbox/start.sh

# Terminal 2 — apply network restrictions
bash sandbox/network-policy.sh
```

Auth is persisted in the sandbox VM so you only need to log in once.

## Scripts

| Script | Description |
|--------|-------------|
| `sandbox/start.sh` | Build template + create/launch sandbox |
| `sandbox/start.sh --rebuild` | Rebuild from scratch (loses auth) |
| `sandbox/stop.sh` | Remove the sandbox |
| `sandbox/shell.sh` | Interactive bash shell inside the sandbox |
| `sandbox/run-claude.sh` | Interactive Claude (no args) or headless mode (with prompt) |
| `sandbox/network-policy.sh` | Apply deny-by-default network policy |
| `sandbox/test.sh` | Run integration tests inside the sandbox |

## What Claude Can Do Inside the Sandbox

- Edit source files (changes sync back to the host)
- Run `bash sandbox/test.sh` to run the full integration test suite via `docker compose up --build`
- Run Docker builds and compose stacks (proxy CA cert is injected automatically)
- Run `pnpm install`, `pnpm build`, `pnpm start` natively on the sandbox VM

## Headless Mode

Run Claude non-interactively from the host:

```bash
bash sandbox/run-claude.sh 'Fix the failing test in orders.ts'
```

This uses `--dangerously-skip-permissions` to allow Claude to execute without interactive approval.

## Network Policy

The MITM proxy blocks all traffic by default. Allowed hosts:

| Host Pattern | Reason |
|---|---|
| `*.anthropic.com`, `platform.claude.com`, `claude.ai` | Claude API + auth |
| `sentry.io` | Error tracking |
| `*.npmjs.org` | npm registry |
| `*.nodesource.com` | Node.js packages |
| `*.docker.io`, `*.docker.com`, `*.cloudflarestorage.com` | Docker Hub |
| `github.com`, `*.github.com`, `*.githubusercontent.com` | Git operations |
| `storage.googleapis.com` | Cloud storage |
| `deb.debian.org` | Debian packages (Docker builds) |
| `cdn.amazonlinux.com` | Amazon Linux packages (Docker builds) |
| `host.docker.internal` | Docker proxy for builds |
| `*.prisma.sh` | Prisma engine binaries |

View network logs: `docker sandbox network log claude-order-service`

## Networking Architecture

Docker AI Sandboxes have two distinct network contexts:

1. **Sandbox VM** — the outer VM where Claude Code and native processes (pnpm, curl, node) run
2. **Docker-in-Docker containers** — containers launched by the inner Docker daemon (via `docker compose`, `docker run`, etc.)

`docker sandbox network proxy` applies a MITM proxy at the VM level. Native processes on the VM go through the proxy and respect the network policy. However, Docker build `RUN` steps inside the sandbox don't automatically inherit proxy configuration.

### What works without extra configuration

- `pnpm install`, `pnpm build`, `node dist/index.js` (native on VM)
- `curl` to allowed external hosts (native on VM)
- `docker pull` (image pulls from registries)
- `docker compose up` with pre-built images
- Inter-container networking (e.g. `order-service` → `postgres`)

### Docker builds (requires proxy workaround)

Docker build `RUN` steps (e.g. `apt-get update`, `npm install`) cannot make outbound connections by default. The sandbox proxy only routes registry traffic for image pulls — build containers use a separate bridge network with no outbound access.

**Workaround** (handled automatically by `sandbox/test.sh`):

1. The `sandbox/Dockerfile` configures `~/.docker/config.json` with proxy settings pointing to `host.docker.internal:3128`
2. `sandbox/test.sh` copies the sandbox MITM proxy's CA cert into the build context
3. A `docker-compose.override.yml` injects `HTTP_PROXY`/`HTTPS_PROXY` as build args and clears them for running containers (so they use Docker compose internal networking)

This means `docker compose up --build` works — `sandbox/test.sh` handles the proxy cert injection and cleanup automatically.

## Git Worktree Support

When launched from a git worktree, `sandbox/start.sh` automatically detects the worktree and mounts the common git directory as a read-only [additional workspace](https://docs.docker.com/ai/sandboxes/workflows/#multiple-workspaces). This allows git commands to work normally inside the sandbox.

## Auth Persistence

- Auth is stored inside the sandbox VM at `~/.claude` and persists across `docker sandbox run` calls
- `docker sandbox run` does NOT support `-v` volume mounts — there is no way to mount an external volume for auth
- **Don't `docker sandbox rm`** unless you want to lose the login. Use `bash sandbox/start.sh --rebuild` only when the template changes

## Platform Notes

- Sandbox runs Linux on the host architecture (ARM on Apple Silicon)
- Host `node_modules` (macOS) contain wrong Prisma engine binaries — always `rm -rf node_modules` before `pnpm install` inside the sandbox
- The base image ships Node 20; the sandbox Dockerfile installs Node 22 via nodesource
- AWS CLI must be the `aarch64` variant on Apple Silicon

## Teardown

```bash
bash sandbox/stop.sh
```
