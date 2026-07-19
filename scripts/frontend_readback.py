#!/usr/bin/env python3
"""Read frontend-relevant Glyph state.

Default mode is offline: it summarizes committed proof/readiness artifacts.
With --live-rpc, it also performs public eth_call/cast readbacks against Monad.
No private keys, no signing, no broadcasts.
"""
from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "state/frontend/readbacks"
RPC = "https://testnet-rpc.monad.xyz"


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load(path: Path) -> Any:
    return json.loads(path.read_text())


def run(cmd: List[str]) -> Dict[str, Any]:
    p = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, timeout=30)
    return {"ok": p.returncode == 0, "cmd": cmd, "stdout": p.stdout.strip(), "stderr": p.stderr.strip(), "returncode": p.returncode}


def cast_call(addr: str, sig: str, *args: str) -> Dict[str, Any]:
    return run(["cast", "call", addr, sig, *args, "--rpc-url", RPC])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live-rpc", action="store_true", help="perform public cast calls; no signing")
    args = ap.parse_args()

    manifest = load(ROOT / "state/frontend/frontend.manifest.json")
    addresses = load(ROOT / "state/frontend/addresses/monad-testnet.json")
    receipts = load(ROOT / "state/frontend/receipts/index.json")
    proofs = load(ROOT / "state/frontend/proofs/index.json")
    addr_pair = load(ROOT / "state/live/monad-address-pair-proof-20260719T130942Z/evidence.json")
    campaign = load(ROOT / "state/live/monad-campaign-proof-20260719T132755Z/evidence.json")

    report: Dict[str, Any] = {
        "schema": "glyph.frontend.readback.v1",
        "generatedAt": now(),
        "mode": "live-rpc" if args.live_rpc else "offline-artifact",
        "manifest": manifest["schema"],
        "canonicalAddresses": addresses,
        "proofSummary": proofs["proofs"],
        "receiptSummary": receipts["receipts"],
        "offlineReadbacks": {
            "pullSourceReceiptFacts": addr_pair["readbacks"].get("pullSourceReceiptFacts"),
            "pushSourceReceiptFacts": addr_pair["readbacks"].get("pushSourceReceiptFacts"),
            "campaign": campaign["readbacks"].get("campaign"),
            "child0Receipt": campaign["readbacks"].get("child0Receipt"),
            "child1Receipt": campaign["readbacks"].get("child1Receipt"),
        },
        "liveRpc": {},
    }

    if args.live_rpc:
        core = addresses["monadCore"]
        camp = addresses["monadCampaign"]
        report["liveRpc"]["routerCode"] = run(["cast", "code", core["router"], "--rpc-url", RPC])
        report["liveRpc"]["tokenCode"] = run(["cast", "code", core["token"], "--rpc-url", RPC])
        report["liveRpc"]["tokenSymbol"] = cast_call(core["token"], "symbol()(string)")
        report["liveRpc"]["tokenDecimals"] = cast_call(core["token"], "decimals()(uint8)")
        report["liveRpc"]["pullSourceReceiptFacts"] = cast_call(core["router"], "sourceReceiptFacts(bytes32)(bytes32,address,uint256,uint256,uint256,address,uint8)", addr_pair["operations"]["pull"])
        report["liveRpc"]["pushSourceReceiptFacts"] = cast_call(core["router"], "sourceReceiptFacts(bytes32)(bytes32,address,uint256,uint256,uint256,address,uint8)", addr_pair["operations"]["push"])
        report["liveRpc"]["campaign"] = cast_call(camp["campaign"], "campaigns(bytes32)(address,address,uint256,uint256,uint256,uint256,uint64,uint8,uint256,bool)", campaign["programId"])

    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "latest.json"
    out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(out)


if __name__ == "__main__":
    main()
