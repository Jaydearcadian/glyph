#!/usr/bin/env python3
"""Validate Glyph frontend readiness package.

No private keys, no signing, no broadcasts. --live-rpc only uses public eth_call/code.
"""
from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

try:
    import jsonschema
except Exception as exc:  # pragma: no cover
    raise SystemExit(f"jsonschema unavailable: {exc}")

ROOT = Path(__file__).resolve().parents[1]
RPC = "https://testnet-rpc.monad.xyz"


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load(path: Path) -> Any:
    return json.loads(path.read_text())


def ok_msg(checks: List[Dict[str, Any]], name: str, ok: bool, detail: str = "") -> None:
    checks.append({"name": name, "ok": ok, "detail": detail})


def require(path: Path, checks: List[Dict[str, Any]]) -> bool:
    exists = path.exists()
    ok_msg(checks, f"path exists: {path.relative_to(ROOT)}", exists)
    return exists


def abi_functions(path: Path) -> set[str]:
    obj = load(path)
    return {item.get("name") for item in obj.get("abi", []) if item.get("type") == "function" and item.get("name")}


def run(cmd: List[str]) -> Tuple[bool, str, str]:
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=30)
    return p.returncode == 0, p.stdout.strip(), p.stderr.strip()


def validate_receipt(path: Path) -> Tuple[bool, str]:
    ok, out, err = run(["python3", "scripts/receipt_tool.py", "verify", str(path)])
    return ok, out or err


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live-rpc", action="store_true")
    args = ap.parse_args()
    checks: List[Dict[str, Any]] = []

    mandatory = [
        ROOT / "FRONTEND_MANIFEST.md",
        ROOT / "state/frontend/frontend.manifest.json",
        ROOT / "state/frontend/monad-testnet.deployment.json",
        ROOT / "state/frontend/chains/monad-testnet.json",
        ROOT / "state/frontend/chains/base-sepolia.json",
        ROOT / "state/frontend/addresses/monad-testnet.json",
        ROOT / "state/frontend/contracts/glyphContracts.ts",
        ROOT / "state/frontend/contracts/glyphChains.ts",
        ROOT / "state/frontend/CONTRACT_METHODS.md",
        ROOT / "state/frontend/receipts/index.json",
        ROOT / "state/frontend/proofs/index.json",
        ROOT / "state/frontend/transactions/index.json",
        ROOT / "state/frontend/crosschain/base-monad.timeline.json",
        ROOT / "state/frontend/crosschain/CROSSCHAIN_UI_COPY.md",
        ROOT / "state/frontend/crosschain/layerzero-support-packet.md",
        ROOT / "state/schemas/link.schema.json",
        ROOT / "state/schemas/receipt.schema.json",
    ]
    for p in mandatory:
        require(p, checks)

    manifest = load(ROOT / "state/frontend/frontend.manifest.json")
    ok_msg(checks, "manifest schema", manifest.get("schema") == "glyph.frontend.manifest.v1", manifest.get("schema", ""))
    ok_msg(checks, "do-not list count", len(manifest.get("doNots", [])) == 5, str(manifest.get("doNots", [])))

    required_abis = {
        "SourceDeltaRouter": ["escrow", "operationId", "hashTerms", "routeFacts", "sourceReceiptFacts", "actorNonce"],
        "DestinationGlyphVault": ["provideLiquidity"],
        "GlyphLayerZeroApplication": ["sendRouteFromEscrow", "finalizeAndSendReceipt", "claimPushAndAck"],
        "ContributionCampaign": ["create", "reconcileChild", "close"],
        "GlyphReceiptLedger": ["registerOperation", "appendLocalLeg", "appendRemoteLeg", "reconcile"],
        "GlyphAttestationRegistry": [],
        "TestToken": ["approve", "balanceOf", "allowance"],
    }
    for name, funcs in required_abis.items():
        path = ROOT / "state/frontend/abi" / f"{name}.json"
        if require(path, checks):
            present = abi_functions(path)
            missing = [f for f in funcs if f not in present]
            ok_msg(checks, f"ABI functions: {name}", not missing, "missing=" + ",".join(missing))

    link_schema = load(ROOT / "state/schemas/link.schema.json")
    receipts_index = load(ROOT / "state/frontend/receipts/index.json")
    for rec in receipts_index.get("receipts", []):
        for key in ["jsonPath", "cardPath", "linkPath", "qrPath"]:
            p = ROOT / rec[key]
            require(p, checks)
        rpath = ROOT / rec["jsonPath"]
        if rpath.exists():
            ok, detail = validate_receipt(rpath)
            ok_msg(checks, f"receipt verifies: {rec['label']}", ok, detail[:160])
        lpath = ROOT / rec["linkPath"]
        if lpath.exists():
            link = load(lpath)
            try:
                jsonschema.validate(link["payload"], link_schema)
                schema_ok = True
                detail = ""
            except Exception as exc:
                schema_ok = False
                detail = str(exc)
            ok_msg(checks, f"receipt link schema: {rec['label']}", schema_ok, detail[:160])
        qpath = ROOT / rec["qrPath"]
        if qpath.exists():
            ok_msg(checks, f"QR non-empty: {rec['label']}", qpath.stat().st_size > 100, str(qpath.stat().st_size))

    proofs = load(ROOT / "state/frontend/proofs/index.json")
    ok_msg(checks, "proof count", len(proofs.get("proofs", [])) == 3, str(len(proofs.get("proofs", []))))
    timeline = load(ROOT / "state/frontend/crosschain/base-monad.timeline.json")
    ok_msg(checks, "crosschain marked blocked", timeline.get("uiStatus") == "source-send-proven-destination-blocked", timeline.get("uiStatus", ""))
    ok_msg(checks, "crosschain no settlement claim", any(s.get("status") == "not_delivered" for s in timeline.get("stages", [])), "not_delivered stage required")

    for flow in ["pull", "push", "campaign", "receipt", "crosschain-proof"]:
        p = ROOT / "state/frontend/flows" / f"{flow}.flow.json"
        if require(p, checks):
            obj = load(p)
            ok_msg(checks, f"flow schema: {flow}", obj.get("schema") == "glyph.frontend.flow.v1", obj.get("schema", ""))

    if args.live_rpc:
        addresses = load(ROOT / "state/frontend/addresses/monad-testnet.json")
        to_check = {}
        to_check.update({f"monadCore.{k}": v for k, v in addresses["monadCore"].items()})
        to_check.update({f"monadCampaign.{k}": v for k, v in addresses["monadCampaign"].items()})
        for label, addr in to_check.items():
            ok, out, err = run(["cast", "code", addr, "--rpc-url", RPC])
            code_ok = ok and out.startswith("0x") and len(out) > 2
            ok_msg(checks, f"live code: {label}", code_ok, (err or out[:80]))

    passed = sum(1 for c in checks if c["ok"])
    failed = [c for c in checks if not c["ok"]]
    report = {
        "schema": "glyph.frontend.readinessReport.v1",
        "generatedAt": now(),
        "liveRpc": args.live_rpc,
        "passed": passed,
        "failed": len(failed),
        "checks": checks,
    }
    out_json = ROOT / "state/frontend/FRONTEND_READINESS_REPORT.json"
    out_md = ROOT / "state/frontend/FRONTEND_READINESS_REPORT.md"
    out_json.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    rows = ["# Glyph frontend readiness report", "", f"Generated: `{report['generatedAt']}`", "", f"Passed: `{passed}`", f"Failed: `{len(failed)}`", "", "| Check | Status | Detail |", "|---|---:|---|"]
    for c in checks:
        rows.append(f"| `{c['name']}` | {'✅' if c['ok'] else '❌'} | {str(c.get('detail','')).replace('|','/')} |")
    out_md.write_text("\n".join(rows) + "\n")
    print(f"frontend readiness: {passed} passed, {len(failed)} failed")
    print(out_md.relative_to(ROOT))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
