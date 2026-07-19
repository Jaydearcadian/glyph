# Glyph submission

> **A link becomes an operation.**

Glyph is a Monad-anchored protocol for link-native Web3 operations: Push value, Pull payment, campaign contributions, and cross-chain routing through a receipt-first settlement model.

## What is live

| Capability | Status | Evidence |
|---|---|---|
| Pull payment on Monad | Live-proven | `state/live/monad-address-pair-proof-20260719T130942Z/` |
| Push claim on Monad | Live-proven | `state/live/monad-address-pair-proof-20260719T130942Z/` |
| Terminal destination receipts | Live-proven on Monad loopback | `state/live/monad-address-pair-proof-20260719T130942Z/evidence.json` |
| Live receipt JSON/cards/links/QRs | Generated and verified | `scripts/live_receipt_builder.py`, `*.live.receipt.*` in Monad proof bundles |
| Multi-contributor campaign aggregation | Live-proven | `state/live/monad-campaign-proof-20260719T132755Z/` |
| Base Sepolia → Monad Testnet LayerZero lane | Deployed, wired, frozen, readback-good | `state/live/base-monad-crosschain-blocker-20260719T165200Z/` |
| Base→Monad route send | Live source send proven | `state/live/base-monad-crosschain-blocker-20260719T165200Z/fresh-route.json` |
| Base→Monad destination delivery + ACK/finalize | Blocked before app execution by LayerZero DVN validation | `state/live/base-monad-crosschain-blocker-20260719T165200Z/layerzero-fresh-guid.json` |

## Main proof artifacts

### 1. Monad address-pair proof

Path:

```text
state/live/monad-address-pair-proof-20260719T130942Z/
```

Live facts:

| Field | Value |
|---|---|
| Chain | Monad testnet `10143` |
| Payer | `0x014eb22ab7DFa9A843Babc1C6e2dA5B596a62f36` |
| Claimant/recipient | `0xd9fE7c8EE7B5E11f8a4e13811E7CFf01E8c82BbD` |
| Pull operation | `0x8b83664ad0edf186eb6b2b056af9e8778194ad6447813c5a46b60c70b02c6dbc` |
| Push operation | `0x2ce136c0bd76ab6c8bce42c3bcbbc284296a0f7cddebc763e645d5d536a48105` |
| Pull receipt | `0x0fe31e1796c4efac6027c9ac8298fbe55a0b3354014805a0500e4b014e689ded` |
| Push receipt | `0x1f96812d34c4f78737a4f6dd20acf92747076f1e5b140276bbafea45c93ada2c` |
| Transactions | `34`, all status `0x1` |

This proof uses a fresh current-source Monad loopback stack, executes Pull and Push flows with separate addresses, finalizes both operations, and delivers terminal receipt messages to the destination app.

Generated receipt artifacts:

```text
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.json
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.card.svg
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.link.json
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.qr.png
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.json
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.card.svg
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.link.json
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.qr.png
```

### 2. Monad campaign proof

Path:

```text
state/live/monad-campaign-proof-20260719T132755Z/
```

Live facts:

| Field | Value |
|---|---|
| Campaign | `0xc1734449aeca5e45E570afd862f47Ff0eE03bEd1` |
| Program ID | `0x1c02c59218771a5bd216c7ddfa81ef46e0ca88ed35b3eaa70856c9ab3446e4a9` |
| Child A operation | `0x6add05a903aa8f57009aea2b7b2951ae4e750b71184c5ec925236bb28ff977f8` |
| Child A receipt | `0x64340d39714010e82f3efa2164b5316fae426be8ba6aded06c8f95d051c098db` |
| Child B operation | `0x22c539cd643f3444be362b9f736b40175d1983a458593a353b96539d697382aa` |
| Child B receipt | `0x13568ae2146d48456dd086964d9625fcaf86fa409259fbb3f5608755b3d52db8` |
| Aggregate receipt | `0x0f65224219c9db8aba9f580012ea3bd2f3d910bd3b88be35fb9f07d1bd3795af` |
| Transactions | `38`, all status `0x1` |
| Readback | `20 gTST`, `closed=true` |

This proves a campaign can aggregate multiple live child Pull receipts into a final campaign close receipt.

Generated receipt artifacts:

```text
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.json
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.card.svg
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.link.json
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.qr.png
```

Distribution boundary: the campaign backend proves multi-party contribution aggregation and close. A separate split-payout/multi-recipient distribution primitive is not implemented in this pass.

### 3. Base Sepolia → Monad Testnet cross-chain lane

Path:

```text
state/live/base-monad-crosschain-blocker-20260719T165200Z/
```

Fresh current-source lane:

| Side | Router | App | Adapter |
|---|---|---|---|
| Base Sepolia | `0x6eaD1370111e2E747027C728bDb1AD5C39C33294` | `0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF` | `0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43` |
| Monad Testnet | `0x6F505b2c3d28aE37a2e3DC126440fB60e17A69cf` | `0x740d7406889CC1B447422f28468E7e5A100EE6c1` | `0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC` |

Fresh route attempt:

| Field | Value |
|---|---|
| Operation | `0x7d7091b7ec84fd9df9c10ce73d36db65104093be0f11cb64a51ed72605d2580c` |
| LayerZero GUID | `0xfbdabd378ac63c6426fe79e5ff55b005c99c07bddaa27bf0a13e63090f478789` |
| Base adapter status | `SENT` |
| Monad adapter status | `NONE` |
| LayerZero status | `INFLIGHT`, source `VALIDATING_TX`, destination `WAITING`, DVN `WAITING` |

This proves the cross-chain engine, deployed lane, wiring, and Base source send. It does **not** prove destination execution or terminal cross-chain settlement yet, because the packet has not passed LayerZero DVN validation and Monad `lzReceive` has not been called.

## Evidence integrity

Submission hashes are recorded in:

```text
state/live/SUBMISSION_SHA256SUMS.txt
```

## Tests

Latest backend gate:

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

## Scope for judges

What to evaluate as live:

1. Monad Push/Pull operation lifecycle.
2. Receipt-first settlement model.
3. Multi-contributor campaign receipt aggregation.
4. LayerZero Base→Monad lane deployment and source-send evidence.
5. Honest cross-chain limitation evidence: stuck before app execution at LayerZero DVN validation.

What not to evaluate as claimed complete:

1. Public frontend UX.
2. Completed Base→Monad destination delivery.
3. Completed cross-chain ACK/finalize receipt.

## Submission statement

Glyph demonstrates a receipt-first payment/control plane where links encode operations, not trust assumptions. The live Monad proofs show value operations, separate-address claims, terminal receipts, and campaign aggregation. The Base→Monad work shows a real deployed LayerZero lane and successful Base source send, with the remaining cross-chain completion blocked externally at DVN validation before destination execution.
