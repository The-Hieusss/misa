import { useEffect, useMemo, useState } from "react";
import { AnimatePresence, motion, useAnimationFrame, useMotionValue, useReducedMotion, useTransform } from "framer-motion";
import MechaHalo from "./mecha-halo";
import { clock, remainingOf } from "./timer-ring";
import type { TimerState } from "@/bridge";
import { rgb, useSkin } from "./skin";

/* Adapted from the portfolio's phone-view NavCamera, sized to hang from the macOS menu bar. */
const SIZE = 64; // camera diameter (must match Geometry.camera in Swift)
const K = SIZE / 400; // halo viewBox units → px
const MAX_ANGLE = 70; // keep the ray aimed down at the screen, not up into the menu bar
const CYCLE = 11; // s: the ray sweeps on its own this often…
const SHOW = 6; // …for this long
const RING_R = SIZE / 2 + 6;
const RING_C = 2 * Math.PI * RING_R;

const chip =
  "chamfer-sm flex items-center gap-1.5 bg-ink/90 px-2 py-[3px] font-mono text-[9px] leading-none tracking-[0.16em] ring-1 ring-inset ring-ember/35";

/**
 * Docked M.I.S.A.: a surveillance camera hung from the bottom edge of the menu bar.
 * The eye follows your cursor anywhere on screen, a scan cone sweeps now and then,
 * a chip shows a running timer or a new message, and clicking deploys her back out.
 */
export function MenuCamera({
  x,
  y,
  retracting,
  timer,
  unread,
  onClick,
  onMenu,
  onRetracted,
}: {
  /** Camera center in the window. */
  x: number;
  y: number;
  retracting: boolean;
  timer: TimerState;
  unread: boolean;
  onClick: () => void;
  onMenu: () => void;
  onRetracted: () => void;
}) {
  const { p } = useSkin();
  const reduce = useReducedMotion();
  const [hover, setHover] = useState(false);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (timer.state !== "running") return;
    const id = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(id);
  }, [timer.state]);

  // The eye's gaze drives the ray: its tip sits on the iris and it points where the eye looks.
  const lookX = useMotionValue(0);
  const lookY = useMotionValue(0);
  const look = useMemo(() => ({ x: lookX, y: lookY }), [lookX, lookY]);
  const tipX = useTransform(lookX, (v) => v * K);
  const tipY = useTransform(lookY, (v) => v * K);
  const angle = useTransform([lookX, lookY], ([lx, ly]: number[]) => {
    const deg = (Math.atan2(-lx, ly) * 180) / Math.PI;
    return Math.max(-MAX_ANGLE, Math.min(MAX_ANGLE, deg));
  });

  const rayOpacity = useMotionValue(0);
  useAnimationFrame((t) => {
    if (reduce || retracting) return rayOpacity.set(0);
    const c = (t / 1000) % CYCLE;
    const ramp = 0.8;
    const sweep = c < SHOW ? Math.min(1, c / ramp, (SHOW - c) / ramp) : 0;
    rayOpacity.set(Math.max(sweep * 0.85, hover ? 0.9 : 0));
  });

  const timing = timer.state !== "idle";
  const left = remainingOf(timer, now);
  const done = timer.state === "done";
  const progress = done ? 1 : timer.total > 0 ? 1 - left / timer.total : 0;
  const timerColor = timer.label === "Break" ? "#7dd3a8" : p.light;

  return (
    <motion.div
      className="absolute"
      style={{ left: x - SIZE / 2, top: y - SIZE / 2, width: SIZE, height: SIZE }}
      // Deploys down out of the menu bar; retracts back up into it.
      initial={reduce ? { opacity: 0 } : { y: -SIZE, opacity: 0 }}
      animate={retracting ? (reduce ? { opacity: 0 } : { y: -SIZE, opacity: 0 }) : { y: 0, opacity: 1 }}
      transition={{ duration: 0.5, ease: [0.22, 1, 0.36, 1] }}
      onAnimationComplete={() => retracting && onRetracted()}
    >
      {/* scan ray (behind the housing): shines out of the lens and follows the eye */}
      {!reduce ? (
        <motion.div
          aria-hidden
          className="pointer-events-none absolute left-1/2 top-1/2 h-[256px] w-[176px] -translate-x-1/2"
          style={{ x: tipX, y: tipY, rotate: angle, opacity: rayOpacity, transformOrigin: "50% 0%" }}
        >
          <div className="absolute inset-0 [clip-path:polygon(50%_0,0_100%,100%_100%)] bg-[linear-gradient(to_bottom,rgb(var(--peach-rgb)/0.5),rgb(var(--ember-rgb)/0.2)_18%,rgb(var(--ember-rgb)/0.05)_62%,transparent)]" />
          {/* scanlines inside the beam */}
          <div className="scanlines absolute inset-0 opacity-70 [clip-path:polygon(50%_0,0_100%,100%_100%)]" />
        </motion.div>
      ) : null}

      {/* ceiling rail along the menu bar's bottom edge, with bolts */}
      <span
        aria-hidden
        className="chamfer-sm pointer-events-none absolute left-1/2 top-[calc(50%-3px)] h-1.5 w-[132px] -translate-x-1/2 bg-[linear-gradient(90deg,rgb(var(--ember-rgb)/0.15),rgb(var(--ember-rgb)/0.6)_30%,rgb(var(--ember-rgb)/0.6)_70%,rgb(var(--ember-rgb)/0.15))]"
      />
      {[-62, 56].map((dx) => (
        <span
          key={dx}
          aria-hidden
          className="pointer-events-none absolute top-[calc(50%-4px)] h-2 w-2 rotate-45 border border-peach/70 bg-ink"
          style={{ left: SIZE / 2 + dx }}
        />
      ))}

      {/* glow behind the lens */}
      <span
        aria-hidden
        className={`pointer-events-none absolute -inset-5 rounded-full bg-[radial-gradient(circle,rgb(var(--ember-rgb)/0.5)_0%,rgb(var(--ember-rgb)/0.16)_45%,transparent_70%)] transition-opacity duration-300 ${
          hover ? "opacity-100" : "opacity-55"
        }`}
      />

      {/* cradle hugging the lower housing */}
      <span
        aria-hidden
        className="pointer-events-none absolute -inset-x-2 -bottom-2 top-1/2 rounded-b-full border-[3px] border-t-0 border-ember/55 bg-ink/90"
      />
      <span aria-hidden className="pointer-events-none absolute -inset-x-2 -bottom-2 top-1/2 rounded-b-full border border-t-0 border-peach/25 [margin:4px]" />

      {/* timer progress around the lens */}
      {timing ? (
        <svg aria-hidden viewBox={`0 0 ${SIZE + 20} ${SIZE + 20}`} className="pointer-events-none absolute -inset-[10px] -rotate-90">
          <circle cx={SIZE / 2 + 10} cy={SIZE / 2 + 10} r={RING_R} fill="none" stroke={`rgb(${rgb(p.main)} / 0.2)`} strokeWidth="2.5" />
          <motion.circle
            cx={SIZE / 2 + 10}
            cy={SIZE / 2 + 10}
            r={RING_R}
            fill="none"
            stroke={timerColor}
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeDasharray={RING_C}
            animate={{ strokeDashoffset: RING_C * (1 - progress), opacity: done ? [1, 0.3, 1] : timer.state === "paused" ? 0.5 : 1 }}
            transition={done ? { opacity: { duration: 1.1, repeat: Infinity } } : { duration: 0.5, ease: "linear" }}
          />
        </svg>
      ) : null}

      <button
        type="button"
        onClick={onClick}
        onMouseEnter={() => setHover(true)}
        onMouseLeave={() => setHover(false)}
        onContextMenu={(e) => {
          e.preventDefault();
          onMenu();
        }}
        aria-label="Bring M.I.S.A. back"
        className="relative block h-full w-full cursor-pointer rounded-full outline-none"
      >
        <MechaHalo compact charged={hover || done} look={look} className="h-full w-full" />
      </button>

      {/* REC chip, under the menu bar to the left */}
      <span aria-hidden className={`${chip} pointer-events-none absolute right-[calc(100%+10px)] top-[calc(50%+8px)] text-peach/90`}>
        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-red-500 shadow-[0_0_6px_rgba(239,68,68,1)]" />
        REC
      </span>

      {/* status chip to the right: running timer, or a new message */}
      <AnimatePresence>
        {timing || unread ? (
          <motion.span
            key="status"
            initial={{ opacity: 0, x: -6 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -6 }}
            className={`${chip} pointer-events-none absolute left-[calc(100%+10px)] top-[calc(50%+8px)] whitespace-nowrap tabular-nums`}
            style={{ color: timing ? timerColor : p.light }}
          >
            {timing ? (
              <>
                {timer.label.toUpperCase()} {done ? "DONE" : timer.state === "paused" ? `‖ ${clock(left)}` : clock(left)}
              </>
            ) : (
              <>
                <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" />
                NEW
              </>
            )}
          </motion.span>
        ) : null}
      </AnimatePresence>

      {/* hover hint */}
      <AnimatePresence>
        {hover && !retracting ? (
          <motion.span
            key="hint"
            initial={{ opacity: 0, y: -4 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -4 }}
            className={`${chip} pointer-events-none absolute left-1/2 top-[calc(100%+12px)] -translate-x-1/2 whitespace-nowrap text-peach`}
          >
            CLICK TO DEPLOY
          </motion.span>
        ) : null}
      </AnimatePresence>
    </motion.div>
  );
}
