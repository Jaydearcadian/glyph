// SPDX-License-Identifier: MIT
// useVesselClaim — reads a Glyph link from the URL fragment, lets the claimant
// connect and claim. The passcode (ephemeral key source) lives only in location.hash.
import { useState, useEffect } from "react";
import { createWalletClient, createPublicClient, custom, type Address, type Hex } from "viem";
import { monadTestnet, GLYPH_REGISTRY_ADDRESS } from "../config";
import { glyphAbi } from "../lib/abi";
import { parseShareLink, signClaim } from "../lib/crypto";

export function useVesselClaim() {
  const [account, setAccount] = useState<Address | null>(null);
  const [vesselId, setVesselId] = useState<Hex | null>(null);
  const [passcode, setPasscode] = useState<string | null>(null);
  const [status, setStatus] = useState<string>("");

  useEffect(() => {
    const { vesselId, passcode } = parseShareLink(window.location.hash);
    if (vesselId) setVesselId(vesselId);
    if (passcode) setPasscode(passcode);
  }, []);

  const publicClient = createPublicClient({ chain: monadTestnet, transport: custom(window.ethereum!) });

  async function connect() {
    if (!window.ethereum) return setStatus("No injected wallet found.");
    const [addr] = await window.ethereum.request({ method: "eth_requestAccounts" });
    setAccount(addr as Address);
  }

  async function claim() {
    if (!account) return setStatus("Connect a wallet first.");
    if (!vesselId || !passcode) return setStatus("Missing vessel id or passcode from link.");
    try {
      const sig = await signClaim(passcode, account, vesselId);
      const walletClient = createWalletClient({ chain: monadTestnet, transport: custom(window.ethereum!) });
      setStatus("Submitting claim (front-run-proof signature)…");
      const hash = await walletClient.writeContract({
        account,
        address: GLYPH_REGISTRY_ADDRESS,
        abi: glyphAbi,
        functionName: "claimVessel",
        args: [vesselId, sig],
      });
      await publicClient.waitForTransactionReceipt({ hash });
      setStatus("Claimed! Funds are on their way to your wallet.");
    } catch (e: any) {
      setStatus(`Error: ${e?.shortMessage ?? e?.message ?? "unknown"}`);
    }
  }

  return { account, vesselId, passcode, status, connect, claim, setStatus };
}
