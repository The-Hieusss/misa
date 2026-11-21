import { useEffect, useRef } from "react";
import type { ReactNode } from "react";
import { motion, useAnimationFrame, useMotionValue, useReducedMotion, useTransform } from "framer-motion";
import type { MotionValue } from "framer-motion";
import { GLYPHS, rgb, useSkin } from "./skin";
import { C, CLAMP_ART, CogArt, GYRO, PlatePattern, RING_SPECS, arcPath, hex, platePath, pt, spikePaths, ventAngles } from "./shell-parts";
import type { Seg } from "./shell-parts";
import { cn } from "@/lib/utils";
import MechaEye from "./mecha-eye";
import type { EyeLook } from "./mecha-eye";

const origin = { transformOrigin: `${C}px ${C}px` };
const ticks = Array.from({ length: 72 }, (_, i) => ({ a: i * 5, major: i % 6 === 0 }));
const finsFull = Array.from({ length: 48 }, (_, i) => i * 7.5);
const finsCompact = Array.from({ length: 24 }, (_, i) => i * 15);
const bolts = Array.from({ length: 8 }, (_, i) => i * 45 + 22.5);
const sweepSlices = Array.from({ length: 10 }, (_, i) => i); // fading radar trail, 4° each

/** Wedge between two radii (used for the radar sweep trail). */
function wedge(r1: number, r2: number, a0: number, a1: number) {
  return platePath(r1, r2, a0, a1, 0);
}

/* ── Surge timeline (seconds), synced to playMechaSpin(2.6) ─────────────────── */
const T = 2.6; // total
const UNLOCK = 0.25; // clamps retract, plates push out
const UP = 0.9; // spin-up ends
const HOLD = 1.7; // full power ends, wind-down starts
const LOCK = 0.25; // plates slam back in over the last stretch
const SETTLE = 0.18; // bounce after locking
const PUSH_PX = 9; // how far plates slide outward
const ORBIT_IDLE = 6; // deg/s
const GEAR_IDLE = -9;
const ORBIT_PEAK = 300;
const GEAR_PEAK = -480;
const SWEEP_IDLE = 70; // radar sweep, deg/s
const SWEEP_PEAK = 900;

const smooth = (x: number) => {
  const c = Math.min(1, Math.max(0, x));
  return c * c * (3 - 2 * c);
};
/** Power level 0→1→0 across the surge. */
const env = (e: number) =>
  e <= 0 || e >= T ? 0 : e < UP ? smooth(e / UP) : e < HOLD ? 1 : 1 - smooth((e - HOLD) / (T - HOLD));
/** Plate unlock: slide out, hold, slam back with a small bounce. */
const pushAt = (e: number) => {
  if (e <= 0) return 0;
  if (e < UNLOCK) return smooth(e / UNLOCK);
  if (e < T - LOCK) return 1;
  if (e < T) {
    const k = (e - (T - LOCK)) / LOCK;
    return 1 - k * k * k; // accelerates into the lock
  }
  if (e < T + SETTLE) return -0.3 * Math.sin((Math.PI * (e - T)) / SETTLE);
  return 0;
};
// Cumulative power (1ms steps) so plate rotation can land exactly on a quarter turn.
const CUM = (() => {
  const out = new Float32Array(Math.round(T * 1000) + 1);
  for (let i = 1; i < out.length; i++) out[i] = out[i - 1] + env(i / 1000) / 1000;
  return out;
})();
const cumAt = (e: number) => CUM[Math.min(CUM.length - 1, Math.max(0, Math.round(e * 1000)))];

/** A plate or clamp that slides outward along its own axis as the shell unlocks. */
function Radial({ angle, push, dist, children }: { angle: number; push: MotionValue<number>; dist: number; children: ReactNode }) {
  const x = useTransform(push, (p) => Math.sin((angle * Math.PI) / 180) * dist * p);
  const y = useTransform(push, (p) => -Math.cos((angle * Math.PI) / 180) * dist * p);
  return <motion.g style={{ x, y }}>{children}</motion.g>;
}

/* ── 3D rig: the shell is a stack of SVG layers at different depths ─────────── */
// Depths are in cqw (percent of the halo's own width), so the 3D scales with its size.
const Z = {
  back: -9, // glow, outer orbit
  eye: -5, // eye sits recessed in the socket
  collar: -1.5, // fins + bezel ring
  dial: 2.5, // tick dial, radar sweep
  gear: 5.5,
  plates: 10, // armor plates + readout (thickness copies sit just behind)
  clamps: 13,
};
const PLATE_DEPTH = [8, 8.7, 9.4]; // extrusion slices behind the plates
const CLAMP_DEPTH = [11, 12];
const TILT_X = 16; // max deg toward the cursor
const TILT_Y = 22;
const SWAY = { x: 7, y: 11 }; // idle drift amplitude, deg

function Layer({ z, children }: { z: number; children: ReactNode }) {
  return (
    <div className="pointer-events-none absolute inset-0" style={{ transform: `translateZ(${z}cqw)` }}>
      <svg viewBox="0 0 400 400" className="absolute inset-0 h-full w-full overflow-visible">
        {children}
      </svg>
    </div>
  );
}

/** Armored mecha housing around ΑΘΗΝΑ's tracking eye. */
export default function MechaHalo({
  className,
  charged = false,
  compact = false,
  surge = 0,
  look,
}: {
  className?: string;
  charged?: boolean;
  /** Small versions: drop fine text and detail that would be illegible. */
  compact?: boolean;
  /** Increment to fire the overclock spin sequence. */
  surge?: number;
  /** Receives the eye's gaze so something outside can follow it. */
  look?: EyeLook;
}) {
  const { p, skin } = useSkin();
  const spec = RING_SPECS[skin.ring];
  const clamp = skin.clamp === "none" ? null : CLAMP_ART[skin.clamp];
  const glyphs = GLYPHS[skin.glyphs].set;
  const segShape = (s: Seg) => (spec.shape ? spec.shape(s) : platePath(s.r1, s.r2, s.a0, s.a1, spec.chamfer));
  const pushDist = PUSH_PX * (spec.push ?? 1);
  const heat = charged ? 1 : 0;
  const fade = { transition: "stroke-opacity 300ms, stroke 300ms" };
  const reduce = useReducedMotion();

  const orbit = useMotionValue(0);
  const gear = useMotionValue(0);
  const shell = useMotionValue(0);
  const push = useMotionValue(0);
  const shakeX = useMotionValue(0);
  const shakeY = useMotionValue(0);
  const sweep = useMotionValue(0);
  const tiltX = useMotionValue(0);
  const tiltY = useMotionValue(0);
  const root = useRef<HTMLDivElement>(null);
  const aim = useRef({ x: 0, y: 0, at: -1e9 });

  // Lean toward the cursor.
  useEffect(() => {
    if (reduce) return;
    const onMove = (e: PointerEvent) => {
      if (e.pointerType !== "mouse" || !root.current) return;
      const r = root.current.getBoundingClientRect();
      if (!r.width) return;
      const clamp = (v: number) => Math.max(-1, Math.min(1, v));
      const dx = clamp((e.clientX - (r.left + r.width / 2)) / 600);
      const dy = clamp((e.clientY - (r.top + r.height / 2)) / 500);
      aim.current = { x: -dy * TILT_X, y: dx * TILT_Y, at: performance.now() };
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    return () => window.removeEventListener("pointermove", onMove);
  }, [reduce]);

  const run = useRef<{ t0: number; e0: number; from: number; to: number } | null>(null);
  const vel = useRef({ orbit: ORBIT_IDLE, gear: GEAR_IDLE, sweep: SWEEP_IDLE });

  // Start (or extend) a surge whenever `surge` changes.
  useEffect(() => {
    if (!surge || reduce) return;
    const now = performance.now() / 1000;
    const cur = run.current;
    const elapsed = cur ? now - cur.t0 : Infinity;
    // Re-clicked mid-spin: stay at full power instead of restarting the spin-up.
    const e0 = elapsed < T ? Math.min(elapsed, UP) : 0;
    const from = shell.get();
    const to = (Math.floor((from + 45) / 90) + 1) * 90; // next quarter turn
    run.current = { t0: now - e0, e0, from, to };
  }, [surge, reduce, shell]);

  useAnimationFrame((_, delta) => {
    if (reduce) return;
    const dt = Math.min(0.05, delta / 1000);
    const r = run.current;
    const el = r ? performance.now() / 1000 - r.t0 : -1;
    const power = r ? env(el) : 0;
    const idle = charged && !r ? 4 : 1;

    // Velocities ease toward their target so speed changes feel like inertia.
    const tOrbit = ORBIT_IDLE * idle + (ORBIT_PEAK - ORBIT_IDLE) * power;
    const tGear = GEAR_IDLE * idle + (GEAR_PEAK - GEAR_IDLE) * power;
    const k = Math.min(1, dt * 7);
    vel.current.orbit += (tOrbit - vel.current.orbit) * k;
    vel.current.gear += (tGear - vel.current.gear) * k;
    vel.current.sweep += (SWEEP_IDLE * idle + (SWEEP_PEAK - SWEEP_IDLE) * power - vel.current.sweep) * k;
    orbit.set((orbit.get() + vel.current.orbit * dt) % 360);
    gear.set((gear.get() + vel.current.gear * dt) % 360);
    sweep.set((sweep.get() + vel.current.sweep * dt) % 360);

    // Cursor lean, drifting into a slow idle sway when the mouse goes quiet.
    const now = performance.now();
    const quiet = Math.min(1, Math.max(0, (now - aim.current.at - 1800) / 1500));
    const s = now / 1000;
    const swayX = Math.sin(s * 0.9) * SWAY.x;
    const swayY = Math.sin(s * 0.7 + 1.3) * SWAY.y;
    const gx = aim.current.x * (1 - quiet) + swayX * quiet;
    const gy = aim.current.y * (1 - quiet) + swayY * quiet;
    const kt = Math.min(1, dt * 5);
    tiltX.set(tiltX.get() + (gx - tiltX.get()) * kt);
    tiltY.set(tiltY.get() + (gy - tiltY.get()) * kt);

    if (r) {
      const total = cumAt(T) - cumAt(r.e0);
      const prog = total > 0 ? (cumAt(el) - cumAt(r.e0)) / total : 1;
      shell.set(r.from + (r.to - r.from) * Math.min(1, Math.max(0, prog)));
      push.set(pushAt(el));
      const amp = power * 1.4;
      shakeX.set((Math.random() * 2 - 1) * amp);
      shakeY.set((Math.random() * 2 - 1) * amp);
      if (el > T + SETTLE) {
        run.current = null;
        shell.set(r.to % 360);
        push.set(0);
        shakeX.set(0);
        shakeY.set(0);
      }
    }
  });

  return (
    <div
      ref={root}
      className={cn("relative aspect-square [container-type:inline-size]", className)}
      style={{ ["--flow" as string]: charged ? "0.35s" : "2.4s" }}
      aria-hidden
    >
      <div className="absolute inset-0 [perspective:320cqw]">
        <motion.div
          className="absolute inset-0 [transform-style:preserve-3d]"
          style={{ rotateX: tiltX, rotateY: tiltY, x: shakeX, y: shakeY }}
        >
          {/* ── back: glow, orbit ── */}
          <Layer z={Z.back}>
            <defs>
              <radialGradient id="halo-core" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor={p.main} stopOpacity="0.55" />
                <stop offset="55%" stopColor={p.main} stopOpacity="0.12" />
                <stop offset="100%" stopColor={p.main} stopOpacity="0" />
              </radialGradient>
              <linearGradient id="halo-plate" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stopColor={p.plateA} />
                <stop offset="100%" stopColor={p.plateB} />
              </linearGradient>
              <linearGradient id="halo-edge" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stopColor={p.light} />
                <stop offset="100%" stopColor={p.main} />
              </linearGradient>
              <PlatePattern id="halo-pat" color={p.main} />
            </defs>
            <circle
              cx={C}
              cy={C}
              r="196"
              fill="url(#halo-core)"
              style={{ opacity: charged ? 1 : 0.7, transition: "opacity 400ms" }}
            />
            {charged ? (
              <circle cx={C} cy={C} r="110" fill="none" stroke={p.light} strokeWidth="2" className="halo-pulse" style={origin} />
            ) : null}
            <motion.g style={{ rotate: orbit }}>
              <circle cx={C} cy={C} r="193" fill="none" stroke={p.main} strokeOpacity="0.4" strokeWidth="1" strokeDasharray="2 7" />
              <rect x={C - 4} y={3} width="8" height="8" fill={p.main} transform={`rotate(45 ${C} 7)`} />
              <polygon points={`${C},${C + 188} ${C - 5},${C + 197} ${C + 5},${C + 197}`} fill={p.light} fillOpacity="0.8" />
            </motion.g>
          </Layer>

          {/* ── eye, recessed in its socket ── */}
          <Layer z={Z.eye}>
            <circle cx={C} cy={C} r="104" fill={p.ink} />
            <MechaEye cx={C} cy={C} charged={charged} look={look} />
          </Layer>

          {/* ── collar: heat-sink fins + bolted bezel ring (open in the middle) ── */}
          <Layer z={Z.collar}>
            {(compact ? finsCompact : finsFull).map((a) => {
              const [x1, y1] = pt(113, a);
              const [x2, y2] = pt(127, a);
              return (
                <line
                  key={a}
                  x1={x1}
                  y1={y1}
                  x2={x2}
                  y2={y2}
                  stroke={charged ? p.light : p.main}
                  strokeOpacity={0.3 + heat * 0.6}
                  strokeWidth="3"
                  style={fade}
                />
              );
            })}
            <circle cx={C} cy={C} r="129.5" fill="none" stroke={p.main} strokeOpacity="0.55" strokeWidth="1.2" />
            <circle cx={C} cy={C} r="106" fill="none" stroke={p.socket} strokeWidth="6" />
            <circle cx={C} cy={C} r="109" fill="none" stroke={p.main} strokeOpacity="0.75" strokeWidth="1.5" />
            <circle cx={C} cy={C} r="103" fill="none" stroke={p.main} strokeOpacity="0.35" strokeWidth="1" />
            {!compact &&
              bolts.map((a) => {
                const [x, y] = pt(106, a);
                return <polygon key={a} points={hex(x, y, 2.4)} fill={p.bolt} stroke={p.light} strokeOpacity="0.7" strokeWidth="0.7" />;
              })}
          </Layer>

          {/* ── dial: ticks, cardinal markers, radar sweep ── */}
          <Layer z={Z.dial}>
            {!compact &&
              ticks.map(({ a, major }) => {
                const [x1, y1] = pt(major ? 134 : 138, a);
                const [x2, y2] = pt(143, a);
                return (
                  <line
                    key={a}
                    x1={x1}
                    y1={y1}
                    x2={x2}
                    y2={y2}
                    stroke={p.main}
                    strokeOpacity={major ? 0.9 : 0.35}
                    strokeWidth={major ? 2 : 1}
                  />
                );
              })}
            <motion.g style={{ rotate: sweep }}>
              <circle cx={C} cy={C} r="146" fill="none" />
              {sweepSlices.map((i) => (
                <path key={i} d={wedge(110, 146, -i * 4 - 4, -i * 4)} fill={p.main} fillOpacity={(0.32 * (10 - i)) / 10} />
              ))}
              <line x1={C} y1={C - 110} x2={C} y2={C - 146} stroke={p.light} strokeWidth="1.5" />
            </motion.g>
            {!compact &&
              [0, 90, 180, 270].map((a) => (
                <polygon
                  key={a}
                  points={`${C},${C - 131} ${C - 4},${C - 137} ${C + 4},${C - 137}`}
                  fill={p.light}
                  transform={`rotate(${a} ${C} ${C})`}
                />
              ))}
          </Layer>

          {/* ── gear ring + plate rails ── */}
          <Layer z={Z.gear}>
            <motion.g style={{ rotate: gear }}>
              <CogArt kind={skin.cog} p={p} />
            </motion.g>
            {spec.segs.map((s) => {
              const [cx0, cy0] = pt(s.r2 + 4, s.a0 - 2);
              const [cx1, cy1] = pt(s.r2 + 4, s.a1 + 2);
              return (
                <g key={s.mid} stroke={p.main} strokeOpacity="0.35" strokeWidth="1" fill="none">
                  <path d={arcPath(s.r2 + 4, s.a0 - 2, s.a1 + 2)} />
                  <circle cx={cx0} cy={cy0} r="1.6" fill={p.main} />
                  <circle cx={cx1} cy={cy1} r="1.6" fill={p.main} />
                </g>
              );
            })}
          </Layer>

          {/* ── plate thickness: darker slices behind the plates ── */}
          {(compact ? PLATE_DEPTH.slice(1) : PLATE_DEPTH).map((z) => (
            <Layer key={z} z={z}>
              <motion.g style={{ rotate: shell }}>
                <circle cx={C} cy={C} r="184" fill="none" />
                {spec.gyro
                  ? [-GYRO.tilt, GYRO.tilt].map((t) => (
                      <ellipse key={t} cx={C} cy={C} rx={GYRO.rx} ry={GYRO.ry} transform={`rotate(${t} ${C} ${C})`} fill="none" stroke={p.deep} strokeWidth="11" />
                    ))
                  : null}
                {spec.track ? <circle cx={C} cy={C} r={spec.track.r} fill="none" stroke={p.deep} strokeWidth={spec.track.w + 2} /> : null}
                {spec.segs.map((s) => (
                  <Radial key={`${s.mid}-${s.index}`} angle={s.mid} push={push} dist={pushDist}>
                    {spec.spikes
                      ? spikePaths(s).map((d) => <path key={d} d={d} fill={p.deep} stroke={p.main} strokeOpacity="0.3" strokeWidth="1.2" />)
                      : null}
                    <path d={segShape(s)} fillRule="evenodd" fill={p.deep} stroke={p.main} strokeOpacity="0.3" strokeWidth="1.4" />
                  </Radial>
                ))}
              </motion.g>
            </Layer>
          ))}

          {/* ── armor plates ── */}
          <Layer z={Z.plates}>
            {!compact && (
              <text
                x={C}
                y="399"
                textAnchor="middle"
                fontFamily="JetBrains Mono, monospace"
                fontSize="9"
                letterSpacing="3"
                fill={p.main}
                fillOpacity="0.85"
              >
                {charged ? "OVERCLOCK ▲▲▲ ENGAGED" : "UNIT H.THAN-01 · ONLINE"}
              </text>
            )}
            <motion.g style={{ rotate: shell }}>
              <circle cx={C} cy={C} r="184" fill="none" />
              {spec.gyro
                ? [-GYRO.tilt, GYRO.tilt].map((t) => (
                    <g key={t} transform={`rotate(${t} ${C} ${C})`} fill="none">
                      <ellipse cx={C} cy={C} rx={GYRO.rx} ry={GYRO.ry} stroke="url(#halo-edge)" strokeWidth="10" strokeOpacity={charged ? 1 : 0.8} />
                      <ellipse cx={C} cy={C} rx={GYRO.rx} ry={GYRO.ry} stroke={p.plateA} strokeWidth="7" />
                      {!compact && (
                        <ellipse
                          cx={C}
                          cy={C}
                          rx={GYRO.rx}
                          ry={GYRO.ry}
                          stroke={charged ? p.hot : p.main}
                          strokeWidth="1.4"
                          strokeDasharray="5 11"
                          strokeLinecap="round"
                          className="halo-flow"
                        />
                      )}
                      {[-1, 1].map((side) => (
                        <circle key={side} cx={C + side * GYRO.rx} cy={C} r="7" fill={p.ink} stroke={p.light} strokeOpacity="0.8" strokeWidth="1.2" />
                      ))}
                    </g>
                  ))
                : null}
              {spec.track ? (
                <g fill="none">
                  <circle cx={C} cy={C} r={spec.track.r} stroke="url(#halo-edge)" strokeWidth={spec.track.w + 2.4} strokeOpacity={charged ? 1 : 0.8} />
                  <circle cx={C} cy={C} r={spec.track.r} stroke={p.plateA} strokeWidth={spec.track.w} />
                  {!compact && spec.track.w >= 6 ? (
                    <circle cx={C} cy={C} r={spec.track.r} stroke={charged ? p.hot : p.main} strokeWidth="1.2" strokeDasharray="5 11" strokeLinecap="round" className="halo-flow" />
                  ) : null}
                </g>
              ) : null}
              {spec.segs.map((s) => {
                const badge = pt(spec.badgeR ?? s.r1 + 8.5, s.mid);
                return (
                  <Radial key={`${s.mid}-${s.index}`} angle={s.mid} push={push} dist={pushDist}>
                    {spec.spikes
                      ? spikePaths(s).map((d) => (
                          <path key={d} d={d} fill="url(#halo-plate)" stroke="url(#halo-edge)" strokeWidth="1.2" strokeOpacity={charged ? 1 : 0.8} />
                        ))
                      : null}
                    <path
                      d={segShape(s)}
                      fillRule="evenodd"
                      fill="url(#halo-plate)"
                      stroke="url(#halo-edge)"
                      strokeWidth="1.6"
                      strokeOpacity={charged ? 1 : 0.8}
                      style={fade}
                    />
                    {!compact && <path d={segShape(s)} fillRule="evenodd" fill="url(#halo-pat)" />}
                    {!spec.plain && <path d={arcPath(s.r2 - 1.6, s.a0 + 1.5, s.a1 - 1.5)} fill="none" stroke={p.light} strokeOpacity="0.55" strokeWidth="1" />}
                    {!spec.plain && <path d={arcPath(s.r1 + 1.6, s.a0 + 5, s.a1 - 5)} fill="none" stroke={p.ink} strokeOpacity="0.8" strokeWidth="1.5" />}
                    {spec.plain ? null : compact ? (
                      <path d={arcPath(s.r2 - 6, s.a0 + 4, s.a1 - 4)} fill="none" stroke={p.main} strokeOpacity="0.35" strokeWidth="1" />
                    ) : (
                      <>
                        <path d={arcPath(s.r2 - 4.5, s.a0 + 3, s.a1 - 3)} fill="none" stroke={p.ink} strokeWidth="3.4" strokeLinecap="round" />
                        <path
                          d={arcPath(s.r2 - 4.5, s.a0 + 3, s.a1 - 3)}
                          fill="none"
                          stroke={charged ? p.hot : p.main}
                          strokeOpacity={charged ? 1 : 0.85}
                          strokeWidth="1.4"
                          strokeDasharray="5 11"
                          strokeLinecap="round"
                          className="halo-flow"
                          style={{ filter: `drop-shadow(0 0 2px rgb(${rgb(p.main)} / 0.9))` }}
                        />
                        {s.badge &&
                          ventAngles(s).map((a) => {
                            const [x1, y1] = pt(s.r1 + 4, a);
                            const [x2, y2] = pt(s.r1 + 13, a);
                            return (
                              <line
                                key={a}
                                x1={x1}
                                y1={y1}
                                x2={x2}
                                y2={y2}
                                stroke={charged ? p.light : p.main}
                                strokeOpacity={0.45 + heat * 0.5}
                                strokeWidth="2.2"
                                strokeLinecap="round"
                                style={fade}
                              />
                            );
                          })}
                        {[s.a0 + 5, s.a1 - 5].map((a) => {
                          const [x, y] = pt(s.r1 + 9, a);
                          return <circle key={a} cx={x} cy={y} r="2.3" fill={p.ink} stroke={p.main} strokeOpacity="0.8" strokeWidth="1" />;
                        })}
                      </>
                    )}
                    {!compact && s.badge && (
                      <>
                        <circle cx={badge[0]} cy={badge[1]} r="9.5" fill={p.ink} stroke={p.light} strokeOpacity={charged ? 1 : 0.6} strokeWidth="1" style={fade} />
                        <circle cx={badge[0]} cy={badge[1]} r="12" fill="none" stroke={p.main} strokeOpacity="0.35" strokeWidth="0.8" strokeDasharray="1.5 2.5" />
                        <text
                          x={badge[0]}
                          y={badge[1] + 4.5}
                          textAnchor="middle"
                          fontFamily="Cinzel, 'Apple Symbols', serif"
                          fontSize={glyphs[s.index % glyphs.length].length > 2 ? 10 : 13}
                          fill={p.light}
                        >
                          {glyphs[s.index % glyphs.length]}
                        </text>
                      </>
                    )}
                  </Radial>
                );
              })}
            </motion.g>
          </Layer>

          {/* ── clamp thickness ── */}
          {clamp &&
            (compact ? CLAMP_DEPTH.slice(1) : CLAMP_DEPTH).map((z) => (
              <Layer key={z} z={z}>
                {spec.clamps.map((a) => (
                  <Radial key={a} angle={a} push={push} dist={PUSH_PX + 5}>
                    <path
                      d={clamp.outline}
                      transform={`rotate(${a} ${C} ${C})`}
                      fill={p.deep}
                      stroke={p.main}
                      strokeOpacity="0.3"
                      strokeWidth="1.2"
                      strokeLinejoin="round"
                    />
                  </Radial>
                ))}
              </Layer>
            ))}

          {/* ── clamps, front-most ── */}
          {clamp && (
            <Layer z={Z.clamps}>
              {spec.clamps.map((a, i) => (
                <Radial key={a} angle={a} push={push} dist={PUSH_PX + 5}>
                  <g transform={`rotate(${a} ${C} ${C})`}>
                    <path d={clamp.outline} fill={p.socket} stroke={p.main} strokeOpacity="0.85" strokeWidth="1.4" strokeLinejoin="round" />
                    {clamp.detail({ p, compact, charged, i })}
                  </g>
                </Radial>
              ))}
            </Layer>
          )}
        </motion.div>
      </div>
    </div>
  );
}
