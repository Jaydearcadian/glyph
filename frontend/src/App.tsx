// SPDX-License-Identifier: MIT
import { VesselForge } from "./components/VesselForge";
import { VesselClaim } from "./components/VesselClaim";

export default function App() {
  const isClaim = /[#&]v=0x/i.test(window.location.hash);
  return (
    <div className="min-h-screen bg-glyph-bg font-mono text-slate-200">
      <header className="mx-auto max-w-3xl px-4 py-6">
        <h1 className="text-2xl font-bold tracking-tight">
          <span className="text-glyph-accent">GLYPH</span>{" "}
          <span className="text-slate-500">// Vessel</span>
        </h1>
        <p className="text-sm text-slate-400">
          Frictionless, push-based asset &amp; authority delegation on Monad.
        </p>
      </header>

      <main className="mx-auto max-w-3xl space-y-6 px-4 pb-16">
        {isClaim ? <VesselClaim /> : <VesselForge />}
        <footer className="pt-4 text-center text-xs text-slate-600">
          Spark Hackathon · Monad Testnet · front-run-proof claim links
        </footer>
      </main>
    </div>
  );
}
