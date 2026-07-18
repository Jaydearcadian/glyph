# Glyph Push/Pull MVP Execution Contract

Status: **LOCKED — implementation authority**  
Authority: explicit user lock; this contract governs the next isolated `hy3:free` implementation run.  
Scope: build-to-deploy-ready only. No deployment, funding, signing, broadcast, public service, commit, or push is authorized.

## 1. Governing Rule

The executor implements this contract. It does not redesign it.

Priority for the isolated MVP run:

1. this execution contract;
2. `AGENTS.md` and approval boundaries;
3. `docs/architecture/P1_LOCKED_DECISIONS.md` for the retained P1 surface;
4. `docs/architecture/INVARIANTS.md`;
5. `docs/PRODUCT_DOCTRINE.md`;
6. the remaining architecture specifications;
7. reviewed source and test evidence;
8. temporary handoffs.

If two requirements cannot coexist, stop with `BLOCKED_SPEC_CONFLICT`. Do not silently choose one, weaken an invariant, or edit this contract.

## 2. Product Thesis and Completion Definition

> **A link becomes an operation.**

The candidate is complete only when one shared system locally proves:

```text
cross-chain Pull
→ authenticated destination delivery
→ atomic source finalization
→ reconciled JSON receipt
→ deterministic human receipt card

cross-chain Push
→ claimant-safe destination claim
→ authenticated destination delivery
→ atomic source finalization
→ reconciled JSON receipt
→ deterministic human receipt card
```

The same core must also prove:

- direct and gasless submission paths;
- bounded, visible fee splitting;
- multi-source contribution aggregation through independent child operations;
- one funded gift pool with multiple independently safe claims;
- refund/recovery paths that cannot race destination delivery;
- cross-mode, cross-program, cross-message, and cross-domain isolation.

A compiler pass, mock-only happy path, submitted transaction, destination payout, or generated card alone is not completion.

## 3. Locked Product Axes

### 3.1 Operation mode

Stable domain constants:

```text
PUSH
PULL
SESSION
```

For this MVP:

```text
PUSH    enabled
PULL    enabled
SESSION defined but disabled
```

`SESSION` registration/execution must fail closed until the independent P7 authority kernel exists. The deprecated `GlyphSessionProxy` and its storage layout receive no funds, roles, imports, compatibility path, or new integration.

### 3.2 Execution topology

Stable topology constants:

```text
LOCAL
CROSS_CHAIN
```

Topology is independent of mode. Do not create `CROSSCHAIN_PUSH` or `CROSSCHAIN_PULL` operation modes.

### 3.3 Program topology

Programs group independently authorized child operations; they do not replace operation-level accounting.

Stable program constants:

```text
PROGRAM_NONE
PROGRAM_CONTRIBUTION
PROGRAM_GIFT_POOL
```

A standalone operation has `programId == bytes32(0)`. Contribution and gift-pool records use nonzero domain-bound program IDs.

### 3.4 Orthogonal capabilities

These capabilities must not be overloaded into the mode field:

- gas sponsorship: submission and gas-payer policy;
- multi-source aggregation: many contributors funding one objective;
- multi-claim distribution: one funded pool paying many recipients;
- receipt projection: machine and human views of the same canonical facts.

## 4. Toolchain Lock

P1–P6 implementation uses:

```text
Solidity       0.8.24
EVM            Cancun
optimizer      enabled
optimizer runs 200
Foundry        effective installed version, recorded in handoff
```

Prague and EIP-7702 remain deferred to P7.

IDs and signed/domain-bearing structures use `keccak256(abi.encode(...))`, never ambiguous `abi.encodePacked`.

## 5. Shared Architecture

The candidate must contain and test these boundaries:

```text
GlyphReceiptLedger
GlyphAttestationRegistry
SourceDeltaRouter
DestinationGlyphVault
IGlyphMessengerAdapter
MockGlyphMessengerAdapter
one verified testnet adapter candidate, if current lane support is proven
ContributionCampaign
GiftPool
safe token, signature, fee, quote, and receipt helpers
receipt exporter/verifier/card renderer
local deployment and scenario scripts
```

### 5.1 Receipt ledger

Canonical Monad anchor for:

- immutable operation terms;
- value legs;
- explicit proof classes;
- lifecycle state;
- source finalization;
- STN-Delta reconciliation;
- terminal receipt commitment.

It is not an identity oracle and does not transfer or custody value unless a later reviewed design explicitly changes the P1 separation. Value movement belongs in router/vault/program contracts.

### 5.2 Attestation registry

Append-only identity, purpose, acknowledgement, supersession, and revocation. Identity/purpose changes cannot mutate financial facts.

### 5.3 Source router

Responsible for:

- exact signed-term validation;
- direct or relayed payer/sender authorization;
- permit consumption where supported;
- maximum-input escrow;
- outbound authenticated route dispatch;
- stored destination acknowledgement;
- retryable source finalization;
- provider and fee settlement;
- atomic residual return;
- safe full refund after authenticated failure/release evidence.

No unrestricted call execution and no fund-sweep function are permitted.

### 5.4 Destination vault

Responsible for:

- provider-funded available liquidity;
- operation-scoped reservation accounting;
- authenticated source-domain/application validation;
- exact Pull delivery;
- claimant-safe Push claim;
- duplicate/nullifier protection;
- reservation release;
- delivery/failure acknowledgements.

It must never promise more immediately claimable value than available unreserved liquidity.

### 5.5 Messenger isolation

Core accounting depends only on a narrow versioned adapter interface. Messenger-specific endpoints, EIDs/domains, options, DVNs/validators, executors, fee quoting, and wire encoding stay in the adapter/configuration layer.

## 6. Immutable Operation Terms

The implementation may split this struct for stack/gas reasons, but every field below must be bound by `termsHash`, authorization, and `operationId` semantics:

```text
termsVersion
operationType
executionTopology
programId
proposedPurposeCode
initiator
payer
recipient
recoveryAddress
sourceChainId
sourceRouter
sourceAsset
destinationChainId
destinationVault
destinationAsset
maximumInput
destinationAmount
maximumServiceFee
maximumSponsoredGasFee
maximumTotalFee
feePolicyHash
routeQuoteHash
messengerPolicyHash
claimantRule
privateContextHash
expiry
routeNonce
actorNonce
```

Rules:

- changing any field invalidates authorization;
- mode, topology, program ID, parties, assets, chains, endpoints, amounts, policies, expiry, and nonces are immutable after registration;
- local topology requires source and destination chain to be the same and endpoints to satisfy local rules;
- cross-chain topology requires distinct nonzero source/destination chains;
- Pull V1 has exact recipient and no arbitrary calldata or recurring debit;
- Push binds its claimant rule and claim domain;
- `maximumTotalFee <= maximumInput`;
- `destinationAmount > 0` and `maximumInput > 0`;
- caller-supplied timestamps are not trusted.

`operationId` is the canonical receipt lookup key throughout the lifecycle.

## 7. Fee Policy and Splitting

Commercial percentages are configurable and must not be hardcoded as product defaults. Every operation binds its exact quote and fee policy before authorization.

Required fee roles:

```text
PROTOCOL
PROVIDER
REFERRER
GAS_SPONSOR
```

A role may have a zero amount under an explicitly valid policy. A nonzero amount requires a valid, policy-bound recipient or authenticated provider-selection rule.

Required rules:

```text
realizedServiceFees
  = protocolFee
  + providerFee
  + referrerFee

realizedFees
  = realizedServiceFees
  + sponsoredGasFee

maximumInput
  = realizedPrincipal
  + realizedFees
  + residualReturned
```

Additionally:

- `realizedFees <= maximumTotalFee`;
- service and sponsored-gas components obey their separate caps;
- exact destination delivery is not silently reduced by fees;
- fee realization occurs only after authenticated destination delivery;
- a full refund realizes zero principal and zero fees;
- no fee-on-fee arithmetic;
- every rounding remainder follows one deterministic, documented rule and no dust remains trapped;
- no administrator can redirect fee legs for an already-authorized operation;
- global policy changes affect new operations only;
- aggregate `FEE_REALIZED` may exist, but explicit role legs must reconcile exactly.

Required fee legs:

```text
FEE_PROTOCOL
FEE_PROVIDER
FEE_REFERRER
FEE_GAS_SPONSOR
```

Test percentages are fixtures only and must be labeled non-commercial test values.

## 8. Gasless Execution

“Gasless” means gasless to the user; a relayer, provider, paymaster, or sponsor still pays native gas.

MVP baseline:

- action-specific EIP-712 intents;
- EOA low-`s`/valid-`v`/nonzero recovery;
- EIP-1271 contract-wallet validation;
- action-scoped sequential nonces;
- deadlines;
- chain ID and verifying-contract domain separation;
- narrow relayer-call surfaces;
- EIP-2612 permit where the token supports it;
- Permit2-compatible path when prior authority exists;
- ordinary approval fallback when neither permit path exists.

Direct and relayed entrypoints must converge on the same internal economic implementation.

The authenticated actor comes from direct caller or verified signature, never from relayer `msg.sender`.

Relayers cannot alter:

- operation terms;
- payer/sender/recipient/claimant;
- recovery address;
- amounts or fee caps;
- provider or selection rule;
- chains, router, vault, or adapter policy;
- claim nullifier;
- arbitrary calldata.

ERC-4337 may be adapter-ready but is not required until current chain support is verified. EIP-7702 is prohibited in this MVP.

Sponsorship policy must include bounded method, wallet, operation, value, chain, nonce, and deadline controls. Raw observed gas cannot become an unbounded user charge; use a signed fixed or tightly capped sponsorship quote.

## 9. Push Lifecycles

### 9.1 Local Push

```text
register immutable Push
→ sender authorizes/funds
→ value becomes claimable
→ claimant proves claimant rule
→ exact recipient transfer
→ fees/residual reconcile
→ terminal receipt
```

### 9.2 Cross-chain Push

```text
sender authorizes/funds source maximum input
→ source escrow reaches required finality
→ authenticated reserve instruction
→ destination vault reserves liquidity
→ claimant opens fragment-secret link
→ claimant signs domain-bound ClaimIntent
→ gasless or direct claim
→ vault consumes nullifier and transfers exact amount
→ authenticated destination-delivery acknowledgement
→ atomic source provider/fee settlement and residual return
→ final source receipt anchored on Monad
→ RECONCILED receipt
```

Claim-secret requirements:

- fragment material never enters HTTP requests, calldata as raw secret, logs, analytics, previews, screenshots, crash reports, or persistence;
- the claim binds operation, claimant, chain, vault, amount, nonce, and deadline;
- copied calldata/signature from another address fails;
- claim and expiry/release are mutually exclusive;
- a completed claim permanently forbids refund.

## 10. Pull Lifecycles

### 10.1 Local Pull

```text
recipient creates immutable exact request
→ payer inspects terms
→ payer authorizes/funds exact bounded operation
→ recipient receives exact amount
→ fees/residual reconcile
→ terminal receipt
```

### 10.2 Cross-chain Pull

```text
recipient creates immutable destination request
→ payer selects supported source and inspects quote
→ payer authorizes maximum input and exact fee policy
→ source router escrows
→ source escrow reaches required finality
→ authenticated route instruction
→ destination vault reserves/delivers exact amount
→ authenticated destination acknowledgement
→ atomic source provider/fee settlement and residual return
→ final source receipt anchored on Monad
→ RECONCILED receipt
```

Pull cancellation is allowed only before payer authorization/source escrow. Pull V1 remains one-time, exact-recipient, and free of arbitrary calls or recurring debit.

## 11. Cross-Chain Boundary

Cross-chain is asynchronous. Do not claim global atomicity.

Separate transactions may include:

- source authorization/escrow;
- outbound message;
- destination reservation/delivery;
- destination acknowledgement;
- source finalization;
- final Monad receipt anchor.

Only source finalization is locally atomic and must:

1. verify stored authenticated destination evidence;
2. calculate bounded realized obligations;
3. mark source session terminal and remaining balance zero;
4. settle principal and explicit fee legs;
5. return residual to the bound recovery address;
6. emit complete finalization evidence.

Transfer failure reverts the entire local finalization. A stored acknowledgement permits permissionless retry.

### 11.1 Initial public evidence lane

Target lane:

```text
Base Sepolia (84532) source
→ Monad Testnet (10143) destination and canonical receipt anchor
```

Existing P0 LayerZero V2 EID references are candidate configuration, not current support proof. Before calling the candidate `DEPLOY_READY`, the executor must verify current official support, endpoints/EIDs, adapter requirements, and testnet behavior from authoritative sources. If verification is unavailable or contradictory:

```text
implement and fully test the messenger-neutral interface and adversarial mock;
prepare but do not mislabel the real adapter;
return BLOCKED_LANE_SUPPORT rather than inventing support.
```

Architecture is direction-neutral. Public E2E evidence for the reverse lane is not required in this build.

### 11.2 Message envelope

Every semantic message is versioned and binds at least:

```text
messageVersion
messageType
messageId
operationId
termsHash
sourceChainId
sourceApplication
destinationChainId
destinationApplication
routeNonce
payloadHash
```

Trusted adapter context—not payload assertions alone—establishes source domain and application.

Required message classes:

```text
ROUTE_PULL
RESERVE_PUSH
DESTINATION_RESERVED_ACK
DESTINATION_DELIVERED_ACK
RESERVATION_RELEASED_ACK
DESTINATION_FAILED_ACK
SOURCE_FINALIZED_RECEIPT
SOURCE_REFUNDED_RECEIPT
```

Receivers consume unique message IDs and unique `(operationId, messageType, routeNonce)` semantics. Unknown versions/types fail closed.

### 11.3 Proof classes

```text
LOCAL_VERIFIED
AUTHENTICATED_ADAPTER
LIGHT_CLIENT_VERIFIED
```

An authenticated adapter proof is never labeled light-client verification.

## 12. Refund and Recovery Safety

Expiry alone is insufficient when remote delivery may be in flight.

A cross-chain refund requires all applicable evidence:

```text
expiry reached or authenticated route failure
AND no destination-delivery evidence
AND no active destination reservation
AND authenticated reservation-release/failure evidence
AND configured finality/challenge condition satisfied
AND no source finalization/reconciliation
```

Once any authenticated destination-delivery evidence exists, refund is permanently forbidden regardless of message/status append order.

Required recovery paths:

```text
liquidity unavailable
→ authenticated route failure
→ refund pending
→ full refund

Push unclaimed at reservation expiry
→ destination reservation release
→ authenticated release acknowledgement
→ refund pending
→ full refund

callback/finalization failure
→ acknowledgement stored
→ permissionless retry
```

Full refund:

```text
realizedPrincipal = 0
realizedFees = 0
fullRefund = maximumInput
```

## 13. Destination Liquidity and Quotes

Providers pre-fund destination liquidity. Reservations are operation-scoped.

A route quote binds at least:

```text
provider or authenticated selection rule
source/destination chains and assets
source principal quote
exact destination amount
service and gas-sponsorship caps
fee policy
quote expiry
reservation expiry
rate/decimal treatment
messenger/finality policy
```

Do not add raw amounts from unlike assets. Source conservation is denominated in the source asset; destination delivery is independently checked in the destination asset.

Insufficient unreserved destination liquidity must reject reservation without producing a delivery acknowledgement.

## 14. Multi-Source Contribution Program

A contribution campaign is a parent program containing independently authorized child Pull operations.

Never represent multiple payers as one operation.

Campaign terms bind:

```text
campaign/program ID
recipient
destination chain/vault/settlement asset
target amount
minimum contribution
maximum contribution per payer
maximum total amount
deadline
payout mode
overfund policy
fee policy
purpose/context commitment
```

Each child binds its own:

```text
contributor
source chain/asset/router
maximum input
exact normalized destination contribution
fee/gas caps
recovery address
nonce/deadline
programId
```

Campaign totals count only reconciled destination contributions, never authorization, source escrow, or pending delivery.

Required configurable payout modes:

```text
IMMEDIATE
THRESHOLD_ESCROW
```

Required overfund behavior is explicit. Hard-cap mode accepts at most the remaining destination amount and returns unused source value through normal residual accounting. No silent oversubscription.

Threshold failure at deadline returns each contributor’s independently attributable value through proven child refund paths. One contributor cannot consume another contributor’s refund.

Mixed source assets/chains normalize through independent route quotes into one destination settlement asset; raw token units are never summed.

Required receipts:

- one terminal receipt per child contribution;
- one aggregate campaign receipt that commits to reconciled child receipt hashes and aggregate conservation/state.

## 15. Multi-Claim Gift Pool

A gift pool is a funded parent program with independent child claims. It is not one ordinary Push operation that settles repeatedly.

Recommended flow:

```text
one local or cross-chain pool-funding operation
→ funded destination GiftPool
→ many local gasless claims on the distribution chain
→ aggregate pool closure receipt
```

Initial claim policy must support fixed denomination and unique bearer credentials. Variable claims may be implemented only if the same caps and conservation tests are satisfied.

Each bearer credential uses a unique high-entropy secret commitment and unique nullifier. One shared public secret is prohibited.

Every claim binds:

```text
pool/program ID
claim allocation/index
claimant address
amount
nullifier
chain
GiftPool verifying contract
nonce
deadline
```

The raw secret never appears in on-chain state/events, receipt JSON, receipt card, logs, or persistence.

Pool conservation:

```text
fundedPool
  = totalClaimed
  + totalClaimFees
  + remainingPool
```

At terminal closure:

```text
remainingPool = returnedToRecovery
```

Creator-funded fee overhead is the default gift policy so the recipient receives the advertised claim amount. Any claim-deducted policy must be separately explicit and signed; it is not the default.

Required receipts:

- one receipt per successful claim;
- one aggregate gift-pool receipt;
- one closure/refund receipt for unused value.

## 16. Canonical Receipt

The receipt is mandatory protocol evidence, not deferred UI work.

Authority chain:

```text
chain state and contract events
→ canonical receipt JSON
→ human-readable card projection
```

### 16.1 Canonical key and terminal commitment

```text
operationId       stable receipt lookup key
finalReceiptHash  terminal commitment to the completed economic result
```

The final commitment must be domain-separated and bind at least:

```text
receipt schema version
ledger anchor chain and contract
operationId
terminal status
termsHash
value-leg commitment
fee-breakdown commitment
reconciliation commitment
```

Card bytes are not part of the financial receipt hash.

### 16.2 Required JSON outputs

For each standalone Push/Pull and each child operation/claim:

```text
receipt.json
receipt.verify.json
```

For aggregate programs:

```text
campaign.receipt.json
gift-pool.receipt.json
```

Canonical JSON must use stable schema versioning, normalized hex/addresses, integer-safe amount strings, deterministic ordering/canonicalization, and no floating-point accounting.

Required receipt sections:

```text
schema/version
operation/program identifiers
mode/topology/status
immutable terms and hashes
parties and roles
source/destination evidence
value legs
proof classifications
fee breakdown
STN-Delta reconciliation
identity bindings
purpose attestations/consensus or disagreement
privacy-safe commitments
message IDs
finalReceiptHash
verification results
```

Partial receipts are allowed but must label exact completeness. Only `RECONCILED` or `REFUNDED` is terminal.

### 16.3 Human-readable receipt card

No application UI is in scope. A deterministic card generator is mandatory.

Required outputs:

```text
receipt.card.svg
receipt.card.png  optional derivative when deterministic tooling is available
```

The SVG card must display:

- Glyph and receipt schema/renderer version;
- Push/Pull/program/claim type;
- unmistakable pending/reconciled/refunded state;
- purpose with honest attestation label;
- delivered/claimed/contributed amount;
- maximum input, total fee, concise split, residual/refund;
- source and destination chains/assets;
- truncated parties;
- proof class and source/destination/finalization status;
- operation/program ID and final receipt hash;
- verification payload or QR when generated without external tracking.

The card embeds `sourceReceiptHash` and contains no independent financial facts. It is regenerated from verified JSON.

A public card omits private context. Optional local private display context is stored separately, never changes `finalReceiptHash`, and is not written on-chain.

The receipt/card is not an authoritative NFT and is not transferable financial truth.

### 16.4 Receipt tooling behavior

The repository must provide deterministic equivalents of:

```text
receipt export <operationId> --output receipt.json
receipt verify receipt.json
receipt card receipt.json --output receipt.card.svg
```

Verification must recompute/check:

- schema;
- terms hash and operation ID;
- every leg/message identifier;
- proof classes and domains;
- fee splits/caps;
- source conservation;
- exact destination delivery;
- terminal-state/refund mutual exclusion;
- program child commitments and aggregate totals;
- final receipt hash;
- card `sourceReceiptHash`.

## 17. Privacy and Data Minimization

Prohibited in public state, calldata intended for publication, events, receipts, cards, manifests, logs, or handoffs:

- raw legal/personal names unless deliberately public and separately justified;
- email, phone, postal address;
- government/tax/bank/account identifiers;
- private invoice/billing text or URLs;
- raw gift claim secrets;
- credentials/private keys;
- low-entropy unsalted private-context values.

Allowed evidence includes typed namespaces, claim IDs, high-entropy salted commitments, issuer/proof references, deliberately public identifiers, and encrypted/content commitments whose source remains access-controlled.

Identity binding is opt-in per party. Acknowledgement never upgrades self-assertion to issuer verification. Historical bindings remain queryable after append-only revocation/supersession.

## 18. Security and Administrative Boundaries

Required controls:

- minimal, separately authorized writer/configuration roles;
- admin cannot bypass financial writer paths;
- no fund sweep;
- safe token handling and reentrancy protection;
- checks-effects-interactions;
- token allowlist or explicit native-asset policy;
- operation-, message-, route-, intent-, claim-, nullifier-, and receipt-level replay protection;
- fail-closed unknown mode/topology/program/message/proof/version;
- immutable recovery address;
- permissionless retry for stored acknowledgements/finalization where safe;
- emitted configuration changes;
- no unbounded arrays in hot settlement paths;
- aggregate analytics from events or bounded pagination, not global mutable volume counters.

## 19. P1 Candidate Intake and Acceptance Closure

The latest unpromoted P1 candidate is located outside canonical source and is not automatically accepted.

Candidate evidence:

```text
source workspace: /root/monadglyph-p1-engineer
frozen reviewed candidate hash:
fc36f0b30632fd8f0084eac05cc372b0c92d1bb049624abef54a7c46680592ab
historical regression: 35 passed, 0 failed, 0 skipped
review verdict: FAIL with 0 critical, 0 high, 2 medium, 1 low
```

Before extending P1, the executor must independently import only the intended reviewed files into the isolated candidate and close:

1. ledger accounting/authority acceptance-test gaps;
2. attestation/signature/boundary/getter/role-consensus acceptance-test gaps;
3. documentation-path drift in the prior review instructions.

The executor must not claim P1 accepted based on historical test counts. It must reproduce tests against the isolated tree and add the missing adversarial evidence named in `state/reviews/p1-correctness-review3.json`.

## 20. Required Implementation Sequence

The single executor works sequentially. It may repair within the same run but may not spawn or delegate.

### Gate 0 — intake and baseline

- read all governing files;
- record Git HEAD/dirty state and source fingerprints;
- create no deployment or external side effect;
- reproduce effective Foundry configuration and baseline tests;
- identify exact imported P1 candidate files.

### Gate 1 — P1 acceptance closure

- genuine RED tests for every review3 medium gap;
- minimal production repair only if a test exposes a defect;
- targeted GREEN;
- full P1 and legacy regression GREEN.

Failure blocks later gates.

### Gate 2 — shared local value core

- operation terms v2/extensions;
- fee policy/splitting;
- SourceDeltaRouter;
- DestinationGlyphVault;
- token and adversarial token mocks;
- mock messenger with delay/reorder/duplicate controls;
- local Push and Pull direct paths;
- refund/recovery and exact receipt evidence.

### Gate 3 — gasless paths

- signed direct-equivalent intents;
- EIP-2612 and Permit2-compatible paths where testable;
- EIP-1271;
- relayer and gas-sponsor accounting;
- direct-vs-relayed equivalence tests.

### Gate 4 — cross-chain Pull

- authenticated mock lane;
- exact destination delivery;
- source finalization retry;
- STN-Delta reconciliation;
- JSON and card receipt.

### Gate 5 — cross-chain Push

- reservation;
- claimant-bound claim/nullifier;
- gasless destination claim;
- expiry/release/refund;
- STN-Delta reconciliation;
- JSON and card receipt.

### Gate 6 — contribution program

- independent child Pulls;
- immediate and threshold modes;
- hard-cap/remaining behavior;
- mixed-source normalization boundaries;
- child and aggregate receipts.

### Gate 7 — gift pool

- pool funding;
- unique bearer commitments/nullifiers;
- multiple gasless local claims;
- expiry/remaining recovery;
- child and aggregate receipts.

### Gate 8 — verified adapter candidate and deployment readiness

- verify current Base Sepolia → Monad Testnet lane support from authoritative sources;
- implement/configure one real adapter candidate only when support is verified;
- prepare scripts/manifests without keys or broadcasts;
- record unresolved external prerequisites honestly.

### Gate 9 — complete deterministic verification

- run all mandatory commands/tests;
- generate local end-to-end proof bundle;
- generate and verify receipt JSON/cards;
- compute frozen tree fingerprint;
- emit final handoff.

No gate may be marked complete if its required tests are skipped.

## 21. Mandatory Adversarial Tests

At minimum:

### Ledger/attestation

Every unresolved review3 case, including field mutation, actual role/admin bypass attempts, true terminal reentry, every reconciliation/refund mismatch, huge-value conservation, changed chain/verifying contract, malformed ECDSA/EIP-1271, exact expiry equality, revoked/superseded fresh binding, nonexistent getters, authorized outsider-purpose rejection, and coincident payer/recipient role consensus.

### Value movement/accounting

- zero/minimal/nonzero residual;
- over/under-accounting;
- fee split exactness and rounding;
- fee cap breach;
- gas-sponsor cap breach;
- direct/relayed economic equivalence;
- transfer failure and reentrancy;
- insufficient liquidity;
- double reservation/delivery/finalization/refund;
- provider/recipient/recovery redirection.

### Cross-chain

- delayed, duplicated, reordered, and mutated messages;
- wrong source/destination chain/application/adapter;
- unknown version/type/proof kind;
- route quote and reservation expiry;
- delivery/refund race under every message order;
- destination delivered with acknowledgement delayed;
- stored acknowledgement plus retryable source finalization;
- failed final receipt anchor without economic replay;
- underdelivery and explicit overdelivery policy.

### Push/Pull isolation

- Pull authorization cannot fund/settle/claim Push;
- Push claimant proof cannot settle Pull;
- operation ID/message/nonce cannot cross modes;
- mode/topology/program cannot mutate;
- Session always fails closed.

### Contributions/gifts

- one contributor cannot spend/refund another;
- aggregate counts only reconciled children;
- hard-cap concurrency and final partial contribution;
- threshold failure refunds independently;
- one gift credential/nullifier claims once;
- one claimant cannot redirect another allocation;
- shared-secret drain is impossible because shared secrets are not supported;
- claims cannot exceed funded unreserved pool;
- pool closure conservation and recovery.

### Receipts/cards/privacy

- deterministic JSON and final hash;
- tampered terms/legs/fees/messages fail verification;
- partial receipt never renders terminal success;
- card values match canonical JSON;
- public card contains no raw private context or claim secret;
- child/aggregate receipt commitments match;
- renderer changes do not alter financial receipt hash.

Use Foundry unit, fuzz, and invariant/stateful tests. Fuzz runs must be meaningful and recorded; invariant handlers must exercise interleavings rather than merely call view functions.

## 22. Required Deliverables

The exact internal tree may evolve when justified in the handoff, but the result must include:

```text
contracts/src/GlyphReceiptLedger.sol
contracts/src/GlyphAttestationRegistry.sol
contracts/src/SourceDeltaRouter.sol
contracts/src/DestinationGlyphVault.sol
contracts/src/ContributionCampaign.sol
contracts/src/GiftPool.sol
contracts/src/interfaces/*
contracts/src/libraries/*
contracts/test/* unit/fuzz/invariant tests
contracts/test/mocks/*
contracts/script/* local/deploy-ready scripts
receipt schema
receipt exporter/verifier/card renderer
receipt fixtures for Pull, Push, contribution, gift claim, and aggregate programs
adapter configuration template without secrets
local E2E proof bundle
state/handoffs/glyph-mvp-hy3-oneshot.json
```

No frontend application, indexer service, public API, tunnel, or hosted receipt page is required.

## 23. Deterministic Verification Gate

Required commands or exact repository-equivalent commands:

```text
forge config --json
forge fmt --check
forge build --force
forge test -vvv
focused P1 ledger/attestation tests
focused router/vault tests
focused Pull/Push tests
focused contribution/gift tests
fuzz tests
invariant/stateful tests
receipt schema validation
receipt fixture export and verification
receipt SVG deterministic snapshot/hash checks
dangerous-pattern searches
git diff --check
source/tree fingerprint
handoff JSON-schema validation
```

If coverage tooling is available without changing the toolchain, run it and record the result. Coverage is evidence, not a substitute for branch-specific tests.

Dangerous-pattern inspection includes at least:

```text
abi.encodePacked in domain/ID derivation
delegatecall
selfdestruct
tx.origin
unrestricted external call/value call
raw transfer/send usage
fund sweep
arbitrary calldata execution
unchecked token results
secret/PII fixtures
legacy proxy import/address/slot
```

Text matches are inspected; they are not automatically mislabeled vulnerabilities.

## 24. Executor Boundary

The executor may:

- read the locked specifications and reviewed candidate;
- write only inside the isolated candidate workspace;
- install local workspace dependencies when necessary and recorded;
- run local chains, compilers, tests, scripts, receipt tools, and read-only web verification;
- iterate until gates are GREEN or a truthful blocker is reached;
- write the required handoff and evidence bundle.

The executor may not:

- edit this execution contract or its hash manifest;
- edit canonical `/root/monadglyph`;
- edit other profiles, `/root/soul.md`, `/root/workers`, Hermes config, MCP, gateway, cron, or infrastructure;
- invoke `delegate_task`, another model, another Hermes process, MoA, or subagent;
- use `gpt-5.6-sol`;
- deploy, sign, broadcast, fund, move assets, read private keys, or expose a service;
- commit or push;
- delete/weaken/skip failing tests to report GREEN;
- fabricate command results, chain support, addresses, proofs, receipts, or deployment status;
- label mock adapter evidence as public testnet evidence;
- claim `Live` or `Deployed`.

No `--yolo` approval bypass is authorized.

## 25. Completion and Failure Schema

The final handoff must validate against `state/handoff.schema.json` or a compatible locked extension and include:

```text
status: DEPLOY_READY | BLOCKED | FAILED
execution provider/model/source/session
execution-contract path and SHA-256
input workspace/path fingerprints
files changed
RED and GREEN commands with exit codes and output digests
test counts by suite
fuzz/invariant configuration and results
receipt fixture paths and hashes
source/tree fingerprint
verified lane evidence and citations, or exact support blocker
unresolved findings/risks
deployment/signing/funding/external-write fields all false/empty
Git HEAD and dirty state
```

`DEPLOY_READY` requires every mandatory local gate GREEN and a verified real-adapter candidate/configuration. It does not mean deployed or live.

Use `BLOCKED` for external prerequisites or specification conflicts. Use `FAILED` for implementation/test failure after attempted repair. Never downgrade a failure to a skipped success.

## 26. Post-Build Boundary

After the `hy3:free` process exits:

1. deterministic verification is rerun against the exact candidate;
2. the tree is frozen and fingerprinted;
3. one quota-limited `gpt-5.6-sol` strengthening review may inspect that exact tree;
4. any repairs return to the same bounded implementation approach and require a new fingerprint;
5. deployment remains separately prohibited until explicit user approval;
6. public `Live` language remains prohibited until chain readback proves every advertised lifecycle.

## 27. Locked Summary

```text
modes                Push + Pull enabled; Session reserved/disabled
topologies           local + cross-chain
initial evidence lane Base Sepolia → Monad Testnet, support must be verified
accounting           STN-Delta with atomic source closure
fees                protocol/provider/referrer/gas sponsor; configurable and terms-bound
gasless              EIP-712 relayer + permit paths; no EIP-7702
aggregation          contribution parent + independent child Pulls
distribution         gift pool + unique child claims/nullifiers
receipt              canonical JSON + deterministic human SVG card
UI                   excluded
deployment            excluded
executor              one direct sequential `hy3:free` process; no delegation
review model          `gpt-5.6-sol` only after GREEN frozen tree
```
