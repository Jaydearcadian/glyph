#!/usr/bin/env python3
"""Generate ambitious pre-frontend backend readiness package for Glyph.

No frontend app files are created. This only writes root docs, state/frontend/*,
and scripts that validate/read backend surfaces.
"""
from __future__ import annotations

import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "state" / "frontend"
ADDR_PAIR = ROOT / "state/live/monad-address-pair-proof-20260719T130942Z"
CAMPAIGN = ROOT / "state/live/monad-campaign-proof-20260719T132755Z"
XCHAIN = ROOT / "state/live/base-monad-crosschain-blocker-20260719T165200Z"


def load(path: Path) -> Any:
    return json.loads(path.read_text())


def write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def abi_export() -> Dict[str, str]:
    abi_map = {
        "SourceDeltaRouter": ROOT / "contracts/out/SourceDeltaRouter.sol/SourceDeltaRouter.json",
        "DestinationGlyphVault": ROOT / "contracts/out/DestinationGlyphVault.sol/DestinationGlyphVault.json",
        "GlyphLayerZeroApplication": ROOT / "contracts/out/GlyphLayerZeroApplication.sol/GlyphLayerZeroApplication.json",
        "ContributionCampaign": ROOT / "contracts/out/ContributionCampaign.sol/ContributionCampaign.json",
        "GlyphReceiptLedger": ROOT / "contracts/out/GlyphReceiptLedger.sol/GlyphReceiptLedger.json",
        "GlyphAttestationRegistry": ROOT / "contracts/out/GlyphAttestationRegistry.sol/GlyphAttestationRegistry.json",
        "TestToken": ROOT / "contracts/out/TestToken.sol/TestToken.json",
    }
    paths: Dict[str, str] = {}
    for name, src in abi_map.items():
        artifact = load(src)
        obj = {
            "contractName": name,
            "sourceArtifact": rel(src),
            "abi": artifact["abi"],
            "bytecodeHash": hashlib.sha256((artifact.get("bytecode", {}).get("object") or "").encode()).hexdigest(),
        }
        dest = OUT / "abi" / f"{name}.json"
        write_json(dest, obj)
        paths[name] = rel(dest)
    return paths


def tx_url(chain_id: int, tx_hash: str) -> str:
    if chain_id == 10143:
        return f"https://testnet.monadexplorer.com/tx/{tx_hash}"
    if chain_id == 84532:
        return f"https://sepolia.basescan.org/tx/{tx_hash}"
    return tx_hash


def addr_url(chain_id: int, addr: str) -> str:
    if chain_id == 10143:
        return f"https://testnet.monadexplorer.com/address/{addr}"
    if chain_id == 84532:
        return f"https://sepolia.basescan.org/address/{addr}"
    return addr


def build_transactions_index(addr: Dict[str, Any], camp: Dict[str, Any], x: Dict[str, Any]) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []
    for flow, chain_id, bundle, ev in [
        ("monad-address-pair", 10143, ADDR_PAIR, addr),
        ("monad-campaign", 10143, CAMPAIGN, camp),
    ]:
        for tx in ev.get("transactions", []):
            txh = tx.get("txHash")
            items.append({
                "flow": flow,
                "chainId": chain_id,
                "bundle": rel(bundle),
                "index": tx.get("index"),
                "type": tx.get("type"),
                "contract": tx.get("contract"),
                "toOrCreated": tx.get("to_or_created"),
                "function": tx.get("function"),
                "txHash": txh,
                "status": tx.get("status"),
                "explorerUrl": tx_url(chain_id, txh) if txh else None,
            })
    for label, file in [("base-escrow", XCHAIN / "fresh-escrow.json"), ("base-route", XCHAIN / "fresh-route.json")]:
        if file.exists():
            obj = load(file)
            # tolerate variable forge broadcast JSON shapes
            txs = obj.get("transactions") if isinstance(obj, dict) else None
            if not txs and isinstance(obj, dict):
                txs = [obj]
            for i, tx in enumerate(txs or []):
                txh = tx.get("transactionHash") or tx.get("txHash") or tx.get("hash")
                if txh:
                    items.append({
                        "flow": f"crosschain-{label}",
                        "chainId": 84532,
                        "bundle": rel(XCHAIN),
                        "index": i,
                        "type": tx.get("transactionType") or tx.get("type"),
                        "contract": tx.get("contractName") or tx.get("contract"),
                        "toOrCreated": tx.get("contractAddress") or tx.get("to") or tx.get("to_or_created"),
                        "function": tx.get("function") or label,
                        "txHash": txh,
                        "status": tx.get("status") or "recorded",
                        "explorerUrl": tx_url(84532, txh),
                    })
    return {"schema": "glyph.frontend.transactions.v1", "generatedAt": now(), "transactions": items}


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_receipt_index() -> Dict[str, Any]:
    receipts = []
    for bundle, name, title in [
        (ADDR_PAIR, "pull", "Monad Pull receipt"),
        (ADDR_PAIR, "push", "Monad Push receipt"),
        (CAMPAIGN, "campaign", "Monad campaign aggregate receipt"),
    ]:
        rpath = bundle / f"{name}.live.receipt.json"
        receipt = load(rpath)
        receipts.append({
            "label": title,
            "mode": receipt["mode"],
            "topology": receipt["topology"],
            "status": receipt["status"],
            "operationId": receipt["operationId"],
            "termsHash": receipt["termsHash"],
            "finalReceiptHash": receipt["finalReceiptHash"],
            "receiptHashHint": receipt.get("receiptHashHint"),
            "jsonPath": rel(rpath),
            "cardPath": rel(bundle / f"{name}.live.receipt.card.svg"),
            "linkPath": rel(bundle / f"{name}.live.receipt.link.json"),
            "qrPath": rel(bundle / f"{name}.live.receipt.qr.png"),
        })
    return {"schema": "glyph.frontend.receipts.v1", "generatedAt": now(), "receipts": receipts}


def build_proof_index(addr: Dict[str, Any], camp: Dict[str, Any], x: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "schema": "glyph.frontend.proofs.v1",
        "generatedAt": now(),
        "proofs": [
            {
                "id": "monad-address-pair",
                "title": "Monad Pull + Push address-pair proof",
                "status": "live-proven",
                "chainId": addr["chainId"],
                "bundlePath": rel(ADDR_PAIR),
                "evidencePath": rel(ADDR_PAIR / "evidence.json"),
                "readmePath": rel(ADDR_PAIR / "README.md"),
                "operations": addr["operations"],
                "receiptHashes": addr["receiptHashes"],
            },
            {
                "id": "monad-campaign",
                "title": "Monad two-contributor campaign aggregation proof",
                "status": "live-proven",
                "chainId": camp["chainId"],
                "bundlePath": rel(CAMPAIGN),
                "evidencePath": rel(CAMPAIGN / "evidence.json"),
                "readmePath": rel(CAMPAIGN / "README.md"),
                "programId": camp["programId"],
                "children": camp["children"],
                "aggregateReceiptHash": camp["aggregateReceiptHash"],
            },
            {
                "id": "base-monad-crosschain",
                "title": "Base Sepolia to Monad LayerZero source-send proof",
                "status": "source-send-proven-destination-blocked",
                "sourceChainId": 84532,
                "destinationChainId": 10143,
                "bundlePath": rel(XCHAIN),
                "evidencePath": rel(XCHAIN / "evidence.json"),
                "readmePath": rel(XCHAIN / "README.md"),
                "freshOperationId": x["freshAttempt"]["operationId"],
                "freshGuid": x["freshAttempt"]["guid"],
                "blocker": x["conclusion"],
            },
        ],
    }


def build_crosschain_timeline(x: Dict[str, Any]) -> Dict[str, Any]:
    fr = x["freshReadbacks"]
    return {
        "schema": "glyph.frontend.crosschainTimeline.v1",
        "generatedAt": now(),
        "title": "Base Sepolia → Monad Testnet LayerZero proof timeline",
        "sourceChainId": 84532,
        "destinationChainId": 10143,
        "freshOperationId": x["freshAttempt"]["operationId"],
        "freshGuid": x["freshAttempt"]["guid"],
        "uiStatus": "source-send-proven-destination-blocked",
        "safeCopy": "Base source-send and LayerZero packet visibility are proven. Monad-side lzReceive/final settlement is not claimed complete because LayerZero DVN validation remains WAITING.",
        "stages": [
            {"stage": "Base contracts deployed/configured", "status": "success", "evidence": rel(XCHAIN / "base-deploy.json")},
            {"stage": "Monad contracts deployed/configured", "status": "success", "evidence": rel(XCHAIN / "monad-deploy.json")},
            {"stage": "Base escrow", "status": "success", "evidence": rel(XCHAIN / "fresh-escrow.json")},
            {"stage": "Base route send", "status": "success", "evidence": rel(XCHAIN / "fresh-route.json")},
            {"stage": "LayerZero packet", "status": x["freshAttempt"]["layerZeroStatus"]["name"], "guid": x["freshAttempt"]["guid"], "evidence": rel(XCHAIN / "layerzero-fresh-guid.json")},
            {"stage": "DVN verification", "status": x["freshAttempt"]["verification"]["dvn"]["status"], "details": x["freshAttempt"]["verification"]["dvn"]},
            {"stage": "Monad lzReceive", "status": "not_delivered", "readback": fr.get("monadMessageStatus")},
            {"stage": "Source ACK/finalization", "status": "not_complete", "readback": fr.get("baseAckDelivered")},
        ],
        "readbacks": fr,
    }


def write_ts_configs(addr: Dict[str, Any], camp: Dict[str, Any], x: Dict[str, Any]) -> None:
    contracts_ts = f'''// Auto-generated by scripts/generate_frontend_readiness_package.py.
// Frontend may copy this file; this repo intentionally does not create a frontend app.

export const glyphContracts = {{
  monadCore: {{
    router: "{addr['contracts']['router']}",
    token: "{addr['contracts']['token']}",
    vault: "{addr['contracts']['vault']}",
    adapter: "{addr['contracts']['adapter']}",
    sourceApp: "{addr['contracts']['sourceApp']}",
    destinationApp: "{addr['contracts']['destinationApp']}",
  }},
  monadCampaign: {{
    router: "{camp['contracts']['router']}",
    token: "{camp['contracts']['token']}",
    vault: "{camp['contracts']['vault']}",
    adapter: "{camp['contracts']['adapter']}",
    sourceApp: "{camp['contracts']['sourceApp']}",
    destinationApp: "{camp['contracts']['destinationApp']}",
    campaign: "{camp['contracts']['campaign']}",
  }},
  crosschainFreshLane: {{
    baseRouter: "{x['freshLane']['baseRouter']}",
    baseVault: "{x['freshLane']['baseVault']}",
    baseToken: "{x['freshLane']['baseToken']}",
    baseApp: "{x['freshLane']['baseApp']}",
    baseAdapter: "{x['freshLane']['baseAdapter']}",
    monadRouter: "{x['freshLane']['monadRouter']}",
    monadVault: "{x['freshLane']['monadVault']}",
    monadToken: "{x['freshLane']['monadToken']}",
    monadApp: "{x['freshLane']['monadApp']}",
    monadAdapter: "{x['freshLane']['monadAdapter']}",
  }},
}} as const;
'''
    chains_ts = '''// Auto-generated by scripts/generate_frontend_readiness_package.py.

export const monadTestnet = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet-rpc.monad.xyz"] } },
  blockExplorers: {
    default: { name: "Monad Testnet Explorer", url: "https://testnet.monadexplorer.com" },
  },
  testnet: true,
} as const;

export const baseSepolia = {
  id: 84532,
  name: "Base Sepolia",
  nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://sepolia.base.org"] } },
  blockExplorers: { default: { name: "BaseScan", url: "https://sepolia.basescan.org" } },
  testnet: true,
} as const;
'''
    write_text(OUT / "contracts" / "glyphContracts.ts", contracts_ts)
    write_text(OUT / "contracts" / "glyphChains.ts", chains_ts)


def flow(kind: str, title: str, mode: str, stages: List[Dict[str, Any]], disabled: List[str] | None = None) -> Dict[str, Any]:
    return {
        "schema": "glyph.frontend.flow.v1",
        "id": kind,
        "title": title,
        "mode": mode,
        "transactionFirst": mode in {"live-write", "hybrid"},
        "frontendInstruction": "Render only steps whose required actor/authority is available; never show fake success for unavailable provider/system steps.",
        "stages": stages,
        "disabledOrProofOnly": disabled or [],
    }


def write_flows(addr: Dict[str, Any], camp: Dict[str, Any], x: Dict[str, Any]) -> None:
    write_json(OUT / "flows" / "pull.flow.json", flow("pull", "Pull payment link lifecycle", "hybrid", [
        {"step": 1, "name": "Connect wallet", "actor": "payer", "frontendCanExecute": True},
        {"step": 2, "name": "Switch/add Monad Testnet", "actor": "payer", "frontendCanExecute": True, "chainId": 10143},
        {"step": 3, "name": "Read token balance/allowance", "read": ["TestToken.balanceOf", "TestToken.allowance"], "frontendCanExecute": True},
        {"step": 4, "name": "Approve router", "write": "TestToken.approve(router, maximumInput)", "frontendCanExecute": True},
        {"step": 5, "name": "Escrow Pull terms", "write": "SourceDeltaRouter.escrow(terms)", "frontendCanExecute": True},
        {"step": 6, "name": "Route from escrow", "write": "GlyphLayerZeroApplication.sendRouteFromEscrow(op, provider, gasLimit)", "frontendCanExecute": False, "requiredAuthority": "provider/app operator", "proofAvailable": True},
        {"step": 7, "name": "Loopback delivery/finalize", "write": "LocalLoopbackGlyphAdapter.deliver + GlyphLayerZeroApplication.finalizeAndSendReceipt", "frontendCanExecute": False, "requiredAuthority": "demo/provider operator", "proofAvailable": True},
        {"step": 8, "name": "Render receipt", "artifact": rel(ADDR_PAIR / "pull.live.receipt.json"), "frontendCanExecute": True},
    ], ["Do not label provider/operator loopback steps as user-clickable unless a tested user-safe route exists."]))

    write_json(OUT / "flows" / "push.flow.json", flow("push", "Push claim link lifecycle", "hybrid", [
        {"step": 1, "name": "Payer connects and approves", "write": "TestToken.approve(router, maximumInput)", "frontendCanExecute": True},
        {"step": 2, "name": "Payer escrows Push terms", "write": "SourceDeltaRouter.escrow(terms)", "frontendCanExecute": True},
        {"step": 3, "name": "Generate fragment-only claim link", "schema": rel(ROOT / "state/schemas/link.schema.json"), "frontendCanExecute": True, "secretRule": "fragment-only; never persist private claim secret"},
        {"step": 4, "name": "Reserve/route via provider", "write": "sendRouteFromEscrow + deliver", "frontendCanExecute": False, "requiredAuthority": "provider/app operator", "proofAvailable": True},
        {"step": 5, "name": "Claimant claims Push", "write": "GlyphLayerZeroApplication.claimPushAndAck", "frontendCanExecute": "only after claim-secret/signature helper is implemented and tested"},
        {"step": 6, "name": "Finalize and render receipt", "artifact": rel(ADDR_PAIR / "push.live.receipt.json"), "frontendCanExecute": True},
    ], ["Do not store claim secrets in public JSON, logs, query strings, or onchain metadata."]))

    write_json(OUT / "flows" / "campaign.flow.json", flow("campaign", "Multi-party campaign contribution aggregation", "hybrid", [
        {"step": 1, "name": "Create campaign", "write": "ContributionCampaign.create(programId, Campaign)", "frontendCanExecute": True},
        {"step": 2, "name": "Contributor child Pull A", "flowRef": "pull", "frontendCanExecute": True},
        {"step": 3, "name": "Contributor child Pull B", "flowRef": "pull", "frontendCanExecute": True},
        {"step": 4, "name": "Reconcile children", "write": "ContributionCampaign.reconcileChild(programId, childOp, amount, receiptHash)", "frontendCanExecute": False, "requiredAuthority": "campaign/operator reconciliation", "proofAvailable": True},
        {"step": 5, "name": "Close campaign", "write": "ContributionCampaign.close(programId)", "frontendCanExecute": "yes if close preconditions visible", "proofAvailable": True},
        {"step": 6, "name": "Render aggregate receipt", "artifact": rel(CAMPAIGN / "campaign.live.receipt.json"), "frontendCanExecute": True},
    ], ["Split-payout/multi-recipient distribution is not built in this package."]))

    write_json(OUT / "flows" / "receipt.flow.json", flow("receipt", "Receipt viewer and verifier", "live-read", [
        {"step": 1, "name": "Load receipt JSON", "source": rel(OUT / "receipts" / "index.json"), "frontendCanExecute": True},
        {"step": 2, "name": "Verify finalReceiptHash locally", "algorithm": "sha256 canonical JSON with finalReceiptHash omitted; see scripts/receipt_tool.py", "frontendCanExecute": True},
        {"step": 3, "name": "Render SVG card/QR/link", "frontendCanExecute": True},
        {"step": 4, "name": "Read onchain sourceReceiptFacts for Pull/Push", "read": "SourceDeltaRouter.sourceReceiptFacts(operationId)", "frontendCanExecute": True},
        {"step": 5, "name": "Show tx timeline", "source": rel(OUT / "transactions" / "index.json"), "frontendCanExecute": True},
    ]))

    write_json(OUT / "flows" / "crosschain-proof.flow.json", flow("crosschain-proof", "Base Sepolia → Monad proof panel", "proof-only", [
        {"step": 1, "name": "Show Base deployment/config", "status": "success"},
        {"step": 2, "name": "Show Base escrow", "status": "success", "evidence": rel(XCHAIN / "fresh-escrow.json")},
        {"step": 3, "name": "Show Base route send", "status": "success", "evidence": rel(XCHAIN / "fresh-route.json")},
        {"step": 4, "name": "Show LayerZero GUID", "status": x["freshAttempt"]["layerZeroStatus"]["name"], "guid": x["freshAttempt"]["guid"]},
        {"step": 5, "name": "Show DVN blocker", "status": x["freshAttempt"]["verification"]["dvn"]["status"]},
        {"step": 6, "name": "Show Monad delivery not complete", "status": "not_delivered"},
    ], ["Do not claim Base→Monad destination settlement, ACK, or finalization is complete."]))


def docs(addr: Dict[str, Any], camp: Dict[str, Any], x: Dict[str, Any], abi_paths: Dict[str, str]) -> None:
    write_text(ROOT / "FRONTEND_MANIFEST.md", f"""# Glyph frontend integration manifest

Generated: `{now()}`

Scope: ambitious pre-frontend backend readiness package. This repository still does **not** contain or modify a frontend app.

## Product position

Glyph is link-native payment infrastructure on Monad: Push/Pull payment links, campaign contribution aggregation, QR/shareable receipts, and transparent cross-chain proof evidence.

## Hard boundaries

```text
No frontend app is created here.
No Base→Monad destination delivery/final settlement is claimed.
No payout splitter / pro-rata distribution primitive is included.
No indexer is included.
No private-key backend signing is included.
No fake success-button flows are permitted.
```

## Canonical frontend package

| Surface | Path |
|---|---|
| Frontend machine manifest | `state/frontend/frontend.manifest.json` |
| Monad chain config | `state/frontend/chains/monad-testnet.json` |
| Contract addresses | `state/frontend/addresses/monad-testnet.json` |
| TypeScript contract constants | `state/frontend/contracts/glyphContracts.ts` |
| TypeScript chain constants | `state/frontend/contracts/glyphChains.ts` |
| ABI exports | `state/frontend/abi/` |
| Contract method map | `state/frontend/CONTRACT_METHODS.md` |
| Flow specs | `state/frontend/flows/` |
| Receipt index | `state/frontend/receipts/index.json` |
| Proof index | `state/frontend/proofs/index.json` |
| Transaction index | `state/frontend/transactions/index.json` |
| Cross-chain timeline | `state/frontend/crosschain/base-monad.timeline.json` |
| Cross-chain UI copy | `state/frontend/crosschain/CROSSCHAIN_UI_COPY.md` |
| LayerZero support packet | `state/frontend/crosschain/layerzero-support-packet.md` |
| Readback script | `scripts/frontend_readback.py` |
| Readiness validator | `scripts/validate_frontend_readiness.py` |

## Canonical Monad core stack

```json
{json.dumps(addr['contracts'], indent=2)}
```

## Campaign stack

```json
{json.dumps(camp['contracts'], indent=2)}
```

## Cross-chain fresh lane

```json
{json.dumps(x['freshLane'], indent=2)}
```

## Required frontend UX stance

- Show Pull, Push, campaign, receipt, and cross-chain panels.
- Treat user-safe wallet writes separately from provider/operator lifecycle steps.
- Render proof-backed steps as evidence, not fake click success.
- Render cross-chain as source-send proven + LayerZero/DVN blocked, not settled.
- Keep private claim secrets fragment-only.

## Validation

Run:

```bash
python3 scripts/validate_frontend_readiness.py
```

Optional live RPC readbacks:

```bash
python3 scripts/frontend_readback.py --live-rpc
python3 scripts/validate_frontend_readiness.py --live-rpc
```
""")

    write_text(OUT / "CONTRACT_METHODS.md", """# Glyph contract method map for frontend

## General frontend rules

- User wallet actions may prepare/sign/broadcast only the user's own transactions.
- Provider/operator lifecycle actions must be labeled as proof-backed/operator actions unless a user-safe path is tested.
- Never render hardcoded success after a write; wait for receipt and readback.

## ERC20 / TestToken

Reads:

```text
symbol()
decimals()
balanceOf(address)
allowance(owner, spender)
```

Writes:

```text
approve(spender, amount)
```

## SourceDeltaRouter

Reads:

```text
actorNonce(address)
operationId(Terms)
hashTerms(Terms)
routeFacts(bytes32 op)
payoutFacts(bytes32 op)
sourceReceiptFacts(bytes32 op)
operations(bytes32 op)
```

Writes:

```text
escrow(Terms)
escrowWithSignature(Terms, deadline, sig)
finalize(bytes32 op)
refund(bytes32 op)
```

Frontend status:

```text
approve + escrow can be transaction-first user wallet actions.
route/finalize/refund must be exposed only when preconditions and authority are clear.
```

## GlyphLayerZeroApplication

Reads/config:

```text
adapter()
remoteApplication(...)
owner()
```

Writes used in live proofs:

```text
sendRouteFromEscrow(bytes32 op, address payable provider, uint256 gasLimit)
claimPushAndAck(...)
finalizeAndSendReceipt(bytes32 op, address payable provider, uint256 gasLimit)
```

Frontend status:

```text
Proof-backed now; user-facing buttons only after exact authority and preconditions are tested in browser wallet flow.
```

## DestinationGlyphVault

Reads/writes used by proof flow:

```text
provideLiquidity(address token, uint256 amount)
reservePull / reservePush / deliverPull / claimPush / release depending ABI path
```

Frontend status:

```text
Mostly provider/liquidity actions; expose as proof/state unless user is explicitly acting as provider.
```

## ContributionCampaign

Reads:

```text
campaigns(bytes32 programId)
childAmounts / childReceipts as ABI exposes
```

Writes:

```text
create(bytes32 programId, Campaign)
reconcileChild(bytes32 programId, bytes32 childOp, uint256 amount, bytes32 receiptHash)
close(bytes32 programId)
```

Frontend status:

```text
create/close may be user-facing if preconditions are visible; reconcileChild is operator/proof-backed unless a safe authority model is added.
```

## Receipt artifacts

Receipt JSON/card/link/QR artifacts are already generated under live proof bundles and indexed at:

```text
state/frontend/receipts/index.json
```

## Cross-chain

Cross-chain is proof-only for this submission:

```text
Base escrow/send: success
LayerZero GUID: visible/inflight
DVN: WAITING
Monad lzReceive/ACK/finalize: not complete
```
""")

    write_text(OUT / "crosschain" / "CROSSCHAIN_UI_COPY.md", f"""# Cross-chain UI copy

Use this exact stance in the frontend.

## Short label

```text
Base→Monad: source-send proven, destination blocked at LayerZero DVN
```

## Expanded copy

Glyph includes a transparent Base Sepolia → Monad Testnet proof lane. The Base-side escrow and route-send transactions succeeded, the LayerZero packet/GUID is recorded, and both Base/Monad app configs were frozen/readback-good. The packet has not reached Monad `lzReceive`; DVN validation remains `WAITING`, so destination delivery, ACK, and final settlement are **not claimed complete**.

## Do not say

```text
Base→Monad settled
cross-chain complete
destination delivered
ACK finalized
```

## Evidence

```text
{rel(XCHAIN / 'evidence.json')}
{rel(XCHAIN / 'fresh-escrow.json')}
{rel(XCHAIN / 'fresh-route.json')}
{rel(XCHAIN / 'layerzero-fresh-guid.json')}
```
""")

    write_text(OUT / "crosschain" / "layerzero-support-packet.md", f"""# LayerZero support packet — Base Sepolia → Monad Testnet

## Summary

Fresh Base Sepolia → Monad Testnet route-send proof remains externally blocked at LayerZero DVN validation.

## Fresh attempt

| Field | Value |
|---|---|
| Source chain | Base Sepolia `84532` |
| Destination chain | Monad Testnet `10143` |
| Operation ID | `{x['freshAttempt']['operationId']}` |
| LayerZero GUID | `{x['freshAttempt']['guid']}` |
| LayerZero status | `{x['freshAttempt']['layerZeroStatus']['name']}` |
| DVN status | `{x['freshAttempt']['verification']['dvn']['status']}` |
| Destination status | `{x['freshAttempt']['destination']['status']}` |

## Fresh lane contracts

```json
{json.dumps(x['freshLane'], indent=2)}
```

## Readback highlights

```json
{json.dumps(x['freshReadbacks'], indent=2)}
```

## Conclusion

{x['conclusion']}

## Evidence files

```text
{rel(XCHAIN / 'evidence.json')}
{rel(XCHAIN / 'fresh-escrow.json')}
{rel(XCHAIN / 'fresh-route.json')}
{rel(XCHAIN / 'layerzero-fresh-guid.json')}
```
""")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    addr = load(ADDR_PAIR / "evidence.json")
    camp = load(CAMPAIGN / "evidence.json")
    x = load(XCHAIN / "evidence.json")
    abi_paths = abi_export()

    chain = {
        "schema": "glyph.frontend.chain.v1",
        "name": "Monad Testnet",
        "chainId": 10143,
        "rpcUrl": "https://testnet-rpc.monad.xyz",
        "explorer": {"name": "Monad Testnet Explorer", "txUrlPrefix": "https://testnet.monadexplorer.com/tx/", "addressUrlPrefix": "https://testnet.monadexplorer.com/address/"},
        "nativeCurrency": {"name": "MON", "symbol": "MON", "decimals": 18},
    }
    write_json(OUT / "chains" / "monad-testnet.json", chain)
    write_json(OUT / "chains" / "base-sepolia.json", {"schema": "glyph.frontend.chain.v1", "name": "Base Sepolia", "chainId": 84532, "rpcUrl": "https://sepolia.base.org", "explorer": {"name": "BaseScan", "txUrlPrefix": "https://sepolia.basescan.org/tx/", "addressUrlPrefix": "https://sepolia.basescan.org/address/"}, "nativeCurrency": {"name": "ETH", "symbol": "ETH", "decimals": 18}})

    addresses = {
        "schema": "glyph.frontend.addresses.v1",
        "generatedAt": now(),
        "canonicalMode": "reuse-live-proof-stacks-no-redeploy",
        "monadCore": addr["contracts"],
        "monadCampaign": camp["contracts"],
        "crosschainFreshLane": x["freshLane"],
    }
    write_json(OUT / "addresses" / "monad-testnet.json", addresses)
    write_json(OUT / "monad-testnet.deployment.json", {"schema": "glyph.frontend.deployment.v1", "generatedAt": now(), "chain": chain, "contracts": addresses, "features": {"pull": True, "push": True, "campaign": True, "receipts": True, "receiptLinks": True, "receiptQr": True, "crossChainSourceSend": True, "crossChainDestinationDelivery": False, "payoutSplitter": False, "indexer": False}})

    write_ts_configs(addr, camp, x)
    write_flows(addr, camp, x)
    write_json(OUT / "receipts" / "index.json", build_receipt_index())
    write_json(OUT / "proofs" / "index.json", build_proof_index(addr, camp, x))
    write_json(OUT / "transactions" / "index.json", build_transactions_index(addr, camp, x))
    write_json(OUT / "crosschain" / "base-monad.timeline.json", build_crosschain_timeline(x))

    manifest = {
        "schema": "glyph.frontend.manifest.v1",
        "generatedAt": now(),
        "scope": "pre-frontend backend readiness; no frontend app files",
        "doNots": [
            "do not fix Base→Monad / LayerZero delivery in this package",
            "do not add generalized Merkle pro-rata or payout splitter in this package",
            "do not build an indexer in this package",
            "do not add private-key backend signing",
            "do not expose fake success-button flows",
        ],
        "paths": {
            "chains": [rel(OUT / "chains" / "monad-testnet.json"), rel(OUT / "chains" / "base-sepolia.json")],
            "addresses": rel(OUT / "addresses" / "monad-testnet.json"),
            "deployment": rel(OUT / "monad-testnet.deployment.json"),
            "contractsTs": rel(OUT / "contracts" / "glyphContracts.ts"),
            "chainsTs": rel(OUT / "contracts" / "glyphChains.ts"),
            "abis": abi_paths,
            "flows": [rel(p) for p in sorted((OUT / "flows").glob("*.flow.json"))],
            "receiptsIndex": rel(OUT / "receipts" / "index.json"),
            "proofsIndex": rel(OUT / "proofs" / "index.json"),
            "transactionsIndex": rel(OUT / "transactions" / "index.json"),
            "crosschainTimeline": rel(OUT / "crosschain" / "base-monad.timeline.json"),
            "crosschainCopy": rel(OUT / "crosschain" / "CROSSCHAIN_UI_COPY.md"),
            "layerzeroSupportPacket": rel(OUT / "crosschain" / "layerzero-support-packet.md"),
            "contractMethods": rel(OUT / "CONTRACT_METHODS.md"),
            "linkSchema": "state/schemas/link.schema.json",
            "receiptSchema": "state/schemas/receipt.schema.json",
        },
        "features": {"pull": "hybrid transaction/proof", "push": "hybrid transaction/proof", "campaign": "hybrid transaction/proof", "receipts": "live artifact + readback", "crosschain": "proof-only blocker panel"},
    }
    write_json(OUT / "frontend.manifest.json", manifest)
    docs(addr, camp, x, abi_paths)

    files = [p for p in OUT.rglob("*") if p.is_file()] + [ROOT / "FRONTEND_MANIFEST.md"]
    write_json(OUT / "package.sha256.json", {"schema": "glyph.frontend.packageHashes.v1", "generatedAt": now(), "files": [{"path": rel(p), "sha256": sha256_file(p)} for p in sorted(files)]})
    print(f"generated {len(files)} frontend readiness files under {rel(OUT)}")


if __name__ == "__main__":
    main()
