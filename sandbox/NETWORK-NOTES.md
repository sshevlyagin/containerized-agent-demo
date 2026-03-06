# Docker Sandbox Network Notes

## Architecture

Docker AI Sandboxes run a lightweight VM (microVM) that hosts:
- The sandbox environment (Ubuntu, tools, Claude Code binary)
- A Docker daemon (Docker-in-Docker) for running containers

There are two distinct network contexts:
1. **Sandbox VM** -- the outer VM where Claude Code and native processes run
2. **Docker-in-Docker containers** -- containers launched by the inner Docker daemon (via `docker compose`, `docker run`, etc.)

## Network Policy

`docker sandbox network proxy` applies a MITM proxy to the sandbox VM. It supports:
- `--policy deny|allow` -- default policy
- `--allow-host` / `--block-host` -- hostname-based rules (matched via TLS SNI for HTTPS)
- `--allow-cidr` / `--block-cidr` -- IP-range rules
- `--bypass-host` / `--bypass-cidr` -- skip the MITM proxy entirely

View logs with `docker sandbox network log <sandbox-name>`.

## What Works

| Action | Network Context | Works? |
|---|---|---|
| `pnpm install` (native on VM) | Sandbox VM | Yes |
| `pnpm build`, `node dist/index.js` | Sandbox VM | Yes |
| `curl` to external hosts | Sandbox VM | Yes |
| `docker pull postgres:18` | Docker-in-Docker | Yes |
| `docker pull localstack/localstack` | Docker-in-Docker | Yes |
| `docker compose up` (pre-built images only) | Docker-in-Docker | Yes |
| Inter-container networking (`order-service` -> `postgres`) | Docker-in-Docker | Yes |

## What Doesn't Work

| Action | Network Context | Fails? | Error |
|---|---|---|---|
| `apt-get update` in Dockerfile `RUN` | Docker-in-Docker build | Yes | `Connection refused` to `deb.debian.org:80` |
| `pnpm install` in Dockerfile `RUN` | Docker-in-Docker build | Yes | `ECONNREFUSED` to `registry.npmjs.org:443` |
| `npm install` in Dockerfile `RUN` | Docker-in-Docker build | Yes | Same |
| Any outbound HTTP/HTTPS from `RUN` steps | Docker-in-Docker build | Yes | Connection refused |
| Downloading Prisma engine binaries (`binaries.prisma.sh`) | Docker-in-Docker build | Yes | Blocked |

### Root Cause

Docker build containers inside the sandbox have **no outbound internet access** -- only image pulls from Docker registries work. This is a fundamental sandbox restriction, not a network policy issue:

- Persists even with `--policy allow`
- Persists even with `--bypass-host` or `--allow-cidr` for the target IPs
- Persists even with `docker buildx build --network host`
- `curl` from the sandbox VM to the same hosts succeeds -- confirming the restriction is specific to Docker-in-Docker containers

The sandbox proxy operates at the VM level. The inner Docker daemon uses its own bridge network, and only registry traffic (image pulls) is routed through.

## Workaround

Split the workload between Docker and the sandbox VM:

1. **`docker-compose.infra.yml`** -- runs infrastructure containers that only need pre-built images (postgres, localstack). No `build:` directives.
2. **App runs natively on the VM** -- `pnpm install`, `pnpm build`, `node dist/index.js` all execute directly on the sandbox VM, where outbound internet works normally.
3. **Prisma** -- use `engineType = "client"` (WASM engine) in `schema.prisma` to avoid downloading native engine binaries from `binaries.prisma.sh`. Use `docker exec psql` for migrations instead of `prisma migrate deploy` if the schema engine binary is blocked.

### What This Means for `docker compose up --build`

The standard `docker compose up --build` workflow (which builds app images via Dockerfiles with `RUN apt-get`, `RUN pnpm install`, etc.) **does not work inside a sandbox**. Any Dockerfile that needs network access during build steps will fail.

## Allowed Hosts for Network Policy

These are the hosts needed for the sandbox VM's native processes (Claude Code, pnpm, Docker image pulls):

| Host Pattern | Reason |
|---|---|
| `*.anthropic.com`, `platform.claude.com` | Claude API + Enterprise auth |
| `*.npmjs.org` | npm registry |
| `*.nodesource.com` | Node.js packages |
| `*.docker.io`, `*.docker.com` | Docker Hub (image pulls from VM work) |
| `*.cloudflarestorage.com` | Docker Hub blob storage (Cloudflare R2) |
| `github.com`, `*.github.com`, `*.githubusercontent.com` | Git operations |

## Other Gotchas

- **No `-v` volume mounts** -- `docker sandbox run` does not support `-v`. Auth and state persist inside the sandbox VM as long as you don't `docker sandbox rm`.
- **Platform binaries** -- the sandbox runs Linux on the host architecture (ARM on Apple Silicon). Host `node_modules` (macOS) contain wrong Prisma engine binaries. Always `rm -rf node_modules` before `pnpm install` inside the sandbox.
- **AWS CLI** -- install the `aarch64` variant on Apple Silicon, not `x86_64`.
- **Node.js version** -- the base image (`docker/sandbox-templates:claude-code`) ships Node 20. If your project needs Node 22, install it via nodesource in the sandbox Dockerfile.
