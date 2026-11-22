import { useRef } from "react";
import { useAnimationFrame, useReducedMotion } from "framer-motion";
import type { MotionValue } from "framer-motion";
import type { Palette, Skin } from "./skin";

/*
 * Things she can wear on top of her shell. Each is drawn around (0, 0) = the middle of where it
 * sits on her head, growing upward (negative y), in the halo's 400×400 units.
 */

export type AccessoryKind = Exclude<Skin["accessory"], "none">;

const SIZE = 1.5; // drawn small, worn at this size

const GOLD = { fill: "#f5c542", dark: "#a8740a", light: "#fff1b8" };
const PETAL = ["#f9a8d4", "#fde68a", "#c4b5fd", "#fecaca", "#ffffff"];
const LEAF = { fill: "#4ade80", dark: "#15803d" };

/** Moving parts: each frame, `t` seconds in, these set an SVG transform. */
type Motion = Partial<Record<"sway" | "spin" | "bob" | "wiggle", (t: number) => string>>;

const MOTION: Partial<Record<AccessoryKind, Motion>> = {
  flower: { sway: (t) => `rotate(${Math.sin(t * 1.6) * 7})` },
  sprout: { sway: (t) => `rotate(${Math.sin(t * 2.1) * 9})` },
  flowercrown: { sway: (t) => `rotate(${Math.sin(t * 1.3) * 2})` },
  antenna: { sway: (t) => `rotate(${Math.sin(t * 3.2) * 10 * (0.6 + 0.4 * Math.sin(t * 0.7))})` },
  angel: { bob: (t) => `translate(0 ${Math.sin(t * 2) * 5})` },
  propeller: { spin: (t) => `scale(${Math.cos(t * 14).toFixed(3)} 1)` },
  party: { wiggle: (t) => `rotate(${Math.sin(t * 5) * 12})` },
  bow: { wiggle: (t) => `rotate(${Math.sin(t * 1.8) * 4})` },
  catears: { wiggle: (t) => `rotate(${Math.max(0, Math.sin(t * 0.9)) ** 12 * -14})` },
};

function Flower({ x, y, r, petal, n = 8 }: { x: number; y: number; r: number; petal: string; n?: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      {Array.from({ length: n }, (_, i) => (
        <ellipse key={i} cx="0" cy={-r * 0.62} rx={r * 0.34} ry={r * 0.62} transform={`rotate(${(i * 360) / n})`} fill={petal} stroke="#00000033" strokeWidth={r * 0.05} />
      ))}
      <circle r={r * 0.36} fill="#facc15" stroke="#b45309" strokeWidth={r * 0.06} />
    </g>
  );
}

function Leaf({ x, y, a, s = 1 }: { x: number; y: number; a: number; s?: number }) {
  return (
    <path
      d="M0 0 C8 -6 18 -6 26 0 C18 6 8 6 0 0 Z"
      transform={`translate(${x} ${y}) rotate(${a}) scale(${s})`}
      fill={LEAF.fill}
      stroke={LEAF.dark}
      strokeWidth="1.4"
    />
  );
}

/** The drawing. `refs` receives the moving parts (sway, spin, bob, wiggle) for animation. */
export function AccessoryArt({ kind, p, refs }: { kind: AccessoryKind; p: Palette; refs?: (name: keyof Motion, el: SVGGElement | null) => void }) {
  const part = (name: keyof Motion) => (el: SVGGElement | null) => refs?.(name, el);
  switch (kind) {
    case "tophat":
      return (
        <g transform="rotate(-8)">
          <ellipse cx="0" cy="-4" rx="64" ry="11" fill="#141414" stroke="#3a3a3a" strokeWidth="2" />
          <path d="M-38 -8 L-34 -92 Q0 -98 34 -92 L38 -8 Q0 0 -38 -8 Z" fill="#1c1c1c" stroke="#3a3a3a" strokeWidth="2" />
          <path d="M-37 -26 Q0 -18 37 -26 L37.6 -12 Q0 -4 -37.6 -12 Z" fill={p.main} />
          <ellipse cx="0" cy="-93" rx="34" ry="6" fill="#262626" stroke="#3a3a3a" strokeWidth="2" />
          <path d="M-26 -84 L-24 -34" stroke="#ffffff" strokeOpacity="0.12" strokeWidth="6" strokeLinecap="round" />
        </g>
      );
    case "party":
      return (
        <g transform="rotate(10)">
          <path d="M-38 -2 L0 -104 L38 -2 Q0 8 -38 -2 Z" fill={p.main} stroke={p.ink} strokeWidth="2" />
          {[-80, -56, -32].map((y) => (
            <path key={y} d={`M${(y / 104) * 38} ${y} L${(-y / 104) * 38} ${y + 14}`} stroke={p.light} strokeWidth="7" strokeLinecap="round" />
          ))}
          {[[-14, -20], [10, -44], [-4, -66], [16, -14]].map(([x, y]) => (
            <circle key={`${x}${y}`} cx={x} cy={y} r="3.5" fill={GOLD.fill} />
          ))}
          <g transform="translate(0 -104)">
            <g ref={part("wiggle")}>
              {[0, 1, 2, 3, 4].map((i) => (
                <path key={i} d={`M0 0 L${(i - 2) * 6} -16`} stroke={i % 2 ? p.light : GOLD.fill} strokeWidth="3" strokeLinecap="round" />
              ))}
              <circle r="9" fill={p.hot} />
            </g>
          </g>
        </g>
      );
    case "crown":
      return (
        <g>
          <path d="M-52 -4 L-56 -62 L-30 -34 L-14 -74 L0 -40 L14 -74 L30 -34 L56 -62 L52 -4 Q0 6 -52 -4 Z" fill={GOLD.fill} stroke={GOLD.dark} strokeWidth="2.4" strokeLinejoin="round" />
          <path d="M-51 -18 Q0 -8 51 -18" fill="none" stroke={GOLD.dark} strokeWidth="2" />
          {[-34, 0, 34].map((x) => (
            <circle key={x} cx={x} cy="-10" r="6" fill={p.main} stroke={GOLD.light} strokeWidth="1.5" />
          ))}
          {[[-56, -62], [-14, -74], [14, -74], [56, -62]].map(([x, y]) => (
            <circle key={x} cx={x} cy={y} r="4.5" fill={GOLD.light} stroke={GOLD.dark} strokeWidth="1.2" />
          ))}
          <path d="M-42 -14 L-44 -44" stroke="#ffffff" strokeOpacity="0.45" strokeWidth="3" strokeLinecap="round" />
        </g>
      );
    case "flower":
      return (
        <g transform="translate(34 -2)">
          <g ref={part("sway")}>
            <path d="M0 0 C-4 -24 10 -42 6 -66" fill="none" stroke={LEAF.dark} strokeWidth="5" strokeLinecap="round" />
            <Leaf x={2} y={-26} a={-30} />
            <Leaf x={4} y={-40} a={200} s={0.8} />
            <Flower x={6} y={-76} r={26} petal={PETAL[0]} />
          </g>
        </g>
      );
    case "flowercrown":
      return (
        <g ref={part("sway")}>
          <path d="M-86 -2 Q0 -26 86 -2" fill="none" stroke={LEAF.dark} strokeWidth="5" strokeLinecap="round" />
          {[-70, -36, 0, 36, 70].map((x, i) => (
            <Leaf key={`l${x}`} x={x + 8} y={-8 - (1 - (x / 86) ** 2) * 10} a={i % 2 ? 30 : -150} s={0.8} />
          ))}
          {[-78, -48, -18, 18, 48, 78].map((x, i) => (
            <Flower key={x} x={x} y={-6 - (1 - (x / 86) ** 2) * 13} r={i % 2 ? 15 : 18} petal={PETAL[i % PETAL.length]} n={i % 2 ? 6 : 8} />
          ))}
        </g>
      );
    case "bow":
      return (
        <g transform="translate(38 -14) rotate(18)">
          <g ref={part("wiggle")}>
            <path d="M0 0 C-14 -30 -52 -32 -50 -4 C-48 18 -16 14 0 0 Z" fill={PETAL[0]} stroke="#be185d" strokeWidth="2.4" />
            <path d="M0 0 C14 -30 52 -32 50 -4 C48 18 16 14 0 0 Z" fill={PETAL[0]} stroke="#be185d" strokeWidth="2.4" />
            <path d="M-4 4 L-16 34 L-6 30 L0 38 L4 4 Z M4 4 L14 34 L4 31" fill="#f472b6" stroke="#be185d" strokeWidth="2" />
            <rect x="-9" y="-10" width="18" height="18" rx="5" fill="#f472b6" stroke="#be185d" strokeWidth="2.4" />
            <path d="M-36 -16 Q-26 -22 -16 -12" fill="none" stroke="#ffffff" strokeOpacity="0.7" strokeWidth="3" strokeLinecap="round" />
          </g>
        </g>
      );
    case "sprout":
      return (
        <g transform="translate(0 2)">
          <g ref={part("sway")}>
            <path d="M0 0 C2 -18 -2 -34 0 -50" fill="none" stroke={LEAF.dark} strokeWidth="5" strokeLinecap="round" />
            <path d="M0 -48 C-8 -72 -40 -74 -44 -60 C-30 -46 -10 -44 0 -48 Z" fill={LEAF.fill} stroke={LEAF.dark} strokeWidth="2" />
            <path d="M0 -48 C8 -78 40 -84 46 -68 C32 -52 12 -48 0 -48 Z" fill={LEAF.fill} stroke={LEAF.dark} strokeWidth="2" />
            <path d="M-6 -54 Q-22 -62 -34 -60 M6 -54 Q24 -66 38 -68" stroke={LEAF.dark} strokeOpacity="0.6" strokeWidth="1.6" fill="none" />
          </g>
        </g>
      );
    case "antenna":
      return (
        <g>
          <path d="M-14 0 Q0 -14 14 0 Z" fill={p.socket} stroke={p.main} strokeWidth="2" />
          <g transform="translate(0 -6)">
            <g ref={part("sway")}>
              <path d="M0 0 L0 -70" stroke={p.light} strokeWidth="3.5" strokeLinecap="round" />
              <circle cy="-78" r="16" fill={p.main} opacity="0.25" />
              <circle cy="-78" r="10" fill={p.main} stroke={p.light} strokeWidth="2" />
              <circle cx="-3" cy="-81" r="3" fill={p.hot} />
            </g>
          </g>
        </g>
      );
    case "angel":
      return (
        <g transform="translate(0 -42)">
          <g ref={part("bob")}>
            <ellipse rx="56" ry="13" fill="none" stroke={GOLD.light} strokeOpacity="0.35" strokeWidth="14" />
            <ellipse rx="56" ry="13" fill="none" stroke={GOLD.fill} strokeWidth="6" />
            <ellipse rx="56" ry="13" fill="none" stroke={GOLD.light} strokeWidth="1.6" />
          </g>
        </g>
      );
    case "propeller":
      return (
        <g>
          <path d="M-50 0 A50 46 0 0 1 50 0 Q0 8 -50 0 Z" fill="#ef4444" stroke="#7f1d1d" strokeWidth="2.4" />
          <path d="M-17 -42 A50 46 0 0 1 17 -42 L12 2 L-12 2 Z" fill="#facc15" />
          <path d="M-46 -16 A50 46 0 0 1 -30 -36 L-14 2 L-36 2 Z M46 -16 A50 46 0 0 0 30 -36 L14 2 L36 2 Z" fill="#3b82f6" />
          <path d="M-50 0 A50 46 0 0 1 50 0" fill="none" stroke="#7f1d1d" strokeWidth="2.4" />
          <path d="M-56 2 Q0 12 56 2" fill="none" stroke="#7f1d1d" strokeWidth="6" strokeLinecap="round" />
          <path d="M0 -46 L0 -62" stroke="#52525b" strokeWidth="4" />
          <g transform="translate(0 -64)">
            <g ref={part("spin")}>
              <path d="M0 0 C-14 -8 -44 -8 -52 0 C-44 8 -14 8 0 0 Z" fill={p.main} stroke={p.ink} strokeWidth="1.6" />
              <path d="M0 0 C14 -8 44 -8 52 0 C44 8 14 8 0 0 Z" fill={p.light} stroke={p.ink} strokeWidth="1.6" />
            </g>
            <circle r="5" fill="#52525b" />
          </g>
        </g>
      );
    case "catears":
      return (
        <g>
          {[-1, 1].map((side) => (
            <g key={side} transform={`translate(${side * 56} 8) scale(${side} 1)`}>
              <g ref={side === 1 ? part("wiggle") : undefined}>
                <path d="M-26 0 L-6 -62 L26 -6 Z" fill={p.socket} stroke={p.main} strokeWidth="3" strokeLinejoin="round" />
                <path d="M-14 -6 L-6 -44 L12 -10 Z" fill="#f9a8d4" />
              </g>
            </g>
          ))}
        </g>
      );
  }
}

/**
 * The accessory on her head: animates its moving parts, and hops when her shell spins.
 * `y` is where her head is (the top of the shell) in halo units.
 */
export default function Accessory({ kind, p, y, push }: { kind: AccessoryKind; p: Palette; y: number; push?: MotionValue<number> }) {
  const reduce = useReducedMotion();
  const els = useRef<Partial<Record<keyof Motion, SVGGElement | null>>>({});
  const root = useRef<SVGGElement>(null);
  const place = (hop: number) => `translate(200 ${(y - hop).toFixed(1)})`;

  useAnimationFrame((t) => {
    root.current?.setAttribute("transform", place(Math.max(0, push?.get() ?? 0) * 16));
    if (reduce) return;
    const m = MOTION[kind];
    if (!m) return;
    for (const name of Object.keys(m) as (keyof Motion)[]) els.current[name]?.setAttribute("transform", m[name]!(t / 1000));
  });

  return (
    <g ref={root} transform={place(0)}>
      <g transform={`scale(${SIZE})`}>
        <AccessoryArt kind={kind} p={p} refs={(name, el) => void (els.current[name] = el)} />
      </g>
    </g>
  );
}
