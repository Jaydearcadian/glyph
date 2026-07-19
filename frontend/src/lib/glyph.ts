import type { Abi, Address, Hash } from "viem";
import { defineChain, formatUnits } from "viem";
import testTokenArtifact from "@/data/abi/TestToken.json";
import routerArtifact from "@/data/abi/SourceDeltaRouter.json";
import campaignArtifact from "@/data/abi/ContributionCampaign.json";
import splitterArtifact from "@/data/abi/CampaignPayoutSplitter.json";

export const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet-rpc.monad.xyz"] } },
  blockExplorers: { default: { name: "Monad Explorer", url: "https://testnet.monadexplorer.com" } },
  testnet: true,
});

export const contracts = {
  token: "0x1d482783316FdeF2e795A1C193ACE280660A887a" as Address,
  router: "0xC71C119B91Fa1F1861626843Fa653F41cEF9101A" as Address,
  vault: "0xfb2a436Cf72C6FbCc4cCd1A5A4Adef015F370Ca9" as Address,
  campaign: "0xc1734449aeca5e45E570afd862f47Ff0eE03bEd1" as Address,
  proofCampaign: "0x34ebCe467EcB6cA5D9f0E9d5bF3C23b9E2B191bb" as Address,
  splitter: "0x3f90710e945f1BFa07737B97676056DF3F92Db59" as Address,
  distributionId: "0xe91b66e0fd1df23dbd317fc1119202f2460458da2fc276a55627b342f87f888a" as Hash,
} as const;

export const testTokenAbi = ("abi" in testTokenArtifact ? testTokenArtifact.abi : testTokenArtifact) as Abi;
export const routerAbi = ("abi" in routerArtifact ? routerArtifact.abi : routerArtifact) as Abi;
export const campaignAbi = campaignArtifact as Abi;
export const splitterAbi = splitterArtifact as Abi;

export const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;
export const ZERO_HASH = `0x${"0".repeat(64)}` as Hash;
export const PULL_MODE = "0x50554c4c00000000000000000000000000000000000000000000000000000000" as Hash;
export const PUSH_MODE = "0x5055534800000000000000000000000000000000000000000000000000000000" as Hash;

export type Terms = {
  mode: Hash;
  programId: Hash;
  payer: Address;
  recipient: Address;
  recovery: Address;
  sourceAsset: Address;
  sourceChainId: bigint;
  destinationVault: Address;
  destinationAsset: Address;
  destinationChainId: bigint;
  maximumInput: bigint;
  destinationAmount: bigint;
  protocolFee: bigint;
  providerFee: bigint;
  referrerFee: bigint;
  gasSponsorFee: bigint;
  provider: Address;
  protocol: Address;
  referrer: Address;
  gasSponsor: Address;
  claimGatekeeper: Address;
  expiry: bigint;
  nonce: bigint;
};

export function shortHash(value?: string, head = 7, tail = 5) {
  if (!value) return "—";
  return `${value.slice(0, head)}…${value.slice(-tail)}`;
}

export function formatToken(value?: bigint | string, decimals = 18) {
  if (value === undefined) return "—";
  const raw = typeof value === "bigint" ? value : BigInt(value);
  return Number(formatUnits(raw, decimals)).toLocaleString(undefined, { maximumFractionDigits: 4 });
}

export function txUrl(hash: string) {
  return `${monadTestnet.blockExplorers.default.url}/tx/${hash}`;
}
