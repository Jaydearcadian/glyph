import { JudgeConsole } from "@/components/judge-console";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { PageIntro, SectionHeading } from "@/components/ui";

const modes = [
  ["Pull · exact request", "A payer opens immutable terms, approves the exact maximum input, and escrows a one-time payment request.", "User wallet action"],
  ["Push · escrow proof", "A payer can fund Push escrow for proof, but fresh recipient claim needs authorized provider routing before it is executable.", "User wallet + operator route"],
  ["Reserved claim", "Provider routing and claimant signatures produce a reserved Push claim in the proven terminal lifecycle.", "Operator/proof action"],
  ["Expiry + recovery", "Every funded link binds a recovery wallet and explicit expiry before value moves.", "Evidence-only"],
] as const;

export default function LinksPage() {
  return <main className="page-shell"><div className="ledger-bg" /><div className="page-content">
    <PageIntro eyebrow="PUSH + PULL MODE ENGINE" title="Simple links. Exact terms." description="Create a Pull payment request URL first; the payer escrows only after opening the shared link. Push is shown as escrow/proof unless an authorized provider route exists." authority="User wallet + proof-backed terminal lifecycle" />
    <JudgeConsole />
    <SectionHeading eyebrow="MODE SYSTEM" title="Push and Pull are lifecycles, not buttons." copy="Every surface declares who can execute the next state transition and what proof is available." />
    <div className="grid-2">{modes.map(([title,copy,authority],index)=><article className="panel" key={title}><div className="panel-header"><h3>{title}</h3><StatusBadge tone={index < 2 ? "verified" : index === 2 ? "settled" : "neutral"}>{index < 2 ? "Live write" : index === 2 ? "Live proven" : "Bound"}</StatusBadge></div><p className="panel-copy">{copy}</p><AuthorityBadge>{authority}</AuthorityBadge></article>)}</div>
  </div></main>;
}
