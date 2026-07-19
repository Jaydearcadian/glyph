# Glyph Link Protocol v1

Status: MVP-local link layer for the proven core/receipt system. This document defines the frontend-independent contract for creating, inspecting, indexing, and verifying Glyph links before UI wiring.

## Scope

`glyph.link.v1` covers three link kinds:

| Kind | Purpose | Private material |
|---|---|---|
| `PULL` | payer funds an immutable pull/request operation | optional private memo/secret in URL fragment only |
| `PUSH` | payer funds a claimable push/gift/payment operation | claim secret in URL fragment only; public record carries nullifier hash only |
| `RECEIPT` | user opens/verifies a canonical receipt JSON/card | no secret by default |

This version intentionally targets **LOCAL same-chain** MVP flows first. Cross-chain link payloads are reserved by the schema (`topology: CROSS_CHAIN`) but not emitted by `scripts/glyph_link_tool.py` yet.

## URL shape

Links use a URL fragment so private material is not sent to servers in HTTP requests:

```text
https://<host>/<app>#/glyph/<base64url(canonical-json-payload)>
```

Rules:

1. The payload after `#/glyph/` is canonical JSON encoded with URL-safe base64 without padding.
2. The URL query string MUST NOT contain secrets, claim material, private memos, or plaintext purpose.
3. Secrets MUST remain under payload field `secrets` and MUST NOT be copied into public index records.
4. A public crawler/indexer may store only the output of `glyph_link_tool.py index <link>`.
5. Operation terms are immutable by `termsHash`; display fields are hints only.

## Canonical payload fields

Common fields:

```json
{
  "schemaVersion": "glyph.link.v1",
  "kind": "PULL | PUSH | RECEIPT",
  "topology": "LOCAL | CROSS_CHAIN",
  "operationId": "0x...",
  "termsHash": "0x..."
}
```

For `PULL`/`PUSH`, `terms` contains the operation facts used by the helper to compute `termsHash` and `operationId`:

```json
{
  "mode": "PULL",
  "topology": "LOCAL",
  "sourceChainId": 10143,
  "destinationChainId": 10143,
  "router": "0x...",
  "destinationVault": "0x...",
  "sourceAsset": "0x...",
  "destinationAsset": "0x...",
  "payer": "0x...",
  "recipient": "0x...",
  "recovery": "0x...",
  "provider": "0x...",
  "maximumInput": "110000000000000000000",
  "destinationAmount": "100000000000000000000",
  "fees": {
    "protocol": "1",
    "provider": "2",
    "referrer": "3",
    "gasSponsor": "4"
  },
  "expiry": 1784543060,
  "nonce": 7
}
```

`PUSH` also includes:

```json
{
  "claim": {
    "claimSecretTransport": "fragment-only",
    "nullifierHash": "0x...",
    "gatekeeper": "0x..."
  },
  "secrets": {
    "claimSecret": "not-for-query-not-for-index"
  }
}
```

`PULL` may include:

```json
{
  "secrets": {
    "secret": "not-for-query-not-for-index"
  }
}
```

`RECEIPT` includes a receipt pointer and receipt facts:

```json
{
  "kind": "RECEIPT",
  "receipt": {
    "path": "state/receipts/LOCAL_PULL.receipt.json",
    "schemaVersion": "glyph.receipt.v1",
    "mode": "PULL",
    "status": "RECONCILED",
    "topology": "LOCAL",
    "finalReceiptHash": "0x...",
    "termsHash": "0x..."
  }
}
```

## Hash domains

The CLI uses explicit hash domains:

| Value | Domain |
|---|---|
| `termsHash` | `GLYPH_LINK_TERMS_V1` |
| `operationId` | `GLYPH_LINK_OPERATION_V1` over `{termsHash, terms}` |
| `claim.nullifierHash` | `GLYPH_PUSH_CLAIM_NULLIFIER_V1` over operation id + claim secret |
| receipt verification | existing `GLYPH_FINAL_RECEIPT_V1` |

The link helper’s operation id is a deterministic link-layer identifier for preflight/frontends. Contract tests remain the authority for onchain operation semantics.

## Public index record

Public records are generated only through:

```bash
python3 scripts/glyph_link_tool.py index '<link>'
```

Allowed public record fields:

- schemaVersion
- kind
- topology
- operationId
- termsHash
- chainId
- mode
- asset
- amount
- expiry
- `nullifierHash` for `PUSH`
- finalReceiptHash/status for receipt links

Forbidden public fields:

- `secrets`
- `secret`
- `claimSecret`
- private memo/purpose text
- raw passcode/claim material

## CLI examples

Create a local Pull link:

```bash
python3 scripts/glyph_link_tool.py pull create \
  --base-url https://glyph.local/app \
  --chain-id 10143 \
  --router 0x0000000000000000000000000000000000001005 \
  --vault 0x0000000000000000000000000000000000001006 \
  --source-asset 0x0000000000000000000000000000000000002001 \
  --destination-asset 0x0000000000000000000000000000000000002001 \
  --payer 0x0000000000000000000000000000000000001002 \
  --recipient 0x0000000000000000000000000000000000001003 \
  --recovery 0x0000000000000000000000000000000000001004 \
  --provider 0x0000000000000000000000000000000000009001 \
  --maximum-input 110000000000000000000 \
  --destination-amount 100000000000000000000 \
  --protocol-fee 1 --provider-fee 2 --referrer-fee 3 --gas-sponsor-fee 4 \
  --expiry 1784543060 --nonce 7 --secret fragment-only \
  --out state/links/examples/local_pull.link.json
```

Create a local Push link:

```bash
python3 scripts/glyph_link_tool.py push create \
  --base-url https://glyph.local/app \
  --chain-id 10143 \
  --router 0x0000000000000000000000000000000000001005 \
  --vault 0x0000000000000000000000000000000000001006 \
  --source-asset 0x0000000000000000000000000000000000002001 \
  --destination-asset 0x0000000000000000000000000000000000002001 \
  --payer 0x0000000000000000000000000000000000001002 \
  --recipient 0x0000000000000000000000000000000000001003 \
  --recovery 0x0000000000000000000000000000000000001004 \
  --provider 0x0000000000000000000000000000000000009001 \
  --gatekeeper 0x0000000000000000000000000000000000009002 \
  --maximum-input 110000000000000000000 \
  --destination-amount 100000000000000000000 \
  --protocol-fee 1 --provider-fee 2 --referrer-fee 3 --gas-sponsor-fee 4 \
  --expiry 1784543060 --nonce 8 --claim-secret fragment-only-claim \
  --out state/links/examples/local_push.link.json
```

Create and verify a receipt link:

```bash
python3 scripts/glyph_link_tool.py receipt create \
  --base-url https://glyph.local/app \
  --receipt state/receipts/LOCAL_PULL.receipt.json \
  --out state/links/examples/local_pull_receipt.link.json

python3 scripts/glyph_link_tool.py verify-receipt "$(python3 - <<'PY'
import json
print(json.load(open('state/links/examples/local_pull_receipt.link.json'))['link'])
PY
)"
```

## Frontend contract

Frontend screens should consume the CLI/spec fields as follows:

| Screen | Required data | Security rule |
|---|---|---|
| Create Pull | user input -> link payload | never place secret in query string |
| Inspect Pull | decode fragment, show immutable terms + termsHash | wallet signs/funds only shown terms |
| Create Push | user input -> link payload + nullifier hash | claim secret remains fragment-only |
| Claim Push | decode fragment, derive claimant/nullifier material | reject missing/mismatched nullifier |
| Receipt | receipt link -> receipt JSON/card verification | display `finalReceiptHash`, verification result |

## Verification commands

```bash
python3 scripts/test_glyph_link_tool.py
python3 -m py_compile scripts/glyph_link_tool.py scripts/test_glyph_link_tool.py scripts/receipt_tool.py
python3 scripts/receipt_tool.py verify state/receipts/LOCAL_PULL.receipt.json
python3 scripts/receipt_tool.py verify state/receipts/LOCAL_PUSH.receipt.json
```
