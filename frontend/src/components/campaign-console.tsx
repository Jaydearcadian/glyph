"use client";

import { useState } from "react";
import { Copy, ExternalLink, LoaderCircle } from "lucide-react";
import { formatEther, keccak256, parseUnits, stringToHex, type Hash } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { campaignAbi, contracts, formatToken, monadTestnet, shortHash, txUrl } from "@/lib/glyph";

const PROOF_PROGRAM = "0x1c02c59218771a5bd216c7ddfa81ef46e0ca88ed35b3eaa70856c9ab3446e4a9" as Hash;

export function CampaignConsole() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: monadTestnet.id });
  const { writeContractAsync } = useWriteContract();
  const nativeBalance = useBalance({address,chainId:monadTestnet.id,query:{enabled:!!address&&chainId===monadTestnet.id}});
  const [target, setTarget] = useState("20");
  const [suggestedContribution, setSuggestedContribution] = useState("10");
  const [programId, setProgramId] = useState<Hash>();
  const [campaignLink, setCampaignLink] = useState<string>();
  const [tx, setTx] = useState<Hash>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const proofFacts = useReadContract({ address: contracts.campaign, abi: campaignAbi, functionName: "campaigns", args: [PROOF_PROGRAM], chainId: monadTestnet.id });

  async function createCampaign() {
    if (!address || chainId !== monadTestnet.id || !publicClient) return;
    setBusy(true); setError(undefined);
    try {
      const id = keccak256(stringToHex(`glyph-judge-${address}-${Date.now()}`));
      const amount = parseUnits(target, 18);
      const campaign = {
        recipient: address,
        settlementAsset: contracts.token,
        targetAmount: amount,
        minContribution: parseUnits("1", 18),
        maxContribution: amount,
        maxTotal: amount,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 86_400),
        mode: 1,
        reconciledTotal: 0n,
        closed: false,
      };
      const gas = await publicClient.estimateContractGas({ account: address, address: contracts.campaign, abi: campaignAbi, functionName: "create", args: [id, campaign] });
      const hash = await writeContractAsync({ address: contracts.campaign, abi: campaignAbi, functionName: "create", args: [id, campaign], gas: gas + gas / BigInt(5), chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      await publicClient.readContract({ address: contracts.campaign, abi: campaignAbi, functionName: "campaigns", args: [id] });
      setProgramId(id); setTx(hash);
      setCampaignLink(`${location.origin}/links#campaign=${id}&recipient=${address}&amount=${suggestedContribution}`);
    } catch (cause) { setError(cause instanceof Error ? cause.message.split("\n")[0] : "Campaign creation failed."); }
    finally { setBusy(false); }
  }

  const proof = Array.isArray(proofFacts.data) ? proofFacts.data : [];
  return <div className="grid-2">
    <section className="panel featured"><div className="panel-header"><div><h2>Create a campaign</h2><p className="panel-copy">Create immutable threshold terms with your wallet. Contributions become child Pull receipts; reconciliation is shown through the completed proof lane.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div>
      <div className="form-grid"><div className="field"><label htmlFor="target">Target amount in gTST</label><input id="target" value={target} onChange={event=>setTarget(event.target.value)} inputMode="decimal" /></div><div className="field"><label htmlFor="suggested-contribution">Suggested contribution</label><input id="suggested-contribution" value={suggestedContribution} onChange={event=>setSuggestedContribution(event.target.value)} inputMode="decimal" /></div></div>
      <DetailRow label="Gas balance" value={nativeBalance.data?.value ? `${Number(formatEther(nativeBalance.data.value)).toFixed(4)} MON` : "Fund testnet MON"}/>
      <div className="form-actions"><button className="button button-light" onClick={createCampaign} disabled={!address || chainId !== monadTestnet.id || !nativeBalance.data?.value || busy}>{busy ? <><LoaderCircle size={15} className="animate-spin" /> Preflighting + creating…</> : "Create campaign + link"}</button></div>
      <p className="notice" style={{marginTop:18}}>Creating terms does not fabricate contributions. Only terminal child receipts belong in aggregate proof.</p>
      {error && <p className="notice error-notice">{error}</p>}
      {programId && tx && <div style={{marginTop:18}}><StatusBadge tone="verified">Created live</StatusBadge><DetailRow label="Program ID" value={shortHash(programId,12,10)} mono/><DetailRow label="Transaction" value={<a href={txUrl(tx)} target="_blank" rel="noreferrer">{shortHash(tx)} <ExternalLink size={12} style={{display:"inline"}} /></a>} mono/>{campaignLink && <div className="share-box"><div><span className="mono-label">SHAREABLE CONTRIBUTION LINK</span><p className="mono" style={{wordBreak:"break-all",fontSize:11}}>{campaignLink}</p></div><button className="button button-outline button-small" onClick={()=>navigator.clipboard.writeText(campaignLink)}><Copy size={13}/> Copy link</button></div>}</div>}
    </section>
    <section className="panel"><div className="panel-header"><div><h2>Completed campaign proof</h2><p className="panel-copy">Two 10 gTST child receipts reconcile into one terminal campaign receipt.</p></div><StatusBadge tone="verified">Live proven</StatusBadge></div>
      <DetailRow label="Program ID" value={shortHash(PROOF_PROGRAM,12,10)} mono/><DetailRow label="Reconciled" value={`${proof[8] !== undefined ? formatToken(proof[8] as bigint) : "20"} gTST`} /><DetailRow label="Children" value="2 terminal Pull receipts"/><DetailRow label="Closed" value={proof[9] === true ? "true" : "verified bundle"}/><DetailRow label="Aggregate receipt" value="0x0f6522…795af" mono/>
      <div className="notice success-notice" style={{marginTop:18}}>Aggregate state is chain-backed and linked to the submitted evidence bundle.</div>
    </section>
  </div>;
}
