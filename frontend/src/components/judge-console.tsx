"use client";

import { useMemo, useState } from "react";
import { Check, Copy, ExternalLink, FlaskConical, LoaderCircle } from "lucide-react";
import { isAddress, parseUnits, type Address, type Hash } from "viem";
import { useAccount, usePublicClient, useReadContract, useWriteContract } from "wagmi";
import { AuthorityBadge, StatusBadge } from "@/components/status";
import { DetailRow } from "@/components/ui";
import { contracts, formatToken, monadTestnet, PULL_MODE, PUSH_MODE, routerAbi, shortHash, testTokenAbi, txUrl, type Terms, ZERO_ADDRESS, ZERO_HASH } from "@/lib/glyph";

type FlowMode = "pull" | "push";
type Result = { mode: FlowMode; hash: Hash; operationId: Hash; termsHash: Hash; readback: string; claimLink?: string };

function errorText(error: unknown) {
  if (error instanceof Error) return error.message.split("\n")[0];
  return "The wallet or contract rejected the action.";
}

export function JudgeConsole() {
  const { address, chainId, isConnected } = useAccount();
  const publicClient = usePublicClient({ chainId: monadTestnet.id });
  const { writeContractAsync } = useWriteContract();
  const [mode, setMode] = useState<FlowMode>("pull");
  const [amount, setAmount] = useState("10");
  const [recipient, setRecipient] = useState("");
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [result, setResult] = useState<Result>();

  const walletReady = isConnected && chainId === monadTestnet.id && !!address;
  const recipientAddress = useMemo(() => isAddress(recipient) ? recipient as Address : address, [recipient, address]);

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
    if (!walletReady || !publicClient) return;
    await run("approve", async () => {
      const hash = await writeContractAsync({ address: contracts.token, abi: testTokenAbi, functionName: "approve", args: [contracts.router, parseUnits(amount || "0", 18)], chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      await allowance.refetch();
    });
  }

  async function createEscrow() {
    if (!walletReady || !address || !publicClient || !recipientAddress) return;
    await run("escrow", async () => {
      const nonce = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "actorNonce", args: [address] }) as bigint;
      const value = parseUnits(amount || "0", 18);
      const terms: Terms = {
        mode: mode === "pull" ? PULL_MODE : PUSH_MODE,
        programId: ZERO_HASH,
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
        protocolFee: 0n,
        providerFee: 0n,
        referrerFee: 0n,
        gasSponsorFee: 0n,
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
      const hash = await writeContractAsync({ address: contracts.router, abi: routerAbi, functionName: "escrow", args: [terms], chainId: monadTestnet.id });
      await publicClient.waitForTransactionReceipt({ hash });
      const routeFacts = await publicClient.readContract({ address: contracts.router, abi: routerAbi, functionName: "routeFacts", args: [operationId] });
      const readback = JSON.stringify(routeFacts, (_, value) => typeof value === "bigint" ? value.toString() : value);
      let claimLink: string | undefined;
      if (mode === "push") {
        const secret = new Uint8Array(24);
        crypto.getRandomValues(secret);
        const encoded = Array.from(secret, byte => byte.toString(16).padStart(2, "0")).join("");
        claimLink = `${location.origin}/links#claim=${operationId}&key=${encoded}`;
      }
      setResult({ mode, hash, operationId, termsHash, readback, claimLink });
      await Promise.all([balance.refetch(), allowance.refetch()]);
    });
  }

  const balanceValue = typeof balance.data === "bigint" ? balance.data : undefined;
  const allowanceValue = typeof allowance.data === "bigint" ? allowance.data : undefined;
  const enoughAllowance = allowanceValue !== undefined && amount && allowanceValue >= parseUnits(amount, 18);

  return (
    <div className="grid-2">
      <section className="panel featured">
        <div className="panel-header"><div><h2>Try Glyph live</h2><p className="panel-copy">Mint gTST, approve exact spend, and create a real onchain payment or claim link.</p></div><AuthorityBadge>User wallet action</AuthorityBadge></div>
        <div className="detail-row"><span>Network</span><strong>{walletReady ? "Monad Testnet" : "Connect on Monad"}</strong></div>
        <div className="detail-row"><span>gTST balance</span><strong>{formatToken(balanceValue)} gTST</strong></div>
        <div className="detail-row"><span>Router allowance</span><strong>{formatToken(allowanceValue)} gTST</strong></div>
        <div className="form-actions"><button className="button button-dark button-small" onClick={mint} disabled={!walletReady || !!busy}>{busy === "mint" ? <LoaderCircle className="animate-spin" size={15} /> : <FlaskConical size={15} />} Mint 100 gTST</button></div>

        <div style={{marginTop:28}} className="mode-tabs" role="tablist" aria-label="Link mode">
          <button role="tab" aria-selected={mode === "pull"} className={`mode-tab ${mode === "pull" ? "active" : ""}`} onClick={() => setMode("pull")}>Pull · pay request</button>
          <button role="tab" aria-selected={mode === "push"} className={`mode-tab ${mode === "push" ? "active" : ""}`} onClick={() => setMode("push")}>Push · claim link</button>
        </div>
        <div className="form-grid">
          <div className="field"><label htmlFor="amount">Amount in gTST</label><input id="amount" inputMode="decimal" value={amount} onChange={event => setAmount(event.target.value)} /></div>
          <div className="field"><label htmlFor="recipient">{mode === "pull" ? "Recipient wallet" : "Claim recipient preview"}</label><input id="recipient" placeholder={address ?? "0x…"} value={recipient} onChange={event => setRecipient(event.target.value)} /></div>
        </div>
        <div className="form-actions">
          <button className="button button-outline" onClick={approve} disabled={!walletReady || !!busy || !amount}>{busy === "approve" ? "Approving…" : `Approve ${amount || "0"} gTST`}</button>
          <button className="button button-light" onClick={createEscrow} disabled={!walletReady || !!busy || !amount || !enoughAllowance}>{busy === "escrow" ? "Creating onchain…" : mode === "pull" ? "Create Pull link" : "Fund Push link"}</button>
        </div>
        {!enoughAllowance && walletReady && <p className="notice" style={{marginTop:18}}>Approve the exact gTST amount before creating the link. Fresh links resolve to <strong>escrowed</strong>, not terminally settled.</p>}
        {error && <p className="notice error-notice" style={{marginTop:18}}>{error}</p>}
      </section>

      <section className="panel">
        <div className="panel-header"><div><h2>Transaction proof</h2><p className="panel-copy">Success appears only after the wallet receipt and direct contract readback.</p></div>{result ? <StatusBadge tone="pending">Escrowed live</StatusBadge> : <StatusBadge>Waiting</StatusBadge>}</div>
        {result ? <>
          <DetailRow label="Mode" value={result.mode.toUpperCase()} />
          <DetailRow label="Operation" value={shortHash(result.operationId, 12, 10)} mono />
          <DetailRow label="Terms hash" value={shortHash(result.termsHash, 12, 10)} mono />
          <DetailRow label="Transaction" value={<a href={txUrl(result.hash)} target="_blank" rel="noreferrer">{shortHash(result.hash)} <ExternalLink size={12} style={{display:"inline"}} /></a>} mono />
          <div className="notice success-notice" style={{marginTop:18}}><Check size={14} style={{display:"inline",marginRight:8}} />Contract readback returned route facts. Operator routing is intentionally not exposed as a judge-wallet action.</div>
          {result.claimLink && <div style={{marginTop:18}}><label style={{fontSize:11,color:"var(--text-muted)"}}>FRAGMENT-ONLY CLAIM LINK · NOT PERSISTED</label><div className="detail-row"><strong className="mono" style={{textAlign:"left"}}>{shortHash(result.claimLink, 42, 12)}</strong><button aria-label="Copy claim link" onClick={() => navigator.clipboard.writeText(result.claimLink!)} style={{background:"transparent",border:0,cursor:"pointer"}}><Copy size={15} /></button></div></div>}
          <details style={{marginTop:16}}><summary style={{cursor:"pointer",color:"var(--text-muted)",fontSize:12}}>Raw route readback</summary><pre className="mono" style={{whiteSpace:"pre-wrap",wordBreak:"break-all",fontSize:10,color:"var(--text-subtle)"}}>{result.readback}</pre></details>
        </> : <div className="stepper">{["Connect on Monad", "Mint demo gTST", "Approve exact terms", "Create escrow", "Verify onchain readback"].map((step,index)=><div className="step" key={step}><span className="step-number">{index+1}</span>{step}</div>)}</div>}
      </section>
    </div>
  );
}
