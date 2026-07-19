"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { ArrowUpRight, Check, Link2 } from "lucide-react";

const ease = [0.22, 1, 0.36, 1] as const;

export function Hero() {
  return (
    <main>
      <section className="hero" aria-labelledby="hero-title">
        <div className="ledger-bg" aria-hidden />
        <motion.div className="hero-copy" initial="hidden" animate="show" variants={{ hidden: {}, show: { transition: { staggerChildren: .1 } } }}>
          <motion.div className="eyebrow" variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0, transition: { duration: .55, ease } } }}><span className="live-dot" />LINK-NATIVE PAYMENT INFRASTRUCTURE</motion.div>
          <motion.h1 id="hero-title" variants={{ hidden: { opacity: 0, y: 22 }, show: { opacity: 1, y: 0, transition: { duration: .7, ease } } }}>Payment links<br />that end in proof.</motion.h1>
          <motion.p variants={{ hidden: { opacity: 0, y: 16 }, show: { opacity: 1, y: 0, transition: { duration: .6, ease } } }}>Create simple payment, claim, campaign, and payout links while Glyph enforces exact terms, recovery, distribution, and verifiable receipts onchain.</motion.p>
          <motion.div className="hero-actions" variants={{ hidden: { opacity: 0, scale: .98 }, show: { opacity: 1, scale: 1, transition: { duration: .5, ease } } }}>
            <Link className="button button-light" href="/links">Create a payment link <ArrowUpRight size={16} /></Link>
            <Link className="button button-outline" href="/receipts">View verified receipts</Link>
          </motion.div>
        </motion.div>

        <motion.div className="settlement-visual" initial={{ opacity: 0, y: 32 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: .85, delay: .48, ease }} aria-label="A payment link travels through settlement rails, becomes a receipt, and resolves into verified proof.">
          <svg className="route-svg" viewBox="0 0 1180 410" role="img" aria-label="Payment link to verified receipt settlement route">
            <path className="route-base" d="M10 275 C220 275 290 247 400 238 S700 230 780 253 S970 274 1170 242" />
            <motion.path className="route-proof" d="M10 275 C220 275 290 247 400 238 S700 230 780 253 S970 274 1170 242" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.8, delay: .7, ease }} />
          </svg>
          <motion.article className="artifact link-artifact" whileHover={{ y: -3 }}>
            <div className="artifact-kicker">PAYMENT LINK · OPEN</div>
            <div className="artifact-amount">2,400.00 <small style={{fontSize:12,color:"var(--text-muted)"}}>gTST</small></div>
            <div className="artifact-meta"><span><Link2 size={12} /> glyph.link/pay/atlas</span><span>01</span></div>
          </motion.article>
          <motion.article className="artifact receipt-artifact" whileHover={{ y: -4 }}>
            <div className="receipt-top"><span>GLYPH SETTLEMENT RECEIPT</span><div className="receipt-seal">G</div></div>
            <div className="receipt-line"><span>AMOUNT</span><strong>2,400.00 gTST</strong></div>
            <div className="receipt-line"><span>SOURCE</span><strong>Payment link</strong></div>
            <div className="receipt-line"><span>STATUS</span><strong style={{display:"flex",gap:7,alignItems:"center"}}><Check size={15} color="#268d65" /> SETTLED</strong></div>
            <div className="receipt-line"><span>PROOF</span><strong style={{fontFamily:"var(--font-geist-mono)",fontSize:12}}>0x7F4A…92C1</strong></div>
          </motion.article>
          <motion.article className="artifact proof-artifact" whileHover={{ rotate: 8 }}>
            <div className="proof-ring" /><div><Check size={25} color="var(--proof-mint)" /><br /><strong>RECEIPT VERIFIED</strong><br /><span>checksum / block / route</span></div>
          </motion.article>
        </motion.div>
        <motion.div className="trust-strip" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.1, duration: .6 }}>
          <p>Built for teams that need every payment to end in proof.</p>
          <div className="logo-row" aria-label="Example ecosystem integrations">{["Meridian","Relay","Atlas","Northstar","Common","Vector"].map(name => <span key={name}>{name}</span>)}</div>
        </motion.div>
      </section>
    </main>
  );
}
