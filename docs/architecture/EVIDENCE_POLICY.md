# Glyph Evidence Policy

Status: P0 operating specification.

## Principle

No product or implementation claim exceeds its strongest verified evidence.

## Status Vocabulary

| Label | Required evidence |
|---|---|
| Designed | reviewed specification exists |
| Built | compiler succeeds against identified tree/config |
| Tested | named tests pass against identified tree |
| Deployed | successful chain receipt and runtime bytecode |
| Configured | expected values read back from deployed contracts |
| Destination settled | destination receipt + state/balance assertions |
| Source finalized | source receipt + zero/terminal state + transfers |
| Reconciled | Monad anchors complete value legs and conservation passes |
| Refunded | recovery transfer and terminal state proven |
| Live | every advertised route passes publicly end-to-end |

## Required P4/P5 Receipt Bundle

```text
operation terms/termsHash
source chain/address/tx/log
outbound message ID
Monad destination tx/log
recipient before/after balance
acknowledgement message ID
source finalization tx/log
provider settlement amount
payer residual before/after balance
final Monad receipt-anchor tx/log
ledger terminal state
conservation assertion
```

## Deployment Manifest Evidence

A manifest records:

- chain ID and network name;
- contract name/address;
- deployment transaction/block;
- runtime code hash;
- constructor/configuration commitments;
- configured adapters/remote peers;
- explorer URL;
- Git commit/tree;
- verification timestamp/status;
- deprecation state.

All fields are read back or derived reproducibly. Secrets are excluded.

## Tests

Reports include exact commands, exit codes, pass/fail counts, skipped tests, effective EVM/Solc settings, and Git status. Historical test counts do not prove current files.

## Cross-Chain Honesty

- A submitted source transaction is not destination settlement.
- A destination transfer is not source finalization.
- Source finalization is not Monad reconciliation until final receipt anchor.
- LayerZero authenticated messaging is not described as light-client proof.
- Pre-funded testnet liquidity is labeled as such, not production routing.

## Identity Honesty

Receipts display claim verification level and issuer. Self-assertion is never labeled verified identity. Purpose consensus requires matching payer and recipient attestations.

## Brain and State

Brain retains decisions and phase evidence. Canonical session state is regenerated only after targeted recall returns intended nodes/relations. If recall fails or returns stale/noisy state, report the gap and do not claim the projection is Brain-verified.

## Worker Evidence

Worker summaries are untrusted until the orchestrator verifies paths, diffs, commands, and external side effects. A deployment claim requires direct chain readback.

## Public Demo

A demo may show pending/failure states. It must not fake success. Explorer links and receipt details remain accessible through progressive disclosure.
