#!/usr/bin/env bash
# Sync fork with upstream repository
# Usage: syncfork.sh [feature-branch-name]

set -e

echo "=== Syncing fork with upstream ==="

# Sync main branch
echo "Switching to main branch..."
git checkout main

echo "Fetching upstream changes..."
git fetch upstream

echo "Merging upstream/main into local main..."
git merge upstream/main

echo "Pushing updated main to origin..."
git push origin main

echo "Main branch sync complete!"

# Optionally update feature branch if provided
if [ -n "$1" ]; then
    echo ""
    echo "=== Updating feature branch: $1 ==="

    echo "Switching to feature branch: $1"
    git checkout "$1"

    echo "Rebasing feature branch on updated main..."
    git rebase main

    echo "Pushing updated feature branch to origin..."
    git push origin "$1" --force-with-lease

    echo "Feature branch $1 updated!"
fi

echo ""
echo "✅ Fork sync complete!"
