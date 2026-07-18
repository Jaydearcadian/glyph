# Glyph Threat Model

Status: P0 baseline. Review and expand at every phase.

## Assets

- payer source escrow and residual;
- destination liquidity and reservations;
- recipient destination payout;
- route-provider reimbursement;
- operation/claim authorizations;
- receipt integrity;
- identity/purpose attribution;
- configuration/admin authority;
- link-fragment secrets.

## Trust Boundaries

- payer/recipient wallets;
- source router;
- destination vault;
- Monad receipt/attestation registries;
- messenger endpoint/adapter and remote application;
- destination liquidity provider;
- indexer/frontend/relayer;
- identity issuer;
- administrator/configuration roles.

## Critical Threats and Required Controls

| Threat | Required control |
|---|---|
| Forged destination acknowledgement | expected adapter/domain/application + terms hash + nonce |
| Duplicate delivery/settlement | operation/message nullifiers and terminal-state checks |
| Refund races delivered payout | conservative pending state, finality rule, destination proof recovery |
| Route overcharges payer | signed maximum input/fee ceiling and conservation check |
| Residual redirected | recovery address bound in payer authorization |
| Destination underpays | exact destination amount check before acknowledgement |
| Insolvent destination vault | reservation accounting and available-liquidity check |
| Front-run Push claim | claimant-bound signature and consumed claim nonce |
| Fragment leakage | local parsing/stripping before network/analytics |
| Malicious token/reentrancy | safe transfers, checks-effects-interactions, nonReentrant, token allowlist |
| Malicious messenger callback | narrow adapter, domain checks, no arbitrary call surface |
| Failed callback traps funds | stored acknowledgement + retryable finalize/refund |
| Receipt fabrication | financial writes limited to approved contracts/adapters |
| Proof-level inflation | explicit proof enum; adapter proof not labeled light client |
| Identity impersonation | subject EOA/EIP-1271 signature or authorized issuer |
| Counterparty identity overwrite | subject-only binding and append-only history |
| PII permanence | commitments only; prohibited-data policy |
| Purpose rewrite | append-only independent attestations |
| Admin compromise | minimal roles, emitted changes, delay/multisig direction, no fund sweep |
| Cross-chain replay | bind chain IDs, applications, version, operation, nonce |

## Invariants Under Failure

- Destination failure cannot pay route provider.
- Source finalization failure cannot leave partial local accounting.
- Receipt-anchor failure cannot reverse completed settlement but blocks `RECONCILED` label.
- Indexer failure cannot change contract truth.
- Relayer censorship leaves permissionless retry paths.
- Identity issuer failure does not affect financial settlement.

## Deprecated Proxy Risk

The existing `GlyphSessionProxy` has an incorrect namespace slot and inadequate authorization. It is outside active architecture and must not receive new privileges, funds, or integrations.

## Review Gates

P1 review: ledger authorization, signatures, state, privacy.  
P2 review: escrow, liquidity, claims, refunds, mock-message ordering.  
P3 review: adapter configuration, domain verification, retry/replay.  
P4/P5 review: public receipt ordering, balances, failure recovery.  
Mainnet: independent external audit and operational/security governance.
