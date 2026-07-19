# Glyph contract method map for frontend

## General frontend rules

- User wallet actions may prepare/sign/broadcast only the user's own transactions.
- Provider/operator lifecycle actions must be labeled as proof-backed/operator actions unless a user-safe path is tested.
- Never render hardcoded success after a write; wait for receipt and readback.

## ERC20 / TestToken

Reads:

```text
symbol()
decimals()
balanceOf(address)
allowance(owner, spender)
```

Writes:

```text
approve(spender, amount)
```

## SourceDeltaRouter

Reads:

```text
actorNonce(address)
operationId(Terms)
hashTerms(Terms)
routeFacts(bytes32 op)
payoutFacts(bytes32 op)
sourceReceiptFacts(bytes32 op)
operations(bytes32 op)
```

Writes:

```text
escrow(Terms)
escrowWithSignature(Terms, deadline, sig)
finalize(bytes32 op)
refund(bytes32 op)
```

Frontend status:

```text
approve + escrow can be transaction-first user wallet actions.
route/finalize/refund must be exposed only when preconditions and authority are clear.
```

## GlyphLayerZeroApplication

Reads/config:

```text
adapter()
remoteApplication(...)
owner()
```

Writes used in live proofs:

```text
sendRouteFromEscrow(bytes32 op, address payable provider, uint256 gasLimit)
claimPushAndAck(...)
finalizeAndSendReceipt(bytes32 op, address payable provider, uint256 gasLimit)
```

Frontend status:

```text
Proof-backed now; user-facing buttons only after exact authority and preconditions are tested in browser wallet flow.
```

## DestinationGlyphVault

Reads/writes used by proof flow:

```text
provideLiquidity(address token, uint256 amount)
reservePull / reservePush / deliverPull / claimPush / release depending ABI path
```

Frontend status:

```text
Mostly provider/liquidity actions; expose as proof/state unless user is explicitly acting as provider.
```

## ContributionCampaign

Reads:

```text
campaigns(bytes32 programId)
childAmounts / childReceipts as ABI exposes
```

Writes:

```text
create(bytes32 programId, Campaign)
reconcileChild(bytes32 programId, bytes32 childOp, uint256 amount, bytes32 receiptHash)
close(bytes32 programId)
```

Frontend status:

```text
create/close may be user-facing if preconditions are visible; reconcileChild is operator/proof-backed unless a safe authority model is added.
```

## Receipt artifacts

Receipt JSON/card/link/QR artifacts are already generated under live proof bundles and indexed at:

```text
state/frontend/receipts/index.json
```

## Cross-chain

Cross-chain is proof-only for this submission:

```text
Base escrow/send: success
LayerZero GUID: visible/inflight
DVN: WAITING
Monad lzReceive/ACK/finalize: not complete
```
