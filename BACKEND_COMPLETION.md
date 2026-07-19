# Glyph backend completion note

Scope: completed backend/product artifacts **excluding frontend app build** and **excluding cross-chain delivery repair**.

## Completed backend artifacts

| Area | Status | Artifacts |
|---|---|---|
| Monad Pull contract lifecycle | Complete, live-proven | `state/live/monad-address-pair-proof-20260719T130942Z/` |
| Monad Push contract lifecycle | Complete, live-proven | `state/live/monad-address-pair-proof-20260719T130942Z/` |
| Multi-party contribution aggregation | Complete, live-proven | `state/live/monad-campaign-proof-20260719T132755Z/` |
| Receipt ledger spine | Complete for backend MVP | `contracts/src/GlyphReceiptLedger.sol` + tests |
| Live receipt JSON builder | Complete | `scripts/live_receipt_builder.py` |
| Live receipt JSON artifacts | Complete | `*.live.receipt.json` in proof bundles |
| Live receipt SVG cards | Complete | `*.live.receipt.card.svg` in proof bundles |
| Receipt-link JSON artifacts | Complete | `*.live.receipt.link.json` in proof bundles |
| Receipt QR PNG artifacts | Complete | `*.live.receipt.qr.png` in proof bundles |
| Link schema validation | Complete for receipt links | `state/schemas/link.schema.json` |

## Generated live receipt artifacts

### Monad address-pair proof

```text
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.json
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.card.svg
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.link.json
state/live/monad-address-pair-proof-20260719T130942Z/pull.live.receipt.qr.png
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.json
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.card.svg
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.link.json
state/live/monad-address-pair-proof-20260719T130942Z/push.live.receipt.qr.png
```

### Monad campaign proof

```text
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.json
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.card.svg
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.link.json
state/live/monad-campaign-proof-20260719T132755Z/campaign.live.receipt.qr.png
```

## Contribution vs distribution boundary

Completed:

```text
contributor A child Pull receipt
contributor B child Pull receipt
aggregate campaign close receipt
campaign closed=true
```

Not implemented as a separate primitive:

```text
split payout / multi-recipient distribution contract
recipient-side distribution claim UX
```

For this backend completion pass, "multi-party contribution" is complete; "distribution" remains a separate future primitive unless the product scope defines campaign close as the distribution event.

## Verification commands

```bash
python3 scripts/live_receipt_builder.py --base-url 'https://glyph.local/app#/glyph/'
for f in state/live/monad-address-pair-proof-20260719T130942Z/*.live.receipt.json state/live/monad-campaign-proof-20260719T132755Z/*.live.receipt.json; do
  python3 scripts/receipt_tool.py verify "$f"
done
python3 - <<'PY'
import json, pathlib, jsonschema
root=pathlib.Path('.')
schema=json.loads((root/'state/schemas/link.schema.json').read_text())
for f in list((root/'state/live/monad-address-pair-proof-20260719T130942Z').glob('*.live.receipt.link.json')) + list((root/'state/live/monad-campaign-proof-20260719T132755Z').glob('*.live.receipt.link.json')):
    jsonschema.validate(json.loads(f.read_text())['payload'], schema)
PY
```

## Remaining excluded work

```text
frontend app
public frontend deploy
Base→Monad destination delivery / ACK / finalize repair
LayerZero DVN support escalation
split-payout distribution primitive, if required beyond campaign close
```
