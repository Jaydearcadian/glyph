# P1 Locked Decisions — Receipt Ledger and Attestation Registry

Status: **authoritative P1 implementation addendum**  
Reviewed by: `gpt-5.6-sol` orchestrator after `gpt-5.4-mini` matrix draft.  
Priority: this file overrides `P1_INTERFACE_TEST_MATRIX.md` wherever they conflict.

## Scope

P1 implements local, non-custodial accounting/attestation state only:

```text
GlyphReceiptLedger
GlyphAttestationRegistry
small interfaces/libraries/mocks required by tests
```

P1 does not implement token transfers, source router, destination vault, messenger adapters, frontend, deployment, or Sessions.

## Toolchain Lock

```text
Foundry 1.7.1
Solidity 0.8.24
EVM target cancun
optimizer enabled, 200 runs
```

Prague is deferred to the P7 EIP-7702 toolchain gate. P1 code must not depend on Prague-only behavior.

## Shared Rules

- IDs use `keccak256(abi.encode(...))`; never ambiguous packed encoding.
- Domain tags are `keccak256("glyph.<domain>.v1")`, not truncated string casts.
- Contract timestamps (`createdAt`, `boundAt`, `attestedAt`, `registeredAt`, revocation/supersession time) use `block.timestamp` and are not caller supplied.
- Signed authorizations bind chain ID, verifying contract, action-specific typehash, current action nonce, and deadline.
- Operation, claim, binding, acknowledgement, and purpose-attestation identifiers use an explicit domain tag, `block.chainid`, and `address(this)` unless the identifier directly embeds an already chain-bound operation ID; claim and purpose IDs always include chain and verifying contract explicitly.
- EOA recovery enforces valid `v`, nonzero signer, and low-`s`; contract wallets use EIP-1271 magic value `0x1626ba7e`.
- No raw strings/bytes payloads for personal or billing data; identity/purpose content is `bytes32` commitments/references.
- No contract in P1 transfers or escrows value.

# GlyphReceiptLedger

## Immutable Operation Terms

P1 terms bind fields required by I-006 even when later-phase implementations are absent:

```solidity
struct OperationTerms {
    bytes32 operationType;
    bytes32 proposedPurposeCode;
    address initiator;
    address payer;
    address recipient;
    address recoveryAddress;
    address sourceRouter;
    address destinationVault;
    uint64 sourceChainId;
    uint64 destinationChainId;
    address sourceAsset;
    address destinationAsset;
    uint256 maximumInput;
    uint256 destinationAmount;
    uint256 maximumFee;
    bytes32 claimantRule;
    bytes32 privateContextHash;
    uint64 expiry;
    uint256 nonce;
}
```

`termsHash` is computed inside the contract from all fields plus a version/domain tag. `operationId` is computed from a separate domain tag, `block.chainid`, `address(this)`, and `termsHash`. Callers do not supply trusted hashes or timestamps.

`registerOperation` requires `msg.sender == initiator` in P1. Approved factory registration is deferred until a signed factory path is specified.

The ledger stores enough immutable terms for the attestation registry to query initiator/payer/recipient and for reconciliation to compare source asset, destination asset/amount, maximum input/fee, and recovery address.

`sourceChainId` and `destinationChainId` must be nonzero. They MAY be equal for an explicit same-chain/local operation. The canonical ledger may anchor an operation whose source chain is remote; neither operation chain is required to equal the ledger deployment chain. `LOCAL_VERIFIED` legs must name `block.chainid`; remote-proof legs must name a different chain.

## Financial Roles

Admin may grant/revoke narrow roles and cannot directly bypass role checks:

```text
STATUS_WRITER
LOCAL_LEG_WRITER
REMOTE_LEG_WRITER
SOURCE_FINALIZATION_WRITER
```

There is no fund-sweep function. Role changes emit events. `advanceStatus` requires `STATUS_WRITER`; terminal outcomes are only reached through `reconcile` or `recordRefund`, both requiring `SOURCE_FINALIZATION_WRITER`.

## Proof Kinds

Financial-leg enum:

```text
NONE
LOCAL_VERIFIED
AUTHENTICATED_ADAPTER
LIGHT_CLIENT_VERIFIED
```

- `appendLocalLeg` requires `LOCAL_LEG_WRITER` and `LOCAL_VERIFIED`.
- `appendRemoteLeg` requires `REMOTE_LEG_WRITER`, nonzero unique `messageId`, and either `AUTHENTICATED_ADAPTER` or `LIGHT_CLIENT_VERIFIED`.
- `NONE` is rejected for every financial leg.
- `ISSUER_ATTESTED` is not a P1 financial proof kind; issuer identity evidence belongs in the attestation registry.

## Value Leg

`legId` is exactly:

```solidity
keccak256(abi.encode(operationId, chainId, transactionHash, logIndex, legType))
```

Each leg requires an existing operation, nonzero `transactionHash`, and a supported leg type. Duplicate leg IDs and duplicate remote message IDs fail closed.

P1 defines versioned `bytes32` leg constants for at least:

```text
SOURCE_AUTHORIZED
SOURCE_ESCROWED
DESTINATION_RESERVED
DESTINATION_DELIVERED
PROVIDER_SETTLED
FEE_REALIZED
DELTA_RETURNED
SOURCE_FINALIZED
FULL_REFUND
```

The ledger stores operation/leg-type presence and amount needed for reconciliation without unbounded arrays.

## Status

`advanceStatus` accepts only explicitly enumerated adjacent transitions from `STATE_MACHINES.md`. `RECONCILED` and `REFUNDED` cannot be supplied to `advanceStatus`. No transition is allowed from a terminal state. `REFUND_PENDING` is reachable only from `EXPIRED` or `ROUTE_FAILED`. `EXPIRED` is permitted only when `block.timestamp >= immutable expiry`. Evidence-bearing transitions require their corresponding unique leg to exist and match immutable chain, asset, amount, and endpoint terms before status changes: source authorization, source escrow, destination reservation/delivery, and source finalization.

## Reconciliation

`reconcile` requires:

1. existing operation in `SOURCE_FINALIZED`;
2. required unique legs: `SOURCE_ESCROWED`, `DESTINATION_DELIVERED`, `PROVIDER_SETTLED`, `FEE_REALIZED`, `DELTA_RETURNED`, `SOURCE_FINALIZED`;
3. source asset/recovery address/maximum input equal immutable terms;
4. destination delivery asset/recipient satisfy immutable terms and actual amount is at least `destinationAmount`;
5. provider leg amount equals `realizedPrincipal`;
6. fee leg amount equals `realizedFees` and `realizedFees <= maximumFee`;
7. delta leg recipient equals recovery address and amount equals `residualReturned`;
8. source escrow amount equals `maximumInput`;
9. every required leg matches its immutable source/destination chain and applicable payer/router/vault/recipient endpoint;
10. nonzero `sourceFinalizeTx` equals the unique `SOURCE_FINALIZED` leg transaction hash;
11. checked, overflow-safe conservation:

```text
maximumInput = realizedPrincipal + realizedFees + residualReturned
```

Use subtraction/bounds checks so malformed huge inputs return a custom error rather than an uncontrolled arithmetic panic. Success stores the reconciliation and marks `RECONCILED` once.

P1 excess-delivery policy is `RECIPIENT_RETAINS`: when `actualDestinationDelivered > destinationAmount`, the ledger records expected amount, actual amount, excess, and the versioned policy tag. Excess remains with the recipient and is not credited against source principal, fees, or residual in STN-Delta accounting.

## Refund

`recordRefund` requires `REFUND_PENDING`, a `FULL_REFUND` leg matching source asset, recovery address, and full escrowed amount, then marks `REFUNDED`. It cannot run after destination reservation, destination delivery, destination settlement, source finalization, or reconciliation evidence exists, regardless of leg/status write order, and cannot be repeated.

# GlyphAttestationRegistry

## Ledger Reference

Constructor receives a nonzero immutable `IGlyphReceiptLedgerView`. Attestation functions query operation existence and immutable parties. The registry never trusts caller-supplied party roles.

## Verification Model

Stored claim verification is only:

```text
SELF_ASSERTED
ISSUER_VERIFIED
```

Counterparty acknowledgement is a separate append-only relationship/event. It never mutates a claim or upgrades `SELF_ASSERTED` to `ISSUER_VERIFIED`. UI may derive “counterparty acknowledged” alongside the stored verification level.

## Identity Claims

Paths:

1. `registerSelfIdentity` — direct subject call; forces `SELF_ASSERTED` and zero issuer.
2. `registerSelfIdentityWithSignature` — relayed EIP-712/EIP-1271 subject authorization; forces `SELF_ASSERTED` and zero issuer.
3. `registerIssuerIdentity` — direct allowlisted issuer call; forces `ISSUER_VERIFIED` and `issuer = msg.sender`.

The caller cannot choose or upcast verification level. Caller input does not contain a trusted `issuedAt`. Claim IDs include subject, namespace, identifier commitment, issuer, attestation reference, expiry, authority-scoped claim nonce, `block.chainid`, registry address, and domain tag. The registry records `registeredAt = block.timestamp` once; state and events must not mislabel that registry admission time as issuer-verified `issuedAt`.

New operation bindings require the claim to be `ACTIVE` and not expired. For nonzero expiry, a claim is expired when `block.timestamp >= expiresAt`. Later revocation/supersession changes claim status but never mutates historical binding records. Reads for nonexistent claims, bindings, or purpose attestations fail closed rather than returning default enum-zero structs.

Self-asserted claims may be revoked/superseded by the subject (direct or valid signature). Issuer-verified claims may be revoked/superseded only by the same issuer. A subject may add a new self-claim but cannot rewrite an issuer’s claim history. Registration consumes a sequential nonce scoped to the authorizing subject or issuer, and every pre-existing claim ID is rejected. Revocation and supersession use separate action nonces and EIP-712 type hashes. A supersession signature commits to the old claim ID and every replacement claim field.

## Identity Binding

Initial immutable roles:

```text
PAYER
RECIPIENT
INITIATOR
```

Before binding, the registry verifies:

```text
PAYER     => claim.subject == operation.payer
RECIPIENT => claim.subject == operation.recipient
INITIATOR => claim.subject == operation.initiator
```

Only the subject or its EIP-712/EIP-1271 authorization can bind. Each `(operationId, role)` may be bound once in P1; no overwrite/rebind. The binding snapshots `claimId`, subject, role, and contract timestamp.

## Counterparty Acknowledgement

Acknowledgement targets an existing operation binding:

- payer may acknowledge the bound recipient claim;
- recipient may acknowledge the bound payer claim;
- the acknowledged claim/role must match the immutable binding;
- direct and EIP-712/EIP-1271 relayed paths are supported;
- duplicate acknowledgement ID/replay is rejected;
- acknowledgement does not change claim verification level.

Use a dedicated acknowledgement input/typehash; do not reuse binding input.

## Purpose Attestations

Purpose authorization explicitly includes `attestor` and the attested role (`PAYER`, `RECIPIENT`, or `INITIATOR`). The registry verifies the attestor equals the immutable operation party for that role. Direct and EIP-712/EIP-1271 relayed paths are supported.

Attestation fields:

```text
operationId
attestor
role
purposeCode
contextHash
supersedesAttestationId
nonce
signed deadline (authorization only)
contract attestedAt timestamp
```

A superseding attestation must reference the attestor-and-role’s existing unsuperseded latest attestation for the same operation. Once an attestor has a latest record for that role, a new record that omits or references a different predecessor is rejected. The original remains immutable. Exact duplicate/replay is rejected.

Consensus is a derived view over distinct latest payer-role and recipient-role attestations and is true only when both nonzero role-scoped attestations match on `purposeCode` and `contextHash`. If payer and recipient are the same address, two separately authorized role records are still required. Disagreement remains queryable.

## Nonces

Use action-scoped sequential nonces at minimum for:

```text
identity claim registration
identity binding
identity acknowledgement
identity revocation/supersession authorization
purpose attestation
```

A signature for one action cannot be replayed as another action. Direct actions consume the same relevant sequence where needed to prevent a pre-signed stale action from executing after direct state change.

# Required TDD Evidence

The `gpt-5.5` implementation worker must show genuine RED before production code for each contract surface. At minimum tests cover:

## Receipt Ledger

- effective Cancun/Solc configuration;
- deterministic operation ID and duplicate rejection;
- terms hash includes routers, vault, maximum fee, claimant rule, chain/domain, and nonce;
- non-initiator registration rejection;
- admin-only role configuration and unauthorized writer rejection;
- valid transition path, skipped transition rejection, terminal reentry rejection;
- local/remote proof-kind mismatch;
- zero/duplicate remote message rejection;
- deterministic leg ID and duplicate rejection;
- reconciliation with zero, minimal, and nonzero residual;
- missing required leg for every required type;
- source/destination asset, recipient, delivery amount, recovery, maximum input, maximum fee, and leg/delta mismatch rejection;
- over/under-accounting and huge-input overflow-safe rejection;
- second terminal outcome rejection;
- valid full refund and refund mismatch/double-refund rejection.
- immutable-expiry enforcement and delivered/reserved-evidence-before-refund rejection regardless of write order;
- remote-source/local-destination and local-source/remote-destination attribution;
- safe over-delivery with explicit `RECIPIENT_RETAINS` evidence.

## Attestation Registry

- direct self-claim and forced self level;
- relayed EOA claim success, wrong signer/domain/contract/nonce/deadline/replay failure;
- EIP-1271 success, wrong magic, and revert failure;
- unauthorized issuer rejection and issuer level forcing;
- payer/recipient cross-party identity forgery rejection;
- role/subject mismatch rejection;
- one-time immutable binding;
- expired/revoked/superseded claim cannot be newly bound;
- historical binding unchanged after later revocation/supersession;
- acknowledgement restricted to correct counterparty and bound claim;
- acknowledgement does not upgrade verification;
- independent payer/recipient purpose attestations;
- exact consensus, disagreement, and supersession behavior;
- purpose attestor authorization, signature replay/domain/deadline failure;
- coincident payer/recipient still requires two role-scoped purpose records;
- exact expiry-boundary and nonexistent-record getter rejection;
- malformed ECDSA/EIP-1271 and wrong-chain/verifying-contract rejection;
- commitment-only event/API shape with no raw PII fields.

The worker must run targeted tests after each RED/GREEN cycle and then the complete `forge test -vv` regression. Existing legacy 8 tests must remain green.

# Implementation Files

Allowed P1 implementation surface:

```text
contracts/src/GlyphReceiptLedger.sol
contracts/src/GlyphAttestationRegistry.sol
contracts/src/interfaces/IGlyphReceiptLedger.sol
contracts/src/libraries/GlyphSignatureChecker.sol
contracts/test/GlyphReceiptLedger.t.sol
contracts/test/GlyphAttestationRegistry.t.sol
contracts/test/mocks/MockERC1271Wallet.sol
state/handoffs/p1-contract-engineer.json
```

The worker may add another narrowly required interface/mock under the same directories only if the handoff explains why. It may not edit legacy contracts/tests, deployment scripts, global/project governance docs, `MGlyph.session.json`, or `vessel_sync.json`.
