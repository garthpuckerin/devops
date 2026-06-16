#!/usr/bin/env bash
#
# pull-now.sh — trigger an IMMEDIATE Watchtower update on the NAS.
#
# For dev/beta projects running the scoped internal Watchtower
# (deploy/watchtower/docker-compose.dev-watchtower.yml). Run this on the NAS host
# right after a push has built a new `:latest`, to pull it now instead of waiting
# for the nightly sweep. See Constitution §23.4 (The Deploy Cadence).
#
# Usage:
#   WATCHTOWER_TOKEN=secret ./pull-now.sh
#   ./pull-now.sh <token>
#
# Optional env: WATCHTOWER_HOST (default localhost), WATCHTOWER_PORT (default 8080).
set -euo pipefail

TOKEN="${WATCHTOWER_TOKEN:-${1:-}}"
HOST="${WATCHTOWER_HOST:-localhost}"
PORT="${WATCHTOWER_PORT:-8080}"

if [ -z "$TOKEN" ]; then
  echo "error: no token. Usage: WATCHTOWER_TOKEN=... $0   (or: $0 <token>)" >&2
  exit 1
fi

echo "Triggering Watchtower update on ${HOST}:${PORT} ..."
curl -fsS -H "Authorization: Bearer ${TOKEN}" "http://${HOST}:${PORT}/v1/update"
echo
echo "Done — labelled containers with a newer :latest have been updated."
