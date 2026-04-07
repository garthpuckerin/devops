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

## Watchtower Integration

Watchtower on the NAS polls `ghcr.io` and auto-updates containers when new images are pushed. No SSH required.

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
