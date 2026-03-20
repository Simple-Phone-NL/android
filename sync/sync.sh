#!/bin/bash
set -euo pipefail

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

  # Clone fork if missing
  if [ ! -d "$name/.git" ]; then
    echo "Cloning fork..."
    git clone "$fork" "$name" || { echo "Clone failed, skipping $name"; continue; }
  fi

  pushd "$name" > /dev/null

  # Ensure remotes
  git remote add upstream "$upstream" 2>/dev/null || true
  git remote set-url origin "$fork"

  echo "Fetching latest changes from origin (fork) and upstream..."
  git fetch origin --prune
  git fetch upstream --prune

  # Check out the local branch
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
  else
    git checkout -b "$branch" "upstream/$branch"
  fi

  # Get commit hashes
  LOCAL=$(git rev-parse HEAD)
  UPSTREAM=$(git rev-parse "upstream/$branch")

  # Check if the fork already contains upstream commits
  if git merge-base --is-ancestor "$UPSTREAM" "$LOCAL"; then
    echo "✅ $branch is already up-to-date with upstream, skipping merge/rebase."
  else
    echo "Updating $branch with upstream changes..."

    # Try rebase first
    if ! git rebase "upstream/$branch"; then
      echo "Rebase failed, trying fast-forward merge..."
      git rebase --abort || true

      # Try fast-forward merge
      if ! git merge --ff-only "upstream/$branch"; then
        echo "Fast-forward not possible, doing normal merge..."
        git merge "upstream/$branch" || {
          echo "🚨 Merge conflicts detected in $name/$branch. Resolve manually."
          popd > /dev/null
          continue
        }
      fi
    fi

    echo "Pushing updated branch to fork..."
    git push origin "$branch"
  fi

  popd > /dev/null
done

echo ""
echo "✅ All repositories processed."