# NAS runbook — `gcpmedia`

Synology DS1821+, DSM 7.3.2. Facts an operator or agent needs *every* time, so
they stop being re-derived per session. Descriptive, not normative — nothing
here is a standard, and the workaround in "Editing config" disappears once
[#4](https://github.com/garthpuckerin/devops/issues/4) is resolved.

## Reaching it

```bash
ssh nas        # MagicDNS FQDN gcpmedia.tailb28a72.ts.net — works on or off LAN
ssh nas-lan    # 192.168.7.247, fallback for when Tailscale is the problem
```

Tailnet `tailb28a72.ts.net`, MagicDNS enabled tailnet-wide. On-LAN the tailnet
route is direct, not relayed (`tailscale ping` → `via 192.168.7.247:41641`,
~14ms), so there is no reason to prefer the LAN entry except as a fallback.

FQDN rather than bare `gcpmedia` on purpose: short-name resolution depends on
the DNS search domain, which is what breaks under a second VPN or on a
corporate network.

## Paths that are not where you expect

| Thing | Where |
| --- | --- |
| `docker` | **`/usr/local/bin/docker`** — not on the default PATH |
| `tailscale` | `/usr/local/bin/tailscale` |
| finance-freedom compose project | **`/volume1/docker/projects/finance-freedom-compose/`** |
| finance-freedom `.env` | same directory as the compose file |

`/volume1/docker/finance-freedom/` looks like the project directory and is not —
it holds a stray `.env` only. Read the truth from the container rather than
guessing:

```bash
docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

## Editing config on the NAS

Conditional on sessions landing as **root** — see #4.

- `cp -p` a timestamped `.bak-*` first; that is the convention already in use.
- Write with `cat new > target`, **never `mv`** — a move silently re-owns the
  file away from `adminGCP:users`, because the session is root.
- Review the diff before applying, not after.

## Compose gotcha (finance-freedom)

The compose file enumerates every environment variable by name with `${VAR}`
substitution and has **no `env_file:` directive**. Adding a key to `.env` alone
does nothing — the container never sees it. Both files must change.

Verify wiring with a throwaway value, because `docker compose config` silently
omits blank variables, so "no output" looks identical whether the edit worked or
not:

```bash
FOO=probe docker compose config 2>/dev/null | grep FOO
```

## Deploying by hand

GitHub Actions has not run since 2026-05-31 (billing). **GHCR pushes from a
workstation still work** — the block stops Actions, not package-registry writes.

```bash
docker build -t ghcr.io/garthpuckerin/finance-freedom:latest              -t ghcr.io/garthpuckerin/finance-freedom:$(git rev-parse --short HEAD) .
docker push ghcr.io/garthpuckerin/finance-freedom:$(git rev-parse --short HEAD)
docker push ghcr.io/garthpuckerin/finance-freedom:latest
ssh nas 'cd /volume1/docker/projects/finance-freedom-compose   && /usr/local/bin/docker compose pull app   && /usr/local/bin/docker compose up -d app'
curl -s http://192.168.7.247:3200/api/health    # expect the new "version"
```

Take a rollback point first: `docker inspect finance-freedom-app --format '{{.Image}}'`.
The entrypoint runs `prisma migrate deploy` on boot.

## Ogham

Four instances, one per entity, all on the NAS:

| Container | Port |
| --- | --- |
| `ogham_owner` | 8747 |
| `ogham_personal` | 8746 |
| `ogham_mpgworldwide` | 8745 |
| `ogham_blurredconcepts` | 8744 |

Missing `mcp__ogham__*` tools in a long session means a **stale client, not an
outage** — check the container is healthy before concluding otherwise.
