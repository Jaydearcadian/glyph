"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, X } from "lucide-react";
import { useEffect, useState } from "react";
import clsx from "clsx";
import { WalletButton } from "@/components/wallet-button";

const items = [
  ["Product", "/"],
  ["Links", "/links"],
  ["Campaign", "/campaign"],
  ["Distribution", "/distribution"],
  ["Receipts", "/receipts"],
  ["Proofs", "/proofs"],
] as const;

export function Header() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const close = (event: KeyboardEvent) => event.key === "Escape" && setOpen(false);
    document.addEventListener("keydown", close);
    document.body.style.overflow = "hidden";
    return () => { document.removeEventListener("keydown", close); document.body.style.overflow = ""; };
  }, [open]);

  return (
    <header className="site-header">
      <nav className="nav-inner" aria-label="Primary navigation">
        <Link href="/" className="wordmark" aria-label="Glyph home"><span className="wordmark-mark" aria-hidden>G</span>GLYPH</Link>
        <div className="desktop-nav">
          {items.map(([label, href]) => <Link key={href} href={href} className={clsx("nav-link", pathname === href && "active")}>{label}</Link>)}
        </div>
        <div className="desktop-wallet"><WalletButton /></div>
        <button className="menu-button" onClick={() => setOpen(!open)} aria-expanded={open} aria-controls="mobile-navigation" aria-label={open ? "Close menu" : "Open menu"}>{open ? <X /> : <Menu />}</button>
      </nav>
      {open && <div id="mobile-navigation" className="mobile-nav"><div>{items.map(([label, href]) => <Link key={href} href={href} onClick={() => setOpen(false)} className={clsx("mobile-nav-link", pathname === href && "active")}>{label}</Link>)}</div><WalletButton /></div>}
    </header>
  );
}
