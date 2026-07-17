// SPDX-License-Identifier: MIT
// FloatingCore — a lightweight WebGL-free animated SVG "core" visualizer that
// reacts to vessel state. Kept dependency-light (no Three.js) so the demo fits
// in the viewport and builds without native deps; swap for Three.js later if desired.
import { motion } from "framer-motion";
import type { Address, Hex } from "viem";

function hashToHue(seed: string): number {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) % 360;
  return h;
}

export function FloatingCore({
  seed,
  active,
}: {
  seed: string | Address | Hex;
  active: boolean;
}) {
  const hue = hashToHue(seed || "glyph");
  const c1 = `hsl(${hue} 80% 60%)`;
  const c2 = `hsl(${(hue + 60) % 360} 80% 55%)`;
  return (
    <div className="relative flex h-48 w-48 items-center justify-center">
      <motion.div
        className="absolute h-40 w-40 rounded-full blur-2xl"
        style={{ background: `radial-gradient(circle, ${c1}, transparent 70%)` }}
        animate={{ scale: active ? [1, 1.15, 1] : [1, 1.04, 1], opacity: active ? [0.6, 0.9, 0.6] : [0.4, 0.6, 0.4] }}
        transition={{ duration: 3, repeat: Infinity, ease: "easeInOut" }}
      />
      <svg viewBox="0 0 100 100" className="relative h-40 w-40">
        <defs>
          <radialGradient id="coreGrad" cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor={c1} />
            <stop offset="100%" stopColor={c2} />
          </radialGradient>
        </defs>
        <motion.circle
          cx="50" cy="50" r="30" fill="url(#coreGrad)" stroke={c2} strokeWidth="0.6"
          animate={{ rotate: 360 }} transition={{ duration: 12, repeat: Infinity, ease: "linear" }}
          style={{ transformOrigin: "50px 50px" }}
        />
        {[0, 1, 2, 3, 4, 5].map((i) => {
          const a = (i / 6) * Math.PI * 2;
          const x = 50 + Math.cos(a) * 34;
          const y = 50 + Math.sin(a) * 34;
          return (
            <motion.circle
              key={i} cx={x} cy={y} r="2.4" fill={c2}
              animate={{ scale: active ? [1, 1.8, 1] : [1, 1.2, 1] }}
              transition={{ duration: 2, repeat: Infinity, delay: i * 0.3, ease: "easeInOut" }}
            />
          );
        })}
      </svg>
    </div>
  );
}
