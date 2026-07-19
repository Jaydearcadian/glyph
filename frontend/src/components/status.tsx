import { Check, CircleAlert, Clock3, FileCheck2, WalletCards } from "lucide-react";
import clsx from "clsx";

export type StatusTone = "verified" | "settled" | "pending" | "blocked" | "neutral";

const icons = { verified: Check, settled: FileCheck2, pending: Clock3, blocked: CircleAlert, neutral: WalletCards };

export function StatusBadge({ tone = "neutral", children }: { tone?: StatusTone; children: React.ReactNode }) {
  const Icon = icons[tone];
  return <span className={clsx("status-badge", `status-${tone}`)}><Icon size={12} aria-hidden />{children}</span>;
}

export function AuthorityBadge({ children }: { children: React.ReactNode }) {
  return <span className="authority-badge">{children}</span>;
}
