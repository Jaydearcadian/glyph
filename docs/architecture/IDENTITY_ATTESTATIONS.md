# Glyph Identity Attestations

Status: P0 specification.

## Goal

Allow payer and recipient to attach attributable identity claims to operations without making the financial ledger mutable or publishing raw personal information.

## Claim Model

```solidity
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
```

Verification levels:

```text
SELF_ASSERTED
COUNTERPARTY_ACKNOWLEDGED
ISSUER_VERIFIED
```

Claim status:

```text
ACTIVE
SUPERSEDED
REVOKED
```

Expiry is time-derived and does not erase the claim.

## Authorization

A claim is admitted through one of:

1. `msg.sender == subject`;
2. EIP-712 subject signature with nonce, expiry, chain ID, and verifying contract;
3. EIP-1271 subject validation;
4. an allowlisted issuer scheme that identifies subject and evidence.

A payer cannot create a recipient self-claim and vice versa. Relayers may submit but cannot alter signed content.

## Namespaces

Initial namespace identifiers may include:

```text
DID_PKH
ERC_8004
ORNS
ENS
MERCHANT_ID
LEGAL_ENTITY
SERVICE_PROVIDER
CUSTOM
```

Namespace presence is not verification. Level and issuer remain explicit.

## Operation Binding

```solidity
struct OperationIdentityBinding {
    bytes32 operationId;
    bytes32 claimId;
    address subject;
    bytes32 role;
    uint64 boundAt;
}
```

Roles begin with `PAYER`, `RECIPIENT`, and `INITIATOR`. Only the subject or valid delegated signature binds its claim. Binding snapshots a claim ID/version; later revocation does not rewrite the receipt.

## Counterparty Acknowledgement

A payer or recipient may acknowledge the other party’s existing claim for a specific operation. Acknowledgement means “this is the claim I associated with my counterparty,” not issuer verification.

## Revocation and Supersession

- Subject may revoke self-asserted claims.
- Issuer may revoke issuer claims under explicit rules.
- A new claim may supersede an old one.
- Original claim and historical operation bindings remain queryable.
- No deletion or mutation of past receipt identity snapshots.

## Suggested Interface

```solidity
function registerSelfIdentity(IdentityInput calldata input) external returns (bytes32 claimId);
function registerIdentityWithSignature(IdentityInput calldata input, bytes calldata signature) external returns (bytes32 claimId);
function bindIdentity(bytes32 operationId, bytes32 claimId, bytes32 role) external;
function acknowledgeIdentity(bytes32 operationId, bytes32 claimId) external;
function supersedeIdentity(bytes32 oldClaimId, IdentityInput calldata replacement) external returns (bytes32 newClaimId);
function revokeIdentity(bytes32 claimId) external;
```

## Replay and Domain Requirements

Signed identity actions bind:

```text
version, action, subject, namespace, identifierCommitment,
issuer/attestationReference, claim nonce, expiry,
chainId, verifyingContract
```

Nonces are subject-scoped and consumed once.

## UI Language

Correct:

```text
Self-asserted identity
Acknowledged by counterparty
Verified by issuer 0x...
Revoked after settlement; historical receipt preserved
```

Incorrect:

```text
Verified identity
```

when only self-assertion exists.
