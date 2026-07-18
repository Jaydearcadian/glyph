# Glyph Purpose Taxonomy

Status: P0 specification.

## Principle

Operation mechanism and economic purpose are independent dimensions:

```text
operationType = PULL
purposeCode   = BILL
```

Purpose is an attributable claim, not a unilateral mutable label.

## Initial Codes

Use versioned `bytes32` identifiers such as `keccak256("glyph.purpose.bill.v1")`.

| Code | Meaning |
|---|---|
| `TRANSFER` | General value transfer without a more specific declared purpose |
| `PAYMENT` | General payment |
| `BILL` | Payment of a billed obligation |
| `INVOICE` | Payment against an invoice |
| `GOODS_AND_SERVICES` | Purchase of goods or services |
| `REIMBURSEMENT` | Repayment of an expense or advance |
| `DONATION` | Voluntary donation |
| `PAYROLL` | Compensation/payroll intent; not legal classification by itself |
| `BOUNTY` | Bounty/reward settlement |
| `SUBSCRIPTION` | Subscription-related intent; recurring debit is not implemented by declaring this code |
| `SERVICE_USAGE` | Usage/metered service payment intent |
| `OTHER` | Purpose committed by context hash but outside known codes |

Codes describe intent. They do not create legal/tax status.

## Attestation

```solidity
struct PurposeAttestation {
    bytes32 operationId;
    address attestor;
    bytes32 purposeCode;
    bytes32 contextHash;
    uint64 attestedAt;
}
```

- Initiator proposes purpose at registration.
- Payer and recipient attest independently.
- Attestations are append-only.
- Exact matching payer and recipient `(purposeCode, contextHash)` may be surfaced as consensus.
- Disagreement is retained; no last-write-wins field.

## Context

`contextHash` may commit to an invoice, bill, purchase order, private memo, or service receipt. Raw content remains off-chain and should be encrypted/access-controlled where private.

Recommended canonicalization before hashing:

```text
media type + schema version + canonical serialized bytes
```

The SDK must expose how the hash was produced. A hash without retrievable/possessed source content proves only commitment consistency.

## Privacy

Do not store bill description, customer name, address, tax ID, account number, or private document URL in events/calldata. Public purpose code is optional; a party may use a privacy-preserving generic code plus context hash.

## Changes

A mistaken attestation is corrected by appending a superseding attestation referencing the prior attestation ID. Historical values remain visible.
