import { CampaignConsole } from "@/components/campaign-console";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { PageIntro, SectionHeading } from "@/components/ui";

const phases = [
  ["01", "Create terms", "Recipient, asset, threshold, contribution bounds, deadline, and payout mode are immutable."],
  ["02", "Fund child Pulls", "Each contributor funds a real Pull operation rather than a cosmetic progress bar."],
  ["03", "Reconcile receipts", "Terminal child receipts are collected into campaign accounting."],
  ["04", "Close with proof", "The aggregate receipt commits to the reconciled total and child receipt set."],
];

export default function CampaignPage() {
  return <main className="page-shell"><div className="ledger-bg"/><div className="page-content">
    <PageIntro eyebrow="CAMPAIGN AGGREGATION" title="Many contributions. One final receipt." description="Create bounded campaign terms with your wallet, then inspect the live two-contributor proof where child payment receipts resolve into one aggregate close receipt." authority="User-created terms · proof-backed reconciliation" />
    <CampaignConsole />
    <SectionHeading eyebrow="RECEIPT COMPOSITION" title="A campaign is a higher-order payment operation." />
    <div className="grid-2">{phases.map(([id,title,copy],index)=><article className="panel" key={id}><div className="panel-header"><span className="mono" style={{color:"var(--text-subtle)"}}>{id}</span><StatusBadge tone={index === 3 ? "settled" : "neutral"}>{index === 3 ? "Aggregate" : "Bound step"}</StatusBadge></div><h3>{title}</h3><p className="panel-copy">{copy}</p><AuthorityBadge>{index < 2 ? "User wallet action" : "Operator/proof action"}</AuthorityBadge></article>)}</div>
  </div></main>;
}
