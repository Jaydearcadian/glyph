"use client";

import { useEffect, useMemo, useState } from "react";
import { Check, Copy, ExternalLink, FlaskConical, Fuel, LoaderCircle } from "lucide-react";
import { formatEther, isAddress, parseUnits, type Address, type Hash } from "viem";
import { useAccount, useBalance, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { contracts, formatToken, monadTestnet, PULL_MODE, PUSH_MODE, routerAbi, shortHash, testTokenAbi, txUrl, type Terms, ZERO_ADDRESS, ZERO_HASH } from "@/lib/glyph";

type FlowMode = "pull" | "push";
type Result = { mode: FlowMode; hash: Hash; operationId: Hash; termsHash: Hash; readback: string; claimLink?: string };

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

  useEffect(() => {
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams(window.location.hash.slice(1));
      const campaign = params.get("campaign");
      const linkedRecipient = params.get("recipient");
      const linkedAmount = params.get("amount");
      if (campaign?.match(/^0x[0-9a-fA-F]{64}$/)) { setProgramId(campaign as Hash); setMode("pull"); }
      if (linkedRecipient && isAddress(linkedRecipient)) setRecipient(linkedRecipient);
      if (linkedAmount && safeAmount(linkedAmount)) setAmount(linkedAmount);
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  const walletReady = isConnected && chainId === monadTestnet.id && !!address;
  const value = useMemo(() => safeAmount(amount), [amount]);
  const recipientAddress = useMemo(() => isAddress(recipient) ? recipient as Address : address, [recipient, address]);

  const nativeBalance = useBalance({ address, chainId: monadTestnet.id, query: { enabled: !!address && chainId === monadTestnet.id, refetchInterval: 8_000 } });
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
      let claimLink: string | undefined;
      if (mode === "push") {
        const secret = new Uint8Array(24); crypto.getRandomValues(secret);
        const encoded = Array.from(secret, byte => byte.toString(16).padStart(2, "0")).join("");
        claimLink = `${location.origin}/links#claim=${operationId}&key=${encoded}`;
      }
      setResult({ mode, hash, operationId, termsHash, readback, claimLink });
      await Promise.all([balance.refetch(), allowance.refetch(), nativeBalance.refetch()]);
    });
  }

  const balanceValue = typeof balance.data === "bigint" ? balance.data : undefined;
  const allowanceValue = typeof allowance.data === "bigint" ? allowance.data : undefined;
  const nativeValue = nativeBalance.data?.value;
  const hasGas = nativeValue !== undefined && nativeValue > BigInt(0);
  const enoughBalance = value !== undefined && balanceValue !== undefined && balanceValue >= value;
  const enoughAllowance = value !== undefined && allowanceValue !== undefined && allowanceValue >= value;

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
      <div className="form-actions"><button className="button button-outline" onClick={approve} disabled={!walletReady || !hasGas || !!busy || !value || !enoughBalance}>{busy === "approve" ? "Simulating + approving…" : `Approve ${amount || "0"} gTST`}</button><button className="button button-light" onClick={createEscrow} disabled={!walletReady || !hasGas || !!busy || !value || !enoughBalance || !enoughAllowance}>{busy === "escrow" ? "Preflighting + creating…" : mode === "pull" ? "Create Pull link" : "Fund Push link"}</button></div>
      {!enoughBalance && walletReady && <p className="notice" style={{marginTop:18}}>Mint enough demo gTST first.</p>}
      {enoughBalance && !enoughAllowance && walletReady && <p className="notice" style={{marginTop:18}}>Approve the exact gTST amount before creating the link.</p>}
      {error && <p className="notice error-notice" style={{marginTop:18}}>{error}</p>}
    </section>
    <section className="panel"><div className="panel-header"><div><h2>Transaction proof</h2><p className="panel-copy">Success appears only after wallet receipt and direct contract readback.</p></div>{result ? <StatusBadge tone="pending">Escrowed live</StatusBadge> : <StatusBadge>Waiting</StatusBadge>}</div>
      {result ? <><DetailRow label="Mode" value={result.mode.toUpperCase()}/><DetailRow label="Operation" value={shortHash(result.operationId,12,10)} mono/><DetailRow label="Terms hash" value={shortHash(result.termsHash,12,10)} mono/><DetailRow label="Transaction" value={<a href={txUrl(result.hash)} target="_blank" rel="noreferrer">{shortHash(result.hash)} <ExternalLink size={12} style={{display:"inline"}}/></a>} mono/><div className="notice success-notice" style={{marginTop:18}}><Check size={14} style={{display:"inline",marginRight:8}}/>Contract readback returned route facts.</div>{result.claimLink && <div style={{marginTop:18}}><label style={{fontSize:11,color:"var(--text-muted)"}}>FRAGMENT-ONLY CLAIM LINK · NOT PERSISTED</label><div className="detail-row"><strong className="mono" style={{textAlign:"left"}}>{shortHash(result.claimLink,42,12)}</strong><button aria-label="Copy claim link" onClick={()=>navigator.clipboard.writeText(result.claimLink!)} style={{background:"transparent",border:0,cursor:"pointer"}}><Copy size={15}/></button></div></div>}<details style={{marginTop:16}}><summary style={{cursor:"pointer",color:"var(--text-muted)",fontSize:12}}>Raw route readback</summary><pre className="mono" style={{whiteSpace:"pre-wrap",wordBreak:"break-all",fontSize:10,color:"var(--text-subtle)"}}>{result.readback}</pre></details></> : <div className="stepper">{["Connect on Monad", "Fund testnet MON gas", "Mint demo gTST", "Approve exact terms", "Preflight + create escrow"].map((step,index)=><div className="step" key={step}><span className="step-number">{index+1}</span>{step}</div>)}</div>}
    </section>
  </div>;
}
