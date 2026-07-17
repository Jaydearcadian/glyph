// SPDX-License-Identifier: MIT
import { useState } from "react";
import { VesselForge } from "./components/VesselForge";
import { VesselClaim } from "./components/VesselClaim";
import { SessionForge } from "./components/SessionForge";

type Tab = "value" | "authority" | "claim";

export default function App() {
  const [tab, setTab] = useState<Tab>(/[#&]v=0x/i.test(window.location.hash) ? "claim" : "value");
  const isClaim = tab === "claim";

  const TabBtn = ({ id, label }: { id: Tab; label: string }) => (
    <button
      onClick={() => setTab(id)}
      className={`rounded-lg px-3 py-1.5 text-sm transition ${
        tab === id ? "bg-glyph-accent/20 text-glyph-accent" : "text-slate-500 hover:text-slate-300"
      }`}
    >
      {label}
    </button>
  );

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
        <nav className="mt-4 flex gap-2">
          <TabBtn id="value" label="Value Vessel" />
          <TabBtn id="authority" label="Authority Vessel" />
          <TabBtn id="claim" label="Claim Link" />
        </nav>
      </header>

      <main className="mx-auto max-w-3xl space-y-6 px-4 pb-16">
        {tab === "value" && <VesselForge />}
        {tab === "authority" && <SessionForge />}
        {isClaim && <VesselClaim />}
        <footer className="pt-4 text-center text-xs text-slate-600">
          Spark Hackathon · Monad Testnet · front-run-proof links · EIP-7702 sessions
        </footer>
      </main>
    </div>
  );
}
