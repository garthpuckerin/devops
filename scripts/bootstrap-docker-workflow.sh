#!/usr/bin/env bash
# bootstrap-docker-workflow.sh
#
# Adds the standard docker-publish caller workflow to one or more GitHub repos.
# The workflow calls the central definition in garthpuckerin/devops.
#
# Usage:
#   ./bootstrap-docker-workflow.sh repo1 repo2 repo3
#
# Wire all repos at once:
#   gh repo list garthpuckerin --limit 100 --json name -q '.[].name' \
#     | xargs ./bootstrap-docker-workflow.sh
#
# Requires: gh CLI, authenticated

set -euo pipefail

OWNER="${GITHUB_OWNER:-garthpuckerin}"
CALLER_PATH=".github/workflows/docker-publish.yml"
BRANCH="main"

CALLER_CONTENT='name: Docker

on:
  push:
    branches: [main]

jobs:
  publish:
    uses: garthpuckerin/devops/.github/workflows/docker-publish.yml@main
    permissions:
      contents: read
      packages: write
'

if [ $# -eq 0 ]; then
  echo "Usage: $0 <repo1> [repo2] ..."
  exit 1
fi

for REPO in "$@"; do
  # Skip the devops repo itself
  if [ "$REPO" = "devops" ]; then
    echo "Skipping devops (central repo)"
    continue
  fi

  echo -n "Wiring $REPO... "

  # Check if file already exists
  EXISTING=$(gh api "repos/$OWNER/$REPO/contents/$CALLER_PATH" \
    --jq '.sha' 2>/dev/null || echo "")

  ENCODED=$(printf '%s' "$CALLER_CONTENT" | base64 -w0 2>/dev/null || printf '%s' "$CALLER_CONTENT" | base64)

  if [ -n "$EXISTING" ]; then
    # Update existing file
    gh api "repos/$OWNER/$REPO/contents/$CALLER_PATH" \
      --method PUT \
      --field message="chore: update docker publish workflow" \
      --field content="$ENCODED" \
      --field sha="$EXISTING" \
      --field branch="$BRANCH" \
      --silent && echo "updated" || echo "FAILED (update)"
  else
    # Create new file
    gh api "repos/$OWNER/$REPO/contents/$CALLER_PATH" \
      --method PUT \
      --field message="chore: add docker publish workflow" \
      --field content="$ENCODED" \
      --field branch="$BRANCH" \
      --silent && echo "created" || echo "FAILED (create — repo may not have a Dockerfile or $BRANCH branch)"
  fi
done

echo ""
echo "Done. Repos without a Dockerfile will build but produce empty images."
echo "Repos without a '$BRANCH' branch were skipped — re-run after merging."
