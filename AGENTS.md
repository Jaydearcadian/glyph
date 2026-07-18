# AGENTS.md — Glyph Project Operating Contract

This file governs work under `/root/monadglyph`. It extends `/root/AGENTS.md` and `/root/soul.md`; it does not replace them.

## Mission

Glyph turns links into programmable Web3 operations:

1. **Push** — “I am sending you value.”
2. **Pull** — “Pay this exact request.”
3. **Session** — “You may perform these exact actions under these exact limits.”

Current sequence is fixed: same-chain Push/Pull → shared receipts → cross-chain Pull → cross-chain Push → Sessions → Hybrid. Do not attach authority delegation to value flows until the authority kernel is independently rebuilt and proven.

## First Reads

Before changing code, read in order:

1. `docs/PRODUCT_DOCTRINE.md`
2. `docs/architecture/INVARIANTS.md`
3. the architecture document for the touched surface
4. the applicable worker definition under `workers/`
5. `MGlyph.session.json` only as a resumability projection, never as sole proof

## Current Truth Boundary

- Monad testnet chain ID: `10143`.
- Current deployed registry `0xb3671C718d286f1cFF5A895F447503Fac5Bef308` has bytecode, but its newest create→claim lifecycle is not publicly E2E-proven.
- Current deployed proxy `0x83A572FD4E334ed34Aca42B85743Ff122AB3006d` is **experimental/deprecated**. It uses the wrong ERC-7201 slot and lacks adequate session authentication/administration controls.
- Correct ERC-7201 slot for `glyph.storage.session.v1`, verified with `cast index-erc7201`, is `0xe41f22272467a59d9f0c5cddde07c168cf1192ad3a1536e2283f6fbda6e9a300`.
- P1–P6 Foundry target is explicitly `cancun` with Solc `0.8.24`; live `forge config` verifies both. Prague is deferred to the separate P7 EIP-7702 toolchain gate.
- Existing `GlyphRegistry` is a native-MON prototype, not the new receipt-ledger/cross-chain architecture.
- Frontend remains intentionally shattered; do not restore the prior Three.js/Framer/Vessel surface.

## Sources of Truth

Priority order:

1. **Chain state and successful receipts** — runtime truth.
2. **Git-tracked source and passing tests** — implementation truth.
3. **Brain project graph** — decision and roadmap truth, only after targeted recall verifies nodes and edges.
4. **Deployment manifests** — generated evidence projection, verified against chain.
5. **`MGlyph.session.json`** — generated resumability projection.
6. **Worker handoffs** — temporary evidence, never canonical by themselves.

`contracts/vessel_sync.json` is legacy compatibility state. It is not authoritative and must not be updated as a competing master ledger.

## Active Architecture

The customer-facing Glyph Registry is internally separated into:

- `GlyphReceiptLedger`: immutable operation headers, value legs, proof classes, lifecycle, and STN-Delta reconciliation.
- `GlyphAttestationRegistry`: append-only identity and purpose claims, acknowledgements, supersession, and revocation.
- `SourceDeltaRouter`: payer maximum-input escrow, realized settlement, recovery, and atomic source-chain residual return.
- `DestinationGlyphVault`: exact destination delivery, Push claims, Pull settlement, and destination acknowledgements.
- messenger adapters: isolated authenticated transport; core accounting must remain messenger-neutral.

## Non-Negotiable Invariants

- Cross-chain execution is asynchronous; only source-chain finalization is atomic.
- No source settlement without authenticated destination-delivery proof.
- `maximumInput = realizedPrincipal + realizedFees + residualReturned` for every reconciled operation.
- One operation may settle only once globally.
- Destination chain, vault, asset, amount, claimant/recipient, expiry, and nonce are domain-bound.
- No party may write identity for the counterparty without that subject’s signature or an authorized issuer path.
- No raw PII or private billing details are written on-chain.
- Remote receipt legs declare their proof kind; LayerZero/Hyperlane adapter attestation is not called light-client verification.
- Link secrets use URL fragments, are parsed locally, removed from the visible URL, and never enter servers, analytics, logs, screenshots, or persistence.
- `RECONCILED` and `REFUNDED` are the only terminal financial-success states.

## Phase Gates

- **P0 — Control plane/specification:** docs, workers, state schema. No Solidity behavior changes.
- **P1 — Ledger spine:** receipt and attestation interfaces/contracts with local TDD.
- **P2 — Local routing spine:** source router, destination vault, test token, mock messenger.
- **P3 — Testnet messaging:** Base Sepolia ↔ Monad testnet adapter proof.
- **P4 — Cross-chain Pull:** public exact-destination delivery and STN-Delta receipt proof.
- **P5 — Cross-chain Push:** public claimant-safe link lifecycle and STN-Delta proof.
- **P6 — SDK/indexer/frontend:** only after P4 and P5 evidence gates.
- **P7 — Sessions:** separate authority-kernel rebuild; no reuse of the deprecated proxy.

A later phase does not start until the prior phase’s acceptance evidence is recorded and independently reviewed.

## Approval Boundaries

Explicit user approval is required before:

- deploying or upgrading contracts;
- signing or broadcasting transactions;
- moving or funding assets/liquidity;
- reading or using private keys;
- changing network addresses or live configuration;
- starting public tunnels/services;
- modifying global `/root/soul.md`, `/root/workers`, Hermes config, MCP servers, gateways, cron, or infrastructure;
- committing or pushing unless the current instruction explicitly includes it.

Local documentation, read-only inspection, test writing, compilation, and local test execution are permitted within an approved phase.

## Worker Routing and Write Ownership

| Surface | Primary writer | Required reviewer |
|---|---|---|
| `contracts/src`, `contracts/test`, `contracts/script` | `monad-contract-engineer` | `adversarial-reviewer` |
| Cross-chain/accounting specs | `crosschain-delta-architect` | orchestrator + reviewer |
| Receipt/identity/purpose specs | `receipt-ledger-architect` | orchestrator + reviewer |
| Security findings | `adversarial-reviewer` | orchestrator verifies evidence |
| Deployment/evidence bundle | `testnet-e2e-proof` | orchestrator reads back chain state |
| `MGlyph.session.json`, roadmap, canonical handoffs | orchestrator only | targeted Brain recall + Git/chain verification |

Rules:

- one writer per file surface;
- no auto-merge;
- reviewers are read-only against the reviewed source;
- workers never write `MGlyph.session.json` or legacy `vessel_sync.json`;
- workers return verifiable paths, commands, transaction IDs, and assertions;
- a worker’s claim is not evidence until independently inspected.

## Development Method

Use strict RED → GREEN → REFACTOR for contract behavior:

1. write the narrow failing test;
2. run it and record the expected failure;
3. implement the smallest passing change;
4. rerun targeted tests;
5. run broader regression;
6. run spec-compliance review;
7. run adversarial/code-quality review.

Do not burn disposable spike code into production contracts.

## Proof Vocabulary

- **Designed:** specification exists; not compiled.
- **Built:** compiler succeeded.
- **Tested:** named tests passed against an identified commit/tree.
- **Deployed:** successful receipt plus runtime bytecode at the stated chain/address.
- **Configured:** expected on-chain configuration was read back.
- **Destination settled:** destination receipt and balance/state assertions match terms.
- **Source finalized:** realized obligation settled and source state closed.
- **Reconciled:** all value legs and conservation equation are anchored.
- **Live:** every advertised lifecycle route passes publicly; a tunnel or bytecode alone is not live proof.

## Model Routing

- `gpt-5.4-mini`: clerical drafting, schemas, fixtures, formatting.
- `gpt-5.5`: routine implementation from locked specifications.
- `gpt-5.6-sol`: orchestration, architecture, accounting, security, final verification.
- `gpt-5.6-sol-pro`: escalation only for unresolved critical findings.

Model output never substitutes for tests, chain receipts, or source inspection.

## Required Completion Report

Every phase report must include:

- files changed;
- exact commands run and exit status;
- tests passed/failed by name or count;
- unresolved risks;
- deployment/signing/funding status;
- Brain nodes/relations retained;
- whether targeted recall returned the intended project subgraph;
- Git status and commit/tree identifier.
