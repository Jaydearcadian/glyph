# Glyph

> **Programmable money on Monad. Send rules, not just tokens.**

Glyph turns an ordinary link into a verifiable money operation. A Glyph link can describe who should pay, who should receive, how much value moves, what role each wallet plays, when value expires or recovers, and what proof exists after settlement.

Most crypto payment UX stops at “send this token to this address.” Glyph moves the product up one level: the link is no longer just a wrapper around a transfer. The link becomes a programmable payment object with lifecycle state, explicit terms, receipts, and recovery.

## The problem

Crypto payments are still too brittle for everyday coordination:

- **Wallet addresses are not payment intents.** A bare address does not say why value is moving, who requested it, what amount is expected, or whether the payment was completed correctly.
- **Payment links are usually shallow.** They can start a transfer, but they rarely encode durable lifecycle state, proof, expiry, recovery, or reconciliation.
- **Receipts are fragmented.** Users are forced to stitch together wallet history, explorer links, app state, screenshots, and trust assumptions.
- **Campaigns and payouts are manual.** Contributions, creator splits, collaborator payments, and referrer shares often happen outside the payment primitive, creating reconciliation work after the fact.
- **Cross-chain settlement is easy to overclaim.** A source-chain send is not the same thing as destination settlement. Glyph treats those as separate proof states instead of hiding the boundary.

The result is a gap between how people want to coordinate value — invoices, claims, contributions, splits, refunds, proofs — and what a raw token transfer can safely express.

## The Glyph solution

Glyph makes links act like programmable money operations on Monad.

A Glyph operation binds:

- the **mode**: Push, Pull, campaign, distribution, or future session;
- the **wallet roles**: payer, recipient, recovery wallet, provider, referrer, or claimant;
- the **economic terms**: asset, amount, maximum input, fees, destination amount, expiry, and nonce;
- the **lifecycle state**: escrowed, routed, reserved, acknowledged, reconciled, refunded, or blocked;
- the **proof surface**: transaction receipts, onchain readbacks, receipt JSON, cards, links, and QR artifacts.

The user still sees a simple link. The protocol sees explicit terms and a state machine.

## What Glyph enables

### Pull payments

> “Pay this exact request.”

A recipient creates a Pull payment request URL. No funds move when the request is created. A payer opens the shared link, verifies the recipient and amount, then signs the Deposit / Pay transaction from their own wallet.

This solves the “send me tokens” problem by turning an address and amount into a reusable payment intent with an onchain receipt after payment.

### Push escrow proof

> “I am funding value for a claimant.”

A sender can fund Push escrow and produce live proof that value is locked under explicit terms. Fresh recipient claiming requires authorized provider routing before it becomes executable, so the current demo labels this honestly as escrow/proof unless the operation is already routed and reconciled.

This solves the “I sent something, but what exactly happened?” problem by exposing the true lifecycle state instead of pretending escrow is the same as settlement.

### Campaign contribution links

> “Contribute to this program under shared terms.”

A campaign link lets contributors open a shared contribution request and deposit with their own wallet. Contributions can then be aggregated into campaign-level proof.

This solves the campaign coordination problem: contribution intent, payment execution, and receipt evidence stay connected.

### Explicit-recipient distributions

> “Split reconciled value to known recipients.”

Glyph includes a bounded payout splitter for explicit recipients. The live proof demonstrates a 70/20/10 creator, collaborator, and referrer distribution using real Monad testnet claim transactions.

This solves the “who gets paid after the campaign?” problem by making payout destinations, shares, claims, and conservation visible.

### Receipts and proof bundles

> “A payment should end in a record, not a screenshot.”

Glyph generates receipt artifacts from live chain activity: JSON receipts, card summaries, QR links, transaction indexes, readbacks, and SHA-256 checksums.

This solves the proof problem: users and judges can inspect what happened without trusting the UI alone.

## Product thesis

Glyph is best understood as:

```text
Programmable money on Monad
→ exposed through simple links
→ backed by wallet-signed execution
→ ending in verifiable settlement records
```

Short version:

> **Programmable payments that end in proof.**

## Live on Monad Testnet

Glyph is backed by deployed Monad testnet contracts and generated proof bundles. The active demo asset is **Glyph Test Token (`gTST`)**, an 18-decimal public test token for demo transactions only.

### Network

| Field | Value |
|---|---|
| Chain | Monad Testnet |
| Chain ID | `10143` |
| Demo asset | `Glyph Test Token` / `gTST` |
| Token decimals | `18` |

### Core same-chain Push/Pull stack

| Contract | Address |
|---|---|
| `SourceDeltaRouter` | `0xC71C119B91Fa1F1861626843Fa653F41cEF9101A` |
| `Glyph Test Token` (`gTST`) | `0x1d482783316FdeF2e795A1C193ACE280660A887a` |
| `DestinationGlyphVault` | `0xfb2a436Cf72C6FbCc4cCd1A5A4Adef015F370Ca9` |
| `LocalLoopbackGlyphAdapter` | `0x2BC2F59Ae8a01F5698407E58a1828FB51FBa5Db2` |
| Source app | `0xc3D5005A9beCfCcd28A6E66C2d8CC6E5fe3B0854` |
| Destination app | `0xA741e81349733Ac4612AF269A92f2e08F9034307` |

### Campaign stack

| Contract | Address |
|---|---|
| `ContributionCampaign` | `0xc1734449aeca5e45E570afd862f47Ff0eE03bEd1` |
| Campaign router | `0xC71C119B91Fa1F1861626843Fa653F41cEF9101A` |
| Campaign token (`gTST`) | `0x1d482783316FdeF2e795A1C193ACE280660A887a` |
| Campaign vault | `0xb4E40ecEEc4A0498A183EC14EB52B5e0C2434c77` |
| Campaign adapter | `0x8Fdffc7D35c0d3A5662264b05b35d184d7209b57` |
| Campaign source app | `0x63Df5199052915653A8373a1a55329175135D42D` |
| Campaign destination app | `0xDf62c61C73c879921911deE9e8727D797cBD5716` |

### Distribution stack

| Contract | Address |
|---|---|
| `ContributionCampaign` used for distribution proof | `0x34ebCe467EcB6cA5D9f0E9d5bF3C23b9E2B191bb` |
| `CampaignPayoutSplitter` | `0x3f90710e945f1BFa07737B97676056DF3F92Db59` |
| Distribution token (`gTST`) | `0x1d482783316FdeF2e795A1C193ACE280660A887a` |
| Live distribution ID | `0xe91b66e0fd1df23dbd317fc1119202f2460458da2fc276a55627b342f87f888a` |

### Cross-chain lane evidence

A Base Sepolia → Monad Testnet lane is deployed and has source-send evidence, but destination delivery is **not claimed complete**. The packet is documented as blocked before Monad execution at LayerZero DVN validation.

| Contract | Address |
|---|---|
| Base router | `0x6eaD1370111e2E747027C728bDb1AD5C39C33294` |
| Base token | `0x4cBA226A903f44E33446f55499c57147DC03EE82` |
| Base vault | `0xb949494E4430F666174a57d0E0dd4b98c0b7854B` |
| Base app | `0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF` |
| Base adapter | `0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43` |
| Monad router | `0x6F505b2c3d28aE37a2e3DC126440fB60e17A69cf` |
| Monad token | `0xed4152e5a8ea20192BA9B0B4319A2615416341B0` |
| Monad vault | `0x757e30bb637860E2D89F9a85D5A5A5e49313153A` |
| Monad app | `0x740d7406889CC1B447422f28468E7e5A100EE6c1` |
| Monad adapter | `0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC` |

## What is live now

| Capability | Status |
|---|---|
| Pull payment request URL | Live in frontend: creator generates URL; payer opens and deposits |
| Pull payment escrow on Monad | Live wallet-signed write against deployed router/token |
| Campaign contribution link | Live in frontend: contributor opens campaign link and deposits |
| Campaign aggregation proof | Live proof bundle generated from Monad activity |
| Push escrow | Live wallet-signed escrow/proof |
| Fresh Push recipient claim | Not advertised as live; requires authorized provider routing first |
| Historical Push terminal proof | Live-proven in Monad loopback evidence bundle |
| Explicit-recipient payout splitter | Live-proven 70/20/10 distribution with recipient claims |
| Receipt JSON/cards/links/QRs | Generated from live proof bundles |
| Base→Monad source send | Live source-send proven |
| Base→Monad destination settlement | Pending; blocked at LayerZero DVN validation |

## Evidence bundles

Start here for proof artifacts:

1. [`SUBMISSION.md`](SUBMISSION.md) — judge-facing proof summary and scope.
2. [`FRONTEND_MANIFEST.md`](FRONTEND_MANIFEST.md) — frontend routes, addresses, ABIs, flows, proof indexes, and validation commands.
3. [`state/live/monad-address-pair-proof-20260719T130942Z/`](state/live/monad-address-pair-proof-20260719T130942Z/) — Monad Push/Pull proof with receipt JSON/cards/links/QRs.
4. [`state/live/monad-campaign-proof-20260719T132755Z/`](state/live/monad-campaign-proof-20260719T132755Z/) — campaign aggregation proof.
5. [`state/live/monad-distribution-proof-20260719T172223Z/`](state/live/monad-distribution-proof-20260719T172223Z/) — explicit-recipient payout splitter proof.
6. [`state/live/base-monad-crosschain-blocker-20260719T165200Z/`](state/live/base-monad-crosschain-blocker-20260719T165200Z/) — Base→Monad source-send evidence and LayerZero blocker.
7. [`state/live/SUBMISSION_SHA256SUMS.txt`](state/live/SUBMISSION_SHA256SUMS.txt) — checksums for submission artifacts.

## Frontend demo

The interactive judge frontend lives in [`frontend/`](frontend/). It is a production-buildable Next.js static export backed by the generated ABIs and proof indexes in [`state/frontend/`](state/frontend/).

Core routes:

| Route | Purpose |
|---|---|
| `/` | Product narrative and live judge console |
| `/links` | Pull payment request URLs, payer Deposit / Pay flow, Push escrow/proof view |
| `/campaign` | Campaign creation/inspection and contribution link generation |
| `/distribution` | Explicit recipient distribution facts and claim proof surface |
| `/receipts` | Receipt cards, JSON artifacts, links, and QR references |
| `/proofs` | Proof index and cross-chain boundary disclosure |

Run locally:

```bash
cd frontend
npm install
npm run build
```

## Architecture

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

## Settlement invariant

Glyph’s cross-chain accounting follows STN-Delta:

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

Cross-chain execution is asynchronous. Glyph does not claim global atomicity. It claims atomic source-session closure after authenticated destination settlement proof, including settlement, session termination, and residual return.

## Repository layout

```text
SUBMISSION.md              judge-facing proof summary
contracts/                 Solidity contracts, scripts, and Foundry tests
docs/architecture/         executable protocol specifications
state/live/                live testnet evidence bundles
state/frontend/            generated frontend integration data and indexes
frontend/                  Next.js judge demo
workers/                   project-local worker contracts
```

## Verification commands

Backend:

```bash
forge fmt --check
forge build --force
forge test
```

Frontend:

```bash
cd frontend
npm run lint
npm run typecheck
npm run build
```

## Honesty boundary

Glyph’s README intentionally separates live proof from planned direction:

- Same-chain Monad Pull/campaign flows are active demo flows.
- Push escrow is active, but fresh recipient claim needs authorized routing before it is executable.
- The explicit-recipient distribution proof is complete for the recorded recipients.
- Base→Monad source send is proven, but destination delivery is not claimed complete.
- Sessions and authority delegation are future work and are not part of the current live value-flow claim.
