#!/usr/bin/env bash
#
# deploy-local-build.sh — build a repo's image on THIS machine, push it to
# GHCR, and roll the NAS compose service onto it. No GitHub Actions minutes.
#
# The alternate path to the CI route (docker-publish.yml + Watchtower,
# Constitution §23.4). Generalised 2026-09-24 from ShadowStream's
# scripts/deploy-nas.sh, which has shipped every ShadowStream release since
# 2026-09-05 when the owner chose local builds over paid Actions builds.
#
# Order is the whole point — every step is fatal and runs before the next:
#   refuse dirty source -> [gate] -> build+push image -> git push
#   -> open NAS ssh -> compose pull+up -> verify revision label [+ health]
# The image is pushed before the NAS is touched, and the commits are pushed
# before deploying, so production can never run a revision that is not on
# the remote. (A transient `git push` failure inside a hand-typed `&&` chain
# once let prod run an unpushed revision — that is why this is a script.)
#
# Watchtower-safe: it compares image IDs, not age, so a registry push is what
# it will converge on anyway. NEVER sideload with `docker save | load` — the
# nightly Watchtower sweep silently reverts a sideloaded image.
#
# Configuration: a `.deploy.env` file at the repo root (sourced), overridable
# by environment variables. Required: NAS_DIR, SERVICE.
#   NAS_DIR        compose project dir on the NAS, e.g. /volume1/docker/shadowstream
#   SERVICE        compose service name, e.g. shadowstream
#   CONTAINER      container to verify (default: $SERVICE)
#   IMAGE          default ghcr.io/<owner>/<repo>:latest from the origin remote
#   PLATFORM       default linux/amd64 (the NAS is x86_64)
#   HEALTH_URL     optional; must return HTTP 2xx after the rollout
#   HEALTH_MATCH   optional substring the health body must contain
#   GATE_CMD       command run by --gate, e.g. "pnpm run deploy:check"
#   NAS_HOST       ssh alias (default nas); NAS_DOCKER (default /usr/local/bin/docker)
#   MONITOR        NAS container monitor (default http://192.168.7.247:8099);
#                  SSH is re-enabled through it because a watchdog closes it
#                  after ~30 minutes idle.
#   VERIFY_WAIT    seconds to wait before verifying (default 25)
#
# Usage (from the repo root):
#   bash <devops>/scripts/deploy-local-build.sh             # deploy HEAD
#   bash <devops>/scripts/deploy-local-build.sh --gate      # run GATE_CMD first
#   bash <devops>/scripts/deploy-local-build.sh --dry-run   # print, touch nothing
#   bash <devops>/scripts/deploy-local-build.sh --allow-ci  # HEAD lacks [skip ci] on purpose
#   bash <devops>/scripts/deploy-local-build.sh --prune     # prune dangling NAS images after
#
# Requirements: docker buildx logged in to ghcr.io (Docker Desktop's
# credential store), ssh access to $NAS_HOST, run from a git checkout.
set -euo pipefail

GATE=0 DRY=0 ALLOW_CI=0 PRUNE=0
for arg in "$@"; do
  case "$arg" in
    --gate) GATE=1 ;;
    --dry-run) DRY=1 ;;
    --allow-ci) ALLOW_CI=1 ;;
    --prune) PRUNE=1 ;;
    -h|--help) sed -n '2,52p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
if [ -f .deploy.env ]; then
  # Environment variables set by the caller win over the file.
  while IFS='=' read -r key value; do
    case "$key" in ''|\#*) continue ;; esac
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    value="${value%$'\r'}"
    case "$value" in \"*\"|\'*\') value="${value:1:${#value}-2}" ;; esac
    if [ -z "${!key:-}" ]; then export "$key=$value"; fi
  done < .deploy.env
fi

: "${NAS_DIR:?NAS_DIR is required (set it in .deploy.env)}"
: "${SERVICE:?SERVICE is required (set it in .deploy.env)}"
CONTAINER="${CONTAINER:-$SERVICE}"
PLATFORM="${PLATFORM:-linux/amd64}"
NAS_HOST="${NAS_HOST:-nas}"
NAS_DOCKER="${NAS_DOCKER:-/usr/local/bin/docker}"
MONITOR="${MONITOR:-http://192.168.7.247:8099}"
VERIFY_WAIT="${VERIFY_WAIT:-25}"

# owner/repo from the origin remote (https or ssh form), lowercased for GHCR.
REMOTE="$(git remote get-url origin)"
SLUG="$(printf '%s' "$REMOTE" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##' | tr '[:upper:]' '[:lower:]')"
IMAGE="${IMAGE:-ghcr.io/$SLUG:latest}"
REPO_URL="https://github.com/$SLUG"

say() { printf '\n== %s\n' "$1"; }
run() {
  if [ "$DRY" = "1" ]; then printf '   would run: %s\n' "$*"; else "$@"; fi
}

SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
say "HEAD $SHA on $BRANCH -> $IMAGE -> $NAS_HOST:$NAS_DIR ($SERVICE)"

# A dirty tree means the image would not match any commit. Only non-doc
# tracked changes count; untracked scratch files are not in the build context
# of a clean checkout either way, but are worth a look — .dockerignore them.
DIRTY="$(git status --porcelain --untracked-files=no | grep -vE '\.md$' | head -5 || true)"
if [ -n "$DIRTY" ]; then
  echo "refusing: uncommitted changes would not match the pushed commit:" >&2
  echo "$DIRTY" >&2
  exit 1
fi

# This path exists to NOT spend an Actions build. GitHub reads [skip ci] from
# the HEAD commit only, so a pushed HEAD without it triggers push workflows.
if [ -d .github/workflows ] && [ "$ALLOW_CI" = "0" ] && ! git log -1 --format=%B | grep -q '\[skip ci\]'; then
  echo "refusing: HEAD has no [skip ci], so the git push would start paid Actions runs." >&2
  echo "Amend or add a commit carrying [skip ci], or pass --allow-ci deliberately." >&2
  exit 1
fi

if [ "$GATE" = "1" ]; then
  : "${GATE_CMD:?--gate needs GATE_CMD (set it in .deploy.env)}"
  say "gate: $GATE_CMD"
  run bash -c "$GATE_CMD"
fi

say "build + push $IMAGE ($PLATFORM)"
run docker buildx build --platform "$PLATFORM" --push \
  -t "$IMAGE" \
  --label "org.opencontainers.image.revision=$SHA" \
  --label "org.opencontainers.image.source=$REPO_URL" \
  --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg "GIT_SHA=$SHA" .

say "push $BRANCH to origin"
run git push origin "$BRANCH"

say "open NAS ssh"
run curl -s -X POST "$MONITOR/system/ssh/enable" -o /dev/null

say "compose pull + up"
run ssh "$NAS_HOST" "cd '$NAS_DIR' && $NAS_DOCKER compose pull '$SERVICE' && $NAS_DOCKER compose up -d '$SERVICE'"

if [ "$DRY" = "1" ]; then
  say "dry run: skipping verification"
  exit 0
fi

say "verify"
sleep "$VERIFY_WAIT"
DEPLOYED="$(ssh "$NAS_HOST" "$NAS_DOCKER inspect '$CONTAINER' --format '{{index .Config.Labels \"org.opencontainers.image.revision\"}}'" | tr -d '\r')"
if [ "$DEPLOYED" != "$SHA" ]; then
  echo "FAILED: $CONTAINER reports revision '$DEPLOYED', expected $SHA" >&2
  exit 1
fi

if [ -n "${HEALTH_URL:-}" ]; then
  HEALTH="$(curl -fsS --max-time 30 "$HEALTH_URL" || true)"
  if [ -z "$HEALTH" ] || { [ -n "${HEALTH_MATCH:-}" ] && [[ "$HEALTH" != *"$HEALTH_MATCH"* ]]; }; then
    echo "FAILED: health check $HEALTH_URL returned: ${HEALTH:-<no response or non-2xx>}" >&2
    exit 1
  fi
fi

if [ "$PRUNE" = "1" ]; then
  say "prune dangling images on the NAS"
  ssh "$NAS_HOST" "$NAS_DOCKER image prune -f" >/dev/null
fi

printf '\n== deployed %s%s\n' "$SHA" "${HEALTH_URL:+, health ok}"
