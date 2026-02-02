#!/bin/bash
# Optimized XMRig launcher for 16GB RAM + 4 vCPU VPS
# Usage: ./run_miner_optimized.sh <pool_url> <wallet_address> [worker_name]

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parameters
POOL_URL="${1:-pool.supportxmr.com:3333}"
WALLET="${2:-}"
WORKER="${3:-worker-$(hostname)-$(date +%s | tail -c 6)}"
XMRIG_DIR="$HOME/.local/xmrig"
CONFIG="$XMRIG_DIR/config.json"
XMRIG_VERSION="6.21.0"

# Validation
if [ -z "$WALLET" ]; then
    echo -e "${RED}Usage: $0 <pool_url> <wallet_address> [worker_name]${NC}"
    echo -e "${YELLOW}Example: $0 pool.supportxmr.com:3333 YOUR_WALLET_HERE my-worker${NC}"
    exit 1
fi

mkdir -p "$XMRIG_DIR"

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  XMRig Optimized Launcher - 16GB RAM / 4 vCPU      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Download XMRig if needed
if [ ! -f "$XMRIG_DIR/xmrig" ]; then
    echo -e "${GREEN}[1/5] Downloading XMRig ${XMRIG_VERSION}...${NC}"
    DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-linux-static-x64.tar.gz"
    
    cd /tmp
    if ! wget -q --show-progress "$DOWNLOAD_URL" -O xmrig.tar.gz 2>/dev/null; then
        echo -e "${RED}[!] Download failed. Check internet connection.${NC}"
        exit 1
    fi
    
    tar -xzf xmrig.tar.gz
    mv "xmrig-${XMRIG_VERSION}/xmrig" "$XMRIG_DIR/"
    chmod +x "$XMRIG_DIR/xmrig"
    rm -rf xmrig* "xmrig-${XMRIG_VERSION}"
    echo -e "${GREEN}    [+] XMRig installed${NC}"
else
    echo -e "${GREEN}[1/5] XMRig already installed at $XMRIG_DIR/xmrig${NC}"
fi

# Step 2: Generate optimized config
echo -e "${GREEN}[2/5] Generating optimized configuration...${NC}"
cat > "$CONFIG" << 'EOF'
{
    "autosave": true,
    "background": false,
    "colors": true,
    "title": true,
    "randomx": {
        "init": -1,
        "init-avx2": -1,
        "mode": "auto",
        "1gb-pages": true,
        "rdmsr": true,
        "wrmsr": true,
        "cache_qos": true,
        "numa": true,
        "scratchpad_prefetch_mode": 2
    },
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "huge-pages-jit": true,
        "hw-aes": null,
        "priority": null,
        "memory-pool": true,
        "yield": true,
        "max-threads-hint": 100,
        "asm": true,
        "argon2-impl": null,
        "max-threads": 4,
        "affinity": [0, 1, 2, 3]
    },
    "log-file": null,
    "donate-level": 1,
    "donate-over-proxy": 1,
    "pools": [
        {
            "algo": "rx/0",
            "coin": null,
            "url": "POOL_URL_PLACEHOLDER",
            "user": "WALLET_PLACEHOLDER",
            "pass": "WORKER_PLACEHOLDER",
            "rig-id": "WORKER_PLACEHOLDER",
            "nicehash": false,
            "keepalive": true,
            "enabled": true,
            "tls": false,
            "daemon": false
        }
    ],
    "retries": 5,
    "retry-pause": 5,
    "print-time": 60,
    "health-print-time": 60,
    "dmi": false,
    "syslog": false,
    "verbose": 1,
    "watch": false,
    "pause-on-battery": false,
    "pause-on-active": false
}
EOF

# Replace placeholders
sed -i "s|POOL_URL_PLACEHOLDER|$POOL_URL|g" "$CONFIG"
sed -i "s|WALLET_PLACEHOLDER|$WALLET|g" "$CONFIG"
sed -i "s|WORKER_PLACEHOLDER|$WORKER|g" "$CONFIG"
echo -e "${GREEN}    [+] Configuration written to $CONFIG${NC}"

# Step 3: Setup Huge Pages
echo -e "${GREEN}[3/5] Checking huge pages allocation...${NC}"
REQUIRED_HP=6  # 6x 1GB pages = 6GB minimum for 4 threads
CURRENT_HP=$(grep "HugePages_Total:" /proc/meminfo | awk '{print $2}')

if [ "$CURRENT_HP" -lt 6000 ]; then
    echo -e "${YELLOW}    [!] Current huge pages: $CURRENT_HP (need ~6144 for optimal perf)${NC}"
    echo -e "${YELLOW}    Attempting to allocate... (may require sudo)${NC}"
    
    if command -v sudo &>/dev/null; then
        sudo sysctl -w vm.nr_hugepages=6144 2>/dev/null && \
            echo -e "${GREEN}    [+] Huge pages allocated${NC}" || \
            echo -e "${YELLOW}    [!] Could not allocate (requires root or cap_sys_admin)${NC}"
    fi
else
    echo -e "${GREEN}    [+] Huge pages already allocated: $CURRENT_HP${NC}"
fi

# Step 4: Set CPU Performance Mode
echo -e "${GREEN}[4/5] Optimizing CPU performance...${NC}"
if command -v cpupower &>/dev/null; then
    if sudo cpupower frequency-set -g performance 2>/dev/null; then
        echo -e "${GREEN}    [+] CPU set to performance mode${NC}"
    else
        echo -e "${YELLOW}    [!] Could not set performance mode (requires sudo)${NC}"
    fi
else
    echo -e "${YELLOW}    [!] cpupower not installed (optional optimization)${NC}"
    echo -e "${YELLOW}       Install: sudo apt-get install linux-tools-generic${NC}"
fi

# Step 5: Start XMRig
echo -e "${GREEN}[5/5] Starting XMRig...${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Pool:     $POOL_URL${NC}"
echo -e "${GREEN}  Wallet:   ${WALLET:0:16}...${NC}"
echo -e "${GREEN}  Worker:   $WORKER${NC}"
echo -e "${GREEN}  Threads:  4 vCPUs${NC}"
echo -e "${GREEN}  Memory:   6-16 GB (w/ 1GB huge pages)${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Expected Hashrate: 1000-1200 H/s${NC}"
echo -e "${YELLOW}CPU Temp Expected: 65-75°C${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo ""

cd "$XMRIG_DIR"
exec ./xmrig --config="$CONFIG"
