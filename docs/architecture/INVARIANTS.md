# Glyph Protocol Invariants

Status: **P0 executable specification**  
These invariants govern future contracts and tests. They are not claims about the currently deployed prototype.

## Notation

For operation `O`:

- `M` — payer maximum source input.
- `P` — realized source principal settled to the liquidity/route provider.
- `F` — realized fees.
- `D` — residual delta returned to the recovery address.
- `A_dest` — promised destination amount.
- `A_delivered` — destination amount proven delivered.
- `N` — operation/route nonce.

## I-001 — Conservation

A reconciled operation MUST satisfy:

```text
M = P + F + D
```

No value may remain in the terminated source session. The test suite MUST cover zero, minimal, and nonzero residuals and MUST reject over-settlement, under-accounting, and arithmetic overflow/underflow.

## I-002 — Exact Destination Delivery

A successful Pull or fixed-amount Push MUST satisfy:

```text
A_delivered >= A_dest
```

The ledger records the actual delivered amount. Any excess-handling policy must be explicit; it may not silently reduce the payer’s residual or recipient’s claim.

## I-003 — No Source Settlement Without Destination Proof

The source router MUST NOT pay the route/liquidity provider or mark the session final unless an authenticated, domain-bound destination settlement acknowledgement has been recorded.

## I-004 — No Global Atomicity Claim

Cross-chain lifecycle transitions are asynchronous. The source finalization transaction MUST atomically perform its local settlement, residual return, balance zeroing, and terminal state update. It MUST be retryable if message callback execution fails.

## I-005 — Global Single Settlement

An `operationId` may produce at most one terminal economic outcome:

```text
RECONCILED xor REFUNDED
```

A destination claim, destination settlement, source finalization, message delivery, and refund MUST each have replay/nullifier protection.

## I-006 — Domain Binding

Signed terms and authenticated messages MUST bind at least:

```text
version
operationId
operationType
sourceChainId
sourceRouter
destinationChainId
destinationVault
sourceAsset
destinationAsset
maximumInput
destinationAmount
payer
recipient or claimant rule
recoveryAddress
expiry
nonce
```

Changing any bound field invalidates authorization.

## I-007 — Message Provenance

A destination contract accepts messages only from an allowlisted messenger adapter and expected source domain/sender. A source contract accepts acknowledgements only from the expected destination domain/sender. Payload IDs are consumed once.

## I-008 — Explicit Proof Class

Every remote receipt leg declares one proof kind:

```text
LOCAL_VERIFIED
AUTHENTICATED_ADAPTER
LIGHT_CLIENT_VERIFIED
ISSUER_ATTESTED
```

`AUTHENTICATED_ADAPTER` MUST NOT be surfaced as `LIGHT_CLIENT_VERIFIED`.

## I-009 — State-Machine Validity

Only enumerated transitions are allowed. At minimum:

```text
REGISTERED
→ SOURCE_AUTHORIZED
→ SOURCE_ESCROWED
→ DESTINATION_RESERVED/ROUTE_PENDING
→ DESTINATION_SETTLED
→ SOURCE_FINALIZED
→ RECONCILED
```

Recovery paths:

```text
EXPIRED/ROUTE_FAILED
→ REFUND_PENDING
→ REFUNDED
```

A terminal state cannot transition again.

## I-010 — Refund/Delivery Race Safety

A refund MUST NOT execute while a valid destination delivery may already exist. Expiry alone is insufficient if a destination message or settlement is pending. The design MUST specify finality/challenge timing and acknowledgement recovery.

## I-011 — Claimant Safety

Push claim authorization MUST bind the claimant address and operation domain. Copying calldata or a signature into a transaction from another address MUST fail. The fragment secret must never itself authorize source escrow withdrawal or arbitrary routing.

## I-012 — Pull Immutability

Pull terms are immutable after the payer authorizes execution. Pull V1 has exact recipient, destination chain, destination asset, amount, expiry, and nonce; no arbitrary calldata and no recurring debit.

## I-013 — Financial Facts Are Privileged Writes

Only the local settlement contract or an allowlisted authenticated adapter may append financial value legs. Payer/recipient attestations cannot fabricate movement facts.

## I-014 — Deterministic Receipt Legs

Each movement leg has a deterministic unique ID derived from operation, chain, transaction/log reference, and leg type. Duplicate append attempts MUST revert or return an explicit idempotent result without duplicating accounting.

## I-015 — Identity Self-Control

A subject controls its own identity claim through direct caller authorization, EIP-712 EOA signature, EIP-1271 validation, or an explicitly authorized issuer scheme. A payer cannot write recipient identity and vice versa.

## I-016 — Identity Verification Honesty

Identity claims MUST identify verification level:

```text
SELF_ASSERTED
COUNTERPARTY_ACKNOWLEDGED
ISSUER_VERIFIED
```

The protocol and UI MUST NOT collapse these levels.

## I-017 — Historical Identity Stability

An operation binds a specific `claimId`/version. Revocation or supersession is append-only and cannot mutate historical receipt fields.

## I-018 — Purpose Is Attested, Not Dictated

Operation type and purpose are separate. Initiator, payer, and recipient attestations are append-only. Matching payer/recipient purpose plus context hash may be surfaced as consensus; disagreement remains visible.

## I-019 — On-Chain Privacy

Raw PII and private billing text MUST NOT be stored in contract state, events, calldata intended for publication, deployment manifests, or handoffs. Only typed namespaces, commitments, claim IDs, issuer references, and deliberately public identifiers are allowed.

## I-020 — Fragment Secret Hygiene

Claim secrets use URL fragments, are parsed locally, removed from the visible URL, and excluded from network requests, logs, analytics, link previews, screenshots, crash reporting, and persistent storage.

## I-021 — Recovery Address Binding

The recovery address is bound in payer authorization before funding. A router, recipient, messenger, or worker cannot substitute it. Residual and full-refund transfers use the bound address.

## I-022 — Fees Are Realized, Bounded, and Visible

The payer authorizes a maximum input. Realized fees cannot cause settlement above that ceiling. Fee components and quote expiry must be available before authorization and recorded in reconciliation.

## I-023 — Messenger Neutrality

Core ledger and STN-Delta accounting MUST depend on a narrow messenger interface, not LayerZero-specific storage or response objects. Messenger adapters are replaceable and separately allowlisted.

## I-024 — Destination Liquidity Accounting

A destination vault cannot promise more immediately claimable value than its available, unreserved liquidity. Reservations and releases are operation-scoped. The system MUST distinguish reserved, delivered, expired, and recovered liquidity.

## I-025 — Fail-Closed Token Transfers

Token transfer failure MUST NOT leave a receipt marked settled/finalized. State changes and transfers use checks-effects-interactions, safe token handling, and reentrancy protection where applicable.

## I-026 — Receipt Completion

A cross-chain operation is not `RECONCILED` until Monad has anchored:

- source authorization/escrow commitment;
- destination settlement proof;
- source finalization proof;
- principal and fee realization;
- residual return or explicit zero residual;
- a valid conservation equation.

## I-027 — Deployment Evidence

A deployment is recorded only after chain ID, successful receipt, runtime bytecode, expected configuration, and code hash are read back. Submitted transactions and dry runs are not deployments.

## I-028 — Deprecated Authority Isolation

The deployed proxy at `0x83A572FD4E334ed34Aca42B85743Ff122AB3006d` and source using the incorrect slot `0x07d2...3700` MUST NOT be used by new Push/Pull, receipt, routing, or identity contracts. Sessions require a separate future rebuild.

## Required P1 Test Matrix

P1 MUST include tests for:

- operation registration and duplicate operation rejection;
- valid/invalid state transitions;
- deterministic value-leg IDs and duplicate-leg rejection;
- conservation with zero and nonzero residual;
- over-settlement and under-accounting rejection;
- unauthorized financial writer rejection;
- payer and recipient self-identity binding;
- cross-party identity forgery rejection;
- EIP-712 replay/domain rejection;
- EIP-1271 success/failure;
- identity revocation/supersession without historical mutation;
- purpose agreement and disagreement;
- raw metadata represented only by commitment;
- terminal-state immutability.

Later phases add route, messenger, liquidity, claim/refund race, expiry, callback retry, and public E2E tests.
