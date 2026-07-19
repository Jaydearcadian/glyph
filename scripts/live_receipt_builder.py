#!/usr/bin/env python3
"""Build live Glyph receipt artifacts from committed Monad proof bundles.

This intentionally does not build a frontend and does not touch cross-chain delivery.
It converts existing live proof evidence into canonical receipt JSON, SVG receipt
cards, receipt links, and QR PNGs.
"""
import argparse
import base64
import hashlib
import json
import pathlib
import sys
from typing import Any, Dict, Iterable, List, Optional

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import receipt_tool  # type: ignore

try:
    import qrcode
except Exception as exc:  # pragma: no cover
    qrcode = None

DOMAIN = receipt_tool.DOMAIN
DEFAULT_BASE_URL = "https://glyph.local/app#/glyph/"


def canon(obj: Any) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def b64url(obj: Any) -> str:
    return base64.urlsafe_b64encode(canon(obj)).decode().rstrip("=")


def load_json(path: pathlib.Path) -> Dict[str, Any]:
    return json.loads(path.read_text())


def write_json(path: pathlib.Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, sort_keys=True) + "\n")


def tx_for(evidence: Dict[str, Any], fn: str, occurrence: int = 0) -> str:
    seen = 0
    for tx in evidence.get("transactions", []):
        if tx.get("function") == fn:
            if seen == occurrence:
                return tx["txHash"]
            seen += 1
    raise KeyError(f"missing tx function {fn} occurrence {occurrence}")


def txs_for(evidence: Dict[str, Any], fn: str) -> List[str]:
    return [tx["txHash"] for tx in evidence.get("transactions", []) if tx.get("function") == fn]


def split_facts(raw: str) -> List[str]:
    return [x.strip() for x in raw.strip().splitlines() if x.strip()]


def make_base_receipt(
    *,
    mode: str,
    topology: str,
    operation_id: str,
    terms_hash: str,
    payer: str,
    recipient: str,
    amount: str,
    maximum_input: str,
    realized_fees: str,
    source_asset: str,
    destination_asset: str,
    source_chain_id: int,
    destination_chain_id: int,
    contracts: Dict[str, str],
    tx_hashes: List[str],
    receipt_hash_hint: Optional[str] = None,
    message_ids: Optional[List[str]] = None,
    proofs: Optional[List[str]] = None,
) -> Dict[str, Any]:
    residual = str(int(maximum_input) - int(amount) - int(realized_fees))
    receipt: Dict[str, Any] = {
        "schemaVersion": "glyph.receipt.v1",
        "operationId": operation_id,
        "mode": mode,
        "topology": topology,
        "status": "RECONCILED",
        "termsHash": terms_hash,
        "parties": {"payer": payer, "recipient": recipient},
        "assets": {"sourceAsset": source_asset, "destinationAsset": destination_asset},
        "chains": {"sourceChainId": source_chain_id, "destinationChainId": destination_chain_id},
        "contracts": contracts,
        "valueLegs": [
            {"type": "SOURCE_ESCROWED", "amount": maximum_input, "asset": source_asset},
            {"type": "DESTINATION_DELIVERED", "amount": amount, "asset": destination_asset},
            {"type": "PROVIDER_SETTLED", "amount": amount, "asset": source_asset},
            {"type": "FEE_REALIZED", "amount": realized_fees, "asset": source_asset},
            {"type": "DELTA_RETURNED", "amount": residual, "asset": source_asset},
        ],
        "feeBreakdown": {"realizedFees": realized_fees},
        "reconciliation": {
            "maximumInput": maximum_input,
            "realizedPrincipal": amount,
            "realizedFees": realized_fees,
            "residualReturned": residual,
        },
        "proofs": proofs or ["LOCAL_VERIFIED", "AUTHENTICATED_LOOPBACK"],
        "messageIds": message_ids or [],
        "txHashes": tx_hashes,
        "receiptHashHint": receipt_hash_hint,
        "identityBindings": [],
        "purpose": "self-asserted/private-commitment",
        "privacy": {"privateContextHash": "0x" + "00" * 32},
        "verification": {},
    }
    receipt["finalReceiptHash"] = receipt_tool.final_hash(receipt)
    return receipt


def build_address_pair(bundle: pathlib.Path) -> Dict[str, Dict[str, Any]]:
    e = load_json(bundle / "evidence.json")
    pull_facts = split_facts(e["readbacks"]["pullSourceReceiptFacts"])
    push_facts = split_facts(e["readbacks"]["pushSourceReceiptFacts"])
    contracts = e["contracts"]
    source_chain_id = int(e["chainId"])
    destination_chain_id = int(e["chainId"])
    delivered_txs = txs_for(e, "deliver(bytes32)")
    receipts: Dict[str, Dict[str, Any]] = {}
    receipts["pull"] = make_base_receipt(
        mode="PULL",
        topology="LOCAL",
        operation_id=e["operations"]["pull"],
        terms_hash=pull_facts[0],
        payer=e["payer"],
        recipient=e["claimantRecipient"],
        amount=e["expectedDeltas"]["pullAmount"],
        maximum_input=pull_facts[2].split()[0],
        realized_fees=pull_facts[4].split()[0],
        source_asset=pull_facts[1],
        destination_asset=pull_facts[1],
        source_chain_id=source_chain_id,
        destination_chain_id=destination_chain_id,
        contracts=contracts,
        tx_hashes=[
            tx_for(e, "escrow((bytes32,bytes32,address,address,address,address,uint64,address,address,uint64,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,address,uint64,uint256))", 0),
            tx_for(e, "sendRouteFromEscrow(bytes32,address,uint256)", 0),
            delivered_txs[0],
            delivered_txs[1],
            tx_for(e, "finalizeAndSendReceipt(bytes32,address,uint256)", 0),
            delivered_txs[2],
        ],
        receipt_hash_hint=e["receiptHashes"]["pull"],
        message_ids=[e["receiptHashes"]["pull"]],
    )
    receipts["push"] = make_base_receipt(
        mode="PUSH",
        topology="LOCAL",
        operation_id=e["operations"]["push"],
        terms_hash=push_facts[0],
        payer=e["payer"],
        recipient=e["claimantRecipient"],
        amount=e["expectedDeltas"]["pushAmount"],
        maximum_input=push_facts[2].split()[0],
        realized_fees=push_facts[4].split()[0],
        source_asset=push_facts[1],
        destination_asset=push_facts[1],
        source_chain_id=source_chain_id,
        destination_chain_id=destination_chain_id,
        contracts=contracts,
        tx_hashes=[
            tx_for(e, "escrow((bytes32,bytes32,address,address,address,address,uint64,address,address,uint64,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,address,uint64,uint256))", 1),
            tx_for(e, "sendRouteFromEscrow(bytes32,address,uint256)", 1),
            delivered_txs[3],
            delivered_txs[4],
            tx_for(e, "claimPushAndAck(bytes32,address,bytes32,uint64,bytes,bytes)", 0),
            tx_for(e, "finalizeAndSendReceipt(bytes32,address,uint256)", 1),
            delivered_txs[5],
        ],
        receipt_hash_hint=e["receiptHashes"]["push"],
        message_ids=[e["receiptHashes"]["push"]],
    )
    return receipts


def build_campaign(bundle: pathlib.Path) -> Dict[str, Dict[str, Any]]:
    e = load_json(bundle / "evidence.json")
    children = e["children"]
    child_receipts = [children["A"]["receiptHash"], children["B"]["receiptHash"]]
    total = str(int(children["A"]["amount"]) + int(children["B"]["amount"]))
    receipt: Dict[str, Any] = {
        "schemaVersion": "glyph.receipt.v1",
        "operationId": e["programId"],
        "mode": "CONTRIBUTION",
        "topology": "LOCAL",
        "status": "RECONCILED",
        "termsHash": e["programId"],
        "parties": {"payer": "MULTIPLE_CONTRIBUTORS", "recipient": e["ownerRecipient"]},
        "contributors": e["contributors"],
        "contracts": e["contracts"],
        "valueLegs": [
            {"type": "CONTRIBUTION_CHILD", "operationId": children["A"]["operationId"], "amount": children["A"]["amount"], "receiptHash": children["A"]["receiptHash"]},
            {"type": "CONTRIBUTION_CHILD", "operationId": children["B"]["operationId"], "amount": children["B"]["amount"], "receiptHash": children["B"]["receiptHash"]},
            {"type": "CAMPAIGN_CLOSED", "amount": total, "receiptHash": e["aggregateReceiptHash"]},
        ],
        "feeBreakdown": {"campaignFees": "0"},
        "reconciliation": {
            "maximumInput": total,
            "realizedPrincipal": total,
            "realizedFees": "0",
            "residualReturned": "0",
            "reconciledTotal": total,
            "closed": True,
        },
        "proofs": ["LOCAL_VERIFIED", "CAMPAIGN_AGGREGATE"],
        "messageIds": child_receipts,
        "txHashes": [
            tx_for(e, "create(bytes32,(address,address,uint256,uint256,uint256,uint256,uint64,uint8,uint256,bool))", 0),
            tx_for(e, "reconcileChild(bytes32,bytes32,uint256,bytes32)", 0),
            tx_for(e, "reconcileChild(bytes32,bytes32,uint256,bytes32)", 1),
            tx_for(e, "close(bytes32)", 0),
        ],
        "receiptHashHint": e["aggregateReceiptHash"],
        "identityBindings": [],
        "purpose": "campaign-contribution/private-commitment",
        "privacy": {"privateContextHash": "0x" + "00" * 32},
        "verification": {},
    }
    receipt["finalReceiptHash"] = receipt_tool.final_hash(receipt)
    return {"campaign": receipt}


def make_receipt_link(receipt: Dict[str, Any], path: str, base_url: str) -> Dict[str, Any]:
    payload = {
        "schemaVersion": "glyph.link.v1",
        "kind": "RECEIPT",
        "topology": receipt["topology"],
        "operationId": receipt["operationId"],
        "receipt": {
            "path": path,
            "schemaVersion": receipt["schemaVersion"],
            "mode": receipt["mode"],
            "status": receipt["status"],
            "topology": receipt["topology"],
            "finalReceiptHash": receipt["finalReceiptHash"],
            "termsHash": receipt["termsHash"],
        },
    }
    return {
        "link": base_url + b64url(payload),
        "payload": payload,
        "publicIndex": {
            "schemaVersion": "glyph.link.v1",
            "kind": "RECEIPT",
            "topology": receipt["topology"],
            "operationId": receipt["operationId"],
            "status": receipt["status"],
            "finalReceiptHash": receipt["finalReceiptHash"],
        },
    }


def write_card(receipt: Dict[str, Any], path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    r, ok = receipt_tool.verify(path.with_suffix(".json")) if path.with_suffix(".json").exists() else (None, False)
    # Generate directly from the in-memory receipt; verification happens after write.
    path.write_text(receipt_tool.card(receipt))


def write_qr(link: str, path: pathlib.Path) -> None:
    if qrcode is None:
        raise RuntimeError("qrcode module unavailable")
    path.parent.mkdir(parents=True, exist_ok=True)
    img = qrcode.make(link)
    img.save(path)


def verify_receipt_file(path: pathlib.Path) -> None:
    _, ok = receipt_tool.verify(path)
    if not ok:
        raise RuntimeError(f"receipt verification failed: {path}")


def build_all(base_url: str) -> List[pathlib.Path]:
    outputs: List[pathlib.Path] = []
    jobs = [
        (ROOT / "state/live/monad-address-pair-proof-20260719T130942Z", build_address_pair),
        (ROOT / "state/live/monad-campaign-proof-20260719T132755Z", build_campaign),
    ]
    for bundle, builder in jobs:
        receipts = builder(bundle)
        for name, receipt in receipts.items():
            rel_receipt = f"{bundle.relative_to(ROOT)}/{name}.live.receipt.json"
            receipt_path = ROOT / rel_receipt
            card_path = bundle / f"{name}.live.receipt.card.svg"
            link_path = bundle / f"{name}.live.receipt.link.json"
            qr_path = bundle / f"{name}.live.receipt.qr.png"
            write_json(receipt_path, receipt)
            verify_receipt_file(receipt_path)
            card_path.write_text(receipt_tool.card(receipt))
            link = make_receipt_link(receipt, rel_receipt, base_url)
            write_json(link_path, link)
            write_qr(link["link"], qr_path)
            outputs.extend([receipt_path, card_path, link_path, qr_path])
    return outputs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    args = ap.parse_args()
    outputs = build_all(args.base_url)
    for p in outputs:
        print(p.relative_to(ROOT))


if __name__ == "__main__":
    main()
