#!/bin/bash
# Commit and push changes to git
# Usage: commit-and-push.sh <commit_message>

set -euo pipefail

COMMIT_MESSAGE="${1:?Commit message is required}"

echo "Configuring git..."
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

echo "Checking for changes..."
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Found changes, committing..."
  git add .
  git commit -m "$COMMIT_MESSAGE"
  git push origin main
  echo "✓ Changes committed and pushed"
else
  echo "✓ No changes to commit"
fi
