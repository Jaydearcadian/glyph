# Glyph — submission social post

## Short post

Built Glyph on Monad: link-native Web3 operations that settle as receipts, not promises.

What is live now:

- Pull payment on Monad testnet
- Push claim on Monad testnet
- Terminal receipt delivery on Monad loopback
- Two-contributor campaign aggregation into one close receipt
- Live receipt JSON, SVG card, receipt-link JSON, and QR PNG artifacts generated from proof bundles
- Base Sepolia → Monad Testnet LayerZero lane deployed/wired/frozen, with live Base source-send evidence

Honest boundary: Base→Monad destination delivery is not claimed complete yet. LayerZero sees the packet, but DVN validation is still waiting before Monad `lzReceive`.

Evidence-first submission:

```text
SUBMISSION.md
state/live/monad-address-pair-proof-20260719T130942Z/
state/live/monad-campaign-proof-20260719T132755Z/
state/live/base-monad-crosschain-blocker-20260719T165200Z/
```

75 Foundry tests passing.

#Monad #BuildAnything #Web3 #LayerZero

## One-liner

Glyph turns links into verifiable payment operations: live Monad Push/Pull and campaign receipts, plus Base→Monad source-send evidence with the LayerZero DVN blocker isolated.
