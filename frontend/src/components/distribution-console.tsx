"use client";

import { useEffect, useMemo, useState } from "react";
import { Copy, ExternalLink, LoaderCircle, Plus, Users } from "lucide-react";
import { decodeEventLog, formatEther, isAddress, parseUnits, type Address, type Hash } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import distribution from "@/data/indexes/distributions.json";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { contracts, formatToken, monadTestnet, shortHash, splitterAbi, testTokenAbi, txUrl } from "@/lib/glyph";

const CAMPAIGN_ID = "0xd4117f5899cab786974c733c07812ec19e3c0e8579fd15b33d92559c9d55b1e8" as Hash;
const PARENT_RECEIPT = "0x85a1c50b548e26a32765b87fe0413438a5033fa6e0c3205f8afcfd47ac5b665d" as Hash;
const TOTAL = parseUnits("20", 18);
const defaultSplits = [{ role:"Creator", address:"", bps:"7000" }, { role:"Collaborator", address:"", bps:"2000" }, { role:"Referrer", address:"", bps:"1000" }];

type Split = typeof defaultSplits[number];
type SharedPlan = { id: Hash; recipients: Address[]; bps: number[] };

function parseSharedPlan(): SharedPlan | undefined {
  const params = new URLSearchParams(window.location.hash.slice(1));
  const id = params.get("distribution");
  const recipients = (params.get("recipients") ?? "").split(",").filter(item => isAddress(item)) as Address[];
  const bps = (params.get("bps") ?? "").split(",").map(Number).filter(Number.isFinite);
  if (!id?.match(/^0x[0-9a-fA-F]{64}$/) || !recipients.length || recipients.length !== bps.length) return;
  return { id:id as Hash, recipients, bps };
}

export function DistributionConsole() {
  const { address, chainId } = useAccount();
  const client = usePublicClient({ chainId: monadTestnet.id });
  const { writeContractAsync } = useWriteContract();
  const [busy,setBusy] = useState<string>();
  const [claimTx,setClaimTx] = useState<Hash>();
  const [createTx,setCreateTx] = useState<Hash>();
  const [error,setError] = useState<string>();
  const [activeId,setActiveId] = useState<Hash>(contracts.distributionId);
  const [splits,setSplits] = useState<Split[]>(defaultSplits);
  const [sharedPlan,setSharedPlan] = useState<SharedPlan>();
  const [shareLink,setShareLink] = useState<string>();

  useEffect(()=>{ const timer = window.setTimeout(()=>{ const parsed=parseSharedPlan(); if(parsed){setSharedPlan(parsed);setActiveId(parsed.id);} },0); return ()=>window.clearTimeout(timer); },[]);

  const nativeBalance = useBalance({address,chainId:monadTestnet.id,query:{enabled:!!address&&chainId===monadTestnet.id}});
  const tokenBalance = useReadContract({address:contracts.token,abi:testTokenAbi,functionName:"balanceOf",args:address?[address]:undefined,query:{enabled:!!address&&chainId===monadTestnet.id}});
  const allowance = useReadContract({address:contracts.token,abi:testTokenAbi,functionName:"allowance",args:address?[address,contracts.splitter]:undefined,query:{enabled:!!address&&chainId===monadTestnet.id}});
  const totals = useReadContract({ address:contracts.splitter, abi:splitterAbi, functionName:"distributionTotals", args:[activeId], chainId:monadTestnet.id, query:{refetchInterval:10_000} });
  const walletShare = useReadContract({ address:contracts.splitter, abi:splitterAbi, functionName:"recipientShare", args:address?[activeId,address]:undefined, chainId:monadTestnet.id, query:{enabled:!!address,refetchInterval:10_000,retry:false} });
  const totalValues = Array.isArray(totals.data) ? totals.data as bigint[] : [];
  const share = Array.isArray(walletShare.data) ? walletShare.data : [];
  const shareAmount = typeof share[2] === "bigint" ? share[2] : BigInt(0);
  const claimable = !!address && shareAmount > BigInt(0) && share[3] === false;
  const recipientAddresses = useMemo(()=>splits.map(item=>item.address).filter(item=>isAddress(item)) as Address[],[splits]);
  const splitBps = useMemo(()=>splits.map(item=>Number(item.bps)),[splits]);
  const validPlan = recipientAddresses.length === splits.length && new Set(recipientAddresses.map(item=>item.toLowerCase())).size === splits.length && splitBps.every(item=>Number.isInteger(item)&&item>0) && splitBps.reduce((a,b)=>a+b,0)===10_000;
  const tokenValue = typeof tokenBalance.data === "bigint" ? tokenBalance.data : BigInt(0);
  const allowanceValue = typeof allowance.data === "bigint" ? allowance.data : BigInt(0);
  const hasGas = (nativeBalance.data?.value ?? BigInt(0)) > BigInt(0);

  function setSplit(index:number,key:"address"|"bps",value:string){setSplits(current=>current.map((item,i)=>i===index?{...item,[key]:value}:item));}
  async function execute(label:string,task:()=>Promise<void>){setBusy(label);setError(undefined);try{await task();}catch(cause){const message=cause instanceof Error?cause.message.split("\n")[0]:"Transaction failed.";setError(/gas|insufficient funds/i.test(message)?"Not enough testnet MON for gas. Fund the connected wallet and retry.":message);}finally{setBusy(undefined);}}

  async function approveSplitter(){if(!address||!client||chainId!==monadTestnet.id)return;await execute("approve",async()=>{const gas=await client.estimateContractGas({account:address,address:contracts.token,abi:testTokenAbi,functionName:"approve",args:[contracts.splitter,TOTAL]});const hash=await writeContractAsync({address:contracts.token,abi:testTokenAbi,functionName:"approve",args:[contracts.splitter,TOTAL],gas:gas+gas/BigInt(5),chainId:monadTestnet.id});await client.waitForTransactionReceipt({hash});await allowance.refetch();});}

  async function createDistribution(){if(!address||!client||chainId!==monadTestnet.id||!validPlan)return;await execute("create",async()=>{
    const input={campaignId:CAMPAIGN_ID,campaignContract:contracts.proofCampaign,token:contracts.token,totalAmount:TOTAL,recipients:recipientAddresses,bps:splitBps,parentCampaignReceiptHash:PARENT_RECEIPT,deadline:BigInt(Math.floor(Date.now()/1000)+86_400),recovery:address};
    const gas=await client.estimateContractGas({account:address,address:contracts.splitter,abi:splitterAbi,functionName:"createDistribution",args:[input]});
    const hash=await writeContractAsync({address:contracts.splitter,abi:splitterAbi,functionName:"createDistribution",args:[input],gas:gas+gas/BigInt(5),chainId:monadTestnet.id});
    const receipt=await client.waitForTransactionReceipt({hash});
    let created:Hash|undefined;
    for(const log of receipt.logs){if(log.address.toLowerCase()!==contracts.splitter.toLowerCase())continue;try{const decoded=decodeEventLog({abi:splitterAbi,data:log.data,topics:log.topics}) as unknown as {eventName:string;args:{distributionId?:Hash}};if(decoded.eventName==="DistributionCreated"){created=decoded.args.distributionId;break;}}catch{}}
    if(!created)throw new Error("Distribution confirmed but its ID could not be decoded.");
    const plan={id:created,recipients:recipientAddresses,bps:splitBps};setActiveId(created);setSharedPlan(plan);setCreateTx(hash);
    const link=`${location.origin}/distribution#distribution=${created}&recipients=${recipientAddresses.join(",")}&bps=${splitBps.join(",")}`;setShareLink(link);
    await Promise.all([allowance.refetch(),tokenBalance.refetch()]);
  });}

  async function claim(){if(!claimable||!client||chainId!==monadTestnet.id)return;await execute("claim",async()=>{const gas=await client.estimateContractGas({account:address,address:contracts.splitter,abi:splitterAbi,functionName:"claim",args:[activeId]});const hash=await writeContractAsync({address:contracts.splitter,abi:splitterAbi,functionName:"claim",args:[activeId],gas:gas+gas/BigInt(5),chainId:monadTestnet.id});await client.waitForTransactionReceipt({hash});await Promise.all([walletShare.refetch(),totals.refetch()]);setClaimTx(hash);});}

  const displayedRecipients = sharedPlan ? sharedPlan.recipients.map((recipient,index)=>({role:`Recipient ${index+1}`,recipient,bps:sharedPlan.bps[index],amount:(TOTAL*BigInt(sharedPlan.bps[index]))/BigInt(10_000),receipt:"",tx:""})) : distribution.claimReceipts.map(item=>({...item,amount:BigInt(item.amount)}));

  return <>
    <div className="grid-2"><section className="panel featured"><div className="panel-header"><div><h2>{activeId===contracts.distributionId?"20 gTST proof distribution":"Shared distribution"}</h2><p className="panel-copy">Every recipient address, percentage, and destination wallet is explicit.</p></div><StatusBadge tone={activeId===contracts.distributionId?"verified":"pending"}>{activeId===contracts.distributionId?"Fully claimed":"Live plan"}</StatusBadge></div><div className="split-bar"><span style={{width:"70%"}}/><span style={{width:"20%"}}/><span style={{width:"10%"}}/></div><DetailRow label="Total funded" value={`${formatToken(totalValues[0])} gTST`}/><DetailRow label="Total claimed" value={`${formatToken(totalValues[1])} gTST`}/><DetailRow label="Unclaimed" value={`${formatToken(totalValues[2])} gTST`}/><DetailRow label="Distribution ID" value={shortHash(activeId,12,10)} mono/></section>
      <section className="panel"><div className="panel-header"><div><h2>Your recipient state</h2><p className="panel-copy">Connect the exact listed recipient wallet. Funds transfer directly to that wallet when it claims.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div><DetailRow label="Connected wallet" value={address??"Connect wallet"} mono/><DetailRow label="Claim amount" value={address?`${formatToken(shareAmount)} gTST`:"—"}/><DetailRow label="Claimed" value={share[3]===true?"true":share[3]===false?"false":"Not a listed recipient"}/><div className="form-actions"><button className="button button-light" disabled={!claimable||!!busy||!hasGas} onClick={claim}>{busy==="claim"?<><LoaderCircle size={15}/> Claiming…</>:"Claim to connected wallet"}</button></div>{!claimable&&<p className="notice" style={{marginTop:18}}>Claims are enabled only for an unclaimed address listed below.</p>}{claimTx&&<p className="notice success-notice">Claim confirmed: <a href={txUrl(claimTx)} target="_blank" rel="noreferrer">{shortHash(claimTx)} <ExternalLink size={12} style={{display:"inline"}}/></a></p>}</section></div>

    <section className="panel" style={{marginTop:22}}><div className="panel-header"><div><h2>Recipient map</h2><p className="panel-copy">These are the exact wallets that receive funds—not aliases or hidden Merkle leaves.</p></div><Users size={20}/></div><div className="receipt-grid">{displayedRecipients.map((item,index)=><article className="receipt-card" key={item.recipient}><div className="receipt-top"><span>{item.role.toUpperCase()}</span><span>{item.bps/100}%</span></div><h3>{formatToken(item.amount)} gTST</h3><p className="mono recipient-address">{item.recipient}</p><button className="receipt-action" onClick={()=>navigator.clipboard.writeText(item.recipient)}><Copy size={12}/> Copy wallet</button>{"tx" in item&&item.tx&&<a className="receipt-action" href={txUrl(item.tx)} target="_blank" rel="noreferrer">Claim proof <ExternalLink size={12}/></a>}<span className="mono-label">Recipient {index+1} of {displayedRecipients.length}</span></article>)}</div></section>

    <section className="panel" style={{marginTop:22}}><div className="panel-header"><div><h2>Create a recipient-explicit demo distribution</h2><p className="panel-copy">Fund 20 gTST against the proven closed campaign and define exactly who receives 70/20/10.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div>
      <div className="recipient-editor">{splits.map((item,index)=><div className="recipient-edit-row" key={item.role}><div className="field"><label>{item.role} wallet</label><input value={item.address} onChange={event=>setSplit(index,"address",event.target.value)} placeholder="0x…"/></div><div className="field bps-field"><label>Basis points</label><input value={item.bps} onChange={event=>setSplit(index,"bps",event.target.value)} inputMode="numeric"/></div></div>)}</div>
      <div className="detail-row"><span>Split check</span><strong>{splitBps.reduce((a,b)=>a+(Number.isFinite(b)?b:0),0)/100}% · {validPlan?"valid":"needs unique wallets + 100%"}</strong></div><DetailRow label="Your gTST" value={`${formatToken(tokenValue)} gTST`}/><DetailRow label="Splitter allowance" value={`${formatToken(allowanceValue)} gTST`}/><DetailRow label="Gas" value={nativeBalance.data?.value?`${Number(formatEther(nativeBalance.data.value)).toFixed(4)} MON`:"Fund testnet MON"}/>
      <div className="form-actions"><button className="button button-outline" disabled={!address||!hasGas||tokenValue<TOTAL||!!busy} onClick={approveSplitter}>{busy==="approve"?"Preflighting + approving…":"Approve 20 gTST"}</button><button className="button button-light" disabled={!address||!hasGas||!validPlan||tokenValue<TOTAL||allowanceValue<TOTAL||!!busy} onClick={createDistribution}>{busy==="create"?"Preflighting + creating…":<><Plus size={14}/> Create distribution</>}</button></div>
      {error&&<p className="notice error-notice">{error}</p>}{createTx&&<p className="notice success-notice">Distribution created: <a href={txUrl(createTx)} target="_blank" rel="noreferrer">{shortHash(createTx)}</a></p>}{shareLink&&<div className="share-box"><div><span className="mono-label">SHARE WITH RECIPIENTS</span><p className="mono recipient-address">{shareLink}</p></div><button className="button button-outline button-small" onClick={()=>navigator.clipboard.writeText(shareLink)}><Copy size={13}/> Copy link</button></div>}
    </section>
  </>;
}
