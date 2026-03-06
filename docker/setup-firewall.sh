#!/usr/bin/env bash
set -euo pipefail

# Allowed domains (superset of all branches)
ALLOWED_DOMAINS=(
  api.anthropic.com
  statsig.anthropic.com
  console.anthropic.com
  auth.anthropic.com
  platform.claude.com
  claude.ai
  sentry.io
  registry.npmjs.org
  registry-1.docker.io
  auth.docker.io
  production.cloudflare.docker.com
  docker.io
  archive.ubuntu.com
  security.ubuntu.com
  ports.ubuntu.com
  deb.nodesource.com
  download.docker.com
  github.com
  objects.githubusercontent.com
  storage.googleapis.com
  r2.cloudflarestorage.com
)

resolve_domain() {
  local domain="$1"
  dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true
}

create_ipset() {
  local set_name="$1"
  ipset create "$set_name" hash:ip -exist

  for domain in "${ALLOWED_DOMAINS[@]}"; do
    local ips
    ips=$(resolve_domain "$domain")
    for ip in $ips; do
      ipset add "$set_name" "$ip" -exist
    done
  done
}

# --- Initial setup ---
echo "Resolving allowed domains..."
create_ipset allowed_ips

# Only touch the OUTPUT chain — never modify Docker's FORWARD/NAT chains
echo "Configuring iptables OUTPUT chain..."

# Flush only our custom rules (OUTPUT chain)
iptables -F OUTPUT

# 1. Accept loopback
iptables -A OUTPUT -o lo -j ACCEPT

# 2. Accept established/related connections
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. Accept DNS (udp + tcp port 53)
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# 4. Accept private networks (needed for Docker bridge communication)
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# 5. Accept DHCP
iptables -A OUTPUT -p udp --dport 67:68 -j ACCEPT

# 6. Accept traffic to allowed IPs
iptables -A OUTPUT -m set --match-set allowed_ips dst -j ACCEPT

# 7. Drop everything else
iptables -A OUTPUT -j DROP

echo "Firewall configured. $(ipset list allowed_ips | grep -c '^[0-9]' || echo 0) entries in allowed_ips."
echo "Allowed domains: ${#ALLOWED_DOMAINS[@]}"

# --- Install cron job for IP refresh (every 10 minutes) ---
CRON_SCRIPT="/usr/local/bin/refresh-firewall-ips.sh"
cat > "$CRON_SCRIPT" << 'REFRESH_EOF'
#!/usr/bin/env bash
set -euo pipefail

ALLOWED_DOMAINS=(
  api.anthropic.com
  statsig.anthropic.com
  console.anthropic.com
  auth.anthropic.com
  platform.claude.com
  claude.ai
  sentry.io
  registry.npmjs.org
  registry-1.docker.io
  auth.docker.io
  production.cloudflare.docker.com
  docker.io
  archive.ubuntu.com
  security.ubuntu.com
  ports.ubuntu.com
  deb.nodesource.com
  download.docker.com
  github.com
  objects.githubusercontent.com
  storage.googleapis.com
  r2.cloudflarestorage.com
)

# Create a new temporary ipset
ipset create allowed_ips_new hash:ip -exist

for domain in "${ALLOWED_DOMAINS[@]}"; do
  ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
  for ip in $ips; do
    ipset add allowed_ips_new "$ip" -exist
  done
done

# Atomic swap
ipset swap allowed_ips_new allowed_ips
ipset destroy allowed_ips_new

logger "Firewall IPs refreshed: $(ipset list allowed_ips | grep -c '^[0-9]' || echo 0) entries"
REFRESH_EOF

chmod +x "$CRON_SCRIPT"

# Install cron entry
CRON_LINE="*/10 * * * * /usr/local/bin/refresh-firewall-ips.sh"
(crontab -l 2>/dev/null | grep -v refresh-firewall-ips.sh; echo "$CRON_LINE") | crontab -

echo "Cron job installed for IP refresh every 10 minutes."
