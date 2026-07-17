// SPDX-License-Identifier: MIT
// control_client.ts — EIP-7702 emergency undelegation (DESIGN; not run)
//
// CORRECTION vs manifest: the manifest's Type-4 (0x04) undelegation is CORRECT.
// EIP-7702 authorizations ride in type-4 transactions; setting contractAddress = 0x00...
// wipes the delegated code, reverting the EOA to pristine.
//
// The manifest's TS had a type bug (`compromisedKey: 0x${string}`) and called
// signAuthorization with the paymaster as sender. Fixed below: the COMPROMISED account
// signs the auth tuple; the SPONSOR broadcasts the 0x04 tx.

import { createWalletClient, http, type Hex } from "viem";
import { monadTestnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

export async function absoluteVesselRevocation(compromisedKey: Hex, gasPayerKey: Hex): Promise<Hex> {
  const compromisedAccount = privateKeyToAccount(compromisedKey);
  const paymasterAccount = privateKeyToAccount(gasPayerKey);

  const walletClientPaymaster = createWalletClient({
    account: paymasterAccount,
    chain: monadTestnet,
    transport: http(),
  });

  // 1. Compromised account signs the zero-address auth tuple (detaches its code).
  const authorization = await compromisedAccount.signAuthorization({
    contractAddress: "0x0000000000000000000000000000000000000000", // hard reset
    chainId: monadTestnet.id,
  } as any);

  // 2. Sponsor broadcasts the type-4 (0x04) set-code tx.
  const hash = await walletClientPaymaster.sendTransaction({
    to: compromisedAccount.address,
    authorizationList: [authorization],
    data: "0x",
  });

  return hash; // on-chain tx hash of the clean undelegation
}
