# Lima VM Isolation

Runs Claude Code inside an isolated **Lima VM** (macOS hypervisor) with Docker and restricted network access.

## How It Works

1. A Lima VM runs Ubuntu 24.04 with Docker CE, Node.js 22, pnpm, and Claude Code
2. The host project directory is mounted writable via virtiofs
3. iptables + ipset restrict outbound traffic to an allowlist of domains
4. Claude credentials are symlinked to `lima/.claude-data/` for persistence across VM restarts

## Prerequisites

- macOS (arm64 or x86_64)
- [Lima](https://lima-vm.io/) installed: `brew install lima`
- `ANTHROPIC_API_KEY` env var set, or authenticate interactively via `claude login`

## Quick Start

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
bash lima/start.sh        # Create/start the VM (first run provisions ~5 min)
bash lima/shell.sh        # Open a shell (first time: run `claude login`)
claude login              # Authenticate — persists in lima/.claude-data/
exit
bash lima/run-claude.sh   # Interactive Claude session inside VM
bash lima/stop.sh         # Stop the VM
```

> **Claude Enterprise users:** `ANTHROPIC_API_KEY` is optional. Skip the `export` and just run `bash lima/start.sh`. On first run, open a shell and run `claude` to complete the OAuth login flow.

## Scripts

| Script | Purpose |
|--------|---------|
| `lima/start.sh` | Create or start the `claude-agent` VM |
| `lima/stop.sh` | Stop the VM |
| `lima/shell.sh` | Open a shell inside the VM |
| `lima/run-claude.sh` | No args = interactive Claude; with args = headless with `--dangerously-skip-permissions` |

## Network Restrictions

The VM firewall allows outbound traffic only to:
- Private networks (Docker bridge, Lima host)
- Anthropic API + OAuth (`api.anthropic.com`, `console.anthropic.com`, `auth.anthropic.com`, `statsig.anthropic.com`, `platform.claude.com`, `claude.ai`, `sentry.io`)
- Package registries (npm, Docker Hub, apt, NodeSource)
- GitHub (`github.com`, `objects.githubusercontent.com`)
- `storage.googleapis.com`

All other outbound traffic is dropped. IPs are refreshed via cron every 10 minutes.

## Lima Gotchas

| Issue | Fix |
|-------|-----|
| `location: "."` in yaml mounts | Lima 1.0 requires absolute paths. Pass project mount via `--mount=/path:w` in `start.sh` instead |
| `limactl create --name=foo file.yaml` | Lima 1.0 wants the template as the first positional arg: `limactl create file.yaml --name=foo` |
| `limactl create` doesn't auto-start | Call `limactl start` after `limactl create` |
| `limactl list --json` with no instances | Returns empty stdout (not `[]`), exits 0. Check `~/.lima/$NAME` dir instead |
| `--workdir` flag on `limactl shell` | Doesn't work reliably. Use `bash -c "cd /path && exec ..."` instead |
| `set -u` with empty bash arrays | `"${ARR[@]}"` errors if array is empty. Use explicit if/else branches instead |
| `package.json` has `"type": "module"` | Node.js scripts using `require()` must use `.cjs` extension |
| Docker Hub CDN IPs not in firewall | Claude may need to add IPs at runtime. The ipset cron refresh helps but CDN IPs rotate |
| VM I/O errors under heavy Docker builds | Ensure enough disk space. The VM disk is 50 GiB; Docker images + layers can fill it fast |
| `--dangerously-skip-permissions` required for headless | Without it, Claude prompts for tool approval interactively |

## Verification

```bash
bash lima/shell.sh
# Inside VM:
docker --version && node --version && pnpm --version && claude --version
curl -I https://api.anthropic.com        # should succeed
curl -I https://example.com              # should timeout/fail
docker compose up --build                # watch for ALL TESTS PASSED
docker compose down -v
```

## Teardown

```bash
bash lima/stop.sh
limactl delete claude-agent    # remove VM entirely
```
