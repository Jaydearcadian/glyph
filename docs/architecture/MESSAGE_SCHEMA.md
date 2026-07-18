# Cross-Chain Message Schema

Status: P0 specification. Transport encoding remains adapter-specific; semantic payloads are versioned and messenger-neutral.

## Envelope

```solidity
struct GlyphMessageEnvelope {
    uint16 version;
    uint8 messageType;
    bytes32 messageId;
    bytes32 operationId;
    uint64 sourceChainId;
    uint64 destinationChainId;
    address sourceApplication;
    address destinationApplication;
    uint64 routeNonce;
    bytes payload;
}
```

`messageId` is deterministic over the complete envelope excluding itself or provided by the adapter and mapped to an envelope hash. The receiver validates chain/application domains from trusted adapter context, not payload assertions alone.

## Message Types

```text
ROUTE_PULL
RESERVE_PUSH
CANCEL_OR_EXPIRE
DESTINATION_SETTLED_ACK
DESTINATION_FAILED_ACK
SOURCE_FINALIZED_RECEIPT
SOURCE_REFUNDED_RECEIPT
```

## Route Instruction

```solidity
struct RouteInstructionV1 {
    bytes32 termsHash;
    address payer;
    address recipient;
    address recoveryAddress;
    address sourceAsset;
    address destinationAsset;
    uint256 maximumInput;
    uint256 destinationAmount;
    uint256 maximumFee;
    uint64 expiry;
    address gatekeeper;
}
```

`gatekeeper` is zero for an exact-recipient Pull and nonzero for a Push claim rule. The signed terms determine interpretation; adapters cannot modify it.

## Destination Acknowledgement

```solidity
struct DestinationSettlementAckV1 {
    bytes32 operationId;
    bytes32 termsHash;
    address claimantOrRecipient;
    address destinationAsset;
    uint256 deliveredAmount;
    bytes32 destinationTxHash;
    uint32 destinationLogIndex;
    bytes32 destinationLegId;
    uint64 routeNonce;
}
```

The source accepts it only from the configured destination application/domain and only once.

## Source Final Receipt

```solidity
struct SourceFinalReceiptV1 {
    bytes32 operationId;
    bytes32 termsHash;
    address sourceAsset;
    uint256 maximumInput;
    uint256 realizedPrincipal;
    uint256 realizedFees;
    uint256 residualReturned;
    address recoveryAddress;
    bytes32 sourceTxHash;
    uint32 settlementLogIndex;
    uint32 residualLogIndex;
    uint64 routeNonce;
}
```

Monad marks `RECONCILED` only if the conservation equation passes and prior destination evidence matches.

## Failure Acknowledgement

Failure payloads contain a typed reason code, no arbitrary revert strings as canonical state:

```text
LIQUIDITY_UNAVAILABLE
TERMS_EXPIRED
INVALID_DESTINATION_TERMS
UNSUPPORTED_ASSET
CLAIM_NOT_COMPLETED
ADAPTER_FAILURE
```

A negative acknowledgement does not automatically authorize refund if destination-delivery ambiguity exists.

## Replay Protection

Receivers track at least:

```text
consumedMessageId
consumed(operationId, messageType, routeNonce)
```

Retries may re-deliver the same semantic message but cannot duplicate economic effects.

## Encoding Rules

- Use fixed-width EVM types and `abi.encode`, not ambiguous packed encoding for signed/domain-bearing structures.
- Version every envelope and payload.
- Reject unknown versions/types fail-closed.
- Hash variable metadata separately and bind the hash in terms.
- Do not transmit link-fragment secrets.
- Do not transmit raw PII or private billing text.

## Configuration

Deployment manifests bind:

- local chain ID;
- remote chain ID/domain/EID;
- adapter address;
- remote application address;
- message schema version;
- proof kind.

Configuration changes are privileged, delayed/controlled, emitted, and verified after deployment.
