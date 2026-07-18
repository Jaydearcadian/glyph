# Glyph Product Doctrine

Status: **P0 canonical product direction**  
Scope: product meaning and sequencing; not an implementation claim.

## Master Thesis

> **A link becomes an operation.**

Glyph makes self-custodial blockchain operations feel as direct as ordinary Web links while preserving immutable terms, bounded authority, verifiable settlement, recovery, and receipts.

## Product Ladder

```text
PUSH VALUE → PULL PAYMENT → ROUTE ACROSS CHAINS → DELEGATE AUTHORITY
```

### Push

> “I am sending you value.”

The sender creates a claimant-safe value link. The recipient opens it, verifies terms, claims once, and receives a receipt. Unclaimed value follows an explicit expiry/recovery path.

### Pull

> “Pay this exact request.”

The recipient creates immutable payment terms. The payer opens the link, verifies the destination and amount, chooses a supported funding source, and pays. Pull V1 is one-time and contains no arbitrary calldata or recurring debit.

### Cross-chain

> “You choose where value arrives. The payer chooses where it comes from.”

Cross-chain routing is an adapter-backed settlement path, not a new bridge owned by Glyph. The UI hides unnecessary route ceremony but never hides destination asset, fees, finality, proof class, or recovery behavior.

### Session

> “You may perform these exact actions under these exact limits.”

Sessions are authority operations. They follow Push/Pull only after a separate EIP-7702 authorization kernel is rebuilt and independently proven. The current deployed proxy is deprecated and cannot be used as the future authority foundation.

## STN-Delta

> **Authorize enough for certainty. Consume exactly what settles. Return everything else.**

A payer may overfund a bounded source session. After authenticated destination settlement, source finalization atomically:

1. settles the realized principal;
2. settles realized fees;
3. zeros and terminates the source session;
4. returns the residual to the payer’s recovery wallet.

The cross-chain lifecycle is asynchronous. Glyph promises atomic **source-session closure**, not global atomicity across independent chains.

## Receipt-Led Product

Every successful operation produces a Monad-anchored account of:

- the operation and immutable terms;
- payer, recipient, and initiator wallets;
- optional identity claims selected by each party;
- operation type and purpose attestations;
- each value leg across chains;
- proof type and transaction reference;
- destination delivery;
- realized fees;
- STN-Delta residual return;
- terminal reconciliation or refund status.

The ledger records facts and attributable claims. It does not declare a self-asserted identity legally verified or a party-supplied purpose legally true.

## Identity Doctrine

- A payer controls payer identity attachment.
- A recipient controls recipient identity attachment.
- One party cannot author identity for the other without the subject’s signature or an authorized issuer path.
- Claims distinguish `SELF_ASSERTED`, `COUNTERPARTY_ACKNOWLEDGED`, and `ISSUER_VERIFIED`.
- Historical receipts bind a claim ID/version; later revocation or supersession does not rewrite history.
- Raw PII, names, emails, addresses, tax data, account numbers, and private invoice descriptions do not belong on-chain.

## Purpose Doctrine

Operation mechanism and economic purpose are separate:

```text
Operation: PULL
Purpose:   BILL
```

The initiator proposes purpose. Payer and recipient may attest independently. Agreement can be presented as consensus; disagreement remains visible and append-only.

Initial purpose families:

```text
TRANSFER
PAYMENT
BILL
INVOICE
GOODS_AND_SERVICES
REIMBURSEMENT
DONATION
PAYROLL
BOUNTY
SUBSCRIPTION
SERVICE_USAGE
OTHER
```

Specific details are committed through hashes or privacy-preserving references, not published in plaintext.

## Interaction Doctrine

Web2-like means:

- one obvious primary action;
- mobile-first opening;
- progressive disclosure;
- chain details available but not forced before they matter;
- no fake success state;
- clear recovery and receipt.

Web3 guarantees remain:

- self-custody;
- immutable operation terms;
- claimant/recipient binding;
- replay resistance;
- verifiable settlement;
- explicit expiry and refund;
- no unrestricted wallet or master-key exposure.

## Link Security

Secrets use URL fragments:

```text
https://glyph.example/push/<operationId>#key=<secret>
```

Fragment material must be parsed locally, removed from the visible URL, and kept out of HTTP requests, analytics, logs, previews, screenshots, and persistent browser storage.

## Scope Discipline

Build order:

1. protocol doctrine and invariants;
2. receipt/attestation ledger spine;
3. same-chain/local routing behavior;
4. public-testnet Cross-chain Pull;
5. public-testnet Cross-chain Push;
6. shared SDK/indexer/receipt UI;
7. Sessions;
8. Hybrid value + authority.

Do not broaden into subscriptions, bill splitting, streams, recurring outlays, multi-chain netting, or broad commerce before the core Push/Pull lifecycle is publicly proven.

## Design Direction

The prior frontend is intentionally retired. Future UI is brutalist and mobile-first:

- Electric Cyan — value;
- Deep Purple — authority/session;
- Cyber Green — hybrid.

This document does not authorize rebuilding the frontend. Product behavior and receipts must be proven first.

## Honest Public Language

Use:

> Glyph turns links into programmable Web3 operations.

> Send from your chain. They receive on theirs.

> Overfund for certainty. Settle exactly. Snap back the rest.

Do not use:

- globally atomic cross-chain payment;
- production-ready authority proxy;
- live cross-chain routing without source and destination receipts;
- verified identity for self-asserted claims;
- reconciled when only destination delivery is known.
