import { cp, mkdir, rm } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(process.cwd(), "..");
const publicRoot = resolve(process.cwd(), "public/glyph-data/state");
const dataRoot = resolve(process.cwd(), "src/data");

await mkdir(resolve(dataRoot, "abi"), { recursive: true });
await mkdir(resolve(dataRoot, "indexes"), { recursive: true });
await rm(publicRoot, { recursive: true, force: true });
await mkdir(resolve(publicRoot, "frontend"), { recursive: true });

for (const name of ["TestToken", "SourceDeltaRouter", "ContributionCampaign", "CampaignPayoutSplitter"]) {
  await cp(resolve(root, `state/frontend/abi/${name}.json`), resolve(dataRoot, `abi/${name}.json`));
}
for (const [from, to] of [["receipts/index.json", "receipts.json"], ["proofs/index.json", "proofs.json"], ["distributions/index.json", "distributions.json"]]) {
  await cp(resolve(root, `state/frontend/${from}`), resolve(dataRoot, `indexes/${to}`));
}
await cp(resolve(root, "state/live"), resolve(publicRoot, "live"), { recursive: true });
for (const dir of ["receipts", "proofs", "distributions"]) {
  await cp(resolve(root, `state/frontend/${dir}`), resolve(publicRoot, `frontend/${dir}`), { recursive: true });
}
console.log("Synced Glyph ABIs and evidence artifacts.");
