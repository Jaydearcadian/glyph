# Glyph State Machines

Status: P0 executable specification.

## Operation State

```text
NONE
  → REGISTERED
  → SOURCE_AUTHORIZED
  → SOURCE_ESCROWED
  → ROUTE_PENDING or DESTINATION_RESERVED
  → DESTINATION_SETTLED
  → SOURCE_FINALIZED
  → RECONCILED
```

Recovery:

```text
REGISTERED/SOURCE_AUTHORIZED/SOURCE_ESCROWED/ROUTE_PENDING/DESTINATION_RESERVED
  → EXPIRED or ROUTE_FAILED
  → REFUND_PENDING
  → REFUNDED
```

Optional annotation state `DISPUTED` does not rewrite financial state. A reconciled or refunded operation remains terminal even when an attestation dispute exists.

## Transition Authority

| Transition | Authorized actor/evidence |
|---|---|
| `NONE → REGISTERED` | Glyph operation creator/authorized factory |
| `REGISTERED → SOURCE_AUTHORIZED` | payer authorization validated |
| `SOURCE_AUTHORIZED → SOURCE_ESCROWED` | source router observes successful funding |
| `SOURCE_ESCROWED → ROUTE_PENDING` | authenticated outbound dispatch |
| `ROUTE_PENDING → DESTINATION_RESERVED` | destination vault reservation |
| `ROUTE_PENDING/DESTINATION_RESERVED → DESTINATION_SETTLED` | local destination transfer success |
| `DESTINATION_SETTLED → SOURCE_FINALIZED` | source router consumes authenticated acknowledgement and closes |
| `SOURCE_FINALIZED → RECONCILED` | Monad ledger receives final source receipt and conservation passes |
| eligible nonterminal → `REFUND_PENDING` | expiry/failure plus safety condition |
| `REFUND_PENDING → REFUNDED` | successful bound recovery transfer and final receipt |

## Push Claim State

```text
UNAVAILABLE → RESERVED → CLAIMABLE → CLAIMED
                         ↘ EXPIRED → RELEASED
```

- Claim and expiry are mutually exclusive.
- A copied claim from another address fails claimant binding.
- `CLAIMED` is written before external transfer and the transfer failure reverts state.

## Pull Request State

```text
NONE → OPEN → ROUTING → PAID
          ↘ CANCELLED
          ↘ EXPIRED
```

Cancellation is allowed only before payer authorization/source escrow. Pull V1 is one-time.

## Source Delta Session

```text
NONE → FUNDED → DISPATCHED → ACKNOWLEDGED → FINALIZED
          ↘ REFUNDABLE → REFUNDED
```

- `ACKNOWLEDGED` stores proof even if automatic finalization fails.
- `FINALIZED` records zero remaining balance and completed residual transfer.
- A destination-settled session cannot become refundable.

## Receipt State

```text
REGISTERED
→ DESTINATION_EVIDENCED
→ SOURCE_EVIDENCED
→ RECONCILED
```

A receipt can show partial evidence without presenting terminal success.

## Identity Claim State

```text
ACTIVE → SUPERSEDED
ACTIVE → REVOKED
ACTIVE → EXPIRED (derived from time)
```

Historical operation bindings remain immutable.

## Invalid Transitions

At minimum, contracts/tests reject:

- terminal → any other financial state;
- destination settled twice;
- source finalized before destination proof;
- refunded after destination settlement;
- reconciled before final source receipt;
- cancelled after source escrow;
- identity revocation by a non-subject/non-issuer;
- purpose attestation overwrite.
