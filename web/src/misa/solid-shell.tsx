import { useId, useMemo, useRef } from "react";
import { useAnimationFrame } from "framer-motion";
import type { MotionValue } from "framer-motion";
import type { Palette, Skin } from "./skin";
import { C } from "./shell-parts";
import MechaEye from "./mecha-eye";

/*
 * Solid shells (pyramid, cube, sphere) around her eye, in the halo's 400×400 viewBox.
 *
 * The ring shell is a stack of flat CSS 3D layers. A solid needs faces that turn away and hide,
 * so it's projected here instead: the same tilt and perspective as the CSS rig (320cqw = 1280
 * units), back faces culled, faces lit by a fixed light. It draws in front of the rig, with a
 * window cut where the eye shows through.
 */


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

type Face = { pts: V[]; c: V; n: V; u: V; v: V; win: number; smooth: boolean; inr: number; tone?: number };

/** Distance from a face's middle to its nearest edge (how much room a window has). */
const inradius = (f: { pts: V[]; c: V }) =>
  Math.min(
    ...f.pts.map((a, i) => {
      const b = f.pts[(i + 1) % f.pts.length];
      const e = unit(sub(b, a));
      const w = sub(f.c, a);
      return Math.hypot(...sub(w, mul(e, dot(w, e))));
    }),
  );

function face(pts: V[], center: V, win = 0, smooth = false): Face {
  const c = mul(pts.reduce(add), 1 / pts.length);
  let n = unit(cross(sub(pts[1], pts[0]), sub(pts[2], pts[0])));
  if (dot(n, sub(c, center)) < 0) n = mul(n, -1);
  const u = unit(sub(pts[1], pts[0]));
  const f: Face = { pts, c, n, u, v: cross(n, u), win, smooth, inr: 0 };
  f.inr = inradius(f);
  return f;
}

const rotZ = ([x, y, z]: V, deg: number): V => {
  const r = (deg * Math.PI) / 180;
  const c = Math.cos(r);
  const s = Math.sin(r);
  return [x * c - y * s, x * s + y * c, z];
};

/**
 * The faces of a convex solid: for each outward direction in `normals`, the corners of `verts`
 * furthest along it, in order around the face.
 */
function hull(verts: V[], normals: V[]): V[][] {
  return normals.map((raw) => {
    const n = unit(raw);
    const top = Math.max(...verts.map((q) => dot(q, n)));
    const on = verts.filter((q) => dot(q, n) > top - 1e-6 * Math.abs(top) - 1e-9);
    const c = mul(on.reduce(add), 1 / on.length);
    const u = unit(sub(on[0], c));
    const v = cross(n, u);
    return on.sort((a, b) => Math.atan2(dot(sub(a, c), v), dot(sub(a, c), u)) - Math.atan2(dot(sub(b, c), v), dot(sub(b, c), u)));
  });
}

/** Turns a solid so the face with normal `front` faces you, one corner straight up, and scales it. */
function orient(faces: V[][], front: V, size: number): V[][] {
  const f = unit(front);
  const yaw = (-Math.atan2(f[0], f[2]) * 180) / Math.PI;
  const f1 = rotY(f, yaw);
  const pitch = (Math.atan2(f1[1], f1[2]) * 180) / Math.PI;
  const turn = (q: V) => rotX(rotY(q, yaw), pitch);
  const frontFace = faces.find((pts) => dot(unit(mul(pts.reduce(add), 1 / pts.length)), f) > 0.999)!.map(turn);
  const corner = frontFace[0];
  const roll = (Math.atan2(corner[0], -corner[1]) * 180) / Math.PI; // put that corner at the top
  const longest = Math.max(...faces.flat().map((q) => Math.hypot(...q)));
  return faces.map((pts) => pts.map((q) => mul(rotZ(turn(q), roll), size / longest)));
}

const PHI = (1 + Math.sqrt(5)) / 2;
const ICOSA: V[] = [[0, 1, PHI], [0, 1, -PHI], [0, -1, PHI], [0, -1, -PHI], [1, PHI, 0], [1, -PHI, 0], [-1, PHI, 0], [-1, -PHI, 0], [PHI, 0, 1], [PHI, 0, -1], [-PHI, 0, 1], [-PHI, 0, -1]];
const DODECA: V[] = [
  ...[-1, 1].flatMap((x) => [-1, 1].flatMap((y) => [-1, 1].map((z): V => [x, y, z]))),
  ...[-1, 1].flatMap((a) => [-1, 1].flatMap((b): V[] => [[0, a * PHI, b / PHI], [a * PHI, b / PHI, 0], [a / PHI, 0, b * PHI]])),
];

type Spec = {
  faces: Face[];
  /** What a surge turns her around, and by how much per quarter turn of the ring shell. */
  spin: { axis: "y" | "z"; step: number };
  /** Round solids: one window that always faces you (the panels turn around it). */
  window?: { depth: number; r: number };
  /** A glowing seam loop that turns with her. `round`: hidden where it goes around the back. */
  flow?: { pts: V[]; round: boolean };
  /** Panels without inner lines, bolts or flow (curved and many-faced shells). */
  smooth?: boolean;
  /** Every window has an eye looking out, not just the front one. */
  sideEyes?: boolean;
  /** Round solids: a backing disc of this radius fills the edge between panels. */
  body?: number;
  /** Where the eye sits inside (depth in cqw), how big it is, and the socket behind it. */
  eye: { z: number; scale: number; socket: number };
  /** The angle for the wardrobe tile. */
  tile?: Pose;
};

const solidFaces = (polys: V[][], win: (pts: V[]) => number, center: V = [0, 0, 0], smooth = false) =>
  polys.map((pts) => face(pts, center, win(pts), smooth));
/** Only the face looking straight at you gets the window (for solids that spin around the view axis). */
const frontOnly = (r: number) => (pts: V[]) => (unit(mul(pts.reduce(add), 1 / pts.length))[2] > 0.999 ? r : 0);

const SPHERE_R = 160;
const SPHERE_WIN = 108; // window radius
const roundWindow = (R: number) => ({ depth: Math.sqrt(R ** 2 - SPHERE_WIN ** 2), r: SPHERE_WIN });

export type SolidKind = "pyramid" | "cube" | "hexprism" | "diamond" | "dodeca" | "sphere" | "geodesic";

const SPECS: Record<SolidKind, Spec> = {
  cube: (() => {
    const a = 140;
    const front: V[] = [[-a, -a, a], [a, -a, a], [a, a, a], [-a, a, a]];
    const sides = [0, 90, 180, 270].map((d) => face(front.map((p) => rotY(p, d)), [0, 0, 0], 104));
    const top = face([[-a, -a, -a], [a, -a, -a], [a, -a, a], [-a, -a, a]], [0, 0, 0]);
    const bottom = face([[-a, a, a], [a, a, a], [a, a, -a], [-a, a, -a]], [0, 0, 0]);
    return { faces: [...sides, top, bottom], spin: { axis: "y", step: 90 }, eye: { z: 31, scale: 1, socket: 124 } };
  })(),
  pyramid: (() => {
    const [b, base, apex] = [170, 107, -213]; // half base width; base and apex heights (y down)
    const center: V = [0, base - (base - apex) / 4, 0];
    const front: V[] = [[-b, base, b], [b, base, b], [0, apex, 0]];
    const sides = [0, 90, 180, 270].map((d) => face(front.map((p) => rotY(p, d)), center, 80));
    const floor = face([[-b, base, b], [b, base, b], [b, base, -b], [-b, base, -b]], center);
    return { faces: [...sides, floor], spin: { axis: "y", step: 90 }, eye: { z: 24, scale: 0.78, socket: 98 } };
  })(),
  diamond: (() => {
    const v: V[] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
    const normals = [-1, 1].flatMap((x) => [-1, 1].flatMap((y) => [-1, 1].map((z): V => [x, y, z])));
    const polys = orient(hull(v, normals), [1, 1, 1], 210);
    return { faces: solidFaces(polys, frontOnly(74)), spin: { axis: "z", step: 120 }, eye: { z: 27, scale: 0.7, socket: 84 } };
  })(),
  dodeca: (() => {
    const polys = orient(hull(DODECA, ICOSA), ICOSA[0], 182);
    return { faces: solidFaces(polys, frontOnly(74)), spin: { axis: "z", step: 72 }, eye: { z: 32, scale: 0.7, socket: 86 } };
  })(),
  hexprism: (() => {
    const [a, h] = [165, 140]; // apothem, half height
    const R = a / Math.cos(Math.PI / 6);
    const corner = (i: number, y: number): V => [R * Math.sin(((i * 60 - 30) * Math.PI) / 180), y, R * Math.cos(((i * 60 - 30) * Math.PI) / 180)];
    const sides = Array.from({ length: 6 }, (_, i) => face([corner(i, -h), corner(i + 1, -h), corner(i + 1, h), corner(i, h)], [0, 0, 0], 74));
    const top = face(Array.from({ length: 6 }, (_, i) => corner(i, -h)), [0, 0, 0]);
    const bottom = face(Array.from({ length: 6 }, (_, i) => corner(i, h)), [0, 0, 0]);
    return { faces: [...sides, top, bottom], spin: { axis: "y", step: 60 }, sideEyes: true, eye: { z: 37.5, scale: 0.7, socket: 92 } };
  })(),
  sphere: (() => {
    const R = SPHERE_R;
    const lats = [-90, -60, -30, 0, 30, 60, 90];
    const lons = 8;
    const at = (lat: number, lon: number): V => {
      const la = (lat * Math.PI) / 180;
      const lo = (lon * Math.PI) / 180;
      return [R * Math.cos(la) * Math.sin(lo), -R * Math.sin(la), R * Math.cos(la) * Math.cos(lo)];
    };
    const faces: Face[] = [];
    const step = 360 / lons;
    for (let i = 0; i < lats.length - 1; i++)
      for (let j = 0; j < lons; j++) {
        const [l0, l1] = [lats[i], lats[i + 1]];
        const [o0, o1] = [j * step + step / 2, (j + 1) * step + step / 2];
        const pts = [at(l0, o0), at(l0, o1), at(l1, o1), at(l1, o0)].filter((p, k, all) => k === 0 || Math.hypot(...sub(p, all[k - 1])) > 0.01);
        const f = face(pts.length >= 3 ? pts : [at(l0, o0), at(l1, o1), at(l1, o0)], [0, 0, 0], 0, true);
        // A panel's normal is the direction to its middle (its corners can be uneven near the poles).
        f.n = unit(at((l0 + l1) / 2, (o0 + o1) / 2));
        faces.push(f);
      }
    const equator = Array.from({ length: 73 }, (_, i): V => [R * Math.sin((i * Math.PI) / 36), 0, R * Math.cos((i * Math.PI) / 36)]);
    return { faces, spin: { axis: "y", step: 90 }, window: roundWindow(R), flow: { pts: equator, round: true }, smooth: true, body: R, eye: { z: 27.5, scale: 1, socket: 128 } };
  })(),
  geodesic: (() => {
    // An icosahedron with each triangle split in four, pushed out onto a sphere.
    const R = 168;
    const onSphere = (q: V) => mul(unit(q), R);
    const tris = hull(ICOSA, DODECA).flatMap(([a, b, c]) => {
      const [ab, bc, ca] = [mul(add(a, b), 0.5), mul(add(b, c), 0.5), mul(add(c, a), 0.5)];
      return [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]].map((t) => t.map(onSphere));
    });
    const polys = orient(tris.map((t) => t.map((q) => q)), tris[0].reduce(add), R).map((t) => t.map((q) => rotX(q, 12)));
    const equator = Array.from({ length: 73 }, (_, i): V => [R * 0.97 * Math.sin((i * Math.PI) / 36), 0, R * 0.97 * Math.cos((i * Math.PI) / 36)]);
    return { faces: solidFaces(polys, () => 0, [0, 0, 0], true), spin: { axis: "y", step: 90 }, window: roundWindow(R), flow: { pts: equator, round: true }, smooth: true, body: R * 0.95, eye: { z: 29.5, scale: 1, socket: 128 } };
  })(),
};

export const SOLID_EYE = Object.fromEntries(Object.entries(SPECS).map(([k, s]) => [k, s.eye])) as Record<SolidKind, Spec["eye"]>;

/** How many of each drawn piece a kind needs, so the elements never change while animating. */
const SLOTS = (k: SolidKind) => ({ panels: SPECS[k].faces.length, rims: SPECS[k].window ? 1 : SPECS[k].faces.filter((f) => f.win).length });

type Pose = { rx: number; ry: number; spin: number; push: number };
type Drawn = { d: string; fill: string; inset: string; bolts: string };
type Frame = { panels: Drawn[]; holes: string; rims: string[]; lenses: string[]; eyes: (string | null)[]; marks: (string | null)[]; flow: string; eye: [number, number] | null };

const hexRgb = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const toHex = (rgb: string) => (rgb.startsWith("#") ? rgb : `#${rgb.match(/\d+/g)!.map((v) => (+v).toString(16).padStart(2, "0")).join("")}`);
const mix = (a: string, b: string, t: number) => {
  const [x, y] = [hexRgb(toHex(a)), hexRgb(toHex(b))];
  return `rgb(${x.map((v, i) => Math.round(v + (y[i] - v) * t)).join(" ")})`;
};

function build(kind: SolidKind, { rx, ry, spin, push }: Pose, p: Palette, compact: boolean, marked = false): Frame {
  const spec = SPECS[kind];
  const turn = (spin * spec.spin.step) / 90;
  const spun = (q: V) => (spec.spin.axis === "y" ? rotY(q, turn) : rotZ(q, turn));
  const view = (q: V) => rotX(rotY(spun(q), ry), rx); // spin inside the tilt, like the CSS rig
  const tilt = (q: V) => rotX(rotY(q, ry), rx);
  // Lit faces go from the plate's dark to a brighter metal; the brightest catch a little glow.
  const metal = mix(p.plateA, p.light, 0.3);
  const shade = (l: number) => (l > 0.8 ? mix(metal, p.main, (l - 0.8) * 1.6) : mix(p.deep, metal, 0.12 + l * 1.1));
  const panels: Drawn[] = [];
  const holes: string[] = [];
  const rims: string[] = [];
  const lenses: string[] = []; // closed hatches: windows that aren't the one facing you
  const eyes: (string | null)[] = []; // with sideEyes: where each hatch's eye sits (an SVG matrix)
  let eye: [number, number] | null = null; // the open window's middle on screen (for previews)
  const flat = (q: V): [number, number] => {
    const k = PERSPECTIVE / (PERSPECTIVE - q[2]);
    return [C + q[0] * k, C + q[1] * k];
  };
  const out = 14 * push; // faces split apart along their normals in a surge
  const marks: (string | null)[] = spec.faces.map(() => null); // each face's frame on screen, while it faces you
  /** An SVG matrix that lays a face's own flat frame onto the screen at its middle. */
  const onFace = (c: V, right: V, down: V) => {
    const [ex, ey] = flat(c);
    const axis = (d: V) => {
      const [x, y] = flat(add(c, view(d)));
      return [(x - ex).toFixed(4), (y - ey).toFixed(4)];
    };
    return `matrix(${[...axis(right), ...axis(down), ex.toFixed(1), ey.toFixed(1)].join(" ")})`;
  };

  const seen = spec.faces
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
    if (marked) {
      const { right, down } = faceFrame(f);
      marks[spec.faces.indexOf(f)] = onFace(c, right, down);
    }
    const pts = f.pts.map((q) => add(view(q), shift));
    const lit = Math.max(0, dot(n, LIGHT)) * (f.tone ?? 1);
    const toward = (k: number) => f.pts.map((q) => add(view(add(f.c, mul(sub(q, f.c), k))), shift));
    const room = f.win ? Math.max(0.87, (f.win + 13) / f.inr) : 0.87;
    const detail = !(spec.smooth || compact);
    panels.push({
      d: poly(pts),
      fill: shade(lit),
      inset: detail && room < 0.98 ? poly(toward(room)) : "",
      bolts: detail
        ? toward(Math.max(0.94, room + 0.04))
            .map((q) => `M${project(q)} m-2.4 0 a2.4 2.4 0 1 0 4.8 0 a2.4 2.4 0 1 0 -4.8 0`)
            .join(" ")
        : "",
    });
    if (f.win) {
      const u = view(f.u);
      const v = view(f.v);
      rims.push(`${poly(ring(c, u, v, f.win + 9))} ${poly(ring(c, u, v, f.win))}`);
      if (item === open) {
        holes.push(poly(ring(c, u, v, f.win)));
        eye = flat(c);
        lenses.push("");
        eyes.push(null);
      } else {
        lenses.push(poly(ring(c, u, v, f.win)));
        if (spec.sideEyes) {
          // The eye drawn flat on the face, upright: right is across the face, down is down.
          const right = unit(cross([0, 1, 0], f.n));
          const down = cross(f.n, right);
          const [ex, ey] = flat(c);
          const k = f.win / 104; // the eye is drawn at the halo's size (socket r=104)
          const axis = (d: V) => {
            const [x, y] = flat(add(c, view(d)));
            return [((x - ex) * k).toFixed(3), ((y - ey) * k).toFixed(3)];
          };
          eyes.push(`matrix(${[...axis(right), ...axis(down), ex.toFixed(1), ey.toFixed(1)].join(" ")})`);
        } else eyes.push(null);
      }
    }
  }

  if (spec.window) {
    // The window faces you and doesn't spin; the panels turn around it.
    const f = tilt([0, 0, 1]);
    const u = tilt([1, 0, 0]);
    const v = tilt([0, 1, 0]);
    const c = add(mul(f, spec.window.depth), mul(f, out));
    holes.push(poly(ring(c, u, v, spec.window.r)));
    eye = flat(c);
    rims.push(`${poly(ring(c, u, v, spec.window.r + 10))} ${poly(ring(c, u, v, spec.window.r))}`);
    lenses.push("");
  } else if (!eye) eye = flat(view([0, 0, 0]));

  let flow = "";
  if (spec.flow && !compact) {
    let pen = false;
    for (const raw of spec.flow.pts) {
      const q = view(raw);
      const ok = !spec.flow.round || dot(q, sub(CAM, q)) > 0;
      if (ok) flow += `${pen ? "L" : "M"}${project(q)} `;
      pen = ok;
    }
  }

  const empty = { d: "", fill: "none", inset: "", bolts: "" };
  const slots = SLOTS(kind);
  while (panels.length < slots.panels) panels.unshift(empty);
  while (rims.length < slots.rims) rims.push("");
  while (lenses.length < slots.rims) lenses.push("");
  while (eyes.length < slots.rims) eyes.push(null);
  return { panels, holes: holes.join(" "), rims, lenses, eyes, marks, flow, eye };
}

/* ── Markings: symbols engraved on the faces ───────────────────────────────── */

type MarkKind = Exclude<Skin["marks"], "none">;
// Runes drawn as strokes in a box about ±0.5 wide and ±0.8 tall (no font has them everywhere).
const RUNES = [
  "M0 -0.8V0.8M0 -0.3L0.45 -0.75M0 0.05L0.45 -0.4",
  "M-0.3 0.8V-0.8L0.35 -0.35V0.8",
  "M-0.2 -0.8V0.8M-0.2 -0.35L0.3 0L-0.2 0.35",
  "M-0.2 -0.8V0.8M-0.2 -0.8L0.3 -0.4M-0.2 -0.35L0.3 0.05",
  "M-0.25 0.8V-0.8L0.3 -0.4L-0.25 0L0.3 0.8",
  "M0.25 -0.5L-0.25 0L0.25 0.5",
  "M-0.4 -0.8L0.4 0.8M0.4 -0.8L-0.4 0.8",
  "M-0.2 0.8V-0.8L0.3 -0.45L-0.2 -0.1",
  "M-0.3 -0.8V0.8M0.3 -0.8V0.8M-0.3 -0.2L0.3 0.2",
  "M0 -0.8V0.8M-0.3 -0.3L0.3 0.2",
  "M0 -0.8V0.8M-0.4 -0.4L0 -0.8L0.4 -0.4",
  "M-0.25 -0.8V0.8L0.3 0.4L-0.25 0L0.3 -0.4L-0.25 -0.8",
  "M-0.35 0.8V-0.8L0.35 -0.2M0.35 0.8V-0.8L-0.35 -0.2",
  "M-0.4 0.8L0.25 0L0 -0.7L-0.25 0L0.4 0.8",
];
const SETS: Record<MarkKind, { glyphs: string[]; font: string }> = {
  greek: { glyphs: [..."ΑΒΓΔΘΛΞΠΣΦΨΩ"], font: "Times New Roman, Georgia, serif" },
  roman: { glyphs: ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"], font: "Times New Roman, Georgia, serif" },
  runes: { glyphs: RUNES, font: "" },
  kanji: { glyphs: [..."一二三四五六七八九十百千"], font: "Hiragino Mincho ProN, Songti SC, serif" },
  binary: { glyphs: ["0110", "1011", "0001", "1110", "0101", "1001", "0011", "1100"], font: "JetBrains Mono, monospace" },
};

/** A face's own flat frame: right across it, down along it (upright where it can be). */
function faceFrame(f: Face) {
  const down0: V = [0, 1, 0];
  const right = Math.abs(dot(f.n, down0)) > 0.95 ? f.u : unit(cross(down0, f.n));
  return { right, down: cross(f.n, right) };
}

type Mark = { x: number; y: number; size: number; glyph: string };

/** Where each face's symbols go, in the face's own frame: one big one in the middle of a plain
 * face, small ones in the corners around a window. Faces too small for one get none. */
function layoutMarks(kind: SolidKind, set: MarkKind): Mark[][] {
  const { glyphs } = SETS[set];
  return SPECS[kind].faces.map((f, i) => {
    const { right, down } = faceFrame(f);
    const local = (q: V) => [dot(sub(q, f.c), right), dot(sub(q, f.c), down)] as const;
    const pick = (k: number) => glyphs[(i * 7 + k * 3) % glyphs.length];
    if (!f.win) {
      if (f.inr < 24) return [];
      return [{ x: 0, y: 0, size: Math.min(f.inr * 0.95, 64), glyph: pick(0) }];
    }
    const size = 30;
    return f.pts.flatMap((q, k) => {
      const [x, y] = local(q);
      const far = Math.hypot(x, y);
      const want = f.win + 9 + size * 0.75; // clear of the window's rim
      if (far * 0.9 < want) return [];
      const at = Math.max(want, far * 0.74) / far;
      return [{ x: x * at, y: y * at, size, glyph: pick(k) }];
    });
  });
}

function MarkGlyph({ m, set, color, shadow, weight }: { m: Mark; set: MarkKind; color: string; shadow: string; weight: number }) {
  if (set === "runes") {
    const t = `translate(${m.x} ${m.y}) scale(${m.size * 0.62})`;
    return (
      <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth={0.13}>
        <path d={m.glyph} transform={`translate(1.2 1.2) ${t}`} stroke={shadow} />
        <path d={m.glyph} transform={t} stroke={color} strokeOpacity={weight} />
      </g>
    );
  }
  const fit = set === "binary" ? m.size * 0.5 : m.glyph.length > 2 ? m.size * 0.62 : m.size;
  const text = (dx: number, fill: string, op: number) => (
    <text x={m.x + dx} y={m.y + dx} fontFamily={SETS[set].font} fontSize={fit} fontWeight={600} textAnchor="middle" dominantBaseline="central" fill={fill} fillOpacity={op}>
      {m.glyph}
    </text>
  );
  return (
    <>
      {text(1.2, shadow, 1)}
      {text(0, color, weight)}
    </>
  );
}

/** A wardrobe preview: a small engraved plate with two of the set's symbols. */
export function MarkSample({ marks, p }: { marks: Skin["marks"]; p: Palette }) {
  return (
    <svg viewBox="0 0 60 34" className="h-[30px] w-[54px]" aria-hidden>
      <rect x="1" y="1" width="58" height="32" rx="3" fill={mix(p.plateA, p.light, 0.12)} stroke={p.main} strokeOpacity="0.6" />
      {marks === "none"
        ? null
        : [0, 1].map((k) => (
            <MarkGlyph key={k} m={{ x: 18 + k * 24, y: 17, size: 18, glyph: SETS[marks].glyphs[k * 3 + 1] }} set={marks} color={p.light} shadow={p.ink} weight={1} />
          ))}
    </svg>
  );
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
  pose,
  marks = "none",
}: {
  marks?: Skin["marks"];
  kind: SolidKind;
  p: Palette;
  charged?: boolean;
  compact?: boolean;
  live?: Live;
  pose?: Pose;
}) {
  const mask = `solid-${useId().replace(/[^a-z0-9]/gi, "")}`;
  const spec = SPECS[kind];
  const still = pose ?? SPECS[kind].tile ?? { rx: -12, ry: 26, spin: 0, push: 0 };
  const now = (): Pose => (live ? { rx: live.tiltX.get(), ry: live.tiltY.get(), spin: live.spin.get(), push: live.push.get() } : still);
  const set = marks === "none" ? null : marks;
  const layout = useMemo(() => (set ? layoutMarks(kind, set) : []), [kind, set]);
  const first = build(kind, now(), p, compact, !!set);
  const el = useRef({ panels: [] as (SVGPathElement | null)[][], rims: [] as (SVGPathElement | null)[], lenses: [] as (SVGPathElement | null)[], eyes: [] as (SVGGElement | null)[], marks: [] as (SVGGElement | null)[], holes: null as SVGPathElement | null, flow: null as SVGPathElement | null });

  const keep = (i: number, k: number, n: SVGPathElement | null) => {
    const all = el.current.panels;
    if (!all[i]) all[i] = [];
    all[i][k] = n;
  };

  useAnimationFrame(() => {
    if (!live) return;
    const f = build(kind, now(), p, compact, !!set);
    const e = el.current;
    f.marks.forEach((m, i) => {
      const g = e.marks[i];
      if (!g) return;
      g.setAttribute("display", m ? "inline" : "none");
      if (m) g.setAttribute("transform", m);
    });
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
    f.eyes.forEach((m, i) => {
      const g = e.eyes[i];
      if (!g) return;
      g.setAttribute("display", m ? "inline" : "none");
      if (m) g.setAttribute("transform", m);
    });
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
        {spec.body ? (
          // fills the rim between panels, which are only drawn while their middle faces you
          <circle cx={C} cy={C} r={(spec.body * PERSPECTIVE) / Math.sqrt(PERSPECTIVE ** 2 - spec.body ** 2)} fill={p.deep} stroke={p.main} strokeOpacity={edge * 0.6} strokeWidth="1.4" />
        ) : null}
        {first.panels.map((d, i) => (
          <g key={i}>
            <path
              ref={(n) => keep(i, 0, n)}
              d={d.d}
              fill={d.fill}
              stroke={p.main}
              strokeOpacity={spec.smooth ? edge * 0.75 : edge}
              strokeWidth={spec.smooth ? 1.1 : 1.8}
              strokeLinejoin="round"
            />
            {spec.smooth ? null : (
              <>
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
              </>
            )}
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
        {set
          ? layout.map((items, i) =>
              items.length ? (
                <g key={`m${i}`} ref={(n) => void (el.current.marks[i] = n)} transform={first.marks[i] ?? undefined} display={first.marks[i] ? "inline" : "none"}>
                  {items.map((m, k) => (
                    <MarkGlyph key={k} m={m} set={set} color={charged ? p.hot : p.main} shadow={p.ink} weight={charged ? 1 : 0.85} />
                  ))}
                </g>
              ) : null,
            )
          : null}
      </g>
      {!live && first.eye ? (
        // previews have no eye behind them: a small one in the open window
        <g>
          <path d={first.holes} fill={p.ink} />
          <circle cx={first.eye[0]} cy={first.eye[1]} r={42 * SPECS[kind].eye.scale} fill={p.main} />
          <circle cx={first.eye[0]} cy={first.eye[1]} r={17 * SPECS[kind].eye.scale} fill={p.hot} />
        </g>
      ) : null}
      {first.lenses.map((d, i) => (
        <path key={`l${i}`} ref={(n) => void (el.current.lenses[i] = n)} d={d} fill={p.ink} stroke={p.main} strokeOpacity="0.45" strokeWidth="1.2" />
      ))}
      {spec.sideEyes && live
        ? first.eyes.map((m, i) => (
            <g key={`e${i}`} ref={(n) => void (el.current.eyes[i] = n)} transform={m ?? undefined} display={m ? "inline" : "none"}>
              <circle r="104" fill={p.ink} />
              <MechaEye cx={0} cy={0} charged={charged} />
            </g>
          ))
        : null}
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
