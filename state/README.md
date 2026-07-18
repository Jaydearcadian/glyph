# Glyph State System

This directory contains schemas and temporary evidence projections. It is not a competing source of truth.

## Authority Order

1. chain receipts and readback;
2. Git-tracked source and tests;
3. Brain project graph after targeted recall verifies intended nodes/edges;
4. verified deployment manifests;
5. `MGlyph.session.json` generated from verified Brain recall;
6. worker handoffs.

## Files

- `handoff.schema.json` — worker-to-orchestrator evidence contract.
- `session.schema.json` — canonical resumability projection schema.
- `deployment.schema.json` — deployment/readback evidence schema.
- `handoffs/` — temporary task outputs; never canonical by themselves.
- `deployments/` — verified deployment manifests only.

## Ownership

Only the orchestrator may write `MGlyph.session.json`, canonical roadmap state, or deployment manifests. Workers may write task-scoped handoffs only after being assigned a unique path.

## Brain Rule

A session projection may claim `brainVerified: true` only when:

1. decisions/evidence were retained;
2. relationships were created;
3. a targeted recall returned the intended project nodes and relationships;
4. the projection was generated from that recalled graph;
5. Git/chain facts were independently verified.

If recall is noisy, stale, or empty, do not regenerate canonical session state. Record the blocker in the completion report.

## Legacy State

`contracts/vessel_sync.json` is a legacy compatibility artifact. It contains stale deployment/test/slot assertions and must not be treated as authoritative or updated as a second master state.

The current `MGlyph.session.json` is also stale until a verified Brain recall allows regeneration under `session.schema.json`.

## Secrets

No state, handoff, or manifest may contain private keys, mnemonics, API credentials, fragment secrets, raw PII, or private invoice/billing content.
