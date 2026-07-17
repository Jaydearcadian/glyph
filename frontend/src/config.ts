import { defineChain } from "viem";

export const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://testnet-rpc.monad.xyz"] },
  },
  blockExplorers: {
    default: { name: "MonadScan", url: "https://testnet.monadscan.com" },
  },
  testnet: true,
});

// Set after `forge create` — see scripts/deploy.mjs / README.
export const GLYPH_REGISTRY_ADDRESS =
  (import.meta.env.VITE_GLYPH_REGISTRY as `0x${string}`) ??
  ("0x0000000000000000000000000000000000000000" as `0x${string}`);
