# Glyph frontend readiness report

Generated: `2026-07-19T17:38:10Z`

Passed: `95`
Failed: `0`

| Check | Status | Detail |
|---|---:|---|
| `path exists: FRONTEND_MANIFEST.md` | ✅ |  |
| `path exists: state/frontend/frontend.manifest.json` | ✅ |  |
| `path exists: state/frontend/monad-testnet.deployment.json` | ✅ |  |
| `path exists: state/frontend/chains/monad-testnet.json` | ✅ |  |
| `path exists: state/frontend/chains/base-sepolia.json` | ✅ |  |
| `path exists: state/frontend/addresses/monad-testnet.json` | ✅ |  |
| `path exists: state/frontend/contracts/glyphContracts.ts` | ✅ |  |
| `path exists: state/frontend/contracts/glyphChains.ts` | ✅ |  |
| `path exists: state/frontend/CONTRACT_METHODS.md` | ✅ |  |
| `path exists: state/frontend/receipts/index.json` | ✅ |  |
| `path exists: state/frontend/proofs/index.json` | ✅ |  |
| `path exists: state/frontend/transactions/index.json` | ✅ |  |
| `path exists: state/frontend/distributions/index.json` | ✅ |  |
| `path exists: state/frontend/crosschain/base-monad.timeline.json` | ✅ |  |
| `path exists: state/frontend/crosschain/CROSSCHAIN_UI_COPY.md` | ✅ |  |
| `path exists: state/frontend/crosschain/layerzero-support-packet.md` | ✅ |  |
| `path exists: state/schemas/link.schema.json` | ✅ |  |
| `path exists: state/schemas/receipt.schema.json` | ✅ |  |
| `manifest schema` | ✅ | glyph.frontend.manifest.v1 |
| `do-not list count` | ✅ | ['do not fix Base→Monad / LayerZero delivery in this package', 'do not add generalized Merkle distribution in this package; explicit-recipient splitter is included', 'do not build an indexer in this package', 'do not add private-key backend signing', 'do not expose fake success-button flows'] |
| `path exists: state/frontend/abi/SourceDeltaRouter.json` | ✅ |  |
| `ABI functions: SourceDeltaRouter` | ✅ | missing= |
| `path exists: state/frontend/abi/DestinationGlyphVault.json` | ✅ |  |
| `ABI functions: DestinationGlyphVault` | ✅ | missing= |
| `path exists: state/frontend/abi/GlyphLayerZeroApplication.json` | ✅ |  |
| `ABI functions: GlyphLayerZeroApplication` | ✅ | missing= |
| `path exists: state/frontend/abi/ContributionCampaign.json` | ✅ |  |
| `ABI functions: ContributionCampaign` | ✅ | missing= |
| `path exists: state/frontend/abi/CampaignPayoutSplitter.json` | ✅ |  |
| `ABI functions: CampaignPayoutSplitter` | ✅ | missing= |
| `path exists: state/frontend/abi/GlyphReceiptLedger.json` | ✅ |  |
| `ABI functions: GlyphReceiptLedger` | ✅ | missing= |
| `path exists: state/frontend/abi/GlyphAttestationRegistry.json` | ✅ |  |
| `ABI functions: GlyphAttestationRegistry` | ✅ | missing= |
| `path exists: state/frontend/abi/TestToken.json` | ✅ |  |
| `ABI functions: TestToken` | ✅ | missing= |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.json` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.card.svg` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.link.json` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.qr.png` | ✅ |  |
| `receipt verifies: Monad Pull receipt` | ✅ | {
  "expectedFinalReceiptHash": "0x91380b49d81d03f0ac938aeba9f1164ccdb6d5224d42325cce1e2c5bd04ae256",
  "ok": true,
  "sourceReceiptHash": "0x91380b49d81d03f0ac |
| `receipt link schema: Monad Pull receipt` | ✅ |  |
| `QR non-empty: Monad Pull receipt` | ✅ | 5077 |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.json` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.card.svg` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.link.json` | ✅ |  |
| `path exists: state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.qr.png` | ✅ |  |
| `receipt verifies: Monad Push receipt` | ✅ | {
  "expectedFinalReceiptHash": "0xc4b5eb516bb24ae18b93e500b7d4fba5b6601a581d38d9e9a209f41f8c1782ff",
  "ok": true,
  "sourceReceiptHash": "0xc4b5eb516bb24ae18b |
| `receipt link schema: Monad Push receipt` | ✅ |  |
| `QR non-empty: Monad Push receipt` | ✅ | 4930 |
| `path exists: state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.json` | ✅ |  |
| `path exists: state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.card.svg` | ✅ |  |
| `path exists: state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.link.json` | ✅ |  |
| `path exists: state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.qr.png` | ✅ |  |
| `receipt verifies: Monad campaign aggregate receipt` | ✅ | {
  "expectedFinalReceiptHash": "0x5840cf2cd3ec307731c13824646d49f81e6b6aabf963be7c4580cb3231919d22",
  "ok": true,
  "sourceReceiptHash": "0x5840cf2cd3ec307731 |
| `receipt link schema: Monad campaign aggregate receipt` | ✅ |  |
| `QR non-empty: Monad campaign aggregate receipt` | ✅ | 5274 |
| `path exists: state/live/monad-distribution-proof-20260719T172223Z/aggregate.distribution.receipt.json` | ✅ |  |
| `path exists: state/live/monad-distribution-proof-20260719T172223Z/aggregate.distribution.receipt.card.svg` | ✅ |  |
| `path exists: state/live/monad-distribution-proof-20260719T172223Z/aggregate.distribution.receipt.link.json` | ✅ |  |
| `path exists: state/live/monad-distribution-proof-20260719T172223Z/aggregate.distribution.receipt.qr.png` | ✅ |  |
| `distribution receipt schema: Aggregate distribution receipt` | ✅ | glyph.distribution.aggregateReceipt.v1 |
| `receipt link schema: Aggregate distribution receipt` | ✅ | distribution/simple receipt link |
| `QR non-empty: Aggregate distribution receipt` | ✅ | 2060 |
| `proof count` | ✅ | 4 |
| `crosschain marked blocked` | ✅ | source-send-proven-destination-blocked |
| `crosschain no settlement claim` | ✅ | not_delivered stage required |
| `path exists: state/frontend/flows/pull.flow.json` | ✅ |  |
| `flow schema: pull` | ✅ | glyph.frontend.flow.v1 |
| `path exists: state/frontend/flows/push.flow.json` | ✅ |  |
| `flow schema: push` | ✅ | glyph.frontend.flow.v1 |
| `path exists: state/frontend/flows/campaign.flow.json` | ✅ |  |
| `flow schema: campaign` | ✅ | glyph.frontend.flow.v1 |
| `path exists: state/frontend/flows/distribution.flow.json` | ✅ |  |
| `flow schema: distribution` | ✅ | glyph.frontend.flow.v1 |
| `path exists: state/frontend/flows/receipt.flow.json` | ✅ |  |
| `flow schema: receipt` | ✅ | glyph.frontend.flow.v1 |
| `path exists: state/frontend/flows/crosschain-proof.flow.json` | ✅ |  |
| `flow schema: crosschain-proof` | ✅ | glyph.frontend.flow.v1 |
| `live code: monadCore.adapter` | ✅ | 0x608060405260043610610054575f3560e01c806304f7dd62146100585780630fa566fa1461007e |
| `live code: monadCore.destinationApp` | ✅ | 0x6080604052600436106101f4575f3560e01c80639db1cb6611610108578063e05598411161009d |
| `live code: monadCore.router` | ✅ | 0x608060405234801561000f575f80fd5b5060043610610208575f3560e01c806392584d80116101 |
| `live code: monadCore.sourceApp` | ✅ | 0x6080604052600436106101f4575f3560e01c80639db1cb6611610108578063e05598411161009d |
| `live code: monadCore.token` | ✅ | 0x608060405234801561000f575f80fd5b50600436106100e5575f3560e01c806340c10f19116100 |
| `live code: monadCore.vault` | ✅ | 0x608060405234801561000f575f80fd5b506004361061011c575f3560e01c80637ecf686d116100 |
| `live code: monadCampaign.adapter` | ✅ | 0x608060405260043610610054575f3560e01c806304f7dd62146100585780630fa566fa1461007e |
| `live code: monadCampaign.campaign` | ✅ | 0x608060405234801561000f575f80fd5b5060043610610060575f3560e01c80630bbc2ded146100 |
| `live code: monadCampaign.destinationApp` | ✅ | 0x6080604052600436106101f4575f3560e01c80639db1cb6611610108578063e05598411161009d |
| `live code: monadCampaign.router` | ✅ | 0x608060405234801561000f575f80fd5b5060043610610208575f3560e01c806392584d80116101 |
| `live code: monadCampaign.sourceApp` | ✅ | 0x6080604052600436106101f4575f3560e01c80639db1cb6611610108578063e05598411161009d |
| `live code: monadCampaign.token` | ✅ | 0x608060405234801561000f575f80fd5b50600436106100e5575f3560e01c806340c10f19116100 |
| `live code: monadCampaign.vault` | ✅ | 0x608060405234801561000f575f80fd5b506004361061011c575f3560e01c80637ecf686d116100 |
| `live code: monadDistribution.campaign` | ✅ | 0x608060405234801561000f575f80fd5b506004361061007a575f3560e01c80634b0405e3116100 |
| `live code: monadDistribution.splitter` | ✅ | 0x608060405234801561000f575f80fd5b5060043610610090575f3560e01c806398e5c5e1116100 |
| `live code: monadDistribution.token` | ✅ | 0x608060405234801561000f575f80fd5b50600436106100e5575f3560e01c806340c10f19116100 |
