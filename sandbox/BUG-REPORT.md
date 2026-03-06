# Bug: Docker build RUN steps have no outbound network inside AI Sandboxes

## Summary

`docker build` `RUN` steps inside a Docker AI Sandbox cannot make any outbound network connections. Only image pulls (`FROM`) succeed. This makes it impossible to build any Dockerfile that installs packages (apt-get, npm, pip, etc.).

The same network requests succeed when run natively on the sandbox VM, confirming the issue is specific to Docker-in-Docker build containers.

## Root Cause

The sandbox routes all traffic through a MITM proxy at `host.docker.internal:3128`. The sandbox VM is configured with `HTTP_PROXY`/`HTTPS_PROXY` env vars and a custom CA cert, but Docker build containers don't inherit any of this. Two things are missing:

1. **No proxy config** -- Build containers don't know about the proxy, so connections go direct and get refused.
2. **No CA cert** -- Even with the proxy configured, HTTPS fails because the proxy does SSL inspection with its own CA cert, which build containers don't trust.

## Environment

- Docker Desktop CLI plugin: v0.3.0
- Docker Engine (host + sandbox): 29.2.1
- Host: macOS (Apple Silicon / ARM64)
- Sandbox template: `docker/sandbox-templates:claude-code`

## Minimal Reproduction

### 1. Create a sandbox
```
docker sandbox run my-repro
```

### 2. Inside the sandbox, create a trivial Dockerfile
```
mkdir /tmp/repro && cd /tmp/repro
cat > Dockerfile <<'EOF'
FROM node:22-slim
RUN apt-get update
EOF
```

### 3. Build it
```
docker build --no-cache -t repro-test .
```

### 4. Observe the failure
```
#5 [2/2] RUN apt-get update
#5 0.142 Ign:1 http://deb.debian.org/debian bookworm InRelease
...
#5 7.189 Err:1 http://deb.debian.org/debian bookworm InRelease
#5 7.189   Could not connect to deb.debian.org:80 (151.101.130.132). - connect (111: Connection refused)
```

### 5. Confirm the VM itself has network access
```
sudo apt-get update
# Fetched 1073 kB in 2s (662 kB/s) -- succeeds
```

## What was tried (all still fail without the fix)

| Attempt | Result |
|---|---|
| `docker build .` (default) | `Connection refused` in RUN step |
| `docker build --network host .` | `Connection refused` in RUN step |
| `docker sandbox network proxy <name> --policy allow` then rebuild | `Connection refused` in RUN step |
| Same `apt-get update` on the VM directly | **Succeeds** |

## Workaround

Two steps are needed:

### Step 1: Add `~/.docker/config.json` with proxy settings

This tells Docker to inject proxy env vars into all build containers automatically:

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://host.docker.internal:3128",
      "httpsProxy": "http://host.docker.internal:3128",
      "noProxy": "localhost,127.0.0.1,::1"
    }
  }
}
```

**After this step alone**, HTTP works (`apt-get update` succeeds with `--policy allow`) but HTTPS fails with `SELF_SIGNED_CERT_IN_CHAIN` because the proxy does SSL inspection.

### Step 2: Inject the proxy CA cert into the Dockerfile

Copy `/usr/local/share/ca-certificates/proxy-ca.crt` from the sandbox VM into the build context, then add it to your Dockerfile:

```dockerfile
FROM node:22-slim
COPY proxy-ca.crt /usr/local/share/ca-certificates/proxy-ca.crt
ENV NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/proxy-ca.crt
```

For non-Node images, use the system CA store instead:

```dockerfile
COPY proxy-ca.crt /usr/local/share/ca-certificates/proxy-ca.crt
RUN apt-get update && apt-get install -y ca-certificates && update-ca-certificates
```

### Verified results

| Scenario | Result |
|---|---|
| No fix (default) | `Connection refused` |
| Step 1 only (proxy config) + HTTP (`apt-get update`) | **Works** |
| Step 1 only (proxy config) + HTTPS (`npm install`) | `SELF_SIGNED_CERT_IN_CHAIN` |
| Step 1 + Step 2 (proxy config + CA cert) | **Works** -- `added 68 packages in 3s` |

## Expected behavior

Docker should automatically propagate the proxy configuration and CA cert to build containers inside sandboxes. The sandbox VM already has `HTTP_PROXY`, `HTTPS_PROXY`, `NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, and the CA cert at `/usr/local/share/ca-certificates/proxy-ca.crt` -- this should be inherited by the inner Docker daemon or injected via `~/.docker/config.json` automatically.

## Impact

Without the workaround, any Dockerfile with network-dependent `RUN` steps cannot be built inside a sandbox:

- `RUN apt-get update && apt-get install -y ...`
- `RUN npm install` / `RUN pnpm install`
- `RUN pip install -r requirements.txt`
- `RUN curl ...` / `RUN wget ...`

This makes `docker compose up --build` unusable out of the box for any real-world project.
