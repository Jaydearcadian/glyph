# Cross-Chain STN-Delta Architecture

Status: P0 specification; no implementation or deployment claim.

## Goal

Allow a payer to authorize a bounded maximum source input, deliver an exact value on a destination chain, settle only the realized source obligation, and atomically return the unused residual on source-chain closure.

## Testnet Reference Topology

```text
Base Sepolia (84532, LayerZero V2 EID 40245)
    SourceDeltaRouter + TestUSDC
              ↕ authenticated messages
Monad testnet (10143, LayerZero V2 EID 40204)
    DestinationGlyphVault + TestUSDC + Receipt Ledger
```

Destination TestUSDC is pre-funded demo liquidity. This proves authenticated two-chain settlement and accounting; it is not called production liquidity or Relay testnet routing.

## Session Terms

A route session binds:

```text
operationId, operationType, version
sourceChainId, sourceRouter, sourceAsset
destinationChainId, destinationVault, destinationAsset
payer, recipient/claim rule, recoveryAddress
maximumInput, destinationAmount, maximumFee
expiry, routeNonce, termsHash
```

## Accounting

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

- `maximumInput`: transferred into source escrow.
- `realizedPrincipal`: amount owed to the destination liquidity provider after valid delivery proof.
- `realizedFees`: bounded route/messaging/protocol fees actually charged.
- `residualReturned`: remainder transferred to the bound recovery address.

## Source Finalization

One source-chain transaction MUST:

1. verify authenticated destination acknowledgement;
2. calculate bounded realized obligation;
3. set remaining balance to zero;
4. set terminal source status;
5. settle principal/fees;
6. transfer residual to recovery address;
7. emit settlement and residual events.

Any transfer failure reverts the whole local finalization. A stored acknowledgement allows permissionless retry.

## Pull

1. Recipient creates immutable exact-output terms.
2. Payer chooses a supported source and funds `maximumInput`.
3. Source dispatches route instruction.
4. Destination vault pays exact recipient amount.
5. Destination records payout and sends acknowledgement.
6. Source finalizes and flushes delta.
7. Final source receipt is returned to Monad for reconciliation.

## Push

1. Sender funds source session and creates claimant-safe operation.
2. Destination vault reserves liquidity but does not pay yet.
3. Recipient opens fragment-secret link and signs a claimant-bound claim.
4. Destination vault pays claimant once.
5. Destination acknowledgement unlocks source settlement.
6. Source finalizes and flushes delta.
7. Final receipt returns to Monad.

If Push expires before destination payout, destination reservation releases and source full-refund becomes available after the defined safety/finality condition.

## Atomicity Boundary

The following are separate transactions:

- source open;
- destination reserve/delivery;
- source finalize/flush;
- final Monad receipt anchor.

Only source finalize/flush is atomic. Public language is “asynchronous cross-chain settlement with atomic STN-Delta source closure.”

## Adapter Boundary

Core contracts depend on an interface conceptually equivalent to:

```solidity
interface IGlyphMessenger {
    function quote(uint64 destinationChainId, bytes calldata payload)
        external view returns (uint256 nativeFee);
    function send(uint64 destinationChainId, address receiver, bytes calldata payload)
        external payable returns (bytes32 messageId);
}
```

Inbound adapters call domain-checked receive functions. LayerZero-specific endpoint IDs, options, DVNs, executors, and message formats stay in adapter/configuration layers.

## Failure and Recovery

- Quote expired before open: reject and requote.
- Source message delayed: session remains pending; no provider settlement.
- Destination liquidity unavailable: reject/negative acknowledgement; source eventually refundable.
- Destination delivered, acknowledgement delayed: no refund until delivery ambiguity resolves.
- Callback finalization fails: store acknowledgement; retry `finalizeAndFlush`.
- Final receipt message fails: source remains finalized; retry only the receipt anchor.
- Duplicate message: consumed message/operation nonce makes it idempotent or rejects it.

## Production Boundary

Relay exact-output routing is a future mainnet adapter candidate. The P0/P1/P2 design must not hard-code Relay and must not claim Relay supports Monad testnet 10143.
