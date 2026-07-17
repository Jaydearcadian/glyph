// SPDX-License-Identifier: MIT
// VesselForge — tactile control panel: connect wallet, forge a Value Vessel
// (escrow funds behind a passcode gatekeeper), and produce a shareable link.
import { useState } from "react";
import { createWalletClient, createPublicClient, custom, type Address, type Hex } from "viem";
import { monadTestnet, GLYPH_REGISTRY_ADDRESS } from "../config";
import { glyphAbi } from "../lib/abi";
import {
  passcodeToGatekeeper,
  buildShareLink,
  deriveVesselId,
} from "../lib/crypto";
import { FloatingCore } from "./FloatingCore";
import { BiopunkLine } from "./BiopunkLine";

export function VesselForge() {
  const [account, setAccount] = useState<Address | null>(null);
  const [passcode, setPasscode] = useState("");
  const [amount, setAmount] = useState("0.05");
  const [status, setStatus] = useState<string>("");
  const [shareLink, setShareLink] = useState<string>("");
  const [vesselId, setVesselId] = useState<Hex | null>(null);

  const publicClient = createPublicClient({ chain: monadTestnet, transport: custom(window.ethereum!) });

  async function connect() {
    if (!window.ethereum) {
      setStatus("No injected wallet (MetaMask/Rabby). Install one or use a wallet connector.");
      return;
    }
    const [addr] = await window.ethereum.request({ method: "eth_requestAccounts" });
    setAccount(addr as Address);
    setStatus("Wallet connected.");
  }

  async function forge() {
    if (!account) return setStatus("Connect a wallet first.");
    if (!passcode) return setStatus("Set a passcode for the claim link.");
    try {
      const gatekeeper = passcodeToGatekeeper(passcode);
      const vid = deriveVesselId(`${account}-${Date.now()}-${Math.random()}`);
      const valueWei = BigInt(Math.floor(parseFloat(amount) * 1e18));
      const walletClient = createWalletClient({ chain: monadTestnet, transport: custom(window.ethereum!) });

      setStatus("Confirm the escrow transaction in your wallet…");
      const hash = await walletClient.writeContract({
        account,
        address: GLYPH_REGISTRY_ADDRESS,
        abi: glyphAbi,
        functionName: "createValueVessel",
        args: [vid, "0x0000000000000000000000000000000000000000" as Address, valueWei, gatekeeper, 0n],
        value: valueWei,
      });
      setStatus(`Submitted: ${hash.slice(0, 10)}… waiting for finality`);
      await publicClient.waitForTransactionReceipt({ hash });
      setVesselId(vid);
      setShareLink(buildShareLink(window.location.origin, vid, passcode));
      setStatus("Vessel forged. Share the link below — passcode stays in the URL fragment only.");
    } catch (e: any) {
      setStatus(`Error: ${e?.shortMessage ?? e?.message ?? "unknown"}`);
    }
  }

  return (
    <div className="rounded-2xl border border-glyph-line bg-glyph-panel p-6 shadow-glow">
      <div className="flex items-center gap-4">
        <FloatingCore seed={account ?? "glyph"} active={!!vesselId} />
        <div className="flex-1">
          <h2 className="text-lg font-semibold text-glyph-accent">Vessel Forge</h2>
          <p className="text-sm text-slate-400">Escrow MON behind a front-run-proof claim link.</p>
          <button
            onClick={connect}
            className="mt-3 rounded-lg border border-glyph-accent/40 bg-glyph-accent/10 px-4 py-2 text-sm text-glyph-accent hover:bg-glyph-accent/20"
          >
            {account ? `Connected ${account.slice(0, 6)}…${account.slice(-4)}` : "Connect Wallet"}
          </button>
        </div>
      </div>

      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <label className="text-sm text-slate-300">
          Amount (MON)
          <input
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            className="mt-1 w-full rounded-lg border border-glyph-line bg-glyph-bg px-3 py-2 text-glyph-accent outline-none"
          />
        </label>
        <label className="text-sm text-slate-300">
          Claim passcode
          <input
            value={passcode}
            onChange={(e) => setPasscode(e.target.value)}
            placeholder="shared word/phrase"
            className="mt-1 w-full rounded-lg border border-glyph-line bg-glyph-bg px-3 py-2 text-glyph-accent outline-none"
          />
        </label>
      </div>

      <button
        onClick={forge}
        className="mt-4 w-full rounded-lg bg-glyph-accent px-4 py-3 font-semibold text-glyph-bg hover:opacity-90"
      >
        Forge Value Vessel
      </button>

      {shareLink && (
        <div className="mt-4 rounded-lg border border-glyph-line bg-glyph-bg p-3">
          <p className="text-xs uppercase tracking-wide text-slate-500">Shareable Glyph Link</p>
          <a href={shareLink} className="break-all text-sm text-glyph-accent2">{shareLink}</a>
          <BiopunkLine from={{ x: 0, y: 0 }} to={{ x: 300, y: 40 }} />
        </div>
      )}

      {status && <p className="mt-3 text-xs text-slate-400">{status}</p>}
    </div>
  );
}
