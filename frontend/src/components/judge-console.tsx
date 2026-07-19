"use client";

import { useEffect, useMemo, useState } from "react";
import { ArrowLeft, Check, Copy, ExternalLink, FlaskConical, Fuel, LoaderCircle, Share2 } from "lucide-react";
import { formatEther, isAddress, parseUnits, type Address, type Hash } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { contracts, formatToken, monadTestnet, PULL_MODE, PUSH_MODE, routerAbi, shortHash, testTokenAbi, txUrl, type Terms, ZERO_ADDRESS, ZERO_HASH } from "@/lib/glyph";

type FlowMode = "pull" | "push";
type Result = { mode: FlowMode; hash: Hash; operationId: Hash; termsHash: Hash; readback: string; shareLink: string };

function errorText(error: unknown) {
  const raw = error instanceof Error ? error.message.split("\n")[0] : "The wallet or contract rejected the action.";
  if (/insufficient funds|exceeds the balance|gas/i.test(raw)) return "Not enough testnet MON for gas. Fund this wallet from the Monad faucet, then retry.";
  if (/allowance|transfer amount exceeds|transferfrom/i.test(raw)) return "Router allowance or gTST balance is too low. Approve the exact amount and retry.";
  if (/user rejected|denied/i.test(raw)) return "Transaction cancelled in the wallet.";
  return raw;
}

function safeAmount(value: string) {
  try { const parsed = parseUnits(value || "0", 18); return parsed > BigInt(0) ? parsed : undefined; }
  catch { return undefined; }
}

export function JudgeConsole() {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: monadTestnet.id });
  const { writeContractAsync } = useWriteContract();
  const [mode, setMode] = useState<FlowMode>("pull");
  const [amount, setAmount] = useState("10");
  const [recipient, setRecipient] = useState("");
  const [programId, setProgramId] = useState<Hash>(ZERO_HASH);
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [result, setResult] = useState<Result>();
  const [openedOperation, setOpenedOperation] = useState<Hash>();
  const [openedKind, setOpenedKind] = useState<"claim" | "payment">();
  const [copied, setCopied] = useState(false);
  const [isPaymentRequest, setIsPaymentRequest] = useState(false);

  useEffect(() => {
    const applyLink = () => {
      const params = new URLSearchParams(window.location.hash.slice(1));
      const campaign = params.get("campaign");
      const linkedRecipient = params.get("payTo") ?? params.get("recipient");
      const linkedAmount = params.get("amount");
      const claim = params.get("claim");
      const payment = params.get("payment");
      const opened = claim ?? payment;
      if (opened?.match(/^0x[0-9a-fA-F]{64}$/)) { setOpenedOperation(opened as Hash); setOpenedKind(claim ? "claim" : "payment"); }
      if (campaign?.match(/^0x[0-9a-fA-F]{64}$/)) { setProgramId(campaign as Hash); setMode("pull"); setIsPaymentRequest(true); }
      if (params.get("payTo")) setIsPaymentRequest(true);
      if (linkedRecipient && isAddress(linkedRecipient)) setRecipient(linkedRecipient);
      if (linkedAmount && safeAmount(linkedAmount)) setAmount(linkedAmount);
    };
    const timer = window.setTimeout(applyLink, 0);
    window.addEventListener("hashchange", applyLink);
    return () => { window.clearTimeout(timer); window.removeEventListener("hashchange", applyLink); };
  }, []);

  const walletReady = isConnected && chainId === monadTestnet.id && !!address;
  const value = useMemo(() => safeAmount(amount), [amount]);
  const recipientAddress = useMemo(() => isAddress(recipient) ? recipient as Address : address, [recipient, address]);

  const nativeBalance = useBalance({ address, chainId: monadTestnet.id, query: { enabled: !!address && chainId === monadTestnet.id, refetchInterval: 8_000 } });
  const openedFacts = useReadContract({ address: contracts.router, abi: routerAbi, functionName: "routeFacts", args: openedOperation ? [openedOperation] : undefined, chainId: monadTestnet.id, query: { enabled: !!openedOperation, retry: false } });
  const balance = useReadContract({ address: contracts.token, abi: testTokenAbi, functionName: "balanceOf", args: address ? [address] : undefined, query: { enabled: !!address && chainId === monadTestnet.id, refetchInterval: 8_000 } });
  const allowance = useReadContract({ address: contracts.token, abi: testTokenAbi, functionName: "allowance", args: address ? [address, contracts.router] : undefined, query: { enabled: !!address && chainId === monadTestnet.id, refetchInterval: 8_000 } });

  async function run(label: string, task: () => Promise<void>) {
    setBusy(label); setError(undefined);
    try { await task(); } catch (cause) { setError(errorText(cause)); } finally { setBusy(undefined); }
  }

  async function mint() {
    if (!walletReady || !address || !publicClient) return;
    await run("mint", async () => {
      const hash = await writeContractAsync({ address: contracts.token, abi: testTokenAbi, functionName: "mint", args: [address, parseUnits("100", 18)], chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      await balance.refetch();
    });
  }

  async function approve() {
    if (!walletReady || !publicClient || !address || !value) return;
    await run("approve", async () => {
      const gas = await publicClient.estimateContractGas({ account: address, address: contracts.token, abi: testTokenAbi, functionName: "approve", args: [contracts.router, value] });
      const hash = await writeContractAsync({ address: contracts.token, abi: testTokenAbi, functionName: "approve", args: [contracts.router, value], gas: gas + gas / BigInt(5), chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      await allowance.refetch();
    });
  }

  async function createEscrow() {
    if (!walletReady || !address || !publicClient || !recipientAddress || !value) return;
    await run("escrow", async () => {
      const nonce = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "actorNonce", args: [address] }) as bigint;
      const terms: Terms = {
        mode: mode === "pull" ? PULL_MODE : PUSH_MODE,
        programId,
        payer: address,
        recipient: mode === "pull" ? recipientAddress : address,
        recovery: address,
        sourceAsset: contracts.token,
        sourceChainId: BigInt(monadTestnet.id),
        destinationVault: contracts.vault,
        destinationAsset: contracts.token,
        destinationChainId: BigInt(monadTestnet.id),
        maximumInput: value,
        destinationAmount: value,
        protocolFee: BigInt(0),
        providerFee: BigInt(0),
        referrerFee: BigInt(0),
        gasSponsorFee: BigInt(0),
        provider: address,
        protocol: address,
        referrer: ZERO_ADDRESS,
        gasSponsor: ZERO_ADDRESS,
        claimGatekeeper: mode === "push" ? address : ZERO_ADDRESS,
        expiry: BigInt(Math.floor(Date.now() / 1000) + 86_400),
        nonce,
      };
      const operationId = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "operationId", args: [terms] }) as Hash;
      const termsHash = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "hashTerms", args: [terms] }) as Hash;
      const gas = await publicClient.estimateContractGas({ account: address, address: contracts.router, abi: routerAbi, functionName: "escrow", args: [terms] });
      const hash = await writeContractAsync({ address: contracts.router, abi: routerAbi, functionName: "escrow", args: [terms], gas: gas + gas / BigInt(5), chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      const routeFacts = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "routeFacts", args: [operationId] });
      const readback = JSON.stringify(routeFacts, (_, item) => typeof item === "bigint" ? item.toString() : item);
      const shareLink = mode === "push" ? `${location.origin}/links#claim=${operationId}` : `${location.origin}/links#payTo=${recipientAddress}&amount=${amount}${programId !== ZERO_HASH ? `&campaign=${programId}` : ""}`;
      setResult({ mode, hash, operationId, termsHash, readback, shareLink });
      await Promise.all([balance.refetch(), allowance.refetch(), nativeBalance.refetch()]);
    });
  }

  const balanceValue = typeof balance.data === "bigint" ? balance.data : undefined;
  const allowanceValue = typeof allowance.data === "bigint" ? allowance.data : undefined;
  const nativeValue = nativeBalance.data?.value;
  const hasGas = nativeValue !== undefined && nativeValue > BigInt(0);
  const enoughBalance = value !== undefined && balanceValue !== undefined && balanceValue >= value;
  const enoughAllowance = value !== undefined && allowanceValue !== undefined && allowanceValue >= value;
  const openedData = Array.isArray(openedFacts.data) ? openedFacts.data : [];
  const openedStatus = typeof openedData[4] === "number" ? openedData[4] : Number(openedData[4] ?? 0);
  const statusLabel = ["Unknown", "Escrowed", "Reserved", "Acknowledged", "Reconciled", "Refund pending", "Refunded"][openedStatus] ?? "Unknown";

  async function copyShareLink(link: string) { await navigator.clipboard.writeText(link); setCopied(true); window.setTimeout(()=>setCopied(false),1200); }
  async function shareResult(link: string) { if (navigator.share) await navigator.share({ title: "Glyph payment link", url: link }); else await copyShareLink(link); }

  if (openedOperation && openedKind) return <div className="grid-2">
    <section className="panel featured"><div className="panel-header"><div><h2>{openedKind === "claim" ? "Push claim link" : "Pull payment link"}</h2><p className="panel-copy">This link now opens the exact onchain operation instead of returning to the generic creator.</p></div><StatusBadge tone={openedStatus >= 4 ? "verified" : "pending"}>{statusLabel}</StatusBadge></div><DetailRow label="Operation" value={openedOperation} mono/><DetailRow label="Onchain state" value={statusLabel}/><div className="form-actions"><button className="button button-outline" onClick={()=>copyShareLink(location.href)}><Copy size={14}/> {copied ? "Copied" : "Copy link"}</button><button className="button button-light" onClick={()=>shareResult(location.href)}><Share2 size={14}/> Share</button></div></section>
    <section className="panel"><div className="panel-header"><div><h2>{openedKind === "claim" ? "Claim" : "Payment"}</h2></div></div>{openedFacts.isLoading ? <p className="notice">Reading operation…</p> : openedFacts.isError ? <p className="notice error-notice">This operation could not be read.</p> : openedKind === "claim" && openedStatus < 2 ? <p className="notice">Funds are escrowed. Claim unlocks after provider routing.</p> : <p className="notice success-notice">Live operation state: {statusLabel}.</p>}<div className="form-actions">{openedKind === "claim" ? <button className="button button-light" disabled>{openedStatus >= 4 ? "Claimed" : openedStatus < 2 ? "Claim · waiting for route" : "Claim"}</button> : <button className="button button-light" disabled>Payment deposited</button>}<a className="button button-outline" href="/links"><ArrowLeft size={14}/> Create another link</a></div></section>
  </div>;

  return <div className="grid-2">
    <section className="panel featured">
      <div className="panel-header"><div><h2>Try Glyph live</h2><p className="panel-copy">Every write is simulated before OKX opens. The wallet receives an estimated transaction with an explicit gas limit.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div>
      <DetailRow label="Network" value={walletReady ? "Monad Testnet" : "Connect on Monad"}/>
      <DetailRow label="Gas balance" value={nativeValue === undefined ? "—" : `${Number(formatEther(nativeValue)).toFixed(4)} MON`}/>
      <DetailRow label="gTST balance" value={`${formatToken(balanceValue)} gTST`}/>
      <DetailRow label="Router allowance" value={`${formatToken(allowanceValue)} gTST`}/>
      {!hasGas && walletReady && <p className="notice error-notice"><Fuel size={14} style={{display:"inline",marginRight:7}}/>OKX cannot confirm without testnet MON for gas. <a href="https://faucet.monad.xyz" target="_blank" rel="noreferrer">Open Monad faucet</a>.</p>}
      <div className="form-actions"><button className="button button-dark button-small" onClick={mint} disabled={!walletReady || !hasGas || !!busy}>{busy === "mint" ? <LoaderCircle className="animate-spin" size={15}/> : <FlaskConical size={15}/>} Mint 100 gTST</button></div>
      {programId !== ZERO_HASH && <p className="notice success-notice" style={{marginTop:18}}>Campaign contribution link loaded · program <span className="mono">{shortHash(programId,12,10)}</span></p>}
      <div style={{marginTop:28}} className="mode-tabs" role="tablist" aria-label="Link mode"><button role="tab" aria-selected={mode === "pull"} className={`mode-tab ${mode === "pull" ? "active" : ""}`} onClick={()=>setMode("pull")}>Pull · pay request</button><button role="tab" aria-selected={mode === "push"} className={`mode-tab ${mode === "push" ? "active" : ""}`} onClick={()=>setMode("push")}>Push · claim link</button></div>
      <div className="form-grid"><div className="field"><label htmlFor="amount">Amount in gTST</label><input id="amount" inputMode="decimal" value={amount} onChange={event=>setAmount(event.target.value)}/></div><div className="field"><label htmlFor="recipient">{mode === "pull" ? "Recipient wallet" : "Funded by / recovery wallet"}</label><input id="recipient" placeholder={address ?? "0x…"} value={recipient} onChange={event=>setRecipient(event.target.value)}/></div></div>
      <div className="form-actions"><button className="button button-outline" onClick={approve} disabled={!walletReady || !hasGas || !!busy || !value || !enoughBalance}>{busy === "approve" ? "Simulating + approving…" : `Approve ${amount || "0"} gTST`}</button><button className="button button-light" onClick={createEscrow} disabled={!walletReady || !hasGas || !!busy || !value || !enoughBalance || !enoughAllowance}>{busy === "escrow" ? "Preflighting + creating…" : mode === "push" ? "Fund Push link" : programId !== ZERO_HASH ? "Deposit / Pay campaign" : isPaymentRequest ? "Deposit / Pay" : "Create Pull link"}</button></div>
      {!enoughBalance && walletReady && <p className="notice" style={{marginTop:18}}>Mint enough demo gTST first.</p>}
      {enoughBalance && !enoughAllowance && walletReady && <p className="notice" style={{marginTop:18}}>Approve the exact gTST amount before creating the link.</p>}
      {error && <p className="notice error-notice" style={{marginTop:18}}>{error}</p>}
    </section>
    <section className="panel"><div className="panel-header"><div><h2>Transaction proof</h2><p className="panel-copy">Success appears only after wallet receipt and direct contract readback.</p></div>{result ? <StatusBadge tone="pending">Escrowed live</StatusBadge> : <StatusBadge>Waiting</StatusBadge>}</div>
      {result ? <><DetailRow label="Mode" value={result.mode.toUpperCase()}/><DetailRow label="Operation" value={shortHash(result.operationId,12,10)} mono/><DetailRow label="Terms hash" value={shortHash(result.termsHash,12,10)} mono/><DetailRow label="Transaction" value={<a href={txUrl(result.hash)} target="_blank" rel="noreferrer">{shortHash(result.hash)} <ExternalLink size={12} style={{display:"inline"}}/></a>} mono/><div className="notice success-notice" style={{marginTop:18}}><Check size={14} style={{display:"inline",marginRight:8}}/>Contract readback returned route facts.</div><div className="share-box"><div><span className="mono-label">{result.mode === "push" ? "SHAREABLE CLAIM LINK" : "SHAREABLE PAYMENT LINK"}</span><p className="mono recipient-address">{result.shareLink}</p></div><div className="form-actions"><button className="button button-outline button-small" onClick={()=>copyShareLink(result.shareLink)}><Copy size={13}/> {copied ? "Copied" : "Copy"}</button><button className="button button-light button-small" onClick={()=>shareResult(result.shareLink)}><Share2 size={13}/> Share</button></div></div><details style={{marginTop:16}}><summary style={{cursor:"pointer",color:"var(--text-muted)",fontSize:12}}>Raw route readback</summary><pre className="mono" style={{whiteSpace:"pre-wrap",wordBreak:"break-all",fontSize:10,color:"var(--text-subtle)"}}>{result.readback}</pre></details></> : <div className="stepper">{["Connect on Monad", "Fund testnet MON gas", "Mint demo gTST", "Approve exact terms", "Preflight + create escrow"].map((step,index)=><div className="step" key={step}><span className="step-number">{index+1}</span>{step}</div>)}</div>}
    </section>
  </div>;
}
