#!/usr/bin/env python3
"""Live cross-chain Pull E2E: Base Sepolia -> Monad Testnet via LayerZero V2.

Drives REAL deployed contracts. Polls for LZ testnet relay delivery.
Uses `cast` subprocess; signs with the gitignored deployer key.
"""
import json, subprocess, time

KEYFILE = "/root/monadglyph-hy3-oneshot/state/keys/generated_testnet_wallets.json"
BASE_RPC = "https://sepolia.base.org"
MONAD_RPC = "https://testnet-rpc.monad.xyz"

BASE = {
    "router": "0xb28c11ae970d4bdda4a221b9a5ceb5d287d336f3",
    "app":    "0x689979129f4ad12df09c0a48d7dd08af3b73ff5d",
    "token":  "0xc0d50bb3aee4c7bf969d143fc8d8a78841bc752f",
}
MONAD = {
    "vault":  "0x5c9b29130a91c8419ccaa33d7febe6de0b26824a",
    "app":    "0xb30a58245300127110583925956207f859947936",
    "token":  "0x1d482783316fdef2e795a1c193ace280660a887a",
    "adapter":"0x8ad972eabc36f01136b13f98afb8225e13bf57c",
}
PK = json.load(open(KEYFILE))["private_key"]
OWNER = json.load(open(KEYFILE))["address"].lower()

def cast(args, rpc=None):
    cmd = ["cast"] + args
    if rpc: cmd += ["--rpc-url", rpc]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"cast failed: {' '.join(args)}\n{r.stderr}")
    return r.stdout.strip()

def send(fn_sig, args, rpc, contract, value="0", selector=None):
    if isinstance(args, str) or (isinstance(args, list) and "(" in fn_sig):
        # Tuple/struct arg: encode via cast abi-encode (args only, no selector), prepend selector.
        enc_args = [args] if isinstance(args, str) else list(args)
        enc = subprocess.run(["cast", "abi-encode", fn_sig, *enc_args], capture_output=True, text=True)
        if enc.returncode != 0:
            raise RuntimeError(f"abi-encode failed: {fn_sig}\n{enc.stderr}")
        data = enc.stdout.strip()
        if selector:
            data = selector + data[2:]  # prepend 4-byte selector
        cmd = ["cast", "send", contract, data, "--private-key", PK, "--rpc-url", rpc, "--legacy"]
    else:
        # Scalar args: direct cast send with signature (gas estimation works).
        cmd = ["cast", "send", contract, fn_sig, *list(args), "--private-key", PK, "--rpc-url", rpc, "--legacy"]
    if value != "0": cmd += ["--value", value]
    cmd += ["--gas-limit", "600000"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"send failed: {fn_sig}\n{r.stderr}")
    time.sleep(3)  # let node advance pending nonce
    for line in r.stdout.splitlines():
        if "transaction_hash" in line or "tx:" in line:
            return line.split()[-1]
    return r.stdout.strip()

def call(fn_sig, args, rpc, contract):
    # Direct cast call with return type (decodes correctly).
    calldata_args = [args] if isinstance(args, str) else list(args)
    cmd = ["cast", "call", contract, fn_sig, *calldata_args, "--rpc-url", rpc]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"call failed: {fn_sig}\n{r.stderr}")
    return r.stdout.strip()

TERMS_INNER = "bytes32,bytes32,address,address,address,address,uint64,address,address,uint64,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,address,uint64,uint256"
TERMS_SIG = f"({TERMS_INNER})"
ENC_SIG = f"escrow(({TERMS_INNER}))"

def wait_tx(tx_hash, rpc):
    """Poll until tx is mined; return receipt json."""
    for _ in range(30):
        r = subprocess.run(["cast", "receipt", tx_hash, "--json", "--rpc-url", rpc],
                           capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return json.loads(r.stdout)
        time.sleep(3)
    return None

def get_op_from_receipt(receipt):
    """OperationEscrowed(bytes32 op, bytes32 mode, address payer, uint256 amount): op = topic[1]."""
    for log in receipt.get("logs", []):
        topics = log.get("topics", [])
        if len(topics) >= 2:
            return topics[1]
    return None

def main():
    import random
    print(f"Owner: {OWNER}")
    MODE_PULL = call("PULL()", [], BASE_RPC, BASE["router"])
    print(f"Mode PULL: {MODE_PULL}")

    expiry = int(time.time()) + 86400  # 24h buffer to avoid mempool-delay expiry revert
    maximumInput = 110 * 10**18
    destinationAmount = 100 * 10**18
    providerFee = 10 * 10**18
    # Router requires sequential per-payer nonce: t.nonce must == actorNonce[payer]
    try:
        an = call("actorNonce(address)(uint256)", [OWNER], BASE_RPC, BASE["router"])
        nonce = int(an, 16)
    except Exception:
        nonce = 0
    print(f"Using sequential nonce: {nonce}")
    ZERO = "0x0000000000000000000000000000000000000000"
    terms = [
        MODE_PULL, "0x" + "0"*64, OWNER, OWNER, OWNER,
        BASE["token"], "84532", MONAD["vault"], MONAD["token"], "10143",
        str(maximumInput), str(destinationAmount),
        "0", str(providerFee), "0", "0",
        OWNER, OWNER, OWNER, OWNER, ZERO,
        str(expiry), str(nonce),
    ]
    terms_tuple = "(" + ",".join(terms) + ")"

    print("== Approve Base token -> router ==")
    h = send("approve(address,uint256)", [BASE["router"], str(maximumInput)], BASE_RPC, BASE["token"])
    wait_tx(h, BASE_RPC)
    print("   approved (mined)")

    print("== Escrow on Base ==")
    h = send(ENC_SIG, terms_tuple, BASE_RPC, BASE["router"])
    print(f"   escrow tx: {h}")
    rcpt = wait_tx(h, BASE_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! escrow tx reverted (status={rcpt.get('status') if rcpt else 'unknown'}). Aborting.")
        return
    op = get_op_from_receipt(rcpt)
    if not op:
        print("   !! could not extract opId from logs. Aborting.")
        return
    print(f"   operationId: {op}")

    print("== Quote LZ route fee ==")
    gasLimit = 300_000
    q = call("quoteRouteFromEscrow(bytes32,uint256)(uint256)", [op, str(gasLimit)], BASE_RPC, BASE["app"])
    fee = int(q, 16)
    print(f"   LZ fee: {fee} wei ({fee/1e18:.6f} ETH)")

    print("== sendRouteFromEscrow (pays LZ fee, onlyOwner) ==")
    h = send("sendRouteFromEscrow(bytes32,address,uint256)", [op, OWNER, str(gasLimit)], BASE_RPC, BASE["app"], value=str(fee))
    rcpt = wait_tx(h, BASE_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! route tx reverted. Aborting. (op {op} escrowed; recoverable)")
        return
    print(f"   route tx: {h}")
    print("   >> Waiting for LayerZero testnet relayer to deliver packet to Monad...")

    # Poll Monad reservation status (tuple idx 9: 0 NONE,1 RESERVED,2 DELIVERED,3 RELEASED)
    print("== Poll Monad reservation status (timeout 240s) ==")
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
        print("\n!! LZ testnet relay did not deliver within timeout.")
        print(f"   Source op {op} is escrowed + routed on Base. Relay may be down or slow.")
        print("   Re-run later; contract state is correct. No funds lost (escrowed, recoverable).")
        return

    print("== finalizeAndSendReceipt on Base (onlyOwner, pays LZ ack fee) ==")
    h = send("finalizeAndSendReceipt(bytes32,address,uint256)", [op, OWNER, str(gasLimit)], BASE_RPC, BASE["app"], value=str(fee))
    rcpt = wait_tx(h, BASE_RPC)
    if not rcpt or rcpt.get("status") != 1:
        print(f"   !! finalize tx reverted. (op {op} delivered on Monad; source may need manual finalize)")
        return
    print(f"   finalize tx: {h}")

    print("== Read back terminal receipts ==")
    src = call("sourceTerminalReceipt(bytes32)(bytes32)", [op], BASE_RPC, BASE["app"])
    print(f"   sourceTerminalReceipt: {src}")
    print("E2E CROSS-CHAIN PULL: COMPLETE (escrow->route->deliver->finalize).")

if __name__ == "__main__":
    main()
