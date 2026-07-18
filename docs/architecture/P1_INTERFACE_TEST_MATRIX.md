# P1 Interface / Event / Test Matrix

Status: **reviewed draft — subordinate to `P1_LOCKED_DECISIONS.md` where any conflict exists.**

Scope: `GlyphReceiptLedger` and `GlyphAttestationRegistry` only.
This document is clerical/specification work. It does not change Solidity.

P1 exclusions are explicit at the end of this document.

## 1) Contract boundaries and authorized actors

### GlyphReceiptLedger

Purpose: immutable operation headers, financial value legs, proof classes, lifecycle state, and reconciliation.

Authorized writers:

| Surface | Authorized actor(s) | Notes |
|---|---|---|
| `registerOperation` | operation creator, or an explicitly approved factory | must be domain-bound and duplicate-free |
| `appendLocalLeg` | local settlement contract only | financial fact write; no payer/recipient self-reporting |
| `appendRemoteLeg` | allowlisted authenticated remote adapter only | remote receipt leg must declare proof kind |
| `advanceStatus` | approved settlement/finalization adapter, or contract owner/admin for non-fund metadata transitions only if explicitly allowed by spec | status changes remain enumerated and append-only |
| `reconcile` | approved source-finalization adapter only | must satisfy conservation and terminality checks |
| `recordRefund` | approved source-finalization adapter only | recovery-address bound; no double terminal outcome |
| `configureWriterAuthorization` | contract owner / admin role | emits writer authorization changes |

Read access is public for all indexed receipt data.

Forbidden actors:

- payer or recipient acting as a financial writer;
- counterparty writing the other party’s identity;
- any unallowlisted messenger, relayer, or router;
- any token contract or vault contract outside approved writer paths.

### GlyphAttestationRegistry

Purpose: append-only identity claims, operation bindings, acknowledgements, purpose attestations, supersession, and revocation.

Authorized actors:

| Surface | Authorized actor(s) | Notes |
|---|---|---|
| `registerSelfIdentity` | subject itself (`msg.sender == subject`) or subject-authorized signer path | self-asserted only |
| `registerIdentityWithSignature` | relayer plus subject EIP-712 signature or EIP-1271 approval | relayer may submit but not alter content |
| `registerIdentityWithIssuerProof` | allowlisted issuer scheme only | issuer path must identify subject and evidence |
| `bindIdentity` | subject itself, or subject-authorized signature / EIP-1271 path | binds claim snapshot to an operation |
| `acknowledgeIdentity` | payer or recipient for the counterparty’s existing claim on a specific operation | acknowledgement is not verification |
| `attestPurpose` | initiator, payer, or recipient; relayers may submit signed payloads | append-only; no overwrite |
| `supersedeIdentity` | claim subject or authorized issuer path | supersession is append-only |
| `revokeIdentity` | claim subject, or issuer under the explicit issuer rules | revocation is append-only |

Forbidden actors:

- payer writing recipient identity without recipient authorization;
- recipient writing payer identity without payer authorization;
- any caller attempting to mutate historical claim snapshots;
- any caller attempting to present self-asserted identity as issuer-verified.

## 2) Proposed enums, structs, errors, events, and external functions

### Stable enums

Use enums only where the states are truly finite and closed.
Versioned operation and purpose codes remain `bytes32` values.

```solidity
enum OperationStatus {
    NONE,
    REGISTERED,
    SOURCE_AUTHORIZED,
    SOURCE_ESCROWED,
    ROUTE_PENDING,
    DESTINATION_RESERVED,
    DESTINATION_SETTLED,
    SOURCE_FINALIZED,
    RECONCILED,
    REFUND_PENDING,
    REFUNDED,
    EXPIRED,
    ROUTE_FAILED
}

enum ProofKind {
    NONE,
    LOCAL_VERIFIED,
    AUTHENTICATED_ADAPTER,
    LIGHT_CLIENT_VERIFIED,
    ISSUER_ATTESTED
}

enum VerificationLevel {
    SELF_ASSERTED,
    COUNTERPARTY_ACKNOWLEDGED,
    ISSUER_VERIFIED
}

enum ClaimStatus {
    ACTIVE,
    SUPERSEDED,
    REVOKED
}
```

`EXPIRED` for identity claims is a derived view from `expiresAt`, not a mutation that erases history.

### Proposed structs

```solidity
struct OperationTerms {
    bytes32 operationType;
    bytes32 proposedPurposeCode;
    address initiator;
    address payer;
    address recipient;
    address recoveryAddress;
    uint64 sourceChainId;
    uint64 destinationChainId;
    address sourceAsset;
    address destinationAsset;
    uint256 maximumInput;
    uint256 destinationAmount;
    bytes32 termsHash;
    bytes32 privateContextHash;
    uint64 createdAt;
    uint64 expiry;
    uint64 nonce;
}

struct OperationRecord {
    bytes32 operationId;
    bytes32 termsHash;
    address initiator;
    address payer;
    address recipient;
    uint64 createdAt;
    uint64 expiry;
    OperationStatus status;
}

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

struct ValueLegInput {
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

struct DeltaReconciliation {
    address sourceAsset;
    uint256 maximumInput;
    uint256 realizedPrincipal;
    uint256 realizedFees;
    uint256 residualReturned;
    address recoveryAddress;
    bytes32 sourceFinalizeTx;
}

struct RefundReceipt {
    address sourceAsset;
    address recoveryAddress;
    uint256 amount;
    bytes32 refundTx;
    ProofKind proofKind;
}

struct IdentityClaim {
    bytes32 claimId;
    address subject;
    bytes32 namespace;
    bytes32 identifierCommitment;
    address issuer;
    bytes32 attestationReference;
    uint64 issuedAt;
    uint64 expiresAt;
    VerificationLevel level;
    ClaimStatus status;
}

struct IdentityClaimInput {
    address subject;
    bytes32 namespace;
    bytes32 identifierCommitment;
    address issuer;
    bytes32 attestationReference;
    uint64 issuedAt;
    uint64 expiresAt;
    VerificationLevel level;
    uint256 nonce;
    uint64 deadline;
}

struct OperationIdentityBinding {
    bytes32 operationId;
    bytes32 claimId;
    address subject;
    bytes32 role;
    uint64 boundAt;
}

struct OperationIdentityBindingInput {
    bytes32 operationId;
    bytes32 claimId;
    address subject;
    bytes32 role;
    uint64 boundAt;
    uint256 nonce;
    uint64 deadline;
}

struct PurposeAttestation {
    bytes32 attestationId;
    bytes32 operationId;
    address attestor;
    bytes32 purposeCode;
    bytes32 contextHash;
    bytes32 supersedesAttestationId;
    uint64 attestedAt;
}

struct PurposeAttestationInput {
    bytes32 operationId;
    bytes32 purposeCode;
    bytes32 contextHash;
    bytes32 supersedesAttestationId;
    uint64 attestedAt;
    uint256 nonce;
    uint64 deadline;
}
```

### Proposed errors

```solidity
error DuplicateOperationId(bytes32 operationId);
error DuplicateLegId(bytes32 legId);
error InvalidOperationTransition(bytes32 operationId, OperationStatus currentStatus, OperationStatus nextStatus);
error TerminalOperation(bytes32 operationId, OperationStatus status);
error UnauthorizedFinancialWriter(address caller);
error ProofKindMismatch(ProofKind provided, ProofKind expected);
error UnsupportedProofKind(ProofKind proofKind);
error InvalidConservationEquation(uint256 maximumInput, uint256 realizedPrincipal, uint256 realizedFees, uint256 residualReturned);
error MissingRequiredReceipt(bytes32 operationId, bytes32 requirement);
error RecoveryAddressMismatch(address expectedRecoveryAddress, address actualRecoveryAddress);
error UnauthorizedSubject(address caller, address subject);
error InvalidIdentityLevel(VerificationLevel level);
error ClaimExpired(bytes32 claimId);
error ClaimRevoked(bytes32 claimId);
error ClaimSuperseded(bytes32 claimId);
error ClaimNonceUsed(address subject, uint256 nonce);
error InvalidEIP712Domain();
error InvalidSignature();
error InvalidEIP1271Signature(address subject);
error PurposeAttestationOverwrite(bytes32 operationId, address attestor);
error PurposeConsensusConflict(bytes32 operationId);
error HistoricalClaimImmutable(bytes32 claimId);
error ReplayOrNullifierConsumed(bytes32 id);
```

### Proposed events

```solidity
event OperationRegistered(
    bytes32 indexed operationId,
    bytes32 indexed operationType,
    bytes32 indexed proposedPurposeCode,
    address initiator,
    address payer,
    address recipient,
    bytes32 termsHash,
    bytes32 privateContextHash,
    uint64 createdAt,
    uint64 expiry
);

event OperationStatusAdvanced(
    bytes32 indexed operationId,
    OperationStatus previousStatus,
    OperationStatus nextStatus,
    address actor,
    bytes32 evidenceReference
);

event ValueLegAppended(
    bytes32 indexed legId,
    bytes32 indexed operationId,
    uint64 chainId,
    bytes32 indexed legType,
    address asset,
    address from,
    address to,
    uint256 amount,
    ProofKind proofKind,
    bytes32 proofReference
);

event OperationReconciled(
    bytes32 indexed operationId,
    address sourceAsset,
    uint256 maximumInput,
    uint256 realizedPrincipal,
    uint256 realizedFees,
    uint256 residualReturned,
    address recoveryAddress,
    bytes32 sourceFinalizeTx
);

event OperationRefunded(
    bytes32 indexed operationId,
    address sourceAsset,
    address recoveryAddress,
    uint256 amount,
    bytes32 refundTx,
    ProofKind proofKind
);

event WriterAuthorizationChanged(
    address indexed writer,
    bool allowed,
    bytes32 indexed writerRole,
    address indexed admin
);

event IdentityClaimRegistered(
    bytes32 indexed claimId,
    address indexed subject,
    bytes32 indexed namespace,
    bytes32 identifierCommitment,
    address issuer,
    bytes32 attestationReference,
    uint64 issuedAt,
    uint64 expiresAt,
    VerificationLevel level,
    ClaimStatus status
);

event IdentityBoundToOperation(
    bytes32 indexed operationId,
    bytes32 indexed claimId,
    address indexed subject,
    bytes32 role,
    uint64 boundAt
);

event IdentityAcknowledged(
    bytes32 indexed operationId,
    bytes32 indexed claimId,
    address indexed attestor,
    bytes32 role,
    uint64 acknowledgedAt
);

event IdentityClaimSuperseded(
    bytes32 indexed oldClaimId,
    bytes32 indexed newClaimId,
    address indexed subject
);

event IdentityClaimRevoked(
    bytes32 indexed claimId,
    address indexed subject,
    uint64 revokedAt
);

event PurposeAttested(
    bytes32 indexed attestationId,
    bytes32 indexed operationId,
    address indexed attestor,
    bytes32 purposeCode,
    bytes32 contextHash,
    bytes32 supersedesAttestationId,
    uint64 attestedAt
);

event PurposeSuperseded(
    bytes32 indexed oldAttestationId,
    bytes32 indexed newAttestationId,
    bytes32 indexed operationId,
    address attestor
);
```

### Proposed external functions

`GlyphReceiptLedger`

```solidity
function registerOperation(OperationTerms calldata terms) external returns (bytes32 operationId);
function getOperation(bytes32 operationId) external view returns (OperationRecord memory);
function appendLocalLeg(ValueLegInput calldata leg) external returns (bytes32 legId);
function appendRemoteLeg(ValueLegInput calldata leg, bytes32 messageId) external returns (bytes32 legId);
function advanceStatus(bytes32 operationId, OperationStatus nextStatus) external;
function reconcile(bytes32 operationId, DeltaReconciliation calldata delta) external;
function recordRefund(bytes32 operationId, RefundReceipt calldata refund) external;
function isWriterAuthorized(address writer) external view returns (bool);
function configureWriterAuthorization(address writer, bool allowed, bytes32 writerRole) external;
function getValueLeg(bytes32 legId) external view returns (ValueLeg memory);
function getReconciliation(bytes32 operationId) external view returns (DeltaReconciliation memory);
```

`GlyphAttestationRegistry`

```solidity
function registerSelfIdentity(IdentityClaimInput calldata input) external returns (bytes32 claimId);
function registerIdentityWithSignature(IdentityClaimInput calldata input, bytes calldata signature) external returns (bytes32 claimId);
function registerIdentityWithIssuerProof(IdentityClaimInput calldata input, bytes calldata issuerProof) external returns (bytes32 claimId);
function bindIdentity(OperationIdentityBindingInput calldata input, bytes calldata signature) external;
function acknowledgeIdentity(OperationIdentityBindingInput calldata input, bytes calldata signature) external;
function supersedeIdentity(bytes32 oldClaimId, IdentityClaimInput calldata replacement, bytes calldata authorization) external returns (bytes32 newClaimId);
function revokeIdentity(bytes32 claimId) external;
function attestPurpose(PurposeAttestationInput calldata input, bytes calldata signature) external returns (bytes32 attestationId);
function supersedePurpose(bytes32 oldAttestationId, PurposeAttestationInput calldata replacement, bytes calldata signature) external returns (bytes32 newAttestationId);
function getIdentityClaim(bytes32 claimId) external view returns (IdentityClaim memory);
function getOperationIdentityBinding(bytes32 operationId, bytes32 role) external view returns (OperationIdentityBinding memory);
function getPurposeAttestation(bytes32 attestationId) external view returns (PurposeAttestation memory);
function isClaimExpired(bytes32 claimId) external view returns (bool);
```

## 3) EIP-712 domain/action fields and EIP-1271 validation path

### Domain separator

For all signed P1 actions, bind the signature domain to:

- `name` — contract-specific name, proposed: `GlyphReceiptLedger` or `GlyphAttestationRegistry`;
- `version` — proposed: `1`;
- `chainId` — current chain;
- `verifyingContract` — deployed contract address.

No packed encoding for signatures or IDs. Use canonical EIP-712 hashing plus `abi.encode` for deterministic ID derivation.

### Identity claim typed data

Proposed primary action type:

```solidity
IdentityClaimAuthorization(
    address subject,
    bytes32 namespace,
    bytes32 identifierCommitment,
    address issuer,
    bytes32 attestationReference,
    uint64 issuedAt,
    uint64 expiresAt,
    uint8 level,
    uint256 nonce,
    uint64 deadline
)
```

Validation path:

1. `msg.sender == subject` may authorize the claim directly when the claim is self-issued.
2. Otherwise recover the EOA signer from the EIP-712 digest; recovered signer must equal `subject`.
3. If `subject` is a contract wallet, call `IERC1271(subject).isValidSignature(digest, signature)` and require `0x1626ba7e`.
4. Nonces are subject-scoped and consumed once.
5. `deadline` must not have passed.
6. The recovered signer or EIP-1271 subject must match the claim payload exactly.

### Operation binding typed data

Proposed binding type:

```solidity
OperationIdentityBindingAuthorization(
    bytes32 operationId,
    bytes32 claimId,
    address subject,
    bytes32 role,
    uint64 boundAt,
    uint256 nonce,
    uint64 deadline
)
```

Validation path:

1. The binder must be the claim subject or the subject’s valid delegate/signature path.
2. The claim must exist and may be `ACTIVE`; historical claims can still be bound if the binding snapshots that version.
3. The binding must not alter or overwrite previous history.
4. EIP-1271 follows the same digest/`isValidSignature` path as identity claims.
5. Role values are `bytes32` constants; initial roles are `PAYER`, `RECIPIENT`, and `INITIATOR`.

### Acknowledgement typed data

Proposed acknowledgement type:

```solidity
IdentityAcknowledgementAuthorization(
    bytes32 operationId,
    bytes32 claimId,
    address subject,
    bytes32 role,
    uint256 nonce,
    uint64 deadline
)
```

Acknowledgement means “I associated this claim with my counterparty for this operation.” It does not elevate verification level.

## 4) Deterministic ID derivations using `abi.encode`

All ID derivations below MUST use `abi.encode`, not `abi.encodePacked`.

### Operation ID

Proposed derivation:

```solidity
operationId = keccak256(abi.encode(
    bytes32("glyph.operation.v1"),
    operationType,
    proposedPurposeCode,
    initiator,
    payer,
    recipient,
    recoveryAddress,
    sourceChainId,
    destinationChainId,
    sourceAsset,
    destinationAsset,
    maximumInput,
    destinationAmount,
    termsHash,
    privateContextHash,
    expiry,
    nonce,
    address(this)
));
```

### Value leg ID

From `RECEIPT_LEDGER.md`, kept verbatim in spirit:

```solidity
legId = keccak256(abi.encode(operationId, chainId, transactionHash, logIndex, legType));
```

### Identity claim ID

```solidity
claimId = keccak256(abi.encode(
    bytes32("glyph.identity.claim.v1"),
    subject,
    namespace,
    identifierCommitment,
    issuer,
    attestationReference,
    issuedAt,
    expiresAt,
    level,
    nonce,
    address(this)
));
```

### Operation identity binding ID

```solidity
bindingId = keccak256(abi.encode(
    bytes32("glyph.identity.binding.v1"),
    operationId,
    claimId,
    subject,
    role,
    boundAt,
    address(this)
));
```

### Purpose attestation ID

```solidity
attestationId = keccak256(abi.encode(
    bytes32("glyph.purpose.attestation.v1"),
    operationId,
    attestor,
    purposeCode,
    contextHash,
    supersedesAttestationId,
    attestedAt,
    address(this)
));
```

### Reconciliation reference

```solidity
reconciliationId = keccak256(abi.encode(
    bytes32("glyph.reconciliation.v1"),
    operationId,
    sourceAsset,
    maximumInput,
    realizedPrincipal,
    realizedFees,
    residualReturned,
    recoveryAddress,
    sourceFinalizeTx,
    address(this)
));
```

## 5) Operation status transition table

Financial state machine for P1-visible ledger states:

| From | To | Authorized by / evidence | Notes |
|---|---|---|---|
| `NONE` | `REGISTERED` | creator / approved factory | creates immutable operation record |
| `REGISTERED` | `SOURCE_AUTHORIZED` | payer authorization validated | can be signature-based |
| `SOURCE_AUTHORIZED` | `SOURCE_ESCROWED` | approved settlement writer | actual funding observed |
| `SOURCE_ESCROWED` | `ROUTE_PENDING` | authenticated dispatch | routing annotation only |
| `SOURCE_ESCROWED` | `DESTINATION_RESERVED` | destination-side reservation evidence | optional alternate branch |
| `ROUTE_PENDING` / `DESTINATION_RESERVED` | `DESTINATION_SETTLED` | local destination delivery evidence | receipt leg must exist |
| `DESTINATION_SETTLED` | `SOURCE_FINALIZED` | authenticated source finalization receipt | local closure only |
| `SOURCE_FINALIZED` | `RECONCILED` | conservation passes | terminal financial success |
| any eligible nonterminal | `REFUND_PENDING` | expiry / failure / safety condition | must not race a valid delivery |
| `REFUND_PENDING` | `REFUNDED` | successful recovery transfer | terminal financial success |
| any eligible nonterminal | `EXPIRED` | time-based expiry | nonterminal for the receipt until refund/recovery completes |
| any eligible nonterminal | `ROUTE_FAILED` | failed route or callback | may lead to refund path |

Important notes:

- `RECONCILED` and `REFUNDED` are terminal.
- `DISPUTED` is an annotation state only; it must not rewrite financial history.
- any attempted transition out of a terminal state must revert.

## 6) Financial writer authorization and proof-kind treatment

### Writer authorization

Only these writers may append financial facts:

1. the local settlement contract;
2. allowlisted authenticated remote adapters;
3. approved source-finalization adapters.

A payer or recipient may never self-report a settled financial leg.

### Proof-kind treatment

| Proof kind | Allowed meaning | Notes |
|---|---|---|
| `LOCAL_VERIFIED` | on-chain local fact directly observed by the ledger | same-chain / local execution evidence |
| `AUTHENTICATED_ADAPTER` | authenticated messenger / adapter proof | must never be surfaced as light-client verification |
| `LIGHT_CLIENT_VERIFIED` | proof validated by a real light client | only when the proof is actually light-client based |
| `ISSUER_ATTESTED` | trusted issuer attestation | acceptable only when the proof is not adapter-derived |
| `NONE` | no proof | permitted only for pure metadata, never for settled value legs |

Writer authority and proof kind are orthogonal:

- writer authority decides who may append the leg;
- proof kind declares what kind of evidence backs the leg;
- a writer cannot upcast a weaker proof to a stronger one.

## 7) Reconciliation preconditions and conservation equation

A call to `reconcile(operationId, delta)` MUST satisfy all of the following:

1. operation exists and is not already terminal;
2. a destination-delivery leg exists and matches terms;
3. a source-finalization receipt exists;
4. `delta.recoveryAddress` equals the recovery address bound in the operation terms;
5. the conservation equation holds exactly:

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

6. all arithmetic is checked, with no overflow or underflow;
7. every referenced receipt leg is unique and already anchored once.

The ledger must not claim `RECONCILED` unless the receipt also includes:

- source authorization / escrow commitment;
- destination settlement proof;
- source finalization proof;
- principal and fee realization;
- residual return or explicit zero residual.

## 8) Purpose proposal, independent attestations, consensus, disagreement, supersession

### Purpose proposal

The initiator proposes the initial purpose code during operation registration.
Purpose codes are versioned `bytes32` identifiers, not free-form strings.

### Independent attestations

Payer and recipient may each submit an independent purpose attestation for the same operation.
Each attestation includes:

- `operationId`
- `attestor`
- `purposeCode`
- `contextHash`
- `attestedAt`
- `supersedesAttestationId` (optional)

### Consensus

Consensus is derived when payer and recipient attestations match on both:

- `purposeCode`
- `contextHash`

Consensus is a surfaced view only; it is not a mutable overwrite field.

### Disagreement

If the attestors disagree, the registry must retain both attestations.
No last-write-wins behavior is allowed.
Disagreement remains visible in the event history and in derived views.

### Supersession

A mistaken purpose attestation is corrected by appending a superseding attestation that references the prior attestation ID.
Historical attestations remain queryable.
No deletion or rewrite of the original attestation is permitted.

## 9) Identity self-claim, issuer claim, operation binding, acknowledgement, revocation/supersession, expiry, historical immutability

### Self-claim

A subject may register its own claim directly or via subject signature / EIP-1271.
Verification level must be `SELF_ASSERTED`.
No other party may author the claim content for that subject.

### Issuer claim

An allowlisted issuer may register an issuer-verified claim.
The claim must carry:

- issuer address;
- attestation reference;
- explicit `ISSUER_VERIFIED` level;
- subject identity commitment.

### Operation binding

An operation binds a specific `claimId` snapshot and `role`.
The binding stores the selected claim version and does not mutate on later claim changes.

### Acknowledgement

A payer may acknowledge the recipient’s claim for a specific operation, and a recipient may acknowledge the payer’s claim.
Acknowledgement is not verification.
It only records the counterparty association chosen for that receipt.

### Revocation and supersession

- A subject may revoke its own self-asserted claim.
- An issuer may revoke an issuer claim under explicit issuer rules.
- A new claim may supersede an old claim.
- Historical operation bindings remain immutable and queryable.

### Expiry

Claims can expire by time without deleting the underlying record.
`ClaimStatus` stays append-only; `EXPIRED` is derived from `expiresAt`.

### Historical immutability

No revocation or supersession may mutate previously emitted receipt fields.
Historical receipts preserve the exact `claimId` / version that was bound at the time.

## 10) P1 Foundry test matrix mapped one-to-one to INVARIANTS.md identifiers

P1 coverage here is limited to the receipt ledger and attestation registry.
Later-phase routing, token, messenger, vault, frontend, deployment, and Sessions invariants are explicitly excluded below.

| Invariant | Foundry test (one per invariant) | Setup | Expected revert / error | Interface / event under test |
|---|---|---|---|---|
| I-001 Conservation | `test_I001_reconcile_conserves_zero_minimal_and_nonzero_residuals` | register operation; append destination-delivery and source-finalization facts; run zero, minimal, and nonzero residual cases | `InvalidConservationEquation` on over/under-accounting; arithmetic checks must not overflow/underflow | `reconcile`, `OperationReconciled` |
| I-005 Global Single Settlement | `test_I005_rejects_second_terminal_outcome_after_reconcile_or_refund` | reconcile once, then attempt refund; and refund once, then attempt reconcile | `TerminalOperation` / `ReplayOrNullifierConsumed` | `reconcile`, `recordRefund`, terminal status events |
| I-006 Domain Binding | `test_I006_rejects_wrong_chain_contract_or_nonce_for_signed_actions` | craft identity and binding signatures with wrong chainId, verifyingContract, or nonce | `InvalidEIP712Domain`, `InvalidSignature`, or `ClaimNonceUsed` | EIP-712 auth, `IdentityClaimRegistered`, `IdentityBoundToOperation` |
| I-008 Explicit Proof Class | `test_I008_rejects_missing_or_misclassified_proof_kind` | append remote leg with adapter proof; attempt to upcast it to light-client proof or omit proof kind | `UnsupportedProofKind` / `ProofKindMismatch` | `appendRemoteLeg`, `ValueLegAppended` |
| I-009 State-Machine Validity | `test_I009_rejects_invalid_transition_and_terminal_reentry` | create operation; try skipped transitions and post-terminal reentry | `InvalidOperationTransition` / `TerminalOperation` | `advanceStatus`, `OperationStatusAdvanced` |
| I-013 Financial Facts Are Privileged Writes | `test_I013_rejects_user_crafted_financial_leg_append` | caller is payer, recipient, or arbitrary EOA; attempt to append a settled leg | `UnauthorizedFinancialWriter` | `appendLocalLeg`, `appendRemoteLeg`, `ValueLegAppended` |
| I-014 Deterministic Receipt Legs | `test_I014_legId_uses_abi_encode_and_duplicate_append_reverts` | append same `(operationId, chainId, txHash, logIndex, legType)` twice | `DuplicateLegId` | `appendLocalLeg`, `appendRemoteLeg`, `ValueLegAppended` |
| I-015 Identity Self-Control | `test_I015_rejects_cross_party_identity_write_without_subject_authority` | payer tries to register recipient claim, or recipient tries to bind payer claim | `UnauthorizedSubject` | identity registration and binding events |
| I-016 Identity Verification Honesty | `test_I016_preserves_self_counterparty_issuer_levels_and_blocks_collapse` | register one self-asserted claim, one counterparty-acknowledged claim, one issuer-verified claim | `InvalidIdentityLevel` only if a mismatched level is supplied; otherwise no revert | `IdentityClaimRegistered` |
| I-017 Historical Identity Stability | `test_I017_supersession_and_revocation_do_not_mutate_bound_history` | bind a claim to an operation, then supersede or revoke the claim | none on the historical binding; later state changes only append | `IdentityClaimSuperseded`, `IdentityClaimRevoked`, `IdentityBoundToOperation` |
| I-018 Purpose Is Attested, Not Dictated | `test_I018_records_independent_payer_recipient_purpose_attestations_and_retains_disagreement` | payer attests purpose A/context X, recipient attests purpose B/context Y | none; disagreement must remain visible | `PurposeAttested`, `PurposeSuperseded` |
| I-019 On-Chain Privacy | `test_I019_emits_only_commitments_and_ids_no_raw_pii` | register claims/purpose using commitments, then inspect emitted fields | none; the assertion is that events contain only typed commitments and IDs | all identity/purpose events |
| I-021 Recovery Address Binding | `test_I021_rejects_reconciliation_with_mismatched_recovery_address` | bind one recovery address in operation terms, then reconcile with a different address | `RecoveryAddressMismatch` | `reconcile`, `OperationReconciled` |
| I-022 Fees Are Realized, Bounded, and Visible | `test_I022_rejects_realized_fees_above_maximum_input_or_missing_fee_visibility` | reconcile with fees exceeding ceiling or with missing visible fee fields | `InvalidConservationEquation` | `reconcile`, `OperationReconciled` |
| I-026 Receipt Completion | `test_I026_requires_source_authorization_escrow_destination_proof_finalization_and_conservation` | anchor source authorization, escrow, destination delivery, source finalization, then reconcile | `MissingRequiredReceipt` when any prerequisite is absent | `OperationRegistered`, `ValueLegAppended`, `OperationReconciled` |

Notes on the matrix:

- I-001 includes zero, minimal, and nonzero residual cases in one parameterized test.
- I-006 covers both EIP-712 and EIP-1271 path failures/successes.
- I-015 and I-017 are append-only history checks, not overwrite checks.
- I-019 is an event-shape/privacy assertion, not a token-transfer assertion.
- I-021 and I-022 are kept in P1 because they are ledger reconciliation constraints, not vault/router behavior.

## 11) P1 explicit exclusions

The following are intentionally out of scope for this matrix and must not be pulled into P1 implementation work:

- cross-chain adapters and messenger integration details;
- source router implementation;
- destination vault implementation;
- tokens and token transfer behavior;
- frontend / UI behavior;
- deployment and broadcast workflows;
- Sessions / authority-kernel rebuild.

Corresponding later-phase invariants are therefore not mapped here:

- I-002 Exact Destination Delivery
- I-003 No Source Settlement Without Destination Proof
- I-004 No Global Atomicity Claim
- I-007 Message Provenance
- I-010 Refund/Delivery Race Safety
- I-011 Claimant Safety
- I-012 Pull Immutability
- I-020 Fragment Secret Hygiene
- I-023 Messenger Neutrality
- I-024 Destination Liquidity Accounting
- I-025 Fail-Closed Token Transfers
- I-027 Deployment Evidence
- I-028 Deprecated Authority Isolation

## 12) Open questions / blockers

1. The broader invariant set binds `sourceRouter` and `destinationVault` in signed domain terms, but those surfaces are explicitly excluded from P1. This matrix intentionally defers those fields rather than inventing router/vault behavior.
2. `ClaimStatus` has a derived `EXPIRED` state in the state-machine spec, while the storage enum is append-only `ACTIVE / SUPERSEDED / REVOKED`. The recommended handling here is “store the append-only status, derive expiry in views.”
3. `DISPUTED` exists only as an optional annotation state for receipts; whether it should be emitted as a dedicated event or derived by indexers is not finalized.
4. Exact contract `name` / `version` strings for EIP-712 are proposed here, not locked in Solidity.
5. Whether `ISSUER_ATTESTED` is ever acceptable on a financial leg, versus being reserved for identity/purpose attestations, remains underspecified in the source docs.
