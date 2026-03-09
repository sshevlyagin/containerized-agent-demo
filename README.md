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

All three approaches share the same script interface:

| Script | Description |
|--------|-------------|
| `start.sh` | Build and start the isolated environment |
| `stop.sh` | Stop/remove the environment |
| `shell.sh` | Interactive bash shell |
| `run-claude.sh` | Interactive Claude (no args) or headless with `--dangerously-skip-permissions` (with prompt) |

### 1. [Docker-in-Docker](docker/) — Privileged container with iptables firewall

Claude runs inside a privileged Docker container that has its own Docker daemon. The full `docker compose up --build` workflow works inside the container. Network is locked down via iptables + ipset allowlisting individual domain IPs.

```bash
bash docker/start.sh          # build + start
bash docker/shell.sh           # interactive bash shell
bash docker/run-claude.sh     # interactive Claude
bash docker/run-claude.sh "fix the failing test"  # headless
bash docker/stop.sh           # stop
```

### 2. [Lima VM](lima/) — Full VM with iptables firewall

Claude runs inside a Lima VM (macOS hypervisor). Like Docker-in-Docker, but with stronger isolation through a full VM boundary.

```bash
bash lima/start.sh             # create/start VM (~5 min first time)
bash lima/shell.sh              # interactive bash shell
bash lima/run-claude.sh        # interactive Claude
bash lima/run-claude.sh "fix the failing test"  # headless
bash lima/stop.sh              # stop
```

### 3. [Docker Sandbox](sandbox/) — Docker Desktop AI Sandbox with MITM proxy

Claude runs inside a Docker Desktop AI Sandbox — a lightweight microVM managed by Docker Desktop. Network is controlled via a MITM proxy with hostname-based rules. Docker builds work via a proxy workaround that injects the MITM CA cert into the build context.

```bash
bash sandbox/start.sh          # create + launch sandbox
bash sandbox/network-policy.sh # apply network restrictions (separate terminal)
bash sandbox/shell.sh           # interactive bash shell
bash sandbox/run-claude.sh "fix the failing test"  # headless
bash sandbox/stop.sh           # remove sandbox
```

## Comparison

| Aspect | Docker-in-Docker | Lima VM | Docker Sandbox |
|--------|-----------------|---------|----------------|
| Isolation | Privileged container | Full VM (hypervisor) | MicroVM (Docker Desktop) |
| Network control | iptables + ipset | iptables + ipset | MITM proxy |
| Docker builds inside | Yes | Yes | Yes (proxy workaround) |
| Auth persistence | Volume mount `docker/.claude-data/` | Symlink `lima/.claude-data/` | Inside sandbox VM |
| Session logging | Streaming JSONL + markdown summary | Streaming JSONL + markdown summary | Streaming JSONL + markdown summary |
| Host requirements | Docker (any OS) | macOS + Lima | Docker Desktop 4.58+ |
| License | Open source | Open source (CNCF) | Docker Desktop license |
| Security model | `--privileged` + firewall | VM boundary + firewall | VM boundary + proxy |
| Git worktrees | Yes (auto-detected) | Yes (auto-detected) | Yes (auto-detected) |

## Trade-offs

**Docker-in-Docker** is the most portable (runs anywhere Docker runs) and the most capable (full `docker compose up --build` works). The trade-off is security: `--privileged` gives the container full host capabilities, so the iptables firewall is the only barrier. Best for trusted environments where you want full Docker functionality.

**Lima VM** provides the strongest isolation via a real hypervisor boundary *and* an iptables firewall inside the VM. The trade-off is macOS-only and slower startup (~5 min first boot). Best for macOS users who want defense-in-depth.

**Docker Sandbox** offers the simplest setup (one command) and a managed security model via Docker Desktop's MITM proxy. Docker builds work via a proxy workaround: `sandbox/test.sh` injects the MITM proxy's CA cert into the build context so HTTPS connections in `RUN` steps succeed. Best for teams already using Docker Desktop who want managed isolation with minimal configuration.

## Session Logging

All three approaches support real-time session logging in headless mode. When you pass a prompt to `run-claude.sh`, Claude's output is streamed as JSONL and processed on the host:

- **Real-time display** — Tool calls, thinking, and text shown with emoji indicators
- **Raw JSONL capture** — Full session saved to `sessions/raw-<timestamp>.jsonl`
- **Markdown summary** — Auto-generated `sessions/raw-<timestamp>.md` with token counts, cost estimates, tool usage, and conversation timeline

```bash
# Headless mode automatically enables session logging
bash docker/run-claude.sh "fix the failing test"

# View the generated summary
cat sessions/raw-*.md

# Or generate a summary manually
python3 common/session-to-md.py sessions/raw-20260309-143022.jsonl
```

Interactive (headed) mode is unchanged — no streaming, no logging.

Requires `jq` on the host for real-time display parsing.

## Shared Infrastructure

All approaches use the same underlying order-service application and can share:

- **`common/stream-claude.sh`** — Shared bash library for session streaming and logging
- **`common/session-to-md.py`** — JSONL-to-Markdown session summary generator
- **`scripts/create-queue.sh`** — Create the SQS queue in LocalStack
- **`scripts/seed-messages.sh`** — Send sample order messages to the queue
- **`.env.example`** — Default environment variable template
