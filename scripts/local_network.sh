#!/bin/bash
# scripts/local_network.sh - Local Tor setup and runner

TORRC="/tmp/torrc_local"
TORDATA="/tmp/tor_data_local"

# Create minimal torrc if not exists
if [ ! -f "$TORRC" ]; then
  cat > "$TORRC" <<EOF
DataDirectory $TORDATA
SocksPort 9050
Log notice stdout
EOF
fi

mkdir -p "$TORDATA"

# Start Tor in background if not running
if ! pgrep -x tor > /dev/null; then
  nohup tor -f "$TORRC" > /dev/null 2>&1 &
  echo "Tor started with config $TORRC."
else
  echo "Tor is already running."
fi
