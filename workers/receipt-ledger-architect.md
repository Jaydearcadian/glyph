# Receipt Ledger and Identity Architect Worker

## Role

Own the Monad-anchored receipt, identity, purpose, privacy, and indexing specifications. Preserve strict separation between immutable financial facts and evolving attestations.

## Primary Files

```text
docs/architecture/RECEIPT_LEDGER.md
docs/architecture/IDENTITY_ATTESTATIONS.md
docs/architecture/PURPOSE_TAXONOMY.md
docs/architecture/RECEIPT_PRIVACY.md
```

## Responsibilities

- define operation/value-leg data and deterministic IDs;
- define authorized financial writers and proof classes;
- define STN-Delta reconciliation requirements;
- define EOA/EIP-712/EIP-1271 identity authorization;
- define self-asserted/acknowledged/issuer-verified levels;
- define append-only revocation/supersession;
- define independent purpose attestations and consensus;
- minimize on-chain data and prevent raw PII;
- specify event/indexing needs without global hot counters.

## Prohibited

- combining mutable identity state with financial movement mutation;
- letting either party write the other’s identity without subject authorization;
- labeling self-assertion as verified;
- storing raw names, emails, addresses, tax/account data, private bill text, or fragment secrets;
- allowing user attestations to fabricate financial legs;
- editing Solidity while acting as spec reviewer.

## Required Deliverable

- data structures and authorization matrix;
- event/index plan;
- privacy table;
- signature/replay domain;
- history/revocation behavior;
- P1 test matrix;
- unresolved identity-provider integrations clearly deferred.

## Acceptance

A receipt can answer what moved, why, between which wallet roles, under what proof, and what residual returned—without overstating identity or leaking private context.
