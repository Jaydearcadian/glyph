// SPDX-License-Identifier: MIT
// VesselClaim — claim UI for a Glyph link. Reads vesselId + passcode from the URL
// fragment (passcode never leaves the browser / never hits the server).
import { useVesselClaim } from "../hooks/useVesselClaim";
import { FloatingCore } from "./FloatingCore";

export function VesselClaim() {
  const { account, vesselId, passcode, status, connect, claim } = useVesselClaim();
  const isClaim = !!vesselId;

  return (
    <div className="rounded-2xl border border-glyph-line bg-glyph-panel p-6 shadow-glow">
      <div className="flex items-center gap-4">
        <FloatingCore seed={vesselId ?? "claim"} active={!!account} />
        <div className="flex-1">
          <h2 className="text-lg font-semibold text-glyph-accent2">Claim Vessel</h2>
          <p className="text-sm text-slate-400">
            {isClaim ? "A Glyph link was detected. Claim it below." : "Open a Glyph share link to claim."}
          </p>
          {vesselId && (
            <p className="mt-1 break-all text-xs text-slate-500">vessel: {vesselId}</p>
          )}
        </div>
      </div>

      {isClaim && (
        <>
          <button
            onClick={connect}
            className="mt-4 w-full rounded-lg border border-glyph-accent2/40 bg-glyph-accent2/10 px-4 py-2 text-sm text-glyph-accent2 hover:bg-glyph-accent2/20"
          >
            {account ? `Connected ${account.slice(0, 6)}…${account.slice(-4)}` : "Connect Wallet"}
          </button>
          <button
            onClick={claim}
            className="mt-3 w-full rounded-lg bg-glyph-accent2 px-4 py-3 font-semibold text-glyph-bg hover:opacity-90"
          >
            Claim with Front-Run-Proof Signature
          </button>
        </>
      )}
      {passcode && !isClaim && (
        <p className="mt-3 text-xs text-slate-500">Passcode present in link (hidden) but vessel id missing.</p>
      )}
      {status && <p className="mt-3 text-xs text-slate-400">{status}</p>}
    </div>
  );
}
