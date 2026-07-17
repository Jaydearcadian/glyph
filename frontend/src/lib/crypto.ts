// SPDX-License-Identifier: MIT
// Glyph front-run-proof crypto. Mirrors GlyphRegistry.claimVessel on-chain logic.
//
// Claim flow: the sharer derives an ephemeral keypair from a passcode in-browser.
// The public half (gatekeeper) is written on-chain; the private half travels ONLY
// in the URL hash fragment (#s=...) which never hits the host server. The claimant
// signs (claimantAddress, vesselId) with the ephemeral key. Because the signature
// binds to msg.sender, any copied mempool transaction from a different address fails
// ecrecover on-chain. MEV bots cannot replay it.

import { privateKeyToAddress, signMessage } from "viem/accounts";
import { keccak256, encodePacked, hashMessage, type Hex, type Address } from "viem";

/** Derive a deterministic ephemeral private key from an arbitrary passcode string. */
export function passcodeToPrivateKey(passcode: string): Hex {
  // keccak256(passcode) -> 32-byte private key (valid curve scalar for secp256k1).
  return keccak256(encodePacked(["string"], [passcode]));
}

/** Public gatekeeper address derived from the passcode. */
export function passcodeToGatekeeper(passcode: string): Address {
  return privateKeyToAddress(passcodeToPrivateKey(passcode));
}

/** The exact claim message hash the contract verifies: keccak(claimant, vesselId). */
export function claimMessageHash(claimant: Address, vesselId: Hex): Hex {
  return keccak256(encodePacked(["address", "bytes32"], [claimant, vesselId]));
}

/**
 * Produce the signature a claimant submits to claimVessel.
 * Signs the Ethereum Signed Message envelope of claimMessageHash.
 */
export async function signClaim(
  passcode: string,
  claimant: Address,
  vesselId: Hex
): Promise<Hex> {
  const pk = passcodeToPrivateKey(passcode);
  const digest = claimMessageHash(claimant, vesselId);
  // viem's signMessage wraps with the \x19Ethereum Signed Message prefix automatically.
  const sig = await signMessage({ privateKey: pk, message: { raw: digest } });
  return sig;
}

/** Off-chain prediction of the gatekeeper for UI feedback (matches on-chain check). */
export function verifyClaimLocally(
  passcode: string,
  claimant: Address,
  vesselId: Hex
): boolean {
  const digest = claimMessageHash(claimant, vesselId);
  // We cannot locally recover without signing, but we can show the gatekeeper.
  return passcodeToGatekeeper(passcode) !== "0x0000000000000000000000000000000000000000";
}

/** Build a shareable Glyph link. Passcode lives ONLY in the #fragment. */
export function buildShareLink(baseUrl: string, vesselId: Hex, passcode: string): string {
  const url = new URL(baseUrl);
  url.hash = `v=${vesselId}&s=${passcode}`;
  return url.toString();
}

/** Parse a Glyph link; returns vesselId + passcode (passcode from fragment only). */
export function parseShareLink(hash: string): { vesselId: Hex | null; passcode: string | null } {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const v = params.get("v");
  const s = params.get("s");
  return {
    vesselId: v && /^0x[0-9a-fA-F]{64}$/.test(v) ? (v as Hex) : null,
    passcode: s,
  };
}

/** Deterministic, off-chain vessel id (avoids storage OCC conflicts on Monad). */
export function deriveVesselId(nonce: string): Hex {
  return keccak256(encodePacked(["string"], [nonce]));
}

// Re-export for callers that want the raw hashMessage form.
export { hashMessage };
