import { useId, useRef } from "react";
import { useAnimationFrame } from "framer-motion";
import type { MotionValue } from "framer-motion";
import type { Palette } from "./skin";
import { C } from "./shell-parts";

/*
 * Solid shells (pyramid, cube, sphere) around her eye, in the halo's 400×400 viewBox.
 *
 * The ring shell is a stack of flat CSS 3D layers. A solid needs faces that turn away and hide,
 * so it's projected here instead: the same tilt and perspective as the CSS rig (320cqw = 1280
 * units), back faces culled, faces lit by a fixed light. It draws in front of the rig, with a
 * window cut where the eye shows through.
 */

export type SolidKind = "pyramid" | "cube" | "sphere";

type V = [number, number, number];
const add = (a: V, b: V): V => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a: V, b: V): V => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const mul = (a: V, k: number): V => [a[0] * k, a[1] * k, a[2] * k];
const dot = (a: V, b: V) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a: V, b: V): V => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const unit = (a: V) => mul(a, 1 / Math.hypot(a[0], a[1], a[2]));
const rotY = ([x, y, z]: V, deg: number): V => {
  const r = (deg * Math.PI) / 180;
  const c = Math.cos(r);
  const s = Math.sin(r);
  return [x * c + z * s, y, -x * s + z * c];
};
const rotX = ([x, y, z]: V, deg: number): V => {
  const r = (deg * Math.PI) / 180;
  const c = Math.cos(r);
  const s = Math.sin(r);
  return [x, y * c - z * s, y * s + z * c];
};

const PERSPECTIVE = 1280; // matches [perspective:320cqw] in the halo
const CAM: V = [0, 0, PERSPECTIVE];
const LIGHT = unit([-0.45, -0.7, 0.6]); // from the top left, in front
const project = ([x, y, z]: V) => {
  const k = PERSPECTIVE / (PERSPECTIVE - z);
  return `${(C + x * k).toFixed(1)} ${(C + y * k).toFixed(1)}`;
};
const poly = (pts: V[]) => `M${pts.map(project).join(" L")} Z`;
const ring = (c: V, u: V, v: V, r: number, n = 36) =>
  Array.from({ length: n }, (_, i) => {
    const a = (i / n) * Math.PI * 2;
    return add(c, add(mul(u, r * Math.cos(a)), mul(v, r * Math.sin(a))));
  });

type Face = { pts: V[]; c: V; n: V; u: V; v: V; win: number; smooth: boolean };

function face(pts: V[], center: V, win = 0, smooth = false): Face {
  const c = mul(pts.reduce(add), 1 / pts.length);
  let n = unit(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])));
  if (dot(n, sub(c, center)) < 0) n = mul(n, -1);
  const u = unit(sub(pts[1], pts[0]));
  return { pts, c, n, u, v: cross(n, u), win, smooth };
}

/** Where the eye sits inside each solid (depth in cqw), how big it is, and the socket behind it. */
export const SOLID_EYE: Record<SolidKind, { z: number; scale: number; socket: number }> = {
  cube: { z: 31, scale: 1, socket: 124 },
  pyramid: { z: 24, scale: 0.78, socket: 98 },
  sphere: { z: 27.5, scale: 1, socket: 128 },
};

const CUBE_A = 140;
const PYR = { b: 170, base: 107, apex: -213 }; // half base width; base and apex heights (y down)
const SPHERE_R = 160;
const SPHERE_WIN = 108; // window radius
const SPHERE_LAT = [-90, -60, -30, 0, 30, 60, 90];
const SPHERE_LON = 8;

const SOLIDS: Record<SolidKind, Face[]> = {
  cube: (() => {
    const a = CUBE_A;
    const front: V[] = [[-a, -a, a], [a, -a, a], [a, a, a], [-a, a, a]];
    const sides = [0, 90, 180, 270].map((d) => face(front.map((p) => rotY(p, d)), [0, 0, 0], 104));
    const top = face([[-a, -a, -a], [a, -a, -a], [a, -a, a], [-a, -a, a]], [0, 0, 0]);
    const bottom = face([[-a, a, a], [a, a, a], [a, a, -a], [-a, a, -a]], [0, 0, 0]);
    return [...sides, top, bottom];
  })(),
  pyramid: (() => {
    const { b, base, apex } = PYR;
    const center: V = [0, base - (base - apex) / 4, 0];
    const front: V[] = [[-b, base, b], [b, base, b], [0, apex, 0]];
    const sides = [0, 90, 180, 270].map((d) => face(front.map((p) => rotY(p, d)), center, 80));
    const floor = face([[-b, base, b], [b, base, b], [b, base, -b], [-b, base, -b]], center);
    return [...sides, floor];
  })(),
  sphere: (() => {
    const R = SPHERE_R;
    const at = (lat: number, lon: number): V => {
      const la = (lat * Math.PI) / 180;
      const lo = (lon * Math.PI) / 180;
      return [R * Math.cos(la) * Math.sin(lo), -R * Math.sin(la), R * Math.cos(la) * Math.cos(lo)];
    };
    const out: Face[] = [];
    const step = 360 / SPHERE_LON;
    for (let i = 0; i < SPHERE_LAT.length - 1; i++)
      for (let j = 0; j < SPHERE_LON; j++) {
        const [l0, l1] = [SPHERE_LAT[i], SPHERE_LAT[i + 1]];
        const [o0, o1] = [j * step + step / 2, (j + 1) * step + step / 2];
        const pts = [at(l0, o0), at(l0, o1), at(l1, o1), at(l1, o0)].filter((p, k, all) => k === 0 || Math.hypot(...sub(p, all[k - 1])) > 0.01);
        const f = face(pts.length >= 3 ? pts : [at(l0, o0), at(l1, o1), at(l1, o0)], [0, 0, 0], 0, true);
        // A panel's normal is the direction to its middle (its corners can be uneven near the poles).
        f.n = unit(at((l0 + l1) / 2, (o0 + o1) / 2));
        out.push(f);
      }
    return out;
  })(),
};

/** How many of each drawn piece a kind needs, so the elements never change while animating. */
const SLOTS = (k: SolidKind) => ({ panels: SOLIDS[k].length, rims: k === "sphere" ? 1 : SOLIDS[k].filter((f) => f.win).length });

type Pose = { rx: number; ry: number; spin: number; push: number };
type Drawn = { d: string; fill: string; inset: string; bolts: string };
type Frame = { panels: Drawn[]; holes: string; rims: string[]; lenses: string[]; flow: string; eye: [number, number] | null };

const hexRgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const toHex = (rgb: string) => (rgb.startsWith("#") ? rgb : `#${rgb.match(/\d+/g)!.map((v) => (+v).toString(16).padStart(2, "0")).join("")}`);
const mix = (a: string, b: string, t: number) => {
  const [x, y] = [hexRgb(toHex(a)), hexRgb(toHex(b))];
  return `rgb(${x.map((v, i) => Math.round(v + (y[i] - v) * t)).join(" ")})`;
};

function build(kind: SolidKind, { rx, ry, spin, push }: Pose, p: Palette, compact: boolean): Frame {
  const view = (q: V) => rotX(rotY(rotY(q, spin), ry), rx); // spin inside the tilt, like the CSS rig
  const tilt = (q: V) => rotX(rotY(q, ry), rx);
  // Lit faces go from the plate's dark to a brighter metal; the brightest catch a little glow.
  const metal = mix(p.plateA, p.light, 0.3);
  const shade = (l: number) => (l > 0.8 ? mix(metal, p.main, (l - 0.8) * 1.6) : mix(p.deep, metal, 0.12 + l * 1.1));
  const panels: Drawn[] = [];
  const holes: string[] = [];
  const rims: string[] = [];
  const lenses: string[] = []; // closed hatches: windows that aren't the one facing you
  let eye: [number, number] | null = null; // the open window's middle on screen (for previews)
  const flat = (q: V): [number, number] => {
    const k = PERSPECTIVE / (PERSPECTIVE - q[2]);
    return [C + q[0] * k, C + q[1] * k];
  };
  const out = 14 * push; // faces split apart along their normals in a surge

  const seen = SOLIDS[kind]
    .map((f) => {
      const n = view(f.n);
      const shift = mul(n, out);
      const c = add(view(f.c), shift);
      return { f, n, shift, c, z: c[2] };
    })
    .filter(({ n, c }) => dot(n, sub(CAM, c)) > 0)
    .sort((a, b) => a.z - b.z);
  // Only the window turned most toward you is open (the eye sits behind it).
  const open = seen.filter((s) => s.f.win).reduce<(typeof seen)[number] | null>((best, s) => (!best || s.n[2] > best.n[2] ? s : best), null);

  for (const item of seen) {
    const { f, n, shift, c } = item;
    const pts = f.pts.map((q) => add(view(q), shift));
    const lit = Math.max(0, dot(n, LIGHT));
    const toward = (k: number) => f.pts.map((q) => add(view(add(f.c, mul(sub(q, f.c), k))), shift));
    panels.push({
      d: poly(pts),
      fill: shade(lit),
      inset: f.smooth || compact ? "" : poly(toward(0.87)),
      bolts:
        f.smooth || compact
          ? ""
          : toward(0.94)
              .map((q) => `M${project(q)} m-2.4 0 a2.4 2.4 0 1 0 4.8 0 a2.4 2.4 0 1 0 -4.8 0`)
              .join(" "),
    });
    if (f.win) {
      const u = view(f.u);
      const v = view(f.v);
      rims.push(`${poly(ring(c, u, v, f.win + 9))} ${poly(ring(c, u, v, f.win))}`);
      if (item === open) {
        holes.push(poly(ring(c, u, v, f.win)));
        eye = flat(c);
        lenses.push("");
      } else lenses.push(poly(ring(c, u, v, f.win)));
    }
  }

  let flow = "";
  if (kind === "sphere") {
    // The window faces you and doesn't spin; the plates turn around it.
    const f = tilt([0, 0, 1]);
    const u = tilt([1, 0, 0]);
    const v = tilt([0, 1, 0]);
    const depth = Math.sqrt(SPHERE_R ** 2 - SPHERE_WIN ** 2);
    const c = add(mul(f, depth), mul(f, out));
    holes.push(poly(ring(c, u, v, SPHERE_WIN)));
    eye = flat(c);
    rims.push(`${poly(ring(c, u, v, SPHERE_WIN + 10))} ${poly(ring(c, u, v, SPHERE_WIN))}`);
    lenses.push("");
    if (!compact) {
      // The glowing seam along her equator, front half only.
      const pts = Array.from({ length: 73 }, (_, i) => view([SPHERE_R * Math.sin((i * Math.PI) / 36), 0, SPHERE_R * Math.cos((i * Math.PI) / 36)]));
      let pen = false;
      for (const q of pts) {
        const ok = dot(q, sub(CAM, q)) > 0;
        if (ok) flow += `${pen ? "L" : "M"}${project(q)} `;
        pen = ok;
      }
    }
  }

  const empty = { d: "", fill: "none", inset: "", bolts: "" };
  const slots = SLOTS(kind);
  while (panels.length < slots.panels) panels.unshift(empty);
  while (rims.length < slots.rims) rims.push("");
  while (lenses.length < slots.rims) lenses.push("");
  return { panels, holes: holes.join(" "), rims, lenses, flow, eye };
}

type Live = { tiltX: MotionValue<number>; tiltY: MotionValue<number>; spin: MotionValue<number>; push: MotionValue<number> };

/**
 * The solid, as SVG content for the halo's 400×400 viewBox. With `live` it follows her tilt,
 * spin and surge every frame; otherwise it's drawn once at `pose` (wardrobe previews).
 */
export function SolidShell({
  kind,
  p,
  charged = false,
  compact = false,
  live,
  pose = { rx: -12, ry: 26, spin: 0, push: 0 },
}: {
  kind: SolidKind;
  p: Palette;
  charged?: boolean;
  compact?: boolean;
  live?: Live;
  pose?: Pose;
}) {
  const mask = `solid-${useId().replace(/[^a-z0-9]/gi, "")}`;
  const now = (): Pose => (live ? { rx: live.tiltX.get(), ry: live.tiltY.get(), spin: live.spin.get(), push: live.push.get() } : pose);
  const first = build(kind, now(), p, compact);
  const el = useRef({ panels: [] as (SVGPathElement | null)[][], rims: [] as (SVGPathElement | null)[], lenses: [] as (SVGPathElement | null)[], holes: null as SVGPathElement | null, flow: null as SVGPathElement | null });

  const keep = (i: number, k: number, n: SVGPathElement | null) => {
    const all = el.current.panels;
    if (!all[i]) all[i] = [];
    all[i][k] = n;
  };

  useAnimationFrame(() => {
    if (!live) return;
    const f = build(kind, now(), p, compact);
    const e = el.current;
    f.panels.forEach((d, i) => {
      const [base, inset, bolts] = e.panels[i] ?? [];
      base?.setAttribute("d", d.d);
      base?.setAttribute("fill", d.fill);
      inset?.setAttribute("d", d.inset);
      e.panels[i]?.[3]?.setAttribute("d", d.inset);
      bolts?.setAttribute("d", d.bolts);
    });
    f.rims.forEach((d, i) => e.rims[i]?.setAttribute("d", d));
    f.lenses.forEach((d, i) => e.lenses[i]?.setAttribute("d", d));
    e.holes?.setAttribute("d", f.holes || "M0 0");
    e.flow?.setAttribute("d", f.flow);
  });

  const edge = charged ? 1 : 0.7;
  const glow = charged ? p.hot : p.main;
  return (
    <g>
      <defs>
        <mask id={mask} maskUnits="userSpaceOnUse" x="-200" y="-200" width="800" height="800">
          <rect x="-200" y="-200" width="800" height="800" fill="white" />
          <path ref={(n) => void (el.current.holes = n)} d={first.holes || "M0 0"} fill="black" />
        </mask>
      </defs>
      <g mask={`url(#${mask})`}>
        {kind === "sphere" ? (
          // fills the rim between panels, which are only drawn while their middle faces you
          <circle cx={C} cy={C} r={(SPHERE_R * PERSPECTIVE) / Math.sqrt(PERSPECTIVE ** 2 - SPHERE_R ** 2)} fill={p.deep} stroke={p.main} strokeOpacity={edge * 0.6} strokeWidth="1.4" />
        ) : null}
        {first.panels.map((d, i) => (
          <g key={i}>
            <path
              ref={(n) => keep(i, 0, n)}
              d={d.d}
              fill={d.fill}
              stroke={p.main}
              strokeOpacity={kind === "sphere" ? edge * 0.75 : edge}
              strokeWidth={kind === "sphere" ? 1.1 : 1.8}
              strokeLinejoin="round"
            />
            <path ref={(n) => keep(i, 1, n)} d={d.inset} fill="none" stroke={p.main} strokeOpacity="0.3" strokeWidth="1.2" />
            <path
              ref={(n) => keep(i, 3, n)}
              d={d.inset}
              fill="none"
              stroke={glow}
              strokeOpacity={charged ? 1 : 0.8}
              strokeWidth="1.4"
              strokeDasharray="5 11"
              strokeLinecap="round"
              className="halo-flow"
            />
            <path ref={(n) => keep(i, 2, n)} d={d.bolts} fill={p.ink} stroke={p.main} strokeOpacity="0.8" strokeWidth="1" />
          </g>
        ))}
        <path
          ref={(n) => void (el.current.flow = n)}
          d={first.flow}
          fill="none"
          stroke={glow}
          strokeOpacity={charged ? 1 : 0.85}
          strokeWidth="2"
          strokeDasharray="5 11"
          strokeLinecap="round"
          className="halo-flow"
        />
      </g>
      {!live && first.eye ? (
        // previews have no eye behind them: a small one in the open window
        <g>
          <path d={first.holes} fill={p.ink} />
          <circle cx={first.eye[0]} cy={first.eye[1]} r={kind === "pyramid" ? 30 : 40} fill={p.main} />
          <circle cx={first.eye[0]} cy={first.eye[1]} r={kind === "pyramid" ? 12 : 16} fill={p.hot} />
        </g>
      ) : null}
      {first.lenses.map((d, i) => (
        <path key={`l${i}`} ref={(n) => void (el.current.lenses[i] = n)} d={d} fill={p.ink} stroke={p.main} strokeOpacity="0.45" strokeWidth="1.2" />
      ))}
      {first.rims.map((d, i) => (
        <path
          key={i}
          ref={(n) => void (el.current.rims[i] = n)}
          d={d}
          fillRule="evenodd"
          fill={p.socket}
          stroke={charged ? p.hot : p.light}
          strokeOpacity={edge}
          strokeWidth="1.4"
        />
      ))}
    </g>
  );
}
