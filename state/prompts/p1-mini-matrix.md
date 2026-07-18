You are the Glyph receipt-ledger architecture worker for P1. Work in /root/monadglyph and obey AGENTS.md plus workers/receipt-ledger-architect.md.

Runtime routing evidence: you are explicitly invoked with provider openai-codex, model gpt-5.4-mini, source glyph-p1-mini. Record those exact values in the required execution object of the handoff.

Task: Produce the P1 invariant → interface → event → Foundry test matrix for GlyphReceiptLedger and GlyphAttestationRegistry. This is a clerical/specification task, not Solidity implementation.

Required reads:
- AGENTS.md
- docs/PRODUCT_DOCTRINE.md
- docs/architecture/INVARIANTS.md
- docs/architecture/STATE_MACHINES.md
- docs/architecture/RECEIPT_LEDGER.md
- docs/architecture/IDENTITY_ATTESTATIONS.md
- docs/architecture/PURPOSE_TAXONOMY.md
- docs/architecture/RECEIPT_PRIVACY.md
- docs/architecture/THREAT_MODEL.md
- state/handoff.schema.json

Allowed writes only:
- docs/architecture/P1_INTERFACE_TEST_MATRIX.md
- state/handoffs/p1-mini-matrix.json

Do not edit contracts, tests, Foundry config, AGENTS.md, existing architecture specs, MGlyph.session.json, vessel_sync.json, or any global config. Do not deploy, sign, fund, broadcast, commit, or push.

The matrix must include:
1. Contract boundaries and authorized actors.
2. Proposed enums, structs, errors, events, and external functions with precise field names/types.
3. EIP-712 domain/action fields and EIP-1271 validation path for identity claims and operation bindings.
4. Operation status transition table.
5. Deterministic operation/leg/claim/attestation ID derivations using abi.encode, not ambiguous packed encoding.
6. Financial writer authorization and proof-kind treatment.
7. Reconciliation preconditions and exact conservation equation.
8. Purpose proposal, independent payer/recipient attestations, consensus, disagreement, and supersession behavior.
9. Identity self-claim, issuer claim, operation binding, acknowledgement, revocation/supersession, expiry, and historical immutability.
10. P1 Foundry tests mapped one-to-one to INVARIANTS.md identifiers, including expected revert/error and setup.
11. Explicit P1 exclusions: cross-chain adapters, source router, destination vault, tokens, frontend, deployment, and Sessions.
12. Open questions/blockers; do not invent answers where specs conflict.

Use gpt-5.4-mini only to draft this artifact. Do not claim it is locked or approved. Set handoff status to needs-review. Include every command you actually run with exit code. Include current Git HEAD and dirty=true. Validate the JSON handoff against state/handoff.schema.json if jsonschema is available. End with a concise final response naming the two written paths and any blockers.