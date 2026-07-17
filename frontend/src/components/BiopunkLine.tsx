// SPDX-License-Identifier: MIT
// BiopunkLine — a Framer Motion driven SVG connection line between two nodes,
// giving the "living vessel" connective-tissue aesthetic called for in the spec.
import { motion } from "framer-motion";

export function BiopunkLine({
  from,
  to,
  color = "#5eead4",
}: {
  from: { x: number; y: number };
  to: { x: number; y: number };
  color?: string;
}) {
  const midX = (from.x + to.x) / 2;
  const midY = (from.y + to.y) / 2 - 24;
  const d = `M ${from.x} ${from.y} Q ${midX} ${midY} ${to.x} ${to.y}`;
  return (
    <svg className="pointer-events-none absolute inset-0 h-full w-full" style={{ overflow: "visible" }}>
      <motion.path
        d={d}
        fill="none"
        stroke={color}
        strokeWidth={1.5}
        strokeOpacity={0.5}
        initial={{ pathLength: 0 }}
        animate={{ pathLength: [0, 1, 0.2, 1] }}
        transition={{ duration: 5, repeat: Infinity, ease: "easeInOut" }}
      />
    </svg>
  );
}
