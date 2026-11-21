import type { ReactNode } from "react";
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
};

const every = (n: number, offset = 0) => Array.from({ length: n }, (_, i) => offset + (i * 360) / n);
const ring = (mids: number[], span: number, r1: number, r2: number, badge: boolean): Seg[] =>
  mids.map((mid, index) => ({ mid, a0: mid - span / 2, a1: mid + span / 2, r1, r2, badge, index }));
const DIAG = every(4, 45);

export const RING_SPECS: Record<Skin["ring"], RingSpec> = {
  plates4: { segs: ring(every(4), 66, 160, 184, true), clamps: DIAG, chamfer: 4 },
  segments6: { segs: ring(every(6), 50, 160, 184, true), clamps: [30, 150, 210, 330], chamfer: 4 },
  blades8: { segs: ring(every(8), 34, 166, 184, false), clamps: every(4, 22.5), chamfer: 6 },
  band: { segs: ring(every(4), 88.5, 162, 184, true), clamps: DIAG, chamfer: 0 },
  crescents: { segs: ring([90, 270], 136, 158, 186, true), clamps: [-12, 12, 168, 192], chamfer: 6 },
  crown: { segs: ring(every(4), 52, 160, 184, true), clamps: DIAG, chamfer: 4, spikes: true },
  shards: { segs: ring(every(8), 22, 164, 186, false), clamps: every(4, 22.5), chamfer: 6, push: 1.8 },
  gyro: { segs: [], clamps: DIAG, chamfer: 0, gyro: true },
};

/** Vent slots either side of a plate's badge, as many as fit. */
export function ventAngles(s: Seg) {
  const out: number[] = [];
  for (let k = 0; 11 + k * 4 <= (s.a1 - s.a0) / 2 - 6; k++) out.push(s.mid - (11 + k * 4), s.mid + (11 + k * 4));
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
