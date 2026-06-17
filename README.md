# devops

Centralized DevOps for the BC/MPG ecosystem. Reusable GitHub Actions workflows and automation scripts used across 40+ repositories.

## Reusable Workflows

### `docker-publish.yml`

Builds and pushes a Docker image to `ghcr.io` on every push to `main`. Uses GitHub Actions cache for fast incremental builds.

**Add to any repo** with an 8-line caller:

```yaml
# .github/workflows/docker-publish.yml
name: Docker

on:
  push:
    branches: [main]

jobs:
  publish:
    uses: garthpuckerin/devops/.github/workflows/docker-publish.yml@main
    permissions:
      contents: read
      packages: write
```

**Optional inputs** (for non-standard setups):

```yaml
jobs:
  publish:
    uses: garthpuckerin/devops/.github/workflows/docker-publish.yml@main
    permissions:
      contents: read
      packages: write
    with:
      dockerfile: docker/Dockerfile.prod
      context: .
      platforms: linux/amd64,linux/arm64
```

Images are published to `ghcr.io/garthpuckerin/<repo>:latest`.

### `security-headers.yml`

Verifies that a deployed UI emits the correct browser security headers for the
declared access profile. This enforces Constitution §27: production can be
HTTPS-only, but local/LAN/Tailscale demos must not force HTTP origins to HTTPS
with HSTS or CSP `upgrade-insecure-requests`.

**Add to any UI repo** after deploying or starting its demo environment:

```yaml
# .github/workflows/security-headers.yml
name: Security Headers

on:
  workflow_dispatch:
    inputs:
      url:
        description: URL to check
        required: true
      profile:
        description: production-public, staging-private-tls, or local-lan-tailscale
        required: true
        default: local-lan-tailscale

jobs:
  verify:
    uses: garthpuckerin/devops/.github/workflows/security-headers.yml@main
    with:
      url: ${{ inputs.url }}
      profile: ${{ inputs.profile }}
```

Profiles:

- `production-public`: URL must be HTTPS and must emit CSP + HSTS.
- `staging-private-tls`: URL must be HTTPS and must emit CSP. HSTS is optional.
- `local-lan-tailscale`: HTTP is allowed; HSTS and CSP
  `upgrade-insecure-requests` are forbidden unless the checked URL is HTTPS.

## Scripts

### `scripts/bootstrap-docker-workflow.sh`

Wires the docker-publish caller workflow into one or more repos via the GitHub API — no cloning required.

```bash
# Wire specific repos
./scripts/bootstrap-docker-workflow.sh finance-freedom cognee mimir-squared

# Wire all repos at once
gh repo list garthpuckerin --limit 100 --json name -q '.[].name' \
  | xargs ./scripts/bootstrap-docker-workflow.sh
```

## Fork Sync

### `sync-fork.yml`

Reusable workflow that syncs a fork from its upstream. Runs weekly (Monday 6am UTC). On clean rebase → pushes directly. On conflict → opens a PR for manual resolution.

**Add to any fork:**

```yaml
# .github/workflows/sync-upstream.yml
name: Sync from Upstream

on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

jobs:
  sync:
    uses: garthpuckerin/devops/.github/workflows/sync-fork.yml@main
    with:
      upstream: originalowner/originalrepo
    permissions:
      contents: write
      pull-requests: write
```

**Required secret:** `SYNC_PAT` — a GitHub PAT with `contents`, `pull-requests`, and `workflows` write permissions on the fork. Needed because upstream repos may include workflow file changes which `GITHUB_TOKEN` cannot push.

```bash
gh secret set SYNC_PAT --repos garthpuckerin/cognee,garthpuckerin/mimir --body "<PAT>"
```

**When to stop syncing:** Remove the `sync-upstream.yml` workflow from the fork. No other changes needed.

## Deploy Cadence (NAS) — Constitution §23.4

Watchtower on the NAS polls `ghcr.io` for the `:latest` tag (published by
`docker-publish.yml`, §23.1) and recreates containers when the image changes. One
uniform policy, not a per-project invention:

- **Production — baseline nightly sweep.** A single host-level Watchtower runs a
  nightly sweep (e.g. 02:00) and is the baseline release cadence for prod
  services. Prod compose files do **not** bundle their own Watchtower.
- **Dev/beta — fast, scoped updates.** A dev/beta project adds the scoped
  internal Watchtower in [`deploy/watchtower/docker-compose.dev-watchtower.yml`](deploy/watchtower/docker-compose.dev-watchtower.yml)
  so a fresh `:latest` lands quickly — either polled (`WATCHTOWER_POLL_INTERVAL`,
  hands-off near-immediate) or pulled on demand right after a push via
  [`scripts/pull-now.sh`](scripts/pull-now.sh) (hits the localhost HTTP API).

### Rules

- **One owner per container.** Isolate the dev/beta instance with
  `WATCHTOWER_SCOPE` + a matching `com.centurylinklabs.watchtower.scope` label on
  its container; run the host sweep with `WATCHTOWER_SCOPE=none` (or its own
  scope) so it ignores scoped containers. Never let two Watchtowers manage the
  same container. (An `enable=false` label won't work — it would also disable the
  dev/beta instance; scopes are the mechanism for coexisting Watchtowers.)
- **Don't expose the API.** The HTTP-API update endpoint is bound to
  `127.0.0.1` and token-gated; it must never be reachable from the internet.
- **Image contract.** Auto-update requires the service to publish
  `ghcr.io/garthpuckerin/<repo>:latest` via the shared `docker-publish.yml`
  (§23.1). No `:latest` → no auto-update.

### Onboard a project to the dev/beta cadence

1. Ensure the repo publishes `:latest` (wire `docker-publish.yml` — see above).
2. Pick a scope (e.g. the project name). Label the app container in the
   project's compose: `labels: ["com.centurylinklabs.watchtower.scope=<scope>"]`.
3. Drop in `deploy/watchtower/docker-compose.dev-watchtower.yml`; set
   `WATCHTOWER_TOKEN` and `WATCHTOWER_SCOPE=<scope>` in the project `.env`.
   Ensure the host sweep runs `WATCHTOWER_SCOPE=none` so it ignores it.
4. Immediate pull after a push: `WATCHTOWER_TOKEN=… scripts/pull-now.sh` on the NAS
   (or enable `WATCHTOWER_POLL_INTERVAL` for hands-off).

**One-time NAS setup:**
```bash
docker login ghcr.io -u garthpuckerin -p <PAT_read_packages>
```

**docker-compose (per service):**
```yaml
services:
  myservice:
    image: ghcr.io/garthpuckerin/myrepo:latest
    # remove any build: block
```
