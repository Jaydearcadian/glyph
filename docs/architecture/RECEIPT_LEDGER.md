# Monad-Anchored Glyph Receipt Ledger

Status: P0 specification.

## Purpose

`GlyphReceiptLedger` is an append-only Monad anchor for operation terms, financial value legs, proof classes, lifecycle state, and STN-Delta reconciliation. It is an audit anchor, not a replacement for chain explorers or an identity oracle.

## Separation

- Receipt ledger: immutable financial facts and lifecycle.
- Attestation registry: identity, purpose, acknowledgement, revocation/supersession.
- SDK/indexer: joins both into one human receipt.

Identity-module changes cannot mutate financial history.

## Operation Record

```solidity
struct OperationRecord {
    bytes32 operationId;
    bytes32 operationType;
    bytes32 proposedPurposeCode;
    address initiator;
    address payer;
    address recipient;
    bytes32 termsHash;
    bytes32 privateContextHash;
    uint64 createdAt;
    uint64 expiry;
    OperationStatus status;
}
```

`operationId` is globally unique and domain-separated. Creation rejects an existing ID.

## Value Leg

```solidity
struct ValueLeg {
    bytes32 legId;
    bytes32 operationId;
    uint64 chainId;
    bytes32 transactionHash;
    uint32 logIndex;
    address asset;
    address from;
    address to;
    uint256 amount;
    bytes32 legType;
    ProofKind proofKind;
    bytes32 proofReference;
}
```

Leg ID:

```text
keccak256(abi.encode(operationId, chainId, transactionHash, logIndex, legType))
```

A mapping stores existence/hash and compact query fields; events carry the complete append-only timeline. The design avoids unbounded arrays in hot write paths.

## Leg Types

```text
SOURCE_AUTHORIZED       (ceiling, not movement)
SOURCE_ESCROWED
DESTINATION_RESERVED    (liability, not movement)
DESTINATION_DELIVERED
PROVIDER_SETTLED
FEE_REALIZED
DELTA_RETURNED
FULL_REFUND
PARTIAL_REFUND
```

UI/accounting must distinguish ceilings/reservations from transfers.

## Writers

Financial append authority is limited to:

- local approved settlement contracts;
- allowlisted authenticated remote adapters;
- approved source-finalization adapters.

A payer or recipient cannot self-report a financial leg as settled.

## Proof Classes

```solidity
enum ProofKind {
    NONE,
    LOCAL_VERIFIED,
    AUTHENTICATED_ADAPTER,
    LIGHT_CLIENT_VERIFIED,
    ISSUER_ATTESTED
}
```

Every event and receipt UI exposes proof kind.

## Reconciliation

```solidity
struct DeltaReconciliation {
    address sourceAsset;
    uint256 maximumInput;
    uint256 realizedPrincipal;
    uint256 realizedFees;
    uint256 residualReturned;
    address recoveryAddress;
    bytes32 sourceFinalizeTx;
}
```

Before `RECONCILED`:

- destination delivered leg exists and satisfies terms;
- source finalization receipt exists;
- recovery address matches terms;
- conservation equation passes;
- operation is not already terminal.

## Suggested Interface

```solidity
function registerOperation(OperationInput calldata input) external;
function appendLocalLeg(ValueLegInput calldata leg) external returns (bytes32 legId);
function appendRemoteLeg(ValueLegInput calldata leg, bytes32 messageId) external returns (bytes32 legId);
function advanceStatus(bytes32 operationId, OperationStatus next) external;
function reconcile(bytes32 operationId, DeltaReconciliation calldata delta) external;
function recordRefund(bytes32 operationId, RefundReceipt calldata refund) external;
```

Exact interfaces are finalized under P1 TDD.

## Events

```text
OperationRegistered
ValueLegAppended
OperationStatusAdvanced
OperationReconciled
OperationRefunded
WriterAuthorizationChanged
```

Events index `operationId`, relevant party, chain, and leg type for efficient indexing.

## Gas/OCC Discipline

- operation-scoped mappings rather than global mutable counters;
- no global volume accumulator;
- no unbounded per-operation arrays in settlement calls;
- deterministic IDs supplied/derived without a shared incrementing nonce;
- aggregate analytics from events/indexer.

## Receipt Completeness

A human receipt may be partial, but labels it accurately:

- destination proven;
- source finalization pending;
- reconciliation complete;
- refund complete.

Only `RECONCILED` or `REFUNDED` is terminal financial success.
