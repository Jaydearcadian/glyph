# Cross-Chain Receipt Anchoring

Status: P0 specification.

## Goal

Use Monad as the canonical receipt anchor while preserving honest evidence boundaries for remote-chain actions.

## Complete Flow

```text
1. Source session opens on Base Sepolia.
2. Authenticated source commitment reaches Monad.
3. Destination reserve/delivery occurs on Monad.
4. Monad records the local destination leg.
5. Monad sends delivery acknowledgement to source.
6. Source atomically settles realized obligation and returns STN-Delta.
7. Source sends finalization/refund receipt to Monad.
8. Monad validates conservation and marks RECONCILED or REFUNDED.
```

## Why the Final Return Message Is Required

Destination delivery alone cannot prove that source principal, fees, and residual were handled. Without a final source receipt, the ledger displays `DESTINATION_SETTLED` with source reconciliation pending.

## Remote Proof Admission

Monad cannot infer arbitrary remote state. A remote value leg is admitted only when:

- caller is an allowlisted adapter;
- adapter context proves expected source domain/application;
- message schema/version is supported;
- operation/terms hash matches;
- route nonce and message ID are unused;
- referenced transition is valid.

P0 uses proof kind `AUTHENTICATED_ADAPTER`. Future light-client verification is a distinct implementation and proof kind.

## Source Commitment

The source-open message commits to payer, recovery address, source asset, maximum input, destination terms, expiry, nonce, and source transaction/log reference.

## Destination Evidence

Because the destination ledger and vault are on Monad testnet in the initial demo, destination transfer and state are recorded as `LOCAL_VERIFIED` in the same transaction or through a tightly authorized local call.

## Final Source Evidence

The final receipt includes maximum input, realized principal, realized fees, residual returned, recovery address, terminal source state, transaction hash/log references, and route nonce.

## Partial and Terminal Labels

```text
SOURCE_COMMITTED
DESTINATION_PROVEN
SOURCE_FINALIZATION_PENDING
RECONCILED
REFUNDED
```

No partial label is rendered as final success.

## Retry

Messages and finalization are independently retryable. A failed receipt-anchor message does not undo completed source settlement, but the operation remains unreconciled on Monad until the receipt arrives.

## Indexer

An indexer may join explorer data and provide latency-friendly UI, but its view is non-authoritative. Contract state/events and referenced receipts remain the proof source.
