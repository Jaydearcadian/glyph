import { AuthorityBadge } from "@/components/status";

export function PageIntro({ eyebrow, title, description, authority }: { eyebrow: string; title: string; description: string; authority?: string }) {
  return <section className="page-intro"><div className="eyebrow"><span className="live-dot" />{eyebrow}</div><h1>{title}</h1><p>{description}</p>{authority && <AuthorityBadge>{authority}</AuthorityBadge>}</section>;
}

export function DetailRow({ label, value, mono = false }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return <div className="detail-row"><span>{label}</span><strong className={mono ? "mono" : undefined}>{value}</strong></div>;
}

export function SectionHeading({ eyebrow, title, copy }: { eyebrow: string; title: string; copy?: string }) {
  return <div className="section-heading"><span>{eyebrow}</span><h2>{title}</h2>{copy && <p>{copy}</p>}</div>;
}
