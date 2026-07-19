import { DistributionConsole } from "@/components/distribution-console";
import { PageIntro } from "@/components/ui";

export default function DistributionPage(){return <main className="page-shell"><div className="ledger-bg"/><div className="page-content"><PageIntro eyebrow="EXPLICIT PAYOUT DISTRIBUTION" title="One campaign receipt. Three claimable shares." description="Inspect the live 70/20/10 payout split, read conservation directly from Monad, and claim only when your connected wallet is an eligible unclaimed recipient." authority="User-safe claims · proof-backed creation"/><DistributionConsole/></div></main>}
