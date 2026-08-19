# BCSTANDARDS — devops

> AI agents: read this before writing code. This is the AI Context Contract for this repo.

## Governance

- Authority: **Blurred Concepts Engineering Constitution v2.0** — `github.com/garthpuckerin/blurred-concepts-engineering` (local: `D:\BlurredConcepts\blurred-concepts-engineering`).
- Standards library: `blurred-concepts-engineering/standards/`.
- Precedence (Constitution §1): direct owner instruction → this `BCSTANDARDS.md` → Constitution → topic standards → supporting docs.
- This file was seeded fleet-wide on 2026-07-17; tailor repo-specific sections (product class, CI, context) as the repo is worked on.

## Code Comprehension (Comprehension Ladder Standard)

- Graph repo_id: `github.com/garthpuckerin/devops`
- Ladder-first: query the code-graph MCP ladder (`map` / `find` / `explain` /
  `neighbors` / `read`) with the repo_id above BEFORE raw file reads or grep
  for structure/behavior/relationship questions. Raw reads remain correct for
  editing, ungraphed repos, non-code content, and exact-line verification.
  Canonical text: `standards/Comprehension_Ladder_Standard.md` in
  blurred-concepts-engineering — it governs on any conflict.

## Client Enforcement and Memory

- The comprehension and memory habits are active client bindings, not passive
  repository guidance. Each client must use the highest enforcement tier it
  supports under the Comprehension Ladder Standard.
- Codex is Tier B (standing-context injection): the canonical imperative at
  `mimir-squared/clients/shared/infrastructure-imperative.md` is installed to
  `~/.codex/AGENTS.md`. Tier B cannot observe tool calls or enforce a stop gate;
  installation and fresh-session injection must therefore be asserted.
- Recall Ogham with `hybrid_search` when starting work on a system that may have
  prior context. Before ending, store decisions with rationale, gotchas, and
  cross-session operational context with source, controlled tags, and a
  deliberate TTL. Never store secrets or code-structure facts.
- Canonical memory policy: `standards/Memory_Standard.md` in
  blurred-concepts-engineering — it governs on any conflict.
