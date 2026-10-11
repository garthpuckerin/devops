# Issues — devops

> Routing rule (Work Item Routing Standard): this file is the home for anything
> **broken, wrong, missing, or knowingly deferred**. Ideas go to
> `FEATURES-BACKLOG.md`, sequenced commitments to `ROADMAP.md`, decisions with
> rationale to `DECISIONS.md`. Every entry carries evidence (or says it is
> undiagnosed) and says whether it is user-visible.

## Open

### 2026-10-11 · NAS `homarr` crash-looped ~46×/min for an unknown period — STOPPED, not fixed
- **Evidence.** `docker logs --since 60m homarr` showed 2,747 PM2 restarts in one hour. Each start fails with `Error: /app/integration.config.json does not exist`, PM2 restarts it. The container sat at ~51% CPU on an already-overloaded NAS (load ~28 on 8 threads).
- **What it is.** `homarr/homarr:latest`, image built 2022-05-08, container created 2026-04-11 from `/volume1/docker/projects/homarr/docker-compose.yml`, port 7575, `restart: always`. A disabled DSM Task Scheduler entry "Install Homarr" (port 4755) also exists.
- **Start of the loop: unknown.** The log has rotated (36 MB `log.db` + 4 xz archives), so the first failure is no longer visible. Not caused by Watchtower: the image is from 2022 and both Watchtowers have been stopped since 2026-08-19 (see `deploy/nas/README.md`).
- **Action taken 2026-10-11 (owner's instruction).** `POST :8099/autonomy/skip/homarr` (container-monitor will not restart it), `docker update --restart=no homarr`, `docker stop homarr`. Container, image, data and compose file are kept. A `docker compose up` in that directory would bring it back (compose still says `restart: always`).
- **Not user-visible** unless the dashboard is in use; the cost was CPU for the whole NAS.
- **Open decision (owner).** Retire it (remove container, compose dir and the disabled task) or repair it (supply `integration.config.json`). To undo the stop: `docker update --restart=always homarr && docker start homarr`, then `POST :8099/autonomy/unskip/homarr`.

## Closed
