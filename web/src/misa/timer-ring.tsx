import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import type { TimerState } from "@/bridge";
import { rgb, useSkin } from "./skin";

const R = 64; // ring radius inside the 140×140 halo box (the window is clipped to r = 70)
const CIRC = 2 * Math.PI * R;

export function remainingOf(t: TimerState, now: number) {
  if (t.state === "running") return Math.max(0, (t.endsAt - now) / 1000);
  if (t.state === "paused") return t.remaining;
  return 0;
}

export function clock(sec: number) {
  const s = Math.ceil(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}` : `${m}:${String(r).padStart(2, "0")}`;
}

/** Progress ring + countdown drawn over the halo while a timer is active. */
export function TimerRing({ timer }: { timer: TimerState }) {
  const { p } = useSkin();
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (timer.state !== "running") return;
    const id = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [timer.state]);

  if (timer.state === "idle") return null;

  const left = remainingOf(timer, now);
  const done = timer.state === "done";
  const progress = done ? 1 : timer.total > 0 ? 1 - left / timer.total : 0;
  const isBreak = timer.label === "Break";
  const color = isBreak ? "#7dd3a8" : p.light;

  return (
    <div className="pointer-events-none absolute inset-0">
      <svg viewBox="0 0 140 140" className="absolute inset-0 h-full w-full -rotate-90">
        <circle cx="70" cy="70" r={R} fill="none" stroke={`rgb(${rgb(p.main)} / 0.18)`} strokeWidth="3" />
        <motion.circle
          cx="70"
          cy="70"
          r={R}
          fill="none"
          stroke={color}
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={CIRC}
          animate={{ strokeDashoffset: CIRC * (1 - progress), opacity: done ? [1, 0.35, 1] : timer.state === "paused" ? 0.5 : 1 }}
          transition={
            done
              ? { opacity: { duration: 1.1, repeat: Infinity }, strokeDashoffset: { duration: 0.3 } }
              : { duration: 0.3, ease: "linear" }
          }
          style={{ filter: "none" }}
        />
      </svg>
      <div className="absolute inset-x-0 bottom-[13px] flex justify-center">
        <span
          className="chamfer-sm bg-ink/90 px-1.5 py-[1px] font-mono text-[10px] leading-4 tracking-[0.08em] tabular-nums"
          style={{ color }}
        >
          {done ? "DONE" : timer.state === "paused" ? `‖ ${clock(left)}` : clock(left)}
        </span>
      </div>
    </div>
  );
}
