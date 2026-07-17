// SPDX-License-Identifier: MIT
// Deploy GlyphRegistry to Monad Testnet. Prereqs in .env.testnet:
//   PRIVATE_KEY=0x...   DEPLOYER=0x...
// Fund the deployer via the Monad Testnet faucet first.
//
// Run:  node scripts/deploy.mjs   (from contracts/)
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";

const env = readFileSync(new URL("../.env.testnet", import.meta.url), "utf8")
  .split("\n")
  .filter(Boolean)
  .reduce<Record<string, string>>((acc, line) => {
    const [k, v] = line.split("=");
    if (k && v) acc[k.trim()] = v.trim();
    return acc;
  }, {});

const RPC = "https://testnet-rpc.monad.xyz";

if (!env.PRIVATE_KEY) {
  console.error("Missing PRIVATE_KEY in .env.testnet");
  process.exit(1);
}

console.log("Deploying GlyphRegistry to Monad Testnet…");
const out = execSync(
  `forge create --rpc-url ${RPC} --private-key ${env.PRIVATE_KEY} ` +
    `src/GlyphRegistry.sol:GlyphRegistry --broadcast --legacy`,
  { cwd: new URL("..", import.meta.url).pathname, encoding: "utf8" }
);
console.log(out);

const match = out.match(/Deployed to:\s*(0x[0-9a-fA-F]{40})/);
if (!match) {
  console.error("Could not parse deployed address.");
  process.exit(1);
}
const addr = match[1];
console.log(`\n✅ GlyphRegistry deployed at ${addr}`);
console.log(`Set VITE_GLYPH_REGISTRY=${addr} in frontend/.env.local`);
