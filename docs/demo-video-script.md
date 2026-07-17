# Glyph — Spark Demo Video Script (< 3 min)

**Goal:** show a real, working on-chain feature (not a stub). Font: calm, confident. No filler.

## 0:00–0:20 — The problem (personal)
- "I kept hitting the same Web3 wall: to share value I either use a burner wallet that
  fragments my capital, or I paste a secret link that MEV bots snipe from the mempool."
- Cut to terminal: `cast` showing a forged vessel + a claimed vessel, balance moving.
- "Glyph solves both — with one self-custodial URL."

## 0:20–0:50 — Value Vessel (front-run-proof)
- Screen: glyph demo (Cloudflare tunnel URL).
- Click "Value Vessel" → enter amount + passcode → Forge.
- Wallet popup → confirm. Show explorer tx.
- Open the share link in a second browser (no wallet) → Claim → front-run-proof signature.
- Point out: passcode lives only in the URL `#fragment`, never sent to the server.

## 0:50–1:40 — Authority Vessel (EIP-7702 session)
- Click "Authority Vessel" → whitelist a target, set drawdown cap + TTL → Forge.
- Show the session id; click Revoke → on-chain revoke confirmed.
- "I can hand a friend or an AI agent a scoped session — capped, whitelisted, revocable —
  without ever sharing my master key."

## 1:40–2:20 — Under the hood (credibility)
- Quick cut to Foundry: `forge test` → "9 passing".
- Show the contract on Monad testnet explorer (code verified, 9376 bytes).
- "The claim signature binds to msg.sender, so a copied mempool tx fails recovery. MEV-proof by construction."

## 2:20–2:50 — Why it's real
- "No fake toasts. Every button hits the live Monad testnet contract."
- Contract: `0xbD3Eef309bDF82479E089bF718b6E8C02DFd818C`

## 2:50–3:00 — Close
- "Glyph — your sovereign address, temporarily delegated. BuildAnything Spark 2026."

**Recording notes:** capture actual wallet confirms + explorer receipts; keep viewport fitted;
one take per flow, cut the waits. Total ~2:55.
