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

  if [ ! -d "$name/.git" ]; then
    echo "Cloning fork..."
    git clone "$fork" "$name" || {
      echo "Clone failed, skipping $name"
      continue
    }
  fi

  pushd "$name" > /dev/null

  # Ensure remotes
  git remote add upstream "$upstream" 2>/dev/null || true
  git remote set-url origin "$fork"

  echo "Fetching all branches from upstream..."
  git fetch upstream --prune

  echo "Checking out local branch $branch..."
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
  else
    git checkout -b "$branch" "upstream/$branch"
  fi

  echo "Merging upstream/$branch into local $branch..."
  if ! git merge --ff-only "upstream/$branch"; then
    echo "Fast-forward not possible, doing normal merge..."
    git merge "upstream/$branch" || {
      echo "Merge conflicts detected in $name/$branch. Resolve manually."
      popd > /dev/null
      continue
    }
  fi

  echo "Pushing changes to fork..."
  git push origin "$branch"

  popd > /dev/null
done

echo ""
echo "✅ All repositories processed."