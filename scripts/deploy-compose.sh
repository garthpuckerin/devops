#!/usr/bin/env bash
#
# deploy-compose.sh — sync a repo-tracked compose file to a NAS compose project
# and apply it. The manual half of the NAS pipeline (Constitution §23.4):
# images ride CI (docker-publish.yml) + Watchtower automatically; this script
# covers the RARE compose/topology change that Watchtower cannot deliver.
#
# The repo copy of the compose file is the source of truth; the NAS copy is a
# deploy target. Never hand-edit the NAS copy — change the repo file, review,
# merge, then run this.
#
# Usage:
#   ./deploy-compose.sh <local-compose-file> <nas-project-dir> [service ...]
#
# Examples:
#   ./deploy-compose.sh deploy/nas/docker-compose.yml /volume1/docker/projects/finance-freedom-compose
#   ./deploy-compose.sh deploy/nas/docker-compose.yml /volume1/docker/projects/finance-freedom-compose app
#
# Optional env: NAS_HOST (default "nas" — an ~/.ssh/config alias),
#               DOCKER_BIN (default /usr/local/bin/docker — Synology path).
#
# Behavior:
#   1. Backs up the current NAS compose file (timestamped .bak).
#   2. Copies the local file over it.
#   3. Validates with `docker compose config --quiet`; on failure RESTORES the
#      backup and exits non-zero (the running stack is never touched).
#   4. Applies with `docker compose up -d [service ...]`.
set -euo pipefail

LOCAL_FILE="${1:?usage: deploy-compose.sh <local-compose-file> <nas-project-dir> [service ...]}"
NAS_DIR="${2:?usage: deploy-compose.sh <local-compose-file> <nas-project-dir> [service ...]}"
shift 2
SERVICES=("$@")

NAS_HOST="${NAS_HOST:-nas}"
DOCKER_BIN="${DOCKER_BIN:-/usr/local/bin/docker}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_FILE="${NAS_DIR}/docker-compose.yml"
BACKUP_FILE="${REMOTE_FILE}.bak-${STAMP}"

[ -f "$LOCAL_FILE" ] || { echo "error: local file not found: $LOCAL_FILE" >&2; exit 1; }

echo "Backing up ${NAS_HOST}:${REMOTE_FILE} -> ${BACKUP_FILE}"
ssh "$NAS_HOST" "cp '$REMOTE_FILE' '$BACKUP_FILE'"

echo "Uploading ${LOCAL_FILE}"
scp "$LOCAL_FILE" "${NAS_HOST}:${REMOTE_FILE}"

echo "Validating"
if ! ssh "$NAS_HOST" "cd '$NAS_DIR' && '$DOCKER_BIN' compose config --quiet"; then
  echo "error: compose validation failed — restoring backup, stack untouched" >&2
  ssh "$NAS_HOST" "cp '$BACKUP_FILE' '$REMOTE_FILE'"
  exit 1
fi

echo "Applying: docker compose up -d ${SERVICES[*]:-<all services>}"
ssh "$NAS_HOST" "cd '$NAS_DIR' && '$DOCKER_BIN' compose up -d ${SERVICES[*]:-}"

echo "Done. Rollback if needed:"
echo "  ssh $NAS_HOST \"cp '$BACKUP_FILE' '$REMOTE_FILE' && cd '$NAS_DIR' && $DOCKER_BIN compose up -d\""
