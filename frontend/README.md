# Glyph frontend

Interactive, static-exportable judge demo for Glyph’s Monad payment-link protocol.

## Routes

| Route | Surface |
|---|---|
| `/` | Product landing and receipt-led lifecycle overview |
| `/links` | Live gTST faucet, exact approval, Pull/Push escrow, transaction readback |
| `/campaign` | Campaign creation plus shareable contribution links that bind `programId`, recipient, and suggested amount |
| `/distribution` | Full recipient wallets, live conservation, explicit 70/20/10 creation, share links, and claims |
| `/receipts` | Receipt JSON/card/link/QR gallery |
| `/proofs` | Proof bundle dashboard and explicit cross-chain blocker boundary |

## Run

```bash
npm install
npm run dev
```

The pre-dev hook copies canonical ABIs, indexes, and evidence from `../state/` into local app data and `public/glyph-data/`.

## Validate and export

```bash
npm run lint
npm run typecheck
npm run build
npm run start
```

`npm run build` exports the site to `out/`.

## Chain scope

- Network: Monad Testnet (`10143`)
- Wallet transport: injected EIP-1193 provider through `wagmi`
- Contract/RPC client: `viem`
- User writes: demo gTST mint, exact approval, Pull/Push escrow, campaign creation, eligible distribution claim
- Evidence-only lifecycle steps: provider routing, terminal settlement/reconciliation, completed campaign/distribution proofs
- Cross-chain: displayed only as tested source-send evidence with destination DVN blocker; no interactive cross-chain action or settlement claim

## Security and product boundaries

- No API server, indexer, server signer, relayer, or private key.
- No UI-only success state: writes wait for transaction receipts and direct contract readback.
- Push secret material remains browser-local and is placed only in the URL fragment after confirmed escrow.
- Distribution claims fail closed when the connected wallet has no eligible unclaimed share.
- Bundled proof files are copied from canonical repository artifacts at build time.
