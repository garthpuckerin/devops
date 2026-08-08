# Verification substrate findings

## Purpose

This document owns cross-project lessons from Ogham's degraded-embedding
verification work. It records requirements for a future shared verification
substrate; it does not authorize building that substrate or turning a
service-specific verifier into a fleet framework.

The ownership boundary is deliberate:

| Layer | Owns |
| --- | --- |
| DevOps | Disposable target identity, artifact identity, phase orchestration, rollback proof, evidence integrity, cleanup, and reusable fault-injection interfaces |
| Service repository | Domain operations, health and error contracts, canonical state projection, fixtures, and a thin adapter to the shared substrate |
| Deployment | Environment-specific endpoints, credentials, image references, rate limits, and explicit authorization to mutate or promote |

## Cross-project requirements

1. **Prove disposability before mutation.** Loopback addressing is not proof
   that a database, profile, tenant, or container is disposable. A verifier
   must require a unique run identity, positively identify its target, and
   assert the scoped state is empty before its first write.
2. **Bind evidence to one immutable artifact.** Record source revision, image
   digest or platform config, container identity, start time, and restart
   count. Healthy, degraded, and recovery evidence must refer to the same
   candidate unless recreation is itself the behavior under test.
3. **Prove rollback before migration or promotion.** Create backups while
   writers are quiesced, restore them into an isolated target, compare
   service-defined canonical counts or hashes, and preserve the previous
   configuration and image identity.
4. **Use explicit phases.** The reusable lifecycle is `preflight -> healthy ->
   prepare -> snapshot -> degraded -> recovery -> cleanup`. A service adapter
   may omit a phase only when it documents why that phase is inapplicable.
5. **Attribute failures exactly.** A generic tool or HTTP error is not proof of
   the expected policy. Adapters must identify the expected operation and
   stable error category, with log correlation only when the public transport
   intentionally redacts server detail.
6. **Separate domain state from permitted telemetry.** Canonical comparisons
   must include every domain field and relationship while explicitly naming
   access counters, access timestamps, or derived trigger fields that may
   change during read verification. The exclusion list belongs to the service
   adapter and must be reviewed like an API contract.
7. **Check test capacity before starting.** Rate limits, timeouts, fixture
   eligibility, and provider latency must accommodate the declared matrix.
   Configuration mistakes must fail in preflight instead of halfway through a
   destructive run.
8. **Make cleanup scoped and resumable.** Cleanup operates only on recorded
   fixture identifiers, accepts already-absent fixtures, and finishes by
   proving the scoped target is empty. Profile-wide or tenant-wide cleanup is
   forbidden unless the verifier provisioned the entire target.
9. **Keep certificates truthful.** Evidence generated before a verifier change
   cannot certify the changed verifier. Record the last fully executed
   artifact and mark later harness-only corrections as unverified until the
   complete journey is rerun.
10. **Stop when product acceptance is sufficient.** Verifier defects that do
    not invalidate product evidence are surfaced here or in the service
    backlog. They do not automatically expand a restoration or deployment task
    into shared-infrastructure development.

## Service adapter contract

A future shared runner should accept a service-owned adapter with these
responsibilities:

- declare healthy, degraded, and recovered capability expectations;
- provision and identify disposable scope;
- prepare policy-eligible fixtures through supported service interfaces;
- enumerate read paths and mutation paths with expected error contracts;
- capture canonical domain state and its permitted telemetry exclusions;
- inject and remove a dependency fault without changing the candidate;
- clean only recorded fixtures and prove final scoped emptiness.

The shared runner should not know Ogham table names, MCP tool names, embedding
models, profile semantics, or compression rules.

## Ogham as the first recorded consumer

Ogham supplied the initial findings, but its current verifier is an Ogham
artifact rather than the shared substrate. A future Ogham adapter would own:

- the MCP health, retrieval, and mutation operation matrix;
- the `memories`, `memory_relationships`, `profile_settings`, revision, and
  maintenance state projections;
- embedding-provider healthy and unavailable behavior;
- profile-scoped fixture preparation and cleanup;
- Ogham's FastMCP redaction and error-correlation contract.

Ogham-specific follow-up remains in
`ogham-mcp/docs/cohesion/2026-07-26-verification.md`. Shared implementation
should begin only when another service has the same need and both adapters can
validate the boundary; until then, these are requirements and backlog, not a
new platform project.
