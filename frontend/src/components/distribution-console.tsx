"use client";

import { useState } from "react";
import { ExternalLink, LoaderCircle } from "lucide-react";
import { useAccount, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import distribution from "@/data/indexes/distributions.json";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { contracts, formatToken, monadTestnet, shortHash, splitterAbi, txUrl } from "@/lib/glyph";

export function DistributionConsole() {
  const { address, chainId } = useAccount();
  const client = usePublicClient({ chainId: monadTestnet.id });
  const { writeContractAsync } = useWriteContract();
  const [busy,setBusy] = useState(false);
  const [claimTx,setClaimTx] = useState<string>();
  const [error,setError] = useState<string>();
  const totals = useReadContract({ address: contracts.splitter, abi: splitterAbi, functionName: "distributionTotals", args: [contracts.distributionId], chainId: monadTestnet.id, query: { refetchInterval: 10_000 } });
  const walletShare = useReadContract({ address: contracts.splitter, abi: splitterAbi, functionName: "recipientShare", args: address ? [contracts.distributionId,address] : undefined, chainId: monadTestnet.id, query:{enabled:!!address,refetchInterval:10_000} });
  const totalValues = Array.isArray(totals.data) ? totals.data as bigint[] : [];
  const share = Array.isArray(walletShare.data) ? walletShare.data : [];
  const shareAmount = typeof share[2] === "bigint" ? share[2] : BigInt(0);
  const claimable = !!address && shareAmount > BigInt(0) && share[3] === false;

  async function claim() {
    if (!claimable || !client || chainId !== monadTestnet.id) return;
    setBusy(true); setError(undefined);
    try {
      const hash = await writeContractAsync({address:contracts.splitter,abi:splitterAbi,functionName:"claim",args:[contracts.distributionId],chainId:monadTestnet.id});
      await client.waitForTransactionReceipt({hash});
      await Promise.all([walletShare.refetch(),totals.refetch()]);
      setClaimTx(hash);
    } catch(cause){setError(cause instanceof Error ? cause.message.split("\n")[0] : "Claim failed.");} finally {setBusy(false);}
  }

  return <>
    <div className="grid-2">
      <section className="panel featured"><div className="panel-header"><div><h2>20 gTST distribution</h2><p className="panel-copy">A closed campaign branches into three bounded, explicit recipient claims.</p></div><StatusBadge tone="verified">Fully claimed</StatusBadge></div>
        <div className="split-bar" aria-label="70 percent creator, 20 percent collaborator, 10 percent referrer"><span style={{width:"70%"}}/><span style={{width:"20%"}}/><span style={{width:"10%"}}/></div>
        <DetailRow label="Total funded" value={`${formatToken(totalValues[0] ?? "20000000000000000000")} gTST`}/><DetailRow label="Total claimed" value={`${formatToken(totalValues[1] ?? "20000000000000000000")} gTST`}/><DetailRow label="Unclaimed" value={`${formatToken(totalValues[2] ?? "0")} gTST`}/><DetailRow label="Recovered" value={`${formatToken(totalValues[3] ?? "0")} gTST`}/><DetailRow label="Distribution ID" value={shortHash(contracts.distributionId,12,10)} mono/>
      </section>
      <section className="panel"><div className="panel-header"><div><h2>Your recipient state</h2><p className="panel-copy">The claim button is enabled only when the connected wallet has an unclaimed share.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div>
        <DetailRow label="Connected share" value={address ? `${formatToken(share[2] as bigint | undefined)} gTST` : "Connect wallet"}/><DetailRow label="BPS" value={share[1] !== undefined ? String(share[1]) : "—"}/><DetailRow label="Claimed" value={share[3] === true ? "true" : share[3] === false ? "false" : "—"}/>
        <div className="form-actions"><button className="button button-light" disabled={!claimable || busy} onClick={claim}>{busy ? <><LoaderCircle size={15}/> Claiming…</> : "Claim eligible share"}</button></div>
        {!claimable && <p className="notice" style={{marginTop:18}}>The known live recipients already claimed. This control fails closed for ineligible wallets; it never simulates a payout.</p>}
        {error && <p className="notice error-notice">{error}</p>}{claimTx && <p className="notice success-notice">Claim confirmed: <a href={txUrl(claimTx)} target="_blank" rel="noreferrer">{shortHash(claimTx)} <ExternalLink size={12} style={{display:"inline"}}/></a></p>}
      </section>
    </div>
    <div className="receipt-grid" style={{marginTop:22}}>{distribution.claimReceipts.map(item=><article className="receipt-card" key={item.role}><div className="receipt-top"><span>{item.role.toUpperCase()} CLAIM</span><span>{item.bps/100}%</span></div><h3>{formatToken(item.amount)} gTST</h3><p>Explicit recipient distribution receipt</p><DetailRow label="Recipient" value={shortHash(item.recipient)} mono/><DetailRow label="Receipt" value={shortHash(item.receipt)} mono/><div className="receipt-actions"><a className="receipt-action" href={txUrl(item.tx)} target="_blank" rel="noreferrer">Explorer <ExternalLink size={12}/></a></div></article>)}</div>
  </>;
}
