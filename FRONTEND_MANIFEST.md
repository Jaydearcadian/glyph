# Glyph frontend integration manifest

Generated: `2026-07-19T16:42:01Z`

Scope: ambitious pre-frontend backend readiness package. This repository still does **not** contain or modify a frontend app.

## Product position

Glyph is link-native payment infrastructure on Monad: Push/Pull payment links, campaign contribution aggregation, explicit-recipient payout splitting, QR/shareable receipts, and transparent cross-chain proof evidence.

## Hard boundaries

```text
No frontend app is created here.
No Base→Monad destination delivery/final settlement is claimed.
No generalized Merkle distribution primitive is included; the included splitter is explicit-recipient only.
No indexer is included.
No private-key backend signing is included.
No fake success-button flows are permitted.
```

## Canonical frontend package

| Surface | Path |
|---|---|
| Frontend machine manifest | `state/frontend/frontend.manifest.json` |
| Monad chain config | `state/frontend/chains/monad-testnet.json` |
| Contract addresses | `state/frontend/addresses/monad-testnet.json` |
| TypeScript contract constants | `state/frontend/contracts/glyphContracts.ts` |
| TypeScript chain constants | `state/frontend/contracts/glyphChains.ts` |
| ABI exports | `state/frontend/abi/` |
| Contract method map | `state/frontend/CONTRACT_METHODS.md` |
| Flow specs | `state/frontend/flows/` |
| Distribution index | `state/frontend/distributions/index.json` |
| Receipt index | `state/frontend/receipts/index.json` |
| Proof index | `state/frontend/proofs/index.json` |
| Transaction index | `state/frontend/transactions/index.json` |
| Cross-chain timeline | `state/frontend/crosschain/base-monad.timeline.json` |
| Cross-chain UI copy | `state/frontend/crosschain/CROSSCHAIN_UI_COPY.md` |
| LayerZero support packet | `state/frontend/crosschain/layerzero-support-packet.md` |
| Readback script | `scripts/frontend_readback.py` |
| Readiness validator | `scripts/validate_frontend_readiness.py` |

## Canonical Monad core stack

```json
{
  "router": "0xC71C119B91Fa1F1861626843Fa653F41cEF9101A",
  "token": "0x1d482783316FdeF2e795A1C193ACE280660A887a",
  "vault": "0xfb2a436Cf72C6FbCc4cCd1A5A4Adef015F370Ca9",
  "adapter": "0x2BC2F59Ae8a01F5698407E58a1828FB51FBa5Db2",
  "sourceApp": "0xc3D5005A9beCfCcd28A6E66C2d8CC6E5fe3B0854",
  "destinationApp": "0xA741e81349733Ac4612AF269A92f2e08F9034307"
}
```

## Campaign stack

```json
{
  "router": "0xC71C119B91Fa1F1861626843Fa653F41cEF9101A",
  "token": "0x1d482783316FdeF2e795A1C193ACE280660A887a",
  "vault": "0xb4E40ecEEc4A0498A183EC14EB52B5e0C2434c77",
  "adapter": "0x8Fdffc7D35c0d3A5662264b05b35d184d7209b57",
  "sourceApp": "0x63Df5199052915653A8373a1a55329175135D42D",
  "destinationApp": "0xDf62c61C73c879921911deE9e8727D797cBD5716",
  "campaign": "0xc1734449aeca5e45E570afd862f47Ff0eE03bEd1"
}
```

## Distribution stack

```json
{
  "token": "0x1d482783316FdeF2e795A1C193ACE280660A887a",
  "campaign": "0x34ebCe467EcB6cA5D9f0E9d5bF3C23b9E2B191bb",
  "splitter": "0x3f90710e945f1BFa07737B97676056DF3F92Db59",
  "distributionId": "0xe91b66e0fd1df23dbd317fc1119202f2460458da2fc276a55627b342f87f888a"
}
```

Proof bundle: `state/live/monad-distribution-proof-20260719T172223Z/`.

## Cross-chain fresh lane

```json
{
  "orderedExecution": false,
  "baseRouter": "0x6eaD1370111e2E747027C728bDb1AD5C39C33294",
  "baseVault": "0xb949494E4430F666174a57d0E0dd4b98c0b7854B",
  "baseToken": "0x4cBA226A903f44E33446f55499c57147DC03EE82",
  "baseApp": "0xC6C320fB20fF4A5d8E6f5A2FCa5F430A8e43a7AF",
  "baseAdapter": "0xC8Cb1aB6aA5830cF5B928e6152015f3d4C3Ebc43",
  "monadRouter": "0x6F505b2c3d28aE37a2e3DC126440fB60e17A69cf",
  "monadVault": "0x757e30bb637860E2D89F9a85D5A5A5e49313153A",
  "monadToken": "0xed4152e5a8ea20192BA9B0B4319A2615416341B0",
  "monadApp": "0x740d7406889CC1B447422f28468E7e5A100EE6c1",
  "monadAdapter": "0x8a5AfbBBcA3F3Fae0014f58eF25E436DD14d5EEC"
}
```

## Required frontend UX stance

- Show Pull, Push, campaign, distribution, receipt, and cross-chain panels.
- Treat user-safe wallet writes separately from provider/operator lifecycle steps.
- Render proof-backed steps as evidence, not fake click success.
- Render cross-chain as source-send proven + LayerZero/DVN blocked, not settled.
- Keep private claim secrets fragment-only.

## Validation

Run:

```bash
python3 scripts/validate_frontend_readiness.py
```

Optional live RPC readbacks:

```bash
python3 scripts/frontend_readback.py --live-rpc
python3 scripts/validate_frontend_readiness.py --live-rpc
```
