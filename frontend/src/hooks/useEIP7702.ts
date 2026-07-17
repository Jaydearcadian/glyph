// SPDX-License-Identifier: MIT
// useEIP7702 — client session generation + management for Glyph Authority Vessels.
//
// EIP-7702 lets an EOA temporarily delegate to GlyphSessionProxy code. This hook:
//   1. derives a deterministic sessionId off-chain (avoids storage OCC conflicts),
//   2. registers the session policy on GlyphRegistry (whitelist + drawdown + expiry),
//   3. exposes revoke() to instantly kill the session on-chain.
//
// The master key never leaves the wallet; only a scoped session envelope is created.
import { useState } from "react";
import { createWalletClient, createPublicClient, custom, type Address, type Hex } from "viem";
import { monadTestnet, GLYPH_REGISTRY_ADDRESS } from "../config";
import { glyphAbi } from "../lib/abi";
import { deriveVesselId } from "../lib/crypto";

export interface SessionConfig {
  whitelistedTargets: Address[];
  maxDrawdownNative: bigint; // hard cap on native MON spend
  maxDrawdownToken: bigint; // hard cap on ERC-20 spend
  drawdownToken: Address; // token the token cap applies to (address(0) = none)
  expiresInSeconds: number; // time-bound session end
}

export function useEIP7702() {
  const [account, setAccount] = useState<Address | null>(null);
  const [sessionId, setSessionId] = useState<Hex | null>(null);
  const [status, setStatus] = useState<string>("");

  async function connect() {
    if (!window.ethereum) return setStatus("No injected wallet found.");
    const [addr] = await window.ethereum.request({ method: "eth_requestAccounts" });
    setAccount(addr as Address);
  }

  /** Register a scoped EIP-7702 session policy on GlyphRegistry. */
  async function registerSession(cfg: SessionConfig): Promise<Hex | null> {
    if (!account) return (setStatus("Connect a wallet first."), null);
    if (!window.ethereum) return (setStatus("No injected wallet found."), null);
    try {
      const sid = deriveVesselId(`session-${account}-${Date.now()}-${Math.random()}`);
      const walletClient = createWalletClient({ chain: monadTestnet, transport: custom(window.ethereum) });
      const publicClient = createPublicClient({ chain: monadTestnet, transport: custom(window.ethereum) });

      setStatus("Authorize the session envelope in your wallet…");
      const hash = await walletClient.writeContract({
        account,
        address: GLYPH_REGISTRY_ADDRESS,
        abi: glyphAbi,
        functionName: "registerSession",
        args: [
          sid,
          cfg.whitelistedTargets,
          cfg.maxDrawdownNative,
          cfg.maxDrawdownToken,
          cfg.drawdownToken,
          BigInt(Math.floor(Date.now() / 1000) + cfg.expiresInSeconds),
        ],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setSessionId(sid);
      setStatus("Session registered. The agent/recipient can now act within these bounds.");
      return sid;
    } catch (e: any) {
      setStatus(`Error: ${e?.shortMessage ?? e?.message ?? "unknown"}`);
      return null;
    }
  }

  /** Revoke a session instantly — master wallet keeps authority. */
  async function revoke(sid: Hex) {
    if (!account || !window.ethereum) return setStatus("Connect a wallet first.");
    try {
      const walletClient = createWalletClient({ chain: monadTestnet, transport: custom(window.ethereum) });
      const publicClient = createPublicClient({ chain: monadTestnet, transport: custom(window.ethereum) });
      setStatus("Revoking session…");
      const hash = await walletClient.writeContract({
        account,
        address: GLYPH_REGISTRY_ADDRESS,
        abi: glyphAbi,
        functionName: "revokeSession",
        args: [sid],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setSessionId(null);
      setStatus("Session revoked on-chain.");
    } catch (e: any) {
      setStatus(`Error: ${e?.shortMessage ?? e?.message ?? "unknown"}`);
    }
  }

  return { account, sessionId, status, connect, registerSession, revoke };
}
