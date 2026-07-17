// SPDX-License-Identifier: MIT
// SessionForge — create an Authority Vessel: a scoped EIP-7702 session envelope
// handed to a friend or AI agent. Drawdown cap + target whitelist + time-bound.
import { useState } from "react";
import type { Address } from "viem";
import { useEIP7702, type SessionConfig } from "../hooks/useEIP7702";
import { FloatingCore } from "./FloatingCore";
import { BiopunkLine } from "./BiopunkLine";

export function SessionForge() {
  const { account, sessionId, status, connect, registerSession, revoke } = useEIP7702();
  const [targets, setTargets] = useState("");
  const [drawdown, setDrawdown] = useState("0.1");
  const [ttl, setTtl] = useState("3600");

  async function create() {
    const whitelist: Address[] = targets
      .split(/[\s,]+/)
      .map((t) => t.trim())
      .filter((t) => /^0x[0-9a-fA-F]{40}$/.test(t)) as Address[];
    const cfg: SessionConfig = {
      whitelistedTargets: whitelist,
      maxDrawdownNative: BigInt(Math.floor(parseFloat(drawdown || "0") * 1e18)),
      maxDrawdownToken: 0n,
      drawdownToken: "0x0000000000000000000000000000000000000000" as Address,
      expiresInSeconds: parseInt(ttl || "3600", 10),
    };
    await registerSession(cfg);
  }

  return (
    <div className="rounded-2xl border border-glyph-line bg-glyph-panel p-6 shadow-glow">
      <div className="flex items-center gap-4">
        <FloatingCore seed={account ?? "session"} active={!!sessionId} />
        <div className="flex-1">
          <h2 className="text-lg font-semibold text-glyph-accent2">Session Forge</h2>
          <p className="text-sm text-slate-400">
            Mint an Authority Vessel — a scoped, revocable EIP-7702 session for a friend or agent.
          </p>
          <button
            onClick={connect}
            className="mt-3 rounded-lg border border-glyph-accent2/40 bg-glyph-accent2/10 px-4 py-2 text-sm text-glyph-accent2 hover:bg-glyph-accent2/20"
          >
            {account ? `Connected ${account.slice(0, 6)}…${account.slice(-4)}` : "Connect Wallet"}
          </button>
        </div>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <label className="text-sm text-slate-300">
          Whitelisted targets (comma-sep)
          <input
            value={targets}
            onChange={(e) => setTargets(e.target.value)}
            placeholder="0xabc…, 0xdef…"
            className="mt-1 w-full rounded-lg border border-glyph-line bg-glyph-bg px-3 py-2 text-glyph-accent2 outline-none"
          />
        </label>
        <label className="text-sm text-slate-300">
          Max drawdown (MON)
          <input
            value={drawdown}
            onChange={(e) => setDrawdown(e.target.value)}
            className="mt-1 w-full rounded-lg border border-glyph-line bg-glyph-bg px-3 py-2 text-glyph-accent2 outline-none"
          />
        </label>
        <label className="text-sm text-slate-300">
          TTL (seconds)
          <input
            value={ttl}
            onChange={(e) => setTtl(e.target.value)}
            className="mt-1 w-full rounded-lg border border-glyph-line bg-glyph-bg px-3 py-2 text-glyph-accent2 outline-none"
          />
        </label>
      </div>

      <button
        onClick={create}
        className="mt-4 w-full rounded-lg bg-glyph-accent2 px-4 py-3 font-semibold text-glyph-bg hover:opacity-90"
      >
        Forge Authority Vessel
      </button>

      {sessionId && (
        <div className="mt-4 rounded-lg border border-glyph-line bg-glyph-bg p-3">
          <p className="text-xs uppercase tracking-wide text-slate-500">Active session</p>
          <p className="break-all text-sm text-glyph-accent2">{sessionId}</p>
          <button
            onClick={() => revoke(sessionId)}
            className="mt-2 rounded-lg border border-glyph-danger/40 px-3 py-1 text-xs text-glyph-danger hover:bg-glyph-danger/10"
          >
            Revoke
          </button>
        </div>
      )}

      {status && <p className="mt-3 text-xs text-slate-400">{status}</p>}
      <BiopunkLine from={{ x: 0, y: 0 }} to={{ x: 280, y: 30 }} color="#a78bfa" />
    </div>
  );
}
