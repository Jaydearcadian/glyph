#!/usr/bin/env python3
import argparse, hashlib, json, pathlib, re, sys

DOMAIN = "GLYPH_FINAL_RECEIPT_V1"
CARD_VERSION = "glyph.card.svg.v1"

def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()

def final_hash(receipt):
    tmp = {k: v for k, v in receipt.items() if k != "finalReceiptHash"}
    return "0x" + hashlib.sha256(DOMAIN.encode() + canon(tmp)).hexdigest()

def verify(path):
    r = json.loads(pathlib.Path(path).read_text())
    expected = final_hash(r)
    ok = expected == r.get("finalReceiptHash") and r.get("status") in ("RECONCILED", "REFUNDED")
    r["verification"] = {"ok": ok, "expectedFinalReceiptHash": expected, "sourceReceiptHash": r.get("finalReceiptHash")}
    return r, ok

def card(receipt):
    h = receipt["finalReceiptHash"]
    def esc(x): return str(x).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    lines = [
        f"Glyph Receipt {receipt['schemaVersion']} / {CARD_VERSION}",
        f"Type: {receipt['mode']} {receipt['topology']} | Status: {receipt['status']}",
        f"Operation: {receipt['operationId'][:18]}… | Hash: {h[:18]}…",
        f"Purpose: {receipt.get('purpose','self-asserted/private-commitment')}",
        f"Delivered: {receipt['reconciliation'].get('realizedPrincipal','0')} | Fees: {receipt['reconciliation'].get('realizedFees','0')} | Residual/Refund: {receipt['reconciliation'].get('residualReturned', receipt['reconciliation'].get('fullRefund','0'))}",
        f"Source: {receipt.get('source','source-chain')} -> Destination: {receipt.get('destination','destination-chain')}",
        f"Proof: {','.join(receipt.get('proofs', []))}",
        f"sourceReceiptHash={h}"
    ]
    y = 32
    text = []
    for line in lines:
        text.append(f'<text x="28" y="{y}" font-family="monospace" font-size="14" fill="#e8f1ff">{esc(line)}</text>')
        y += 24
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="960" height="260" viewBox="0 0 960 260"><rect width="960" height="260" rx="24" fill="#0b1020"/><rect x="14" y="14" width="932" height="232" rx="18" fill="none" stroke="#6ee7ff" stroke-width="2"/>{"".join(text)}</svg>'

def make_fixture(mode, status="RECONCILED"):
    op = "0x" + hashlib.sha256((mode+status).encode()).hexdigest()
    receipt = {
        "schemaVersion":"glyph.receipt.v1", "operationId":op, "mode":mode, "topology":"CROSS_CHAIN", "status":status,
        "termsHash":"0x"+hashlib.sha256((op+"terms").encode()).hexdigest(),
        "parties":{"payer":"0x0000000000000000000000000000000000001002","recipient":"0x0000000000000000000000000000000000001003"},
        "valueLegs":[{"type":"DESTINATION_DELIVERED","amount":"100000000000000000000"}],
        "feeBreakdown":{"protocol":"1","provider":"2","referrer":"3","gasSponsor":"4"},
        "reconciliation":{"maximumInput":"110000000000000000000","realizedPrincipal":"100000000000000000000","realizedFees":"10000000000000000000","residualReturned":"0"} if status == "RECONCILED" else {"maximumInput":"110000000000000000000","realizedPrincipal":"0","realizedFees":"0","fullRefund":"110000000000000000000"},
        "proofs":["AUTHENTICATED_ADAPTER"], "messageIds":["0x"+hashlib.sha256((op+"msg").encode()).hexdigest()],
        "identityBindings":[], "purpose":"self-asserted/private-commitment", "privacy":{"privateContextHash":"0x"+"11"*32}, "verification":{}
    }
    receipt["finalReceiptHash"] = final_hash(receipt)
    return receipt

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("fixture"); g.add_argument("mode"); g.add_argument("--status", default="RECONCILED"); g.add_argument("--out", required=True)
    v = sub.add_parser("verify"); v.add_argument("path")
    c = sub.add_parser("card"); c.add_argument("path"); c.add_argument("--out", required=True)
    a = ap.parse_args()
    if a.cmd == "fixture":
        r = make_fixture(a.mode, a.status); pathlib.Path(a.out).parent.mkdir(parents=True, exist_ok=True); pathlib.Path(a.out).write_text(json.dumps(r, indent=2, sort_keys=True)+"\n")
    elif a.cmd == "verify":
        r, ok = verify(a.path); print(json.dumps(r["verification"], indent=2, sort_keys=True)); sys.exit(0 if ok else 1)
    elif a.cmd == "card":
        r, ok = verify(a.path)
        if not ok: sys.exit(1)
        svg = card(r); pathlib.Path(a.out).parent.mkdir(parents=True, exist_ok=True); pathlib.Path(a.out).write_text(svg)
        source = re.search(r"sourceReceiptHash=([^<]+)", svg).group(1)
        if source != r["finalReceiptHash"]: sys.exit(1)

if __name__ == "__main__": main()
