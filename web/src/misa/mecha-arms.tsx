import { useEffect, useRef } from "react";
import type { ReactNode } from "react";
import { motion, useAnimationFrame } from "framer-motion";
import { send } from "../bridge";
import { useSkin } from "./skin";
import type { Palette, Skin } from "./skin";
import { hex } from "./shell-parts";

/*
 * Two jointed arms mounted on the sides of her halo (collapsed mode only).
 *
 * Each arm is a two-bone chain (upper arm + forearm) ending in a two-finger claw. Every frame the
 * hand eases toward a target picked from what's going on, and simple two-bone IK places the elbow:
 *   - idle: hangs and sways, now and then snapping its claw
 *   - cursor nearby: the arm on that side reaches for it, claw open
 *   - cursor over the halo: both arms come up in a guard, fists closed
 *   - files dragged over her: both arms reach out wide, claws open
 *   - a message waiting (unread): one arm waves every few seconds
 *   - clicked: that arm waves and snaps
 */

const L1 = 34; // upper arm
const L2 = 31; // forearm
const W = 8; // plate thickness

type Side = -1 | 1; // left, right
type Gesture = { kind: "wave" | "snap"; until: number } | null;
type ArmState = { tx: number; ty: number; grip: number; gesture: Gesture; nextFidget: number };

export type ArmsInput = {
  /** Halo box top-left in window coordinates (140×140). */
  halo: { x: number; y: number };
  /** Which sides have room on screen. */
  room: { left: boolean; right: boolean };
  /** Files are being dragged over her. */
  dragHover: boolean;
  /** A reply is waiting to be read. */
  unread: boolean;
  /** Bumped when she surges (spins up). */
  surge: number;
  reduce: boolean;
  kind: ArmKind;
  /** The chat is open: no reaching for the cursor (it's busy in the chat). */
  chatting: boolean;
  /** She's working on a reply. */
  thinking: boolean;
};

const HALO = 140;

export default function MechaArms({ halo, room, dragHover, unread, surge, reduce, kind, chatting, thinking }: ArmsInput) {
  const { p } = useSkin();
  const center = { x: halo.x + HALO / 2, y: halo.y + HALO / 2 };
  const shoulders: Record<Side, { x: number; y: number }> = {
    [-1]: { x: center.x - 50, y: center.y + 10 },
    [1]: { x: center.x + 50, y: center.y + 10 },
  };

  const cursor = useRef({ x: -1e4, y: -1e4, at: 0 });
  const surgeAt = useRef(-1e4);
  const state = useRef<Record<Side, ArmState>>({
    [-1]: { tx: -40, ty: 44, grip: 18, gesture: null, nextFidget: 4000 },
    [1]: { tx: 40, ty: 44, grip: 18, gesture: null, nextFidget: 7000 },
  });
  const els = useRef<Record<Side, { upper: SVGGElement | null; fore: SVGGElement | null; f1: SVGGElement | null; f2: SVGGElement | null }>>({
    [-1]: { upper: null, fore: null, f1: null, f2: null },
    [1]: { upper: null, fore: null, f1: null, f2: null },
  });
  const lastHot = useRef({ key: "", at: 0 });
  const waveTurn = useRef<Side>(1);

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      cursor.current = { x: e.clientX, y: e.clientY, at: performance.now() };
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    return () => window.removeEventListener("pointermove", onMove);
  }, []);

  useEffect(() => {
    if (surge) surgeAt.current = performance.now();
  }, [surge]);

  // Waiting message: wave every 5 s, alternating arms.
  useEffect(() => {
    if (!unread) return;
    const wave = () => {
      const side = room.right && (waveTurn.current === 1 || !room.left) ? 1 : -1;
      waveTurn.current = side === 1 ? -1 : 1;
      state.current[side as Side].gesture = { kind: "wave", until: performance.now() + 1600 };
    };
    wave();
    const id = window.setInterval(wave, 5000);
    return () => window.clearInterval(id);
  }, [unread, room.left, room.right]);

  // A reply just arrived: both claws snap.
  const wasThinking = useRef(false);
  useEffect(() => {
    if (wasThinking.current && !thinking) {
      const until = performance.now() + 700;
      state.current[-1].gesture = { kind: "snap", until };
      state.current[1].gesture = { kind: "snap", until };
    }
    wasThinking.current = thinking;
  }, [thinking]);

  const poke = (side: Side) => {
    const now = performance.now();
    const a = state.current[side];
    a.gesture = a.gesture?.kind === "wave" && a.gesture.until > now ? { kind: "snap", until: now + 700 } : { kind: "wave", until: now + 1600 };
  };

  useAnimationFrame((time, dt) => {
    const now = performance.now();
    const t = time / 1000;
    const c = cursor.current;
    const recent = now - c.at < 4000;
    const overHalo = recent && Math.hypot(c.x - center.x, c.y - center.y) < 56;
    const surging = now - surgeAt.current < 2600;
    const k = reduce ? 1 : 1 - Math.exp(-dt / 90); // ease toward the target (~90 ms)
    const hot: number[][] = [];

    for (const side of [-1, 1] as Side[]) {
      if (!(side === -1 ? room.left : room.right)) continue;
      const S = shoulders[side];
      const a = state.current[side];
      const sway = reduce ? 0 : 1;
      let tx: number, ty: number, grip: number;

      if (a.gesture && a.gesture.until < now) a.gesture = null;
      if (!a.gesture && !reduce && now > a.nextFidget && !recent) {
        a.gesture = { kind: "snap", until: now + 700 };
        a.nextFidget = now + 6000 + Math.random() * 7000;
      }

      if (a.gesture?.kind === "wave") {
        tx = side * 24 + side * 12 * Math.sin(t * 13) * sway;
        ty = -56;
        grip = 42;
      } else if (dragHover) {
        tx = side * 64 + Math.sin(t * 6 + side) * 3 * sway;
        ty = -16 + Math.cos(t * 5) * 3 * sway;
        grip = 46;
      } else if (surging) {
        tx = side * 66;
        ty = 4;
        grip = 44;
      } else if (overHalo) {
        tx = side * 28;
        ty = -42 + Math.sin(t * 3 + side) * 2 * sway;
        grip = 6;
      } else if (thinking) {
        // Busy: hands working in front of her, taking turns.
        tx = side * 30;
        ty = 30 + 6 * Math.sin(t * 12 + (side === 1 ? Math.PI : 0)) * sway;
        grip = 20 + 14 * Math.sin(t * 16 + side) * sway;
      } else if (!chatting && recent && (c.x - center.x) * side > 30 && Math.hypot(c.x - S.x, c.y - S.y) < 200) {
        // Reach for the cursor on this side (the IK stops at full stretch).
        tx = c.x - S.x;
        ty = c.y - S.y;
        grip = 36;
      } else {
        tx = side * 38 + side * 3 * Math.sin(t * 1.1 + side) * sway;
        ty = 46 + 3 * Math.sin(t * 0.9 + side * 2) * sway;
        grip = 16 + 6 * Math.sin(t * 0.7 + side) * sway;
      }
      if (a.gesture?.kind === "snap") grip = 24 + 22 * Math.cos(((a.gesture.until - now) / 700) * Math.PI * 4);

      a.tx += (tx - a.tx) * k;
      a.ty += (ty - a.ty) * k;
      a.grip += (grip - a.grip) * Math.min(1, k * 1.6);

      // Two-bone IK, elbow bending downward on both sides.
      const d = Math.max(Math.abs(L1 - L2) + 2, Math.min(L1 + L2 - 0.5, Math.hypot(a.tx, a.ty)));
      const aim = Math.atan2(a.ty, a.tx);
      const bend = Math.acos(Math.max(-1, Math.min(1, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))));
      const th1 = aim + side * bend;
      const ex = S.x + L1 * Math.cos(th1);
      const ey = S.y + L1 * Math.sin(th1);
      const hx = S.x + d * Math.cos(aim);
      const hy = S.y + d * Math.sin(aim);
      const th2 = Math.atan2(hy - ey, hx - ex);
      const deg = 180 / Math.PI;

      const e = els.current[side];
      e.upper?.setAttribute("transform", `translate(${S.x} ${S.y}) rotate(${th1 * deg})`);
      e.fore?.setAttribute("transform", `translate(${ex} ${ey}) rotate(${th2 * deg})`);
      const hand = ARM_HAND[kind];
      e.f1?.setAttribute("transform", `translate(${L2} 0) rotate(${-a.grip * hand.grip})`);
      e.f2?.setAttribute("transform", `translate(${L2} 0) rotate(${a.grip * hand.grip})`);

      const xs = [S.x, ex, hx, hx + hand.reach * Math.cos(th2)], ys = [S.y, ey, hy, hy + hand.reach * Math.sin(th2)];
      const pad = 9;
      const x0 = Math.min(...xs) - pad, y0 = Math.min(...ys) - pad;
      hot.push([x0, y0, Math.max(...xs) + pad - x0, Math.max(...ys) + pad - y0].map(Math.round));
    }

    // Tell the window where the arms are, so only they (and the halo) take clicks.
    const key = JSON.stringify(hot);
    if (key !== lastHot.current.key && now - lastHot.current.at > 120) {
      lastHot.current = { key, at: now };
      send({ type: "hot", rects: hot });
    }
  });

  // Clear the click areas when the arms go away.
  useEffect(() => () => send({ type: "hot", rects: [] }), []);

  return (
    <motion.svg
      className="pointer-events-none absolute inset-0 h-full w-full overflow-visible"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: 0.35, delay: 0.25 }}
      aria-hidden
    >
      <motion.g animate={reduce ? undefined : { y: [0, -4, 0] }} transition={{ duration: 3.2, repeat: Infinity, ease: "easeInOut" }}>
        {([-1, 1] as Side[]).map((side) =>
          (side === -1 ? room.left : room.right) ? (
            <g
              key={side}
              className="pointer-events-auto cursor-pointer"
              onPointerDown={(e) => e.stopPropagation()}
              onClick={() => poke(side)}
            >
              <ArmArt key={kind} p={p} kind={kind} refs={els.current[side]} />
            </g>
          ) : null,
        )}
      </motion.g>
    </motion.svg>
  );
}

type Refs = { upper: SVGGElement | null; fore: SVGGElement | null; f1: SVGGElement | null; f2: SVGGElement | null };
export type ArmKind = Exclude<Skin["arms"], "off">;

/** How far each style's hand reaches past the wrist, and how much its fingers open (0 = fixed). */
export const ARM_HAND: Record<ArmKind, { reach: number; grip: number }> = {
  claw: { reach: 15, grip: 1 },
  hydraulic: { reach: 13, grip: 0.7 },
  slim: { reach: 13, grip: 1 },
  blade: { reach: 25, grip: 0 },
  cannon: { reach: 10, grip: 0 },
  tentacle: { reach: 10, grip: 0.8 },
  magnet: { reach: 13, grip: 0 },
};

/** A still pose for previews: shoulder angle, elbow angle (both degrees) and finger opening. */
export type Pose = { x: number; y: number; th1: number; th2: number; grip: number };

/**
 * One arm, drawn along +x. In her window the frame loop sets the transforms through `refs`;
 * a preview passes a fixed `pose` instead.
 */
export function ArmArt({ p, kind, refs, pose }: { p: Palette; kind: ArmKind; refs?: Refs; pose?: Pose }) {
  const r: Refs = refs ?? { upper: null, fore: null, f1: null, f2: null };
  const rad = Math.PI / 180;
  const at = pose ?? { x: 0, y: 0, th1: 60, th2: 0, grip: 20 };
  const g = at.grip * ARM_HAND[kind].grip;
  const upperT = `translate(${at.x} ${at.y}) rotate(${at.th1})`;
  const ex = at.x + L1 * Math.cos(at.th1 * rad), ey = at.y + L1 * Math.sin(at.th1 * rad);
  const foreT = `translate(${ex} ${ey}) rotate(${at.th2})`;

  const plate = (len: number, w: number) => `M0 ${-w / 2} L${len - 3} ${-w / 2 + 1} Q${len} 0 ${len - 3} ${w / 2 - 1} L0 ${w / 2} Q-3 0 0 ${-w / 2} Z`;
  const box = (len: number, w: number) => `M-2 ${-w / 2} H${len - 2} L${len + 1} ${-w / 2 + 2.5} V${w / 2 - 2.5} L${len - 2} ${w / 2} H-2 Z`;
  const edge = { stroke: p.main, strokeWidth: 1.2, strokeLinejoin: "round" as const };
  const joint = (x: number, rr: number) => (
    <>
      <circle cx={x} cy={0} r={rr} fill={p.socket} stroke={p.main} strokeWidth="1.2" />
      <circle cx={x} cy={0} r={rr * 0.42} fill={p.light} className="animate-pulse" />
    </>
  );
  const hexJoint = (rr: number) => <polygon points={hex(0, 0, rr)} fill={p.bolt} stroke={p.light} strokeOpacity="0.8" strokeWidth="1" />;
  const fingers = (a: ReactNode, b: ReactNode) => (
    <>
      <g ref={(el) => void (r.f1 = el)} transform={refs ? undefined : `translate(${L2} 0) rotate(${-g})`}>{a}</g>
      <g ref={(el) => void (r.f2 = el)} transform={refs ? undefined : `translate(${L2} 0) rotate(${g})`}>{b}</g>
    </>
  );
  // A curved claw finger, from the wrist outward; flip mirrors it.
  const claw = (flip: 1 | -1) => (
    <path d={`M0 ${flip * -1.5} Q7 ${flip * -5} 13 ${flip * -2} L14.5 ${flip * 1} Q8 ${flip * -1} 2 ${flip * 2.2} Z`} fill={p.plateA} {...edge} strokeWidth={1} />
  );

  let upper: ReactNode, fore: ReactNode;
  switch (kind) {
    case "claw":
      upper = (
        <>
          <path d={plate(L1, W + 1)} fill={p.plateA} {...edge} />
          <line x1={6} y1={-1.2} x2={L1 - 7} y2={-1.2} stroke={p.light} strokeOpacity="0.7" strokeWidth="1.1" strokeLinecap="round" />
          <line x1={8} y1={2.2} x2={L1 - 9} y2={2.2} stroke={p.main} strokeOpacity="0.45" strokeWidth="0.8" />
          {joint(0, 6)}
        </>
      );
      fore = (
        <>
          <path d={plate(L2, W)} fill={p.plateB} {...edge} />
          <line x1={6} y1={0} x2={L2 - 6} y2={0} stroke={p.light} strokeOpacity="0.6" strokeWidth="1" strokeLinecap="round" />
          {fingers(claw(1), claw(-1))}
          <circle cx={L2} cy={0} r={3.4} fill={p.bolt} stroke={p.light} strokeOpacity="0.8" strokeWidth="0.9" />
          {joint(0, 5)}
        </>
      );
      break;
    case "hydraulic": {
      // Boxy and heavy: a piston along the upper arm, hoses, and a three-jaw gripper.
      const jaw = (flip: 1 | -1) => <path d={`M0 ${flip * -2} H9 V${flip * -6} H13 V${flip * -1} L11 ${flip * 1} H0 Z`} fill={p.plateA} {...edge} strokeWidth={1} />;
      upper = (
        <>
          <path d={box(L1, 12)} fill={p.plateA} {...edge} />
          <rect x={5} y={-3} width={L1 - 12} height={6} rx={1.5} fill={p.ink} stroke={p.main} strokeOpacity="0.6" strokeWidth="0.8" />
          <rect x={7} y={-1.2} width={(L1 - 12) * 0.55} height={2.4} fill={p.light} fillOpacity="0.8" />
          {hexJoint(7)}
          <circle cx={0} cy={0} r={2.4} fill={p.light} className="animate-pulse" />
        </>
      );
      fore = (
        <>
          <path d={box(L2, 10)} fill={p.plateB} {...edge} />
          <path d={`M4 -5 Q${L2 / 2} -9 ${L2 - 4} -5`} fill="none" stroke={p.main} strokeOpacity="0.8" strokeWidth="1.4" />
          {[9, 15, 21].map((x) => <line key={x} x1={x} y1={-3.5} x2={x} y2={3.5} stroke={p.main} strokeOpacity="0.45" strokeWidth="0.9" />)}
          {fingers(jaw(1), jaw(-1))}
          <rect x={L2} y={-1.3} width={10} height={2.6} fill={p.plateA} stroke={p.main} strokeWidth="0.8" />
          <rect x={L2 - 3} y={-5} width={4} height={10} rx={1} fill={p.bolt} stroke={p.light} strokeOpacity="0.7" strokeWidth="0.8" />
          {hexJoint(6)}
        </>
      );
      break;
    }
    case "slim": {
      // Thin rods and glowing ball joints, with hooked prongs.
      const prong = (flip: 1 | -1) => <path d={`M0 0 L9 ${flip * -3} Q13 ${flip * -4} 13 ${flip * 0.5}`} fill="none" stroke={p.main} strokeWidth="2" strokeLinecap="round" />;
      const rod = (len: number) => (
        <>
          <line x1={0} y1={0} x2={len} y2={0} stroke={p.main} strokeWidth="4" strokeLinecap="round" />
          <line x1={3} y1={0} x2={len - 3} y2={0} stroke={p.light} strokeOpacity="0.8" strokeWidth="1.2" strokeLinecap="round" />
        </>
      );
      const ball = (rr: number) => (
        <>
          <circle cx={0} cy={0} r={rr} fill={p.light} fillOpacity="0.25" className="animate-pulse" />
          <circle cx={0} cy={0} r={rr * 0.6} fill={p.light} stroke={p.main} strokeWidth="1" />
        </>
      );
      upper = <>{rod(L1)}{ball(6)}</>;
      fore = (
        <>
          {rod(L2)}
          {fingers(prong(1), prong(-1))}
          <circle cx={L2} cy={0} r={2.6} fill={p.light} />
          {ball(5)}
        </>
      );
      break;
    }
    case "blade":
      // A long glowing blade in place of the hand.
      upper = (
        <>
          <path d={plate(L1, W + 1)} fill={p.plateA} {...edge} />
          <path d={`M6 -2.5 L${L1 - 8} -2.5`} stroke={p.main} strokeOpacity="0.55" strokeWidth="0.9" />
          {joint(0, 6)}
        </>
      );
      fore = (
        <>
          <path d={plate(L2, W)} fill={p.plateB} {...edge} />
          <path d={`M${L2 - 2} -3.6 L${L2 + 21} -0.6 L${L2 + 25} 0 L${L2 + 21} 1.4 L${L2 - 2} 3.6 Z`} fill={p.plateA} {...edge} strokeWidth={1} />
          <path d={`M${L2 + 1} -1.6 L${L2 + 22} -0.2`} stroke={p.light} strokeWidth="1.2" strokeLinecap="round" className="animate-pulse" />
          <rect x={L2 - 4} y={-6} width={4} height={12} rx={1} fill={p.bolt} stroke={p.light} strokeOpacity="0.7" strokeWidth="0.8" />
          {fingers(null, null)}
          {joint(0, 5)}
        </>
      );
      break;
    case "cannon":
      // The forearm is a barrel that flares to a glowing muzzle.
      upper = (
        <>
          <path d={plate(L1, W + 2)} fill={p.plateA} {...edge} />
          <circle cx={L1 / 2} cy={0} r={2.2} fill={p.bolt} stroke={p.main} strokeWidth="0.8" />
          {joint(0, 6.5)}
        </>
      );
      fore = (
        <>
          <path d={`M0 -5 L${L2 + 2} -6.5 V6.5 L0 5 Z`} fill={p.plateB} {...edge} />
          {[10, 17, 24].map((x) => <rect key={x} x={x} y={-6.3} width={2.6} height={12.6} fill={p.plateA} stroke={p.main} strokeOpacity="0.7" strokeWidth="0.7" />)}
          <rect x={L2 + 2} y={-7.5} width={5} height={15} rx={1.5} fill={p.plateA} {...edge} strokeWidth={1} />
          <circle cx={L2 + 8} cy={0} r={4.2} fill={p.light} fillOpacity="0.3" className="animate-pulse" />
          <circle cx={L2 + 7} cy={0} r={2.6} fill={p.light} />
          {fingers(null, null)}
          {joint(0, 5.5)}
        </>
      );
      break;
    case "tentacle": {
      // Beads that shrink toward the tip, with two curling feelers.
      const beads = (len: number, r0: number, r1: number, n: number) =>
        Array.from({ length: n }, (_, i) => {
          const t = i / (n - 1);
          return <circle key={i} cx={t * len} cy={0} r={r0 + (r1 - r0) * t} fill={i % 2 ? p.plateB : p.plateA} stroke={p.main} strokeWidth="1" />;
        });
      const curl = (flip: 1 | -1) => <path d={`M0 0 Q6 ${flip * -1} 9 ${flip * -4} Q10 ${flip * -7} 7 ${flip * -7}`} fill="none" stroke={p.main} strokeWidth="1.8" strokeLinecap="round" />;
      upper = (
        <>
          {beads(L1, 6, 4.6, 7)}
          {Array.from({ length: 4 }, (_, i) => <circle key={i} cx={(i + 0.5) * (L1 / 4)} cy={0} r={1.1} fill={p.light} className="animate-pulse" />)}
        </>
      );
      fore = (
        <>
          {beads(L2, 4.6, 2.8, 7)}
          {fingers(curl(1), curl(-1))}
          <circle cx={L2 + 1} cy={0} r={2.2} fill={p.light} className="animate-pulse" />
        </>
      );
      break;
    }
    case "magnet":
      // A horseshoe magnet with glowing poles.
      upper = (
        <>
          <path d={plate(L1, W + 1)} fill={p.plateA} {...edge} />
          <line x1={6} y1={0} x2={L1 - 7} y2={0} stroke={p.light} strokeOpacity="0.6" strokeWidth="1" strokeLinecap="round" />
          {joint(0, 6)}
        </>
      );
      fore = (
        <>
          <path d={plate(L2, W)} fill={p.plateB} {...edge} />
          <path d={`M${L2 + 12} -7 H${L2 + 6} A7 7 0 0 0 ${L2 + 6} 7 H${L2 + 12}`} fill="none" stroke={p.main} strokeWidth="5.5" />
          <path d={`M${L2 + 12} -7 H${L2 + 6} A7 7 0 0 0 ${L2 + 6} 7 H${L2 + 12}`} fill="none" stroke={p.plateA} strokeWidth="3.2" />
          <rect x={L2 + 9.5} y={-9.6} width={4} height={5.2} fill={p.light} className="animate-pulse" />
          <rect x={L2 + 9.5} y={4.4} width={4} height={5.2} fill={p.light} className="animate-pulse" />
          {fingers(null, null)}
          {joint(0, 5)}
        </>
      );
      break;
  }

  return (
    <>
      {/* live arms: the frame loop owns the transforms, so React must not reset them on re-render */}
      <g ref={(el) => void (r.upper = el)} transform={refs ? undefined : upperT}>{upper}</g>
      <g ref={(el) => void (r.fore = el)} transform={refs ? undefined : foreT}>{fore}</g>
    </>
  );
}
