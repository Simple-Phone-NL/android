#!/bin/bash
set -e

BASE_DIR=${1:-repos}
REPO_FILE="/var/lib/buildkite-agent/Buildkite-1/simplephone/build/sync/repos.yaml"

echo "Using base directory: $BASE_DIR"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

yq -r '.repos[] | "\(.name) \(.fork) \(.upstream) \(.branch)"' "$REPO_FILE" | while read -r name fork upstream branch; do
  echo ""
  echo "=============================="
  echo "Syncing $name ($branch)"
  echo "=============================="

  if [ ! -d "$name/.git" ]; then
    echo "Cloning fork (shallow)..."
    echo "FORK URL: [$fork]"
    git clone --depth=1 --branch "$branch" "$fork" "$name" || {
      echo "Branch not found on fork, cloning default branch..."
      git clone --depth=1 "$fork" "$name"
    }
  fi

  cd "$name"

  # Ensure remotes
  git remote add upstream "$upstream" 2>/dev/null || true
  git remote set-url origin "$fork"

  echo "Fetching latest changes (shallow)..."
  git fetch origin "$branch" --depth=1 --prune || true
  git fetch upstream "$branch" --depth=1 --prune || {
    echo "Upstream branch $branch not found, skipping..."
    cd ..
    continue
  }

  # Ensure correct branch
  git checkout "$branch" 2>/dev/null || git checkout -b "$branch"

  # Get commit hashes
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse "upstream/$branch")

  if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Already up-to-date, skipping..."
    cd ..
    continue
  fi

  echo "Updating branch..."

  # Try rebase first
  if ! git rebase "upstream/$branch"; then
    echo "Rebase failed, trying merge..."
    git rebase --abort || true

    if ! git merge --ff-only "upstream/$branch"; then
      echo "Fast-forward failed, doing normal merge..."
      git merge "upstream/$branch"
    fi
  fi

  echo "Pushing changes..."
  git push origin "$branch"

  cd ..
done

echo ""
echo "✅ All repositories processed."