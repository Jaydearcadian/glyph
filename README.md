# Glyph

> **A link becomes an operation.**

Glyph is a Monad-anchored protocol for link-native Web3 operations:

```text
Push value → Pull payment → Route across chains → Delegate authority
```

## Current Phase

**P0 — control plane and executable specifications.**

No new receipt, attestation, STN-Delta, or cross-chain contracts are implemented or deployed yet. Existing contracts under `contracts/` are historical prototypes and are not the active architecture. The deployed Session proxy is deprecated.

Read in order:

1. [`AGENTS.md`](AGENTS.md)
2. [`docs/PRODUCT_DOCTRINE.md`](docs/PRODUCT_DOCTRINE.md)
3. [`docs/architecture/INVARIANTS.md`](docs/architecture/INVARIANTS.md)
4. the relevant architecture document under `docs/architecture/`

## Active Architecture

```text
GlyphReceiptLedger
GlyphAttestationRegistry
SourceDeltaRouter
DestinationGlyphVault
Messenger adapters
```

The customer sees one Glyph Registry. Internally, immutable financial receipts are separated from evolving identity and purpose attestations.

## STN-Delta

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

Cross-chain settlement is asynchronous. Source finalization atomically settles the realized obligation, closes the source session, and returns the residual to the payer’s bound recovery wallet.

## Layout

```text
AGENTS.md                  project operating contract
docs/PRODUCT_DOCTRINE.md   product truth
docs/architecture/         executable protocol specifications
workers/                   project-local worker contracts
state/                     schemas and evidence/state rules
contracts/                 legacy prototype; future P1 implementation surface
MGlyph.session.json        stale legacy projection pending verified Brain recall
```

## Evidence Standard

A build is not “live” until every advertised lifecycle route has public source, destination, finalization, and Monad receipt evidence. See [`docs/architecture/EVIDENCE_POLICY.md`](docs/architecture/EVIDENCE_POLICY.md).

## Deprecated Artifacts

- `GlyphSessionProxy` deployment `0x83A572FD4E334ed34Aca42B85743Ff122AB3006d` — experimental/deprecated; wrong ERC-7201 slot and insufficient authority controls.
- `contracts/vessel_sync.json` — legacy compatibility state, not canonical.
- `docs/glyph-core-arch.md` — historical EIP-7702 design, not active architecture.
- prior frontend — intentionally removed; no automatic restoration.
