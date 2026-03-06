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
./sandbox/run.sh

# Terminal 2 — apply network restrictions
./sandbox/network-policy.sh
```

Auth is persisted in the sandbox VM so you only need to log in once.

## Scripts

| Script | Description |
|--------|-------------|
| `sandbox/run.sh` | Build template + create/launch sandbox |
| `sandbox/run.sh --rebuild` | Rebuild from scratch (loses auth) |
| `sandbox/network-policy.sh` | Apply deny-by-default network policy |
| `sandbox/test.sh` | Run integration tests inside the sandbox |

## What Claude Can Do Inside the Sandbox

- Edit source files (changes sync back to the host)
- Run `bash sandbox/test.sh` to run the full integration test suite via `docker compose up --build`
- Run Docker builds and compose stacks (proxy CA cert is injected automatically)
- Run `pnpm install`, `pnpm build`, `pnpm start` natively on the sandbox VM

## Sending Prompts to the Sandbox

From the host, use `docker sandbox exec` to run Claude non-interactively:

```bash
docker sandbox exec -w /path/to/project claude-order-service \
  claude --dangerously-skip-permissions -p 'Your prompt here'
```

## Network Policy

The MITM proxy blocks all traffic by default. Allowed hosts:

| Host Pattern | Reason |
|---|---|
| `*.anthropic.com`, `platform.claude.com` | Claude API |
| `*.npmjs.org` | npm registry |
| `*.nodesource.com` | Node.js packages |
| `*.docker.io`, `*.docker.com`, `*.cloudflarestorage.com` | Docker Hub |
| `github.com`, `*.github.com`, `*.githubusercontent.com` | Git operations |

View network logs: `docker sandbox network log claude-order-service`

## Docker Builds Inside the Sandbox

Docker build `RUN` steps inside the sandbox go through Docker Desktop's MITM proxy. The `sandbox/Dockerfile` configures Docker to route through the proxy, and `sandbox/test.sh` injects the proxy's CA cert into the build context so HTTPS connections succeed.

This means `docker compose up --build` works — `sandbox/test.sh` handles the proxy cert injection and cleanup automatically.

For detailed analysis of the sandbox networking, see:
- [NETWORK-NOTES.md](NETWORK-NOTES.md) — architecture and what works vs. what doesn't
- [BUG-REPORT.md](BUG-REPORT.md) — reproduction steps and workaround details

## Auth Persistence

- Auth is stored inside the sandbox VM at `~/.claude` and persists across `docker sandbox run` calls
- `docker sandbox run` does NOT support `-v` volume mounts — there is no way to mount an external volume for auth
- **Don't `docker sandbox rm`** unless you want to lose the login. Use `./sandbox/run.sh --rebuild` only when the template changes

## Platform Notes

- Sandbox runs Linux on the host architecture (ARM on Apple Silicon)
- Host `node_modules` (macOS) contain wrong Prisma engine binaries — always `rm -rf node_modules` before `pnpm install` inside the sandbox
- The base image ships Node 20; the sandbox Dockerfile installs Node 22 via nodesource
- AWS CLI must be the `aarch64` variant on Apple Silicon

## Teardown

```bash
docker sandbox rm claude-order-service
```
