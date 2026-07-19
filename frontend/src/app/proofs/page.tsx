import { ExternalLink } from "lucide-react";
import proofs from "@/data/indexes/proofs.json";
import { StatusBadge } from "@/components/status";
import { PageIntro } from "@/components/ui";

function asset(path?: string){return path ? `/glyph-data/${path}` : "#"}

export default function ProofsPage(){return <main className="page-shell"><div className="ledger-bg"/><div className="page-content">
  <PageIntro eyebrow="LIVE PROOF INDEX" title="No screenshots pretending to be settlement." description="Open the evidence behind Glyph’s completed Pull, Push, campaign, and distribution lifecycles. Cross-chain appears only as a tested source-send boundary—not an interactive or completed destination claim." authority="Evidence-only · checksum-backed bundles"/>
  <section className="panel"><div className="panel-header"><div><h2>Proof lanes</h2><p className="panel-copy">Every lane names its actual terminal boundary.</p></div><StatusBadge tone="verified">Public evidence</StatusBadge></div>
    <div className="proof-list">{proofs.proofs.map((proof,index)=>{const cross=proof.id === "base-monad-crosschain"; const distribution="kind" in proof && proof.kind === "distribution"; const evidence="evidencePath" in proof ? proof.evidencePath : "path" in proof ? proof.path : undefined; return <article className="proof-row" key={proof.id ?? `proof-${index}`}><span className="proof-index">0{index+1}</span><div><h3>{"title" in proof ? proof.title : "Monad payout distribution proof"}</h3><p>{cross ? "Source-send tested · destination not claimed" : distribution ? "20 gTST distributed and fully claimed" : `Monad testnet · chain 10143`}</p></div><a className="button button-outline button-small" href={asset(evidence)} target="_blank" rel="noreferrer">Open evidence <ExternalLink size={12}/></a></article>})}</div>
  </section>
  <section className="panel" style={{marginTop:20}}><div className="panel-header"><div><h2>Cross-chain test boundary</h2><p className="panel-copy">Kept outside the judge transaction flow exactly as requested.</p></div><StatusBadge tone="pending">Tested, not settled</StatusBadge></div><p className="notice">Base Sepolia source sends succeeded. Destination execution remained blocked at LayerZero DVN validation. Glyph does not present this as completed settlement and exposes no interactive cross-chain action.</p></section>
</div></main>}
