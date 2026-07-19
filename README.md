# Glyph

> **A link becomes an operation.**

Glyph is a Monad-anchored protocol for link-native Web3 operations:

```text
Push value → Pull payment → Campaign contribution → Route across chains → Delegate authority
```

## Current phase

**Submission-ready backend proof package.**

The repo now contains live Monad testnet proofs plus a Base Sepolia → Monad Testnet LayerZero lane/send proof. The cross-chain destination delivery is not claimed complete: LayerZero Scan shows the packet stuck before Monad `lzReceive` at DVN validation.

Start here:

1. [`SUBMISSION.md`](SUBMISSION.md) — judge-facing proof summary and scope.
2. [`FRONTEND_MANIFEST.md`](FRONTEND_MANIFEST.md) — pre-frontend integration manifest: addresses, ABIs, flows, indexes, cross-chain proof panel, validator/readback scripts. No frontend app is created here.
3. [`BACKEND_COMPLETION.md`](BACKEND_COMPLETION.md) — backend completion note excluding frontend and cross-chain repair.
4. [`state/live/monad-address-pair-proof-20260719T130942Z/`](state/live/monad-address-pair-proof-20260719T130942Z/) — live Monad Push/Pull proof plus live receipt JSON/cards/links/QRs.
5. [`state/live/monad-campaign-proof-20260719T132755Z/`](state/live/monad-campaign-proof-20260719T132755Z/) — live campaign aggregation proof plus live receipt JSON/card/link/QR.
6. [`state/live/monad-distribution-proof-20260719T172223Z/`](state/live/monad-distribution-proof-20260719T172223Z/) — live explicit-recipient payout splitter proof: 70/20/10 recipient claims plus distribution receipt JSON/cards/links/QRs.
7. [`state/live/base-monad-crosschain-blocker-20260719T165200Z/`](state/live/base-monad-crosschain-blocker-20260719T165200Z/) — Base→Monad lane/source-send evidence and LayerZero DVN blocker.
8. [`state/live/SUBMISSION_SHA256SUMS.txt`](state/live/SUBMISSION_SHA256SUMS.txt) — checksums for submission summary and live proof artifacts.

## What is proven live

| Capability | Status |
|---|---|
| Pull payment on Monad | Live-proven |
| Push claim on Monad | Live-proven |
| Terminal destination receipts | Live-proven on Monad loopback |
| Multi-contributor campaign aggregation | Live-proven |
| Explicit-recipient payout splitter | Live-proven: creator/collaborator/referrer pro-rata claims |
| Distribution receipts/cards/QRs | Generated from live Monad claim txs |
| Base Sepolia → Monad Testnet LayerZero lane | Deployed, wired, frozen, readback-good |
| Base→Monad route send | Live source-send proven |
| Base→Monad delivery + ACK/finalize | Pending; blocked at LayerZero DVN validation before Monad execution |

## Active architecture

```text
GlyphReceiptLedger
GlyphAttestationRegistry
SourceDeltaRouter
DestinationGlyphVault
Messenger adapters
ContributionCampaign
CampaignPayoutSplitter
```

The user sees links. The protocol sees immutable operation terms, source escrow, destination delivery, receipts, and explicit settlement state.

## STN-Delta

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

Cross-chain settlement is asynchronous. Source finalization atomically settles the realized obligation, closes the source session, and returns residual value to the payer’s bound recovery wallet.

## Layout

```text
SUBMISSION.md              judge-facing proof summary
contracts/                 Solidity contracts, scripts, and Foundry tests
docs/architecture/         executable protocol specifications
state/live/                live testnet evidence bundles
state/manifests/           build manifests and oneshot inputs
workers/                   project-local worker contracts
```

## Evidence standard

A route is called live only when the advertised lifecycle has public evidence. Current submission claims are intentionally scoped:

- Monad Push/Pull/campaign flows are live-proven.
- Base→Monad cross-chain engine is deployed and source-send proven.
- Base→Monad destination delivery is not claimed complete until LayerZero DVN validation advances and Monad `lzReceive` executes.

## Latest backend gate

```text
forge fmt
forge build --force
forge test
```

Result:

```text
75 tests passed
0 failed
```
