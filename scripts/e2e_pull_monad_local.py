#!/usr/bin/env python3
"""Live MONAD-ONLY (same-chain) Pull E2E on Monad Testnet (10143) via LayerZero V2 loopback.

Proves the local value loop on Monad: escrow -> route (Monad->Monad LZ loopback)
-> vault delivers to recipient -> finalize. No Base chain involved.

Uses `cast` subprocess; signs with the gitignored deployer key.
"""
import json, subprocess, time

KEYFILE = "/root/monadglyph-hy3-oneshot/state/keys/generated_testnet_wallets.json"
MONAD_RPC = "https://testnet-rpc.monad.xyz"

# All Monad-side deployed addresses (from CROSSCHAIN_DEPLOYMENT_EVIDENCE.json)
MONAD = {
    "router": "0xc71c119b91fa1f1861626843fa653f41cef9101a",
    "app":    "0xb30a58245300127110583925956207f859947936",
    "vault":  "0x5c9b29130a91c8419ccaa33d7febe6de0b26824a",
    "token":  "0x1d482783316fdef2e795a1c193ace280660a887a",
    "adapter":"0x8ad972eabc36f01136b13f98afb8225e13bf57c",
}
ESCROW_SELECTOR = "0x563c1047"  # confirmed from on-chain dispatcher trace

PK = json.load(open(KEYFILE))["private_key"]
OWNER = json.load(open(KEYFILE))["address"]  # keep original EIP-55 mixed-case for cast CLI compatibility

def cast(args, rpc=None):
    cmd = ["cast"] + args
    if rpc: cmd += ["--rpc-url", rpc]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"cast failed: {' '.join(args)}\n{r.stderr}")
    return r.stdout.strip()

def send(fn_sig, args, rpc, contract, value="0", selector=None):
    if isinstance(args, str) or (isinstance(args, list) and "(" in fn_sig):
        enc_args = [args] if isinstance(args, str) else list(args)
        enc = subprocess.run(["cast", "abi-encode", fn_sig, *enc_args], capture_output=True, text=True)
        if enc.returncode != 0:
            raise RuntimeError(f"abi-encode failed: {fn_sig}\n{enc.stderr}")
        data = enc.stdout.strip()
        if selector:
            data = selector + data[2:]
        cmd = ["cast", "send", contract, data, "--private-key", PK, "--rpc-url", rpc, "--legacy"]
    else:
        cmd = ["cast", "send", contract, fn_sig, *list(args), "--private-key", PK, "--rpc-url", rpc, "--legacy"]
    if value != "0": cmd += ["--value", value]
    cmd += ["--gas-limit", "600000"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"send failed: {fn_sig}\n{r.stderr}")
    time.sleep(3)
    for line in r.stdout.splitlines():
        if "transaction_hash" in line or "tx:" in line:
            return line.split()[-1]
    return r.stdout.strip()

def call(fn_sig, args, rpc, contract):
    calldata_args = [args] if isinstance(args, str) else list(args)
    cmd = ["cast", "call", contract, fn_sig, *calldata_args, "--rpc-url", rpc]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"call failed: {fn_sig}\n{r.stderr}")
    return r.stdout.strip()

def wait_tx(tx_hash, rpc):
    for _ in range(30):
        r = subprocess.run(["cast", "receipt", tx_hash, "--json", "--rpc-url", rpc],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return json.loads(r.stdout)
        time.sleep(3)
    return None

def get_op_from_receipt(receipt):
    for log in receipt.get("logs", []):
        topics = log.get("topics", [])
        if len(topics) >= 2:
            return topics[1]
    return None

TERMS_INNER = "bytes32,bytes32,address,address,address,address,uint64,address,address,uint64,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,address,uint64,uint256"
ENC_SIG = f"escrow(({TERMS_INNER}))"

def main():
    print(f"Owner/recipient: {OWNER}")
    MODE_PULL = call("PULL()", [], MONAD_RPC, MONAD["router"])
    print(f"Mode PULL: {MODE_PULL}")

    # sequential per-payer nonce
    try:
        an = call("actorNonce(address)(uint256)", [OWNER], MONAD_RPC, MONAD["router"])
        nonce = int(an, 16)
    except Exception:
        nonce = 0
    print(f"Using sequential nonce: {nonce}")

    expiry = int(time.time()) + 86400
    maximumInput = 110 * 10**18
    destinationAmount = 100 * 10**18
    providerFee = 10 * 10**18
    ZERO = "0x0000000000000000000000000000000000000000"
    terms = [
        MODE_PULL, "0x" + "0"*64, OWNER, OWNER, OWNER,
        MONAD["token"], "10143", MONAD["vault"], MONAD["token"], "10143",
        str(maximumInput), str(destinationAmount),
        "0", str(providerFee), "0", "0",
        OWNER, OWNER, OWNER, OWNER, ZERO,
        str(expiry), str(nonce),
    ]
    terms_tuple = "(" + ",".join(terms) + ")"

    print("== Approve Monad token -> router ==")
    h = send("approve(address,uint256)", [MONAD["router"], str(maximumInput)], MONAD_RPC, MONAD["token"])
    wait_tx(h, MONAD_RPC)
    print("   approved (mined)")

    print("== Escrow on Monad (same-chain Pull) ==")
    h = send(ENC_SIG, terms_tuple, MONAD_RPC, MONAD["router"], selector=ESCROW_SELECTOR)
    rcpt = wait_tx(h, MONAD_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! escrow reverted (status={rcpt.get('status') if rcpt else 'unknown'}). Aborting.")
        return
    op = get_op_from_receipt(rcpt)
    if not op:
        print("   !! could not extract opId. Aborting."); return
    print(f"   operationId: {op}")

    print("== Quote LZ loopback fee ==")
    gasLimit = 300_000
    q = call("quoteRouteFromEscrow(bytes32,uint256)(uint256)", [op, str(gasLimit)], MONAD_RPC, MONAD["app"])
    fee = int(q, 16)
    print(f"   LZ fee: {fee} wei ({fee/1e18:.6f} MON)")

    print("== sendRouteFromEscrow (Monad->Monad loopback, pays LZ fee) ==")
    h = send("sendRouteFromEscrow(bytes32,address,uint256)", [op, OWNER, str(gasLimit)], MONAD_RPC, MONAD["app"], value=str(fee))
    rcpt = wait_tx(h, MONAD_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! route reverted. (op {op} escrowed; recoverable)"); return
    print(f"   route tx: {h}")
    print("   >> Waiting for LZ testnet loopback to deliver packet on Monad...")

    print("== Poll Monad vault reservation status (timeout 240s) ==")
    deadline = time.time() + 240
    delivered = False
    while time.time() < deadline:
        try:
            out = call("reservations(bytes32)((uint8,address,address,address,uint256,uint64,address,uint64,address,uint8,address,bytes32))",
                       [op], MONAD_RPC, MONAD["vault"])
            parts = out.replace("(", "").replace(")", "").split(",")
            status = int(parts[9].strip())
            print(f"   t={int(time.time())%100000} status={status} (2=DELIVERED)", end="\r", flush=True)
            if status >= 2:
                delivered = True
                print(f"\n   DELIVERED on Monad (status={status})")
                break
        except Exception as e:
            print(f"\n   poll err: {e}")
        time.sleep(10)

    if not delivered:
        print("\n!! LZ testnet loopback did not deliver within timeout.")
        print(f"   op {op} escrowed + routed on Monad. Relay may be down; re-run later.")
        return

    print("== finalizeAndSendReceipt on Monad (onlyOwner) ==")
    h = send("finalizeAndSendReceipt(bytes32,address,uint256)", [op, OWNER, str(gasLimit)], MONAD_RPC, MONAD["app"], value=str(fee))
    rcpt = wait_tx(h, MONAD_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! finalize reverted. (delivered; source may need manual finalize)"); return
    print(f"   finalize tx: {h}")

    src = call("sourceTerminalReceipt(bytes32)(bytes32)", [op], MONAD_RPC, MONAD["app"])
    print(f"sourceTerminalReceipt: {src}")
    print("MONAD-ONLY PULL: COMPLETE (escrow->loopback-deliver->finalize, receipt on Monad).")

if __name__ == "__main__":
    main()
