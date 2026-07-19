# Glyph — submission demo script (< 3 min)

**Goal:** show the real backend proofs and avoid claiming a frontend or completed cross-chain delivery that is not live yet.

## 0:00–0:20 — Problem

- "Most crypto links are either secret bearer links or wallet-fragmenting workarounds. Glyph makes a link an operation: typed terms, escrow, destination delivery, and receipts."
- Show `SUBMISSION.md` headline and the proof table.

## 0:20–1:05 — Live Monad Push/Pull proof

- Open `state/live/monad-address-pair-proof-20260719T130942Z/README.md`.
- Point to:
  - payer address
  - separate claimant/recipient address
  - Pull op
  - Push op
  - Pull receipt
  - Push receipt
  - `34` txs, all `0x1`
- Say: "This is the core: one link-native operation, live on Monad testnet, with terminal receipts."

## 1:05–1:45 — Campaign aggregation proof

- Open `state/live/monad-campaign-proof-20260719T132755Z/README.md`.
- Point to:
  - two child operations
  - two child receipts
  - aggregate campaign receipt
  - readback `20 gTST`, `closed=true`
- Say: "Campaigns are just higher-order operations: child Pull receipts reconcile into a campaign close receipt."

## 1:45–2:25 — Cross-chain engine evidence

- Open `state/live/base-monad-crosschain-blocker-20260719T165200Z/README.md`.
- Show fresh Base and Monad app/adapter addresses.
- Show the fresh operation and LayerZero GUID.
- Say: "The Base→Monad lane is deployed, wired, frozen, and source-send proven. The packet is visible in LayerZero Scan, but DVN validation is still waiting before Monad `lzReceive`, so we do not claim destination settlement yet."

## 2:25–2:45 — Quality gate

- Show terminal or commit log:
  - `forge fmt`
  - `forge build --force`
  - `forge test`
  - `75 tests passed, 0 failed`
- Show recent commits:
  - address-pair proof
  - campaign proof
  - cross-chain blocker evidence

## 2:45–3:00 — Close

- "Glyph: links that settle as operations, not promises. Live Monad proofs are complete; cross-chain source send is live, with the remaining delivery blocker isolated at LayerZero DVN validation."

**Recording notes:** keep it evidence-first. Avoid old Value Vessel / Authority Vessel frontend claims unless a current frontend is separately restored and verified.
