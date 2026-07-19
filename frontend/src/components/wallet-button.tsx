"use client";

import { ChevronDown, Wallet } from "lucide-react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { monadTestnet, shortHash } from "@/lib/glyph";

export function WalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  if (!isConnected) {
    return (
      <button className="button button-light wallet-button" onClick={() => connectors[0] && connect({ connector: connectors[0] })} disabled={isPending || !connectors[0]}>
        <Wallet size={15} aria-hidden /> {isPending ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }

  if (chainId !== monadTestnet.id) {
    return <button className="button button-amber wallet-button" onClick={() => switchChain({ chainId: monadTestnet.id })} disabled={isSwitching}>{isSwitching ? "Switching…" : "Switch to Monad"}</button>;
  }

  return (
    <button className="wallet-connected" onClick={() => disconnect()} title="Disconnect wallet">
      <span className="live-dot" />
      <span>{shortHash(address)}</span>
      <ChevronDown size={13} aria-hidden />
    </button>
  );
}
