import { ExternalLink, FileJson2, QrCode, ReceiptText } from "lucide-react";
import receipts from "@/data/indexes/receipts.json";
import { StatusBadge } from "@/components/status";
import { DetailRow, PageIntro } from "@/components/ui";
import { shortHash } from "@/lib/glyph";

function asset(path?: string) { return path ? `/glyph-data/${path}` : "#"; }

export default function ReceiptsPage(){return <main className="page-shell"><div className="ledger-bg"/><div className="page-content">
  <PageIntro eyebrow="RECEIPT LEDGER" title="Proof you can open, scan, and verify." description="Every showcased artifact resolves to structured JSON, a human-readable receipt card, a shareable link payload, and a QR proof surface." authority="Evidence-only · live transaction backed"/>
  <div className="receipt-grid">{receipts.receipts.map(receipt=><article className="receipt-card" key={receipt.operationId}>
    <div className="receipt-top"><span>GLYPH RECEIPT</span><StatusBadge tone={receipt.status === "RECONCILED" || receipt.status === "CLAIMED" ? "verified" : "pending"}>{receipt.status}</StatusBadge></div>
    <h3>{receipt.label}</h3><p>{receipt.mode} · {receipt.topology}</p>
    <DetailRow label="Operation" value={shortHash(receipt.operationId,12,10)} mono/><DetailRow label="Receipt" value={shortHash("finalReceiptHash" in receipt ? receipt.finalReceiptHash : receipt.receiptHash,12,10)} mono/><DetailRow label="Status" value={receipt.status}/>
    <div className="receipt-actions"><a className="receipt-action" href={asset(receipt.jsonPath)} target="_blank"><FileJson2 size={13}/> JSON</a><a className="receipt-action" href={asset(receipt.cardPath)} target="_blank"><ReceiptText size={13}/> Card</a><a className="receipt-action" href={asset(receipt.qrPath)} target="_blank"><QrCode size={13}/> QR</a><a className="receipt-action" href={asset(receipt.linkPath)} target="_blank">Link <ExternalLink size={12}/></a></div>
  </article>)}</div>
</div></main>}
