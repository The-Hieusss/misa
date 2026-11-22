import type { ReactNode } from "react";
import { motion, useTransform } from "framer-motion";
import type { MotionValue } from "framer-motion";
import type { Palette, Skin } from "./skin";

/* Geometry for M.I.S.A.'s swappable shell parts, in the halo's 400×400 viewBox. */

export const C = 200;
const rad = (deg: number) => ((deg - 90) * Math.PI) / 180; // 0° = top, clockwise
export const pt = (r: number, deg: number) => [C + r * Math.cos(rad(deg)), C + r * Math.sin(rad(deg))] as const;

/** Annular armor plate with chamfered ends (inner edge narrower than outer). */
export function platePath(r1: number, r2: number, a0: number, a1: number, chamfer = 4) {
  const [ox0, oy0] = pt(r2, a0);
  const [ox1, oy1] = pt(r2, a1);
  const [ix1, iy1] = pt(r1, a1 - chamfer);
  const [ix0, iy0] = pt(r1, a0 + chamfer);
  const large = a1 - a0 > 180 ? 1 : 0;
  return `M${ox0} ${oy0} A${r2} ${r2} 0 ${large} 1 ${ox1} ${oy1} L${ix1} ${iy1} A${r1} ${r1} 0 ${large} 0 ${ix0} ${iy0} Z`;
}
export function arcPath(r: number, a0: number, a1: number) {
  const [x0, y0] = pt(r, a0);
  const [x1, y1] = pt(r, a1);
  return `M${x0} ${y0} A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1} ${y1}`;
}
export function hex(cx: number, cy: number, r: number) {
  return Array.from({ length: 6 }, (_, i) => {
    const a = (Math.PI / 3) * i + Math.PI / 6;
    return `${cx + r * Math.cos(a)},${cy + r * Math.sin(a)}`;
  }).join(" ");
}

/* ── Rings ─────────────────────────────────────────────────────────────────── */

export type Seg = { mid: number; a0: number; a1: number; r1: number; r2: number; badge: boolean; index: number };
export type RingSpec = {
  segs: Seg[];
  /** Where the four clamps sit (degrees), normally in the gaps between plates. */
  clamps: number[];
  chamfer: number;
  spikes?: boolean;
  gyro?: boolean;
  /** Multiplier on how far plates slide out during the overclock spin. */
  push?: number;
  /** Custom plate outline (default: a chamfered arc plate). Drawn with the even-odd rule, so it can have holes. */
  shape?: (s: Seg) => string;
  /** Skip the arc trim (edge highlights, flow light, screws, vents) for shapes it doesn't fit. */
  plain?: boolean;
  /** A full ring drawn under the plates (r = center radius, w = width). */
  track?: { r: number; w: number };
};

const every = (n: number, offset = 0) => Array.from({ length: n }, (_, i) => offset + (i * 360) / n);
const ring = (mids: number[], span: number, r1: number, r2: number, badge: boolean): Seg[] =>
  mids.map((mid, index) => ({ mid, a0: mid - span / 2, a1: mid + span / 2, r1, r2, badge, index }));
const DIAG = every(4, 45);
const deg = (rad: number) => (rad * 180) / Math.PI;
const P = (r: number, a: number) => pt(r, a).map((v) => v.toFixed(2)).join(" ");

/** A rounded capsule along an arc (round ends). */
function capsule(r1: number, r2: number, a0: number, a1: number) {
  const h = (r2 - r1) / 2;
  const cap = deg(h / ((r1 + r2) / 2));
  const big = a1 - a0 - 2 * cap > 180 ? 1 : 0;
  return `M${P(r2, a0 + cap)} A${r2} ${r2} 0 ${big} 1 ${P(r2, a1 - cap)} A${h} ${h} 0 0 1 ${P(r1, a1 - cap)} A${r1} ${r1} 0 ${big} 0 ${P(r1, a0 + cap)} A${h} ${h} 0 0 1 ${P(r2, a0 + cap)} Z`;
}

/** Hex frame side: straight outer and inner edges between the corners. */
const hexSide = (s: Seg) => `M${P(196, s.a0)} L${P(196, s.a1)} L${P(170, s.a1 - 2.5)} L${P(170, s.a0 + 2.5)} Z`;

/** Band with angled saw teeth along the outside. */
function sawPlate(s: Seg) {
  const pts = [P(s.r2, s.a0)];
  for (let a = s.a0; a + 6 <= s.a1; a += 6) pts.push(P(s.r2 + 9, a + 5), P(s.r2, a + 6));
  pts.push(P(s.r2, s.a1), P(s.r1, s.a1));
  return `M${pts.join(" L")} A${s.r1} ${s.r1} 0 0 0 ${P(s.r1, s.a0)} Z`;
}

/** Plate with a pointed outer tip. */
const petal = (s: Seg) => {
  const k = (s.a1 - s.a0) * 0.3;
  return `M${P(s.r2, s.a0)} Q${P(s.r2 + 14, s.a0 + k)} ${P(199, s.mid)} Q${P(s.r2 + 14, s.a1 - k)} ${P(s.r2, s.a1)} L${P(s.r1, s.a1 - 4)} A${s.r1} ${s.r1} 0 0 0 ${P(s.r1, s.a0 + 4)} Z`;
};

/** Hollow chain link. */
const link = (s: Seg) => `${capsule(s.r1, s.r2, s.a0, s.a1)} ${capsule(s.r1 + 4, s.r2 - 4, s.a0 + 3, s.a1 - 3)}`;

/** Heavy arm that widens outward, with a notch at the tip. */
const arm = (s: Seg) =>
  `M${P(158, s.mid - 10)} L${P(197, s.mid - 14)} L${P(197, s.mid - 4)} L${P(190, s.mid)} L${P(197, s.mid + 4)} L${P(197, s.mid + 14)} L${P(158, s.mid + 10)} Z`;

const seg = (mid: number, a0: number, a1: number, r1: number, r2: number, badge: boolean, index: number): Seg => ({ mid, a0, a1, r1, r2, badge, index });

export const RING_SPECS: Record<Skin["ring"], RingSpec> = {
  plates4: { segs: ring(every(4), 66, 160, 184, true), clamps: DIAG, chamfer: 4 },
  segments6: { segs: ring(every(6), 50, 160, 184, true), clamps: [30, 150, 210, 330], chamfer: 4 },
  blades8: { segs: ring(every(8), 34, 166, 184, false), clamps: every(4, 22.5), chamfer: 6 },
  band: { segs: ring(every(4), 88.5, 162, 184, true), clamps: DIAG, chamfer: 0 },
  crescents: { segs: ring([90, 270], 136, 158, 186, true), clamps: [-12, 12, 168, 192], chamfer: 6 },
  crown: { segs: ring(every(4), 52, 160, 184, true), clamps: DIAG, chamfer: 4, spikes: true },
  shards: { segs: ring(every(8), 22, 164, 186, false), clamps: every(4, 22.5), chamfer: 6, push: 1.8 },
  gyro: { segs: [], clamps: DIAG, chamfer: 0, gyro: true },
  hex: { segs: ring(every(6), 54, 170, 196, true), clamps: [30, 150, 210, 330], chamfer: 0, shape: hexSide, plain: true },
  saw: { segs: ring(every(4), 88.5, 164, 180, true), clamps: DIAG, chamfer: 0, shape: sawPlate },
  visor: { segs: [seg(180, 45, 315, 160, 186, true, 0), seg(0, -20, 20, 164, 182, false, 1)], clamps: [27, 333, 135, 225], chamfer: 5 },
  petals: { segs: ring(every(6), 46, 160, 178, true), clamps: [30, 150, 210, 330], chamfer: 4, shape: petal },
  chain: {
    segs: every(12).map((mid, i) => seg(mid, mid - 17, mid + 17, i % 2 ? 167 : 164, i % 2 ? 181 : 184, false, i)),
    clamps: [15, 105, 195, 285], chamfer: 0, shape: link, plain: true, push: 1.4,
  },
  pods: { segs: ring(every(3), 32, 160, 186, true), clamps: [60, 180, 300], chamfer: 6, track: { r: 173, w: 3 } },
  tiers: {
    segs: [...ring(every(8, 22.5), 40, 158, 168, false), ...ring(every(4), 60, 172, 194, true).map((x) => ({ ...x, index: x.index + 8 }))],
    clamps: DIAG, chamfer: 3,
  },
  cross: { segs: ring(every(4, 45), 28, 158, 197, true), clamps: every(4), chamfer: 0, shape: arm, plain: true, track: { r: 167, w: 10 } },
};

/** Vent slots either side of a plate's badge, as many as fit. */
export function ventAngles(s: Seg) {
  const out: number[] = [];
  for (let k = 0; k < 7 && 11 + k * 4 <= (s.a1 - s.a0) / 2 - 6; k++) out.push(s.mid - (11 + k * 4), s.mid + (11 + k * 4));
  return out;
}

/** Crown spikes rising off a plate's outer edge. */
export function spikePaths(s: Seg) {
  return [
    [s.a0 + 7, 2.6, 10],
    [s.mid, 3.6, 13],
    [s.a1 - 7, 2.6, 10],
  ].map(([a, w, len]) => {
    const [x0, y0] = pt(s.r2 - 1, a - w);
    const [x1, y1] = pt(s.r2 + len, a);
    const [x2, y2] = pt(s.r2 - 1, a + w);
    return `M${x0} ${y0} L${x1} ${y1} L${x2} ${y2} Z`;
  });
}

export const GYRO = { rx: 186, ry: 128, tilt: 32 };

/* ── Clamps (drawn pointing up at 0°, rotated into place) ─────────────────── */

type ClampCtx = { p: Palette; compact: boolean; charged: boolean; i: number };
type ClampArt = { outline: string; detail: (o: ClampCtx) => ReactNode };

const lit = (o: ClampCtx) => (o.charged ? o.p.light : o.p.main);
const pulse = (o: ClampCtx) => ({ className: "animate-pulse", style: { animationDelay: `${o.i * 0.5}s` } });
const bolt = (o: ClampCtx, cx: number, cy: number, r = 3.6) => (
  <polygon points={hex(cx, cy, r)} fill={o.p.bolt} stroke={o.p.light} strokeOpacity="0.8" strokeWidth="0.8" />
);

export const CLAMP_ART: Record<Exclude<Skin["clamp"], "none">, ClampArt> = {
  bracket: {
    outline: `M${C - 8} 1 H${C + 8} L${C + 12} 9 V42 H${C - 12} V9 Z`,
    detail: (o) => (
      <>
        <line x1={C - 7} y1={35} x2={C + 7} y2={35} stroke={o.p.main} strokeOpacity="0.4" strokeWidth="1" />
        {!o.compact && (
          <g stroke={o.p.main} strokeOpacity="0.45" strokeWidth="0.8" fill="none">
            <line x1={C - 8.5} y1={14} x2={C - 8.5} y2={39} />
            <line x1={C + 8.5} y1={14} x2={C + 8.5} y2={39} />
            <rect x={C - 10} y={12} width="3" height="5" fill={o.p.bolt} />
            <rect x={C + 7} y={12} width="3" height="5" fill={o.p.bolt} />
          </g>
        )}
        {bolt(o, C, 25)}
        <rect x={C - 4} y={5} width="8" height="3" fill={lit(o)} {...pulse(o)} />
      </>
    ),
  },
  talon: {
    outline: `M${C - 10} 42 V24 C${C - 10} 12 ${C - 4} 4 ${C + 11} 0 C${C + 5} 7 ${C + 3} 14 ${C + 3} 24 V42 Z`,
    detail: (o) => (
      <>
        {!o.compact && <path d={`M${C - 7} 38 V25 C${C - 7} 16 ${C - 3} 10 ${C + 4} 6`} fill="none" stroke={o.p.main} strokeOpacity="0.4" strokeWidth="0.8" />}
        <path d={`M${C - 5} 20 C${C - 4} 14 ${C} 9 ${C + 6} 5`} fill="none" stroke={lit(o)} strokeWidth="2" strokeLinecap="round" {...pulse(o)} />
        {bolt(o, C - 3.5, 32, 3.2)}
      </>
    ),
  },
  piston: {
    outline: `M${C - 13} 1 H${C + 13} V7 H${C + 4} V20 H${C + 11} V42 H${C - 11} V20 H${C - 4} V7 H${C - 13} Z`,
    detail: (o) => (
      <>
        <g stroke={o.p.main} strokeOpacity="0.45" strokeWidth="0.9">
          <line x1={C - 11} y1={27} x2={C + 11} y2={27} />
          {!o.compact && <line x1={C - 11} y1={32} x2={C + 11} y2={32} />}
          {!o.compact && <line x1={C - 11} y1={37} x2={C + 11} y2={37} />}
        </g>
        <line x1={C - 1.5} y1={8} x2={C - 1.5} y2={19} stroke={o.p.light} strokeOpacity="0.6" strokeWidth="1" />
        <rect x={C - 9} y={3} width="18" height="2" fill={lit(o)} {...pulse(o)} />
      </>
    ),
  },
  fin: {
    outline: `M${C} 0 L${C + 15} 19 H${C + 7} V42 H${C - 7} V19 H${C - 15} Z`,
    detail: (o) => (
      <>
        <line x1={C} y1={14} x2={C} y2={38} stroke={o.p.main} strokeOpacity="0.5" strokeWidth="1" />
        <path d={`M${C} 5 L${C + 5} 12 H${C - 5} Z`} fill={lit(o)} {...pulse(o)} />
        {bolt(o, C, 30, 3)}
      </>
    ),
  },
  lug: {
    outline: `M${C - 11} 42 V16 A11 11 0 0 1 ${C + 11} 16 V42 Z`,
    detail: (o) => (
      <>
        <circle cx={C} cy={16} r="6" fill={o.p.ink} stroke={o.p.light} strokeOpacity="0.7" strokeWidth="0.9" />
        <circle cx={C} cy={16} r="2.4" fill={lit(o)} {...pulse(o)} />
        <g stroke={o.p.main} strokeOpacity="0.45" strokeWidth="0.9">
          {!o.compact && <line x1={C - 7} y1={29} x2={C + 7} y2={29} />}
          <line x1={C - 7} y1={35} x2={C + 7} y2={35} />
        </g>
      </>
    ),
  },
  prongs: {
    outline: `M${C - 12} 42 V24 L${C - 10} 2 H${C - 4} L${C - 3} 22 H${C + 3} L${C + 4} 2 H${C + 10} L${C + 12} 24 V42 Z`,
    detail: (o) => (
      <>
        <line x1={C - 10} y1={36} x2={C + 10} y2={36} stroke={o.p.main} strokeOpacity="0.45" strokeWidth="0.9" />
        <rect x={C - 9} y={5} width="4" height="3" fill={lit(o)} {...pulse(o)} />
        <rect x={C + 5} y={5} width="4" height="3" fill={lit(o)} {...pulse(o)} />
        {bolt(o, C, 30, 3)}
      </>
    ),
  },
  rune: {
    outline: `M${C - 12} 7 L${C} 1 L${C + 12} 7 V42 H${C - 12} Z`,
    detail: (o) => (
      <>
        {!o.compact && <path d={`M${C - 9} 9 L${C} 5 L${C + 9} 9 V39 H${C - 9} Z`} fill="none" stroke={o.p.main} strokeOpacity="0.35" strokeWidth="0.7" />}
        <path
          d={`M${C - 5} 13 L${C + 5} 23 M${C + 5} 13 L${C - 5} 23 M${C} 26 V36`}
          fill="none"
          stroke={lit(o)}
          strokeWidth="1.6"
          strokeLinecap="round"
          {...pulse(o)}
        />
      </>
    ),
  },
  crown: {
    // Three points facing out, a gem on each.
    outline: `M${C - 14} 42 V3 L${C - 7} 11 L${C} 0 L${C + 7} 11 L${C + 14} 3 V42 Z`,
    detail: (o) => (
      <>
        <line x1={C - 12} y1={19} x2={C + 12} y2={19} stroke={o.p.main} strokeOpacity="0.6" strokeWidth="1.2" />
        {!o.compact && <line x1={C - 12} y1={22} x2={C + 12} y2={22} stroke={o.p.main} strokeOpacity="0.35" strokeWidth="0.8" />}
        {[[C - 11.5, 9], [C, 7], [C + 11.5, 9]].map(([x, y]) => (
          <polygon key={x} points={`${x},${y - 3} ${x + 2.4},${y} ${x},${y + 3} ${x - 2.4},${y}`} fill={lit(o)} {...pulse(o)} />
        ))}
        {bolt(o, C, 31, 3.2)}
      </>
    ),
  },
  hammer: {
    // A wide head on a narrow neck, with a lit slot across the head.
    outline: `M${C - 16} 1 H${C + 16} L${C + 17} 6 L${C + 16} 13 H${C + 6} V42 H${C - 6} V13 H${C - 16} L${C - 17} 6 Z`,
    detail: (o) => (
      <>
        <rect x={C - 12} y={5.5} width="24" height="3" rx="1.5" fill={lit(o)} {...pulse(o)} />
        <g stroke={o.p.main} strokeOpacity="0.5" strokeWidth="1">
          <line x1={C - 4} y1={20} x2={C + 4} y2={20} />
          <line x1={C - 4} y1={25} x2={C + 4} y2={25} />
          {!o.compact && <line x1={C - 4} y1={30} x2={C + 4} y2={30} />}
        </g>
        {bolt(o, C, 36, 2.8)}
      </>
    ),
  },
  shield: {
    // A kite shield, point toward her eye, with a glowing chevron.
    outline: `M${C - 13} 3 Q${C} -1 ${C + 13} 3 V21 Q${C + 12} 34 ${C} 42 Q${C - 12} 34 ${C - 13} 21 Z`,
    detail: (o) => (
      <>
        {!o.compact && <path d={`M${C - 10} 6 Q${C} 3 ${C + 10} 6 V21 Q${C + 9} 31 ${C} 38 Q${C - 9} 31 ${C - 10} 21 Z`} fill="none" stroke={o.p.main} strokeOpacity="0.4" strokeWidth="0.8" />}
        <path d={`M${C - 7} 12 L${C} 19 L${C + 7} 12`} fill="none" stroke={lit(o)} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" {...pulse(o)} />
        <path d={`M${C - 7} 20 L${C} 27 L${C + 7} 20`} fill="none" stroke={o.p.main} strokeOpacity="0.6" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
      </>
    ),
  },
  pincer: {
    // Two jaws curling in over an energy orb.
    outline: `M${C - 13} 42 V20 C${C - 13} 9 ${C - 9} 2 ${C - 2} 0 L${C - 3} 6 C${C - 6} 8 ${C - 7} 13 ${C - 7} 20 H${C + 7} C${C + 7} 13 ${C + 6} 8 ${C + 3} 6 L${C + 2} 0 C${C + 9} 2 ${C + 13} 9 ${C + 13} 20 V42 Z`,
    detail: (o) => (
      <>
        <circle cx={C} cy={12} r="5" fill={lit(o)} fillOpacity="0.25" {...pulse(o)} />
        <circle cx={C} cy={12} r="2.8" fill={lit(o)} {...pulse(o)} />
        <line x1={C - 11} y1={28} x2={C + 11} y2={28} stroke={o.p.main} strokeOpacity="0.5" strokeWidth="1" />
        {!o.compact && <path d={`M${C - 10.5} 20 C${C - 10.5} 12 ${C - 7.5} 6 ${C - 4} 4 M${C + 10.5} 20 C${C + 10.5} 12 ${C + 7.5} 6 ${C + 4} 4`} fill="none" stroke={o.p.main} strokeOpacity="0.4" strokeWidth="0.8" />}
        {bolt(o, C, 35, 3)}
      </>
    ),
  },
  turbine: {
    // A round fan housing on a short mount.
    outline: `M${C - 8} 42 V27 A14 14 0 1 1 ${C + 8} 27 V42 Z`,
    detail: (o) => (
      <>
        <circle cx={C} cy={15} r="10" fill={o.p.ink} stroke={o.p.main} strokeOpacity="0.7" strokeWidth="1" />
        {[0, 72, 144, 216, 288].map((a) => (
          <path key={a} d={`M${C} 15 Q${C + 5} 10 ${C + 2} 6.5`} fill="none" stroke={o.p.main} strokeOpacity="0.8" strokeWidth="1.6" strokeLinecap="round" transform={`rotate(${a} ${C} 15)`} />
        ))}
        <circle cx={C} cy={15} r="2.6" fill={lit(o)} {...pulse(o)} />
        <line x1={C - 6} y1={36} x2={C + 6} y2={36} stroke={o.p.main} strokeOpacity="0.5" strokeWidth="1" />
      </>
    ),
  },
  ziggurat: {
    // Stepped tower, a light on every step.
    outline: `M${C - 5} 1 H${C + 5} V9 H${C + 10} V18 H${C + 14} V42 H${C - 14} V18 H${C - 10} V9 H${C - 5} Z`,
    detail: (o) => (
      <>
        <rect x={C - 3} y={4} width="6" height="2.2" fill={lit(o)} {...pulse(o)} />
        <rect x={C - 8} y={12.5} width="16" height="2" fill={lit(o)} fillOpacity="0.75" {...pulse(o)} />
        <rect x={C - 12} y={22} width="24" height="2" fill={lit(o)} fillOpacity="0.5" {...pulse(o)} />
        {!o.compact && <line x1={C} y1={27} x2={C} y2={40} stroke={o.p.main} strokeOpacity="0.4" strokeWidth="0.8" />}
        {bolt(o, C - 7, 33, 2.6)}
        {bolt(o, C + 7, 33, 2.6)}
      </>
    ),
  },
  spear: {
    // A long blade with a glowing fuller.
    outline: `M${C} -2 L${C + 6} 11 L${C + 4} 17 H${C + 11} L${C + 9} 23 V42 H${C - 9} V23 L${C - 11} 17 H${C - 4} L${C - 6} 11 Z`,
    detail: (o) => (
      <>
        <line x1={C} y1={4} x2={C} y2={15} stroke={lit(o)} strokeWidth="2" strokeLinecap="round" {...pulse(o)} />
        <line x1={C - 9} y1={20} x2={C + 9} y2={20} stroke={o.p.main} strokeOpacity="0.6" strokeWidth="1" />
        {!o.compact && <path d={`M${C - 6} 27 H${C + 6} M${C - 6} 31 H${C + 6}`} stroke={o.p.main} strokeOpacity="0.4" strokeWidth="0.8" />}
        {bolt(o, C, 36, 2.8)}
      </>
    ),
  },
  knuckle: {
    // A gauntlet's four knuckles, each with a stud.
    outline: `M${C - 14} 42 V7 A3.5 3.5 0 0 1 ${C - 7} 7 A3.5 3.5 0 0 1 ${C} 7 A3.5 3.5 0 0 1 ${C + 7} 7 A3.5 3.5 0 0 1 ${C + 14} 7 V42 Z`,
    detail: (o) => (
      <>
        {[C - 10.5, C - 3.5, C + 3.5, C + 10.5].map((x) => (
          <circle key={x} cx={x} cy={7.5} r="1.8" fill={lit(o)} {...pulse(o)} />
        ))}
        <line x1={C - 12} y1={14} x2={C + 12} y2={14} stroke={o.p.main} strokeOpacity="0.6" strokeWidth="1.2" />
        {!o.compact && [C - 7, C, C + 7].map((x) => <line key={x} x1={x} y1={15} x2={x} y2={24} stroke={o.p.main} strokeOpacity="0.35" strokeWidth="0.8" />)}
        {bolt(o, C, 31, 3.2)}
      </>
    ),
  },
};

/** The fixed honeycomb texture on the armor plates. */
export function PlatePattern({ id, color }: { id: string; color: string }) {
  return (
    <pattern id={id} patternUnits="userSpaceOnUse" width="9" height="15.6">
      <path d="M4.5 0 L9 2.6 L9 7.8 L4.5 10.4 L0 7.8 L0 2.6 Z M4.5 10.4 L4.5 15.6" fill="none" stroke={color} strokeOpacity="0.13" strokeWidth="0.7" />
    </pattern>
  );
}

/* ── Inner cog ─────────────────────────────────────────────────────────────── */
// The spinning ring between the dial and the plates. It lives in a band from r 146 to 158; the
// designs borrow the old plate-pattern motifs. Each returns static art; the halo spins it.

const poly = (pts: (readonly [number, number])[]) => pts.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(" ");
const range = (n: number) => Array.from({ length: n }, (_, i) => i);

export function CogArt({ kind, p }: { kind: Skin["cog"]; p: Palette }) {
  const rim = (r: number, o = 0.55, w = 1.2) => <circle cx={C} cy={C} r={r} fill="none" stroke={p.main} strokeOpacity={o} strokeWidth={w} />;
  switch (kind) {
    case "classic":
      return (
        <>
          {rim(149, 0.55, 2)}
          {range(48).map((i) => (
            <rect key={i} x={C - 2.5} y={C - 156} width="5" height="7" fill={p.main} fillOpacity={i % 6 === 0 ? 0.95 : 0.5} transform={`rotate(${i * 7.5} ${C} ${C})`} />
          ))}
        </>
      );
    case "honeycomb":
      return (
        <>
          {rim(146.5, 0.45, 1)}
          {range(36).map((i) => {
            const [x, y] = pt(152, i * 10);
            return (
              <polygon key={i} points={hex(x, y, 4.6)} transform={`rotate(${i * 10} ${x} ${y})`} fill={p.main} fillOpacity={i % 9 === 0 ? 0.85 : 0.12} stroke={p.main} strokeOpacity="0.75" strokeWidth="1" />
            );
          })}
        </>
      );
    case "carbon":
      // Woven: tangential and radial bars take turns.
      return (
        <>
          {rim(148, 0.5, 1.4)}
          {range(48).map((i) =>
            i % 2 === 0 ? (
              <rect key={i} x={C - 3.5} y={C - 155} width="7" height="3.2" fill={p.main} fillOpacity={i % 12 === 0 ? 0.95 : 0.55} transform={`rotate(${i * 7.5} ${C} ${C})`} />
            ) : (
              <rect key={i} x={C - 1.2} y={C - 157.5} width="2.4" height="8.5" fill={p.main} fillOpacity="0.4" transform={`rotate(${i * 7.5} ${C} ${C})`} />
            ),
          )}
        </>
      );
    case "circuit":
      // Traces that step out, jog sideways and end in a pad.
      return (
        <>
          {rim(147.5, 0.55, 1.2)}
          {range(24).map((i) => {
            const a = i * 15;
            const [x0, y0] = pt(147.5, a);
            const [x1, y1] = pt(151.5, a);
            const [x2, y2] = pt(151.5, a + 5);
            const [x3, y3] = pt(155.5, a + 5);
            return (
              <g key={i}>
                <path d={`M${x0} ${y0} L${x1} ${y1} A151.5 151.5 0 0 1 ${x2} ${y2} L${x3} ${y3}`} fill="none" stroke={p.main} strokeOpacity="0.7" strokeWidth="1.2" />
                <circle cx={x3} cy={y3} r={i % 3 === 0 ? 2.2 : 1.6} fill={i % 3 === 0 ? p.light : p.main} fillOpacity={i % 3 === 0 ? 0.95 : 0.7} />
              </g>
            );
          })}
        </>
      );
    case "hazard":
      return (
        <>
          <circle cx={C} cy={C} r="151.5" fill="none" stroke={p.ink} strokeOpacity="0.6" strokeWidth="9" />
          {range(45).map((i) => {
            const a = i * 8;
            return <polygon key={i} points={poly([pt(147, a), pt(147, a + 3.2), pt(156, a + 6.4), pt(156, a + 3.2)])} fill={p.main} fillOpacity="0.7" />;
          })}
          {rim(147, 0.6, 1)}
          {rim(156, 0.6, 1)}
        </>
      );
    case "dots":
      // A bearing race: balls between two rims.
      return (
        <>
          {rim(146.5, 0.5, 1)}
          {rim(157.5, 0.5, 1)}
          {range(32).map((i) => {
            const [x, y] = pt(152, i * 11.25);
            return <circle key={i} cx={x} cy={y} r={i % 4 === 0 ? 3.4 : 2.4} fill={i % 4 === 0 ? p.light : p.main} fillOpacity={i % 4 === 0 ? 0.95 : 0.6} />;
          })}
        </>
      );
    case "topo": {
      // Contour lines: two waves around the ring, out of step.
      const wave = (phase: number, amp: number) =>
        poly(range(181).map((k) => pt(152 + amp * Math.sin((k * 2 * 12 * Math.PI) / 180 + phase), k * 2)));
      return (
        <>
          <polyline points={wave(0, 3.6)} fill="none" stroke={p.main} strokeOpacity="0.8" strokeWidth="1.3" />
          <polyline points={wave(Math.PI, 2.2)} fill="none" stroke={p.main} strokeOpacity="0.45" strokeWidth="1" />
          {rim(146.5, 0.35, 0.8)}
        </>
      );
    }
    case "meander": {
      // Greek key: one hook every 12°.
      const P = (u: number, r: number, a0: number) => pt(r, a0 + u * 12);
      return (
        <>
          {rim(147, 0.7, 1.2)}
          {rim(157, 0.45, 1)}
          {range(30).map((i) => {
            const a = i * 12;
            const pts = [P(0, 147, a), P(0, 155, a), P(0.75, 155, a), P(0.75, 149.5, a), P(0.35, 149.5, a), P(0.35, 152.5, a)];
            return <polyline key={i} points={poly(pts)} fill="none" stroke={p.main} strokeOpacity={i % 5 === 0 ? 1 : 0.7} strokeWidth="1.3" strokeLinejoin="miter" />;
          })}
        </>
      );
    }
  }
}

/* ── Scanner: what sweeps around the dial ring (r 110–146) ──────────────────── */

const trail = (n: number, step: number) => Array.from({ length: n }, (_, i) => i).map((i) => ({ a0: -i * step - step, a1: -i * step, k: (n - i) / n }));

/** A beam with a fading trail behind it, pointing at angle `at`. */
function Beam({ p, at = 0, slices = 10, step = 4, r1 = 110, r2 = 146 }: { p: Palette; at?: number; slices?: number; step?: number; r1?: number; r2?: number }) {
  return (
    <g transform={`rotate(${at} ${C} ${C})`}>
      {trail(slices, step).map(({ a0, a1, k }, i) => (
        <path key={i} d={platePath(r1, r2, a0, a1, 0)} fill={p.main} fillOpacity={0.32 * k} />
      ))}
      <line x1={C} y1={C - r1} x2={C} y2={C - r2} stroke={p.light} strokeWidth="1.5" />
    </g>
  );
}

/**
 * The scanner, turning with `angle` (degrees; it speeds up when she's charged). The invisible
 * r = 146 circle keeps the group's box centered, so it spins around her eye.
 */
export function Scanner({ kind, p, angle }: { kind: Skin["scanner"]; p: Palette; angle: MotionValue<number> }) {
  // Pulse: rings that grow outward through the band, one every 120° of turn.
  const r1 = useTransform(angle, (a) => 110 + ((a % 120) / 120) * 36);
  const r2 = useTransform(angle, (a) => 110 + (((a + 60) % 120) / 120) * 36);
  const o1 = useTransform(r1, (r) => 1 - 0.8 * ((r - 110) / 36));
  const o2 = useTransform(r2, (r) => 1 - 0.8 * ((r - 110) / 36));
  const box = <circle cx={C} cy={C} r="146" fill="none" />;
  const spin = (children: ReactNode) => (
    <motion.g style={{ rotate: angle }}>
      {box}
      {children}
    </motion.g>
  );

  switch (kind) {
    case "radar":
      return spin(<Beam p={p} />);
    case "twin":
      return spin(<><Beam p={p} /><Beam p={p} at={180} /></>);
    case "quad":
      return spin([0, 90, 180, 270].map((a) => <Beam key={a} p={p} at={a} slices={6} step={3} />));
    case "comet":
      // A bright head with a tail of shrinking sparks.
      return spin(
        <>
          {Array.from({ length: 12 }, (_, i) => {
            const [x, y] = pt(128, -i * 5);
            return <circle key={i} cx={x} cy={y} r={i === 0 ? 7.5 : 5.8 - i * 0.4} fill={i === 0 ? p.light : p.main} fillOpacity={i === 0 ? 1 : 0.75 - i * 0.055} />;
          })}
          <circle cx={C} cy={C - 128} r="14" fill={p.light} fillOpacity="0.22" />
        </>,
      );
    case "loader":
      // Segmented arc, like a loading spinner, fading toward its tail.
      return spin(
        Array.from({ length: 9 }, (_, i) => (
          <path key={i} d={platePath(122, 140, -i * 13 - 10, -i * 13, 0)} fill={i === 0 ? p.light : p.main} fillOpacity={i === 0 ? 0.95 : 0.8 - i * 0.08} />
        )),
      );
    case "laser":
      // A thin beam straight across both sides, with a soft glow and no trail.
      return spin(
        <>
          {[0, 180].map((a) => (
            <g key={a} transform={`rotate(${a} ${C} ${C})`}>
              <path d={platePath(110, 146, -2.5, 2.5, 0)} fill={p.main} fillOpacity="0.28" />
              <line x1={C} y1={C - 110} x2={C} y2={C - 146} stroke={p.light} strokeWidth="2" />
              <circle cx={C} cy={C - 146} r="2.6" fill={p.light} />
            </g>
          ))}
        </>,
      );
    case "pulse":
      return (
        <>
          <motion.circle cx={C} cy={C} r={r1} fill="none" stroke={p.light} strokeWidth="4" style={{ strokeOpacity: o1 }} />
          <motion.circle cx={C} cy={C} r={r2} fill="none" stroke={p.main} strokeWidth="4" style={{ strokeOpacity: o2 }} />
        </>
      );
    case "none":
      return null;
  }
}
