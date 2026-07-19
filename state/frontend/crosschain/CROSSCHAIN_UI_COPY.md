# Cross-chain UI copy

Use this exact stance in the frontend.

## Short label

```text
Base→Monad: source-send proven, destination blocked at LayerZero DVN
```

## Expanded copy

Glyph includes a transparent Base Sepolia → Monad Testnet proof lane. The Base-side escrow and route-send transactions succeeded, the LayerZero packet/GUID is recorded, and both Base/Monad app configs were frozen/readback-good. The packet has not reached Monad `lzReceive`; DVN validation remains `WAITING`, so destination delivery, ACK, and final settlement are **not claimed complete**.

## Do not say

```text
Base→Monad settled
cross-chain complete
destination delivered
ACK finalized
```

## Evidence

```text
state/live/base-monad-crosschain-blocker-20260719T165200Z/evidence.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/fresh-escrow.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/fresh-route.json
state/live/base-monad-crosschain-blocker-20260719T165200Z/layerzero-fresh-guid.json
```
