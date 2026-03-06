# Docker-in-Docker Isolation

Runs Claude Code inside a **privileged Docker container** with Docker-in-Docker. Claude can `docker compose up --build` the full order-service stack. Network is restricted via iptables + ipset inside the container.

## How It Works

1. A Docker container runs Ubuntu 24.04 with Docker CE, Node.js 22, pnpm, AWS CLI, and Claude Code
2. The host project directory is bind-mounted at `/workspace`
3. An inner Docker daemon runs inside the container (Docker-in-Docker)
4. iptables + ipset restrict outbound traffic to an allowlist of domains
5. Claude Code runs inside the container and can build/run the full compose stack

## Prerequisites

- Docker Desktop (or Docker CE with Docker Compose plugin)
- `ANTHROPIC_API_KEY` env var set, or authenticate interactively via `claude login`

## Quick Start

```bash
bash docker/start.sh          # Build image + start container
bash docker/run-claude.sh     # Interactive Claude session
bash docker/stop.sh           # Stop container
```

## Scripts

| Script | Description |
|--------|-------------|
| `docker/start.sh` | Build image + start container (idempotent) |
| `docker/stop.sh` | Stop the container |
| `docker/shell.sh` | Get a bash shell inside the container |
| `docker/run-claude.sh` | Launch Claude (headed mode) |
| `docker/run-claude.sh "prompt"` | Launch Claude (headless mode with `--dangerously-skip-permissions`) |

## Headed vs Headless

- **Headed** (no args): `bash docker/run-claude.sh` — interactive Claude session
- **Headless** (with args): `bash docker/run-claude.sh "Run docker compose up --build and verify all tests pass"` — uses `--dangerously-skip-permissions` for unattended execution

## Network Restrictions

The container's OUTPUT chain is locked down via iptables + ipset allowlist. Only these domains are reachable:

- `api.anthropic.com`, `statsig.anthropic.com`, `console.anthropic.com`, `auth.anthropic.com`
- `platform.claude.com`, `claude.ai`
- `sentry.io`
- `registry.npmjs.org`
- `registry-1.docker.io`, `auth.docker.io`, `production.cloudflare.docker.com`, `docker.io`, `r2.cloudflarestorage.com`
- `archive.ubuntu.com`, `security.ubuntu.com`, `ports.ubuntu.com`
- `deb.nodesource.com`, `download.docker.com`
- `github.com`, `objects.githubusercontent.com`
- `storage.googleapis.com`

Private networks (10/8, 172.16/12, 192.168/16) are always allowed for Docker bridge communication. DNS (port 53) is always allowed. IPs are refreshed every 10 minutes via cron.

## Docker-in-Docker Notes

- **`--privileged`**: Required for running dockerd inside the container. This gives the container full host capabilities — the security boundary is the iptables firewall, not container isolation.
- **Firewall scope**: Only the OUTPUT chain is modified. Docker's own FORWARD/NAT chains are untouched, so inner container networking works normally.
- **Storage**: Inner Docker uses a named volume (`claude-docker-agent-dind`) for `/var/lib/docker` to avoid overlay-in-overlay issues. Remove with `docker volume rm claude-docker-agent-dind` to reclaim space.
- **DNS**: Inner containers use Docker's embedded DNS. The outer firewall allows all DNS traffic (port 53).
- **Auth persistence**: Claude credentials are stored in `docker/.claude-data/` (git-ignored) via a volume mount to `/root/.claude`.

## Verification

```bash
bash docker/start.sh
bash docker/shell.sh
# Inside container:
docker --version && node --version && claude --version
curl -I https://api.anthropic.com       # should work
curl -I https://example.com             # should fail/timeout
docker compose up --build               # watch for ALL TESTS PASSED
docker compose down -v
exit
bash docker/stop.sh
```

## Teardown

```bash
bash docker/stop.sh
docker rm claude-docker-agent           # remove container
docker rmi claude-docker-agent          # remove image
docker volume rm claude-docker-agent-dind  # remove inner Docker storage
```
