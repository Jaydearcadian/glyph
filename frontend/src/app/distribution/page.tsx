import { DistributionConsole } from "@/components/distribution-console";
import { PageIntro } from "@/components/ui";

export default function DistributionPage(){return <main className="page-shell"><div className="ledger-bg"/><div className="page-content"><PageIntro eyebrow="EXPLICIT PAYOUT DISTRIBUTION" title="Name every wallet before value moves." description="See the exact recipient addresses and amounts in the proven 70/20/10 payout, or create a new recipient-explicit demo distribution and send its claim link directly to those wallets." authority="User-created recipients · direct wallet claims"/><DistributionConsole/></div></main>}
