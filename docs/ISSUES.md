# Issues — devops

> Routing rule (Work Item Routing Standard): this file is the home for anything
> **broken, wrong, missing, or knowingly deferred**. Ideas go to
> `FEATURES-BACKLOG.md`, sequenced commitments to `ROADMAP.md`, decisions with
> rationale to `DECISIONS.md`. Every entry carries evidence (or says it is
> undiagnosed) and says whether it is user-visible.

## Open

### 2026-10-11 · NAS carries 44 stopped containers and ~25 GB of stale images nobody cleaned up — cleanup pending
- **Evidence (measured 2026-10-11 by the orchestrator).** The NAS (Synology, 8 threads) hit load ~29 with 13.4 GB of swap in use. 109 containers, 44 of them stopped. Stopped containers include Codex MediaOS qualification/pilot containers (`mediaos-qualification-20261008`, `mediaos-existing-boot-20261008`, `mediaos-existing-state-20261008`, `mediaos-upgrade-snapshot-20261008`, `mediaos-language-policy-20261008`, `mediaos-pilot-replacement-*` from 10-03) and unnamed one-off build containers (`bold_cannon`, `admiring_beaver`: `npm run build`, no restart policy, no network), among others. About 25 GB of old MediaOS images (`mediaos:nas-20261010-*` and `nas-20261011-*` at ~1.6 GB each, each with an untagged twin), plus many old `ogham-mcp:*` and `mimir-squared-mimir2:*` tags.
- **What is already fixed.** container-monitor-agent autonomy rule 1 revived any exited container regardless of restart policy, so `bold_cannon` and `admiring_beaver` re-ran `npm run build` every ~16 min (125 times in 24 h). Fixed and deployed 2026-10-11 (container-monitor-agent commit `35639fa`: rule 1 now respects restart policy `no`/empty; the scan also stopped inspecting every container, ~109 x 109 inspects per 30 s). That stops the revival; it does not remove the containers or images.
- **What is NOT fixed.** The 44 stopped containers and the stale images are still on the NAS. The images cost disk; the stopped containers hide the real inventory. No per-contributor attribution of the load exists: the clutter is one of several contributors (homarr's crash loop is another, filed separately on branch `docs/nas-homarr-2026-10-11`).
- **MediaOS leftovers are being cleaned by Codex** (owner said so, 2026-10-11). Recorded here as context; this entry does not propose anyone else acts on them. The remaining stopped containers and non-MediaOS image tags have no named owner or cleanup in progress.
- **Existing coverage.** Only `mimir-squared/docs/DEPLOY_RUNBOOK.md` step 8 "Retention" (image tags and tarballs, mimir2/graph-mcp/ogham only, manual). Nothing covers ad-hoc containers or other apps' images.
- **Not user-visible** except through NAS slowness and disk use.
- **Next action (owner decides).** Review the stopped-container list and stale tags once Codex has finished the MediaOS cleanup, then decide what to remove. Prevention is proposed separately: blurred-concepts-engineering `docs/proposals/AMENDMENT_CLEANUP_IS_PART_OF_DONE.md` (process rule) and container-monitor-agent `docs/FEATURES-BACKLOG.md` (ephemeral-container labels; weekly report-only NAS hygiene report). Nothing was deleted or changed on the NAS in filing this.
- **Filed at owner's request.**

## Closed
