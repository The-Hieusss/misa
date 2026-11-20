import { useCallback, useEffect, useRef, useState } from "react";
import type { FormEvent, PointerEvent as ReactPointerEvent } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import type { Variants } from "framer-motion";
import { ArrowUpToLine, Palette, Send, X } from "lucide-react";
import MechaHalo from "./misa/mecha-halo";
import { HudCorners } from "./misa/hud-corners";
import { playMechaClose, playMechaOpen } from "./lib/mecha-sfx";
import { inApp, onMessage, send } from "./bridge";
import type { Confirm, FromSwift, Suggestion, TimerState } from "./bridge";
import { TimerRing } from "./misa/timer-ring";
import { MenuCamera } from "./misa/menu-camera";
import { Wardrobe } from "./misa/wardrobe";
import {
  DEFAULT_SKIN,
  SkinContext,
  applyPaletteToPage,
  paletteFor,
  sanitize,
} from "./misa/skin";
import type { Skin } from "./misa/skin";

/* Sizes must match Swift (Window/Geometry.swift) */
const HALO = 140; // the halo's square box
const PANEL_W = 400;
const PANEL_H = 510;
const GAP = 6;

type Layout = Extract<FromSwift, { type: "layout" }>;
type Msg = {
  id: number;
  from: "user" | "bot";
  text: string;
  suggestions?: Suggestion[];
  confirm?: Confirm;
};

const SUGGESTIONS: Suggestion[] = [
  { label: "What can you do?", prompt: "What can you do?" },
  { label: "Focus for 25 min", prompt: "Focus for 25 minutes" },
  { label: "Tidy my screenshots", prompt: "Tidy my screenshots" },
  { label: "What's in Disposable?", prompt: "What's in Disposable?" },
  { label: "What's using my disk?", prompt: "What's using my disk?" },
];

/* ---------------------------------------------------------------- */
/* Teleport-in, adapted from the portfolio's dock (no tall beam:     */
/* the window is only as big as the halo).                            */
/* ---------------------------------------------------------------- */
const ease = [0.22, 1, 0.36, 1] as const;

const body: Variants = {
  hidden: { opacity: 0, scaleX: 0.2, scaleY: 0.02, filter: "brightness(3)" },
  shown: {
    opacity: [0, 1, 0.35, 1, 0.7, 1],
    scaleX: [0.2, 1.35, 0.9, 1.04, 1],
    scaleY: [0.02, 0.06, 1.15, 0.97, 1],
    filter: [
      "brightness(3)",
      "brightness(2.2)",
      "brightness(1.4)",
      "brightness(1)",
    ],
    // Clear the filter afterwards: a lingering CSS filter makes WebKit draw a box behind her.
    transitionEnd: { filter: "none" },
    transition: { duration: 0.75, delay: 0.15, ease },
  },
  // Teleport out: squash into a bright line and vanish (from the portfolio's dock).
  gone: {
    opacity: [1, 0.6, 0],
    scaleX: [1, 1.35, 0.1],
    scaleY: [1, 0.05, 0.02],
    filter: ["brightness(1)", "brightness(3)", "brightness(3)"],
    transition: { duration: 0.45, ease: "easeIn" },
  },
};

const shock: Variants = {
  hidden: { scale: 0.5, opacity: 0 },
  shown: {
    scale: [0.5, 1.4],
    opacity: [0, 0.9, 0],
    transition: { duration: 0.8, delay: 0.4, ease: "easeOut" },
  },
};

const SPARKS = Array.from({ length: 10 }, (_, i) => {
  const a = (i / 10) * Math.PI * 2;
  return { x: Math.cos(a) * 60, y: Math.sin(a) * 60, d: 0.05 + i * 0.025 };
});

const spark = (s: (typeof SPARKS)[number]): Variants => ({
  hidden: { x: s.x, y: s.y, opacity: 0 },
  shown: {
    x: [s.x, 0],
    y: [s.y, 0],
    opacity: [0, 1, 0],
    transition: { duration: 0.55, delay: s.d, ease: "easeIn" },
  },
});

/* ---------------------------------------------------------------- */
/* Confirm card: nothing risky runs until its button is clicked       */
/* ---------------------------------------------------------------- */
function ConfirmCard({
  c,
  onAnswer,
}: {
  c: Confirm;
  onAnswer: (id: string, ok: boolean) => void;
}) {
  const [answered, setAnswered] = useState<null | boolean>(null);
  const tone = c.danger
    ? "text-red-300 ring-red-400/50"
    : "text-peach ring-ember/40";
  const answer = (ok: boolean) => {
    if (answered !== null) return;
    setAnswered(ok);
    onAnswer(c.id, ok);
  };
  return (
    <motion.div
      initial={{ opacity: 0, y: 4 }}
      animate={{ opacity: 1, y: 0 }}
      className="mt-2"
    >
      <div className={`chamfer-sm bg-ink/90 p-3 ring-1 ring-inset ${tone}`}>
        <p className="text-sm font-medium text-cream">{c.title}</p>
        {c.items.length ? (
          <ul className="selectable messages mt-2 max-h-28 overflow-y-auto font-mono text-[11px] leading-5 text-sand">
            {c.items.map((it, i) => (
              <li key={i} className="truncate">
                · {it}
              </li>
            ))}
          </ul>
        ) : null}
        {answered === null ? (
          <div className="mt-3 flex gap-2">
            <button
              type="button"
              onClick={() => answer(true)}
              className={`chamfer-sm px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.12em] transition ${
                c.danger
                  ? "bg-red-500/80 text-white hover:bg-red-500"
                  : "bg-gold-gradient text-ink hover:brightness-110"
              }`}
            >
              {c.button}
            </button>
            <button
              type="button"
              onClick={() => answer(false)}
              className="chamfer-sm bg-ember/10 px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.12em] text-peach transition hover:bg-ember/25"
            >
              Cancel
            </button>
          </div>
        ) : (
          <p className="mt-2 font-mono text-[10px] uppercase tracking-[0.15em] text-dim">
            {answered ? "Confirmed" : "Cancelled"}
          </p>
        )}
      </div>
    </motion.div>
  );
}

/* ---------------------------------------------------------------- */
/* Bot message with the typewriter effect                             */
/* ---------------------------------------------------------------- */
function BotMessage({
  msg,
  animate,
  onTick,
  onAsk,
  onAnswer,
}: {
  msg: Msg;
  animate: boolean;
  onTick: () => void;
  onAsk: (prompt: string) => void;
  onAnswer: (id: string, ok: boolean) => void;
}) {
  const [n, setN] = useState(animate ? 0 : msg.text.length);
  const done = n >= msg.text.length;

  useEffect(() => {
    if (done) return;
    const step = Math.max(1, Math.round(msg.text.length / 90));
    const id = window.setInterval(
      () => setN((v) => Math.min(msg.text.length, v + step)),
      14,
    );
    return () => window.clearInterval(id);
  }, [done, msg.text.length]);

  useEffect(onTick, [n, onTick]);

  return (
    <div className="max-w-[90%] self-start">
      <div className="selectable chamfer-sm bg-ember/10 px-3.5 py-2.5 text-sm leading-6 whitespace-pre-line text-cream">
        {msg.text.slice(0, n)}
        {!done ? (
          <span className="ml-0.5 inline-block h-3.5 w-1.5 animate-pulse bg-ember align-middle" />
        ) : null}
      </div>
      {done && msg.confirm ? (
        <ConfirmCard c={msg.confirm} onAnswer={onAnswer} />
      ) : null}
      {done && msg.suggestions?.length ? (
        <motion.div
          initial={{ opacity: 0, y: 4 }}
          animate={{ opacity: 1, y: 0 }}
          className="mt-2 flex flex-wrap gap-1.5"
        >
          {msg.suggestions.map((s) => (
            <button
              key={s.label}
              type="button"
              onClick={() => onAsk(s.prompt)}
              className="chamfer-sm bg-ink px-2.5 py-1.5 font-mono text-[10px] uppercase tracking-[0.12em] text-peach ring-1 ring-ember/40 transition ring-inset hover:bg-ember hover:text-ink"
            >
              {s.label}
            </button>
          ))}
        </motion.div>
      ) : null}
    </div>
  );
}

/* ---------------------------------------------------------------- */
/* M.I.S.A.                                                           */
/* ---------------------------------------------------------------- */
export default function App() {
  const reduce = useReducedMotion();
  const [layout, setLayout] = useState<Layout>({
    type: "layout",
    mode: "collapsed",
    halo: { x: 0, y: 0 },
    right: true,
    bottom: true,
  });
  const [panelShown, setPanelShown] = useState(false);
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [thinking, setThinking] = useState(false);
  const [input, setInput] = useState("");
  const [surge, setSurge] = useState(0);
  const [hover, setHover] = useState(false);
  const [timer, setTimer] = useState<TimerState>({
    state: "idle",
    label: "Focus",
    total: 0,
    remaining: 0,
    endsAt: 0,
  });
  const [unread, setUnread] = useState(false);
  const panelShownRef = useRef(false);
  const [leaving, setLeaving] = useState(false); // teleporting out to the menu bar
  const leavingRef = useRef(false);
  const [retracting, setRetracting] = useState(false);
  const [spawn, setSpawn] = useState(0); // bump to replay her teleport-in
  const [skin, setSkin] = useState<Skin>(DEFAULT_SKIN);
  const [draft, setDraft] = useState<Skin | null>(null); // wardrobe open: what she's trying on
  const look = draft ?? skin;

  useEffect(() => applyPaletteToPage(paletteFor(look)), [look]);

  const idRef = useRef(0);
  const lastAnimated = useRef(-1);
  const listRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const press = useRef<{ x: number; y: number } | null>(null);
  const askedAt = useRef(0);

  const open = layout.mode === "open";

  const scrollToEnd = useCallback(() => {
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, []);

  const pushBot = useCallback(
    (text: string, suggestions?: Suggestion[], confirm?: Confirm) => {
      const id = idRef.current++;
      lastAnimated.current = id;
      setMsgs((m) => [...m, { id, from: "bot", text, suggestions, confirm }]);
    },
    [],
  );

  const requestOpen = useCallback(() => {
    playMechaOpen();
    send({ type: "open" });
  }, []);

  const requestClose = useCallback(() => {
    playMechaClose();
    setPanelShown(false); // Swift shrinks the window once the exit animation ends
  }, []);

  // Messages from Swift
  useEffect(
    () =>
      onMessage((m) => {
        switch (m.type) {
          case "layout":
            setLayout((prev) => {
              if (prev.mode === "docked" && m.mode !== "docked")
                setSpawn((n) => n + 1); // back from the menu bar
              return m;
            });
            setPanelShown(m.mode === "open");
            if (m.mode === "docked") {
              leavingRef.current = false;
              setLeaving(false);
              setRetracting(false);
            }
            break;
          case "teleportOut":
            leavingRef.current = true;
            setLeaving(true);
            setPanelShown(false);
            playMechaClose();
            break;
          case "retract":
            setRetracting(true);
            playMechaOpen();
            break;
          case "reply": {
            // Keep "Processing" up briefly so replies don't feel instant and robotic.
            const wait = Math.max(
              0,
              350 - (performance.now() - askedAt.current),
            );
            window.setTimeout(
              () => {
                setThinking(false);
                pushBot(m.text, m.suggestions, m.confirm);
                if (!panelShownRef.current) setUnread(true);
              },
              reduce ? 0 : wait,
            );
            break;
          }
          case "timer":
            setTimer(m);
            break;
          case "dragHover":
            setHover(m.on);
            break;
          case "skin":
            setSkin(sanitize(m.skin));
            break;
          case "toggle":
            if (panelShown) requestClose();
            else requestOpen();
            break;
        }
      }),
    [panelShown, pushBot, reduce, requestClose, requestOpen],
  );

  useEffect(() => send({ type: "ready" }), []);

  useEffect(() => {
    panelShownRef.current = panelShown;
    if (!panelShown) {
      setDraft(null); // closing the chat mid-fitting keeps the old look
      return;
    }
    setUnread(false);
    if (timer.state === "done") send({ type: "timerSeen" });
  }, [panelShown, timer.state]);

  // Greet on first open, focus the input every time.
  useEffect(() => {
    if (!panelShown) return;
    if (msgs.length === 0) {
      pushBot(
        "Systems online. I'm M.I.S.A., your Mac assistant.\nDrop files on me to convert them, copy their text for AI, or prep them for Canvas. Or ask me to tidy screenshots, old downloads or Disposable.",
      );
    }
    window.setTimeout(
      () => inputRef.current?.focus({ preventScroll: true }),
      60,
    );
  }, [panelShown, msgs.length, pushBot]);

  useEffect(() => {
    if (!panelShown) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && requestClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [panelShown, requestClose]);

  useEffect(scrollToEnd, [msgs, thinking, scrollToEnd]);

  const ask = (q: string) => {
    const text = q.trim();
    if (!text) return;
    setMsgs((m) => [...m, { id: idRef.current++, from: "user", text }]);
    setThinking(true);
    setSurge((s) => s + 1);
    askedAt.current = performance.now();
    send({ type: "ask", text });
  };

  const answerConfirm = (id: string, ok: boolean) => {
    if (ok) {
      setThinking(true);
      setSurge((s) => s + 1);
      askedAt.current = performance.now();
    }
    send({ type: ok ? "confirm" : "cancel", id });
  };

  const submit = (e: FormEvent) => {
    e.preventDefault();
    ask(input);
    setInput("");
  };

  /* Dragging: Swift moves the window while the button is held. */
  const startDrag = (e: ReactPointerEvent) => {
    if (e.button !== 0) return;
    if (
      (e.target as HTMLElement).closest(
        "button:not([data-drag]), input, .selectable",
      )
    )
      return;
    press.current = { x: e.screenX, y: e.screenY };
    send({ type: "dragStart" });
  };

  const wasDragged = (e: { screenX: number; screenY: number }) => {
    const p = press.current;
    press.current = null;
    return p ? Math.hypot(e.screenX - p.x, e.screenY - p.y) > 4 : false;
  };

  const onHaloClick = (e: React.MouseEvent) => {
    if (wasDragged(e)) return;
    if (panelShown) requestClose();
    else requestOpen();
  };

  /* Panel placement: open toward the middle of the screen. */
  const panelLeft = layout.right
    ? layout.halo.x + HALO - PANEL_W
    : layout.halo.x;
  const panelTop = layout.bottom
    ? layout.halo.y - GAP - PANEL_H
    : layout.halo.y + HALO + GAP;
  const fromBottom = layout.bottom;

  const saveDraft = () => {
    if (!draft) return;
    setSkin(draft);
    send({ type: "skin", skin: draft });
    setDraft(null);
  };

  return (
    <SkinContext.Provider value={look}>
      <div className="relative h-full w-full">
        {/* Chat panel */}
        <AnimatePresence
          onExitComplete={() => !leavingRef.current && send({ type: "close" })}
        >
          {open && panelShown ? (
            <motion.div
              key="panel"
              role="dialog"
              aria-label="M.I.S.A. assistant"
              initial={
                reduce
                  ? { opacity: 0 }
                  : {
                      opacity: 0,
                      y: fromBottom ? 16 : -16,
                      scale: 0.96,
                      clipPath: fromBottom
                        ? "inset(100% 0 0 0)"
                        : "inset(0 0 100% 0)",
                    }
              }
              animate={{
                opacity: 1,
                y: 0,
                scale: 1,
                clipPath: "inset(0% 0 0% 0)",
              }}
              exit={
                reduce
                  ? { opacity: 0 }
                  : {
                      opacity: 0,
                      y: fromBottom ? 12 : -12,
                      scale: 0.97,
                      clipPath: fromBottom
                        ? "inset(100% 0 0 0)"
                        : "inset(0 0 100% 0)",
                    }
              }
              transition={{ duration: 0.35, ease }}
              style={{
                left: panelLeft,
                top: panelTop,
                width: PANEL_W,
                height: PANEL_H,
              }}
              className={`absolute flex flex-col [color-scheme:dark] ${fromBottom ? "origin-bottom" : "origin-top"}`}
            >
              <div className="chamfer flex h-full flex-col bg-ember/40 p-px">
                <div className="chamfer relative flex h-full flex-col overflow-hidden bg-ink/95">
                  <div
                    aria-hidden
                    className="scanlines pointer-events-none absolute inset-0"
                  />
                  <div
                    aria-hidden
                    className="hud-grid pointer-events-none absolute inset-0 opacity-60"
                  />

                  {/* header (drag handle) */}
                  <div
                    onPointerDown={startDrag}
                    className="relative flex cursor-grab items-center gap-3 border-b border-ember/30 bg-ember/10 px-4 py-3 active:cursor-grabbing"
                  >
                    <MechaHalo
                      compact
                      className="pointer-events-none h-9 w-9 shrink-0"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="font-display text-sm font-semibold tracking-[0.18em] text-cream">
                        M.I.S.A.
                      </p>
                      <p className="flex items-center gap-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-ember">
                        <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-ember" />
                        Mac assistant · {inApp() ? "online" : "browser preview"}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => setDraft((d) => (d ? null : skin))}
                      aria-label={
                        draft
                          ? "Close the wardrobe without saving"
                          : "Change her look"
                      }
                      aria-pressed={Boolean(draft)}
                      title={draft ? "Close wardrobe" : "Change her look"}
                      className={`chamfer-sm flex h-8 w-8 items-center justify-center transition hover:bg-ember hover:text-ink ${
                        draft ? "bg-ember text-ink" : "bg-ember/10 text-peach"
                      }`}
                    >
                      <Palette className="h-4 w-4" />
                    </button>
                    <button
                      type="button"
                      onClick={() => send({ type: "dock" })}
                      aria-label="Put M.I.S.A. away in the menu bar"
                      title="Put away in menu bar"
                      className="chamfer-sm flex h-8 w-8 items-center justify-center bg-ember/10 text-peach transition hover:bg-ember hover:text-ink"
                    >
                      <ArrowUpToLine className="h-4 w-4" />
                    </button>
                    <button
                      type="button"
                      onClick={requestClose}
                      aria-label="Close M.I.S.A."
                      className="chamfer-sm flex h-8 w-8 items-center justify-center bg-ember/10 text-peach transition hover:bg-ember hover:text-ink"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>

                  {draft ? (
                    <Wardrobe
                      draft={draft}
                      onChange={setDraft}
                      onSave={saveDraft}
                      onCancel={() => setDraft(null)}
                    />
                  ) : (
                    <>
                      {/* messages */}
                      <div
                        ref={listRef}
                        role="log"
                        aria-live="polite"
                        className="messages relative flex flex-1 flex-col gap-3 overflow-y-auto px-4 py-4"
                      >
                        {msgs.map((m) =>
                          m.from === "user" ? (
                            <div
                              key={m.id}
                              className="selectable chamfer-sm max-w-[85%] self-end bg-gold-gradient px-3.5 py-2 text-sm font-medium text-ink"
                            >
                              {m.text}
                            </div>
                          ) : (
                            <BotMessage
                              key={m.id}
                              msg={m}
                              animate={!reduce && m.id === lastAnimated.current}
                              onTick={scrollToEnd}
                              onAsk={ask}
                              onAnswer={answerConfirm}
                            />
                          ),
                        )}
                        {thinking ? (
                          <div className="flex items-center gap-2 self-start font-mono text-[10px] uppercase tracking-[0.2em] text-ember">
                            <span className="flex gap-1">
                              {[0, 1, 2].map((i) => (
                                <span
                                  key={i}
                                  className="h-1.5 w-1.5 animate-bounce bg-ember"
                                  style={{ animationDelay: `${i * 120}ms` }}
                                />
                              ))}
                            </span>
                            Processing
                          </div>
                        ) : null}
                      </div>

                      {/* suggestions */}
                      {msgs.length <= 1 ? (
                        <div className="relative flex gap-1.5 overflow-x-auto px-4 pb-3">
                          {SUGGESTIONS.map((s) => (
                            <button
                              key={s.label}
                              type="button"
                              onClick={() => ask(s.prompt)}
                              className="chamfer-sm shrink-0 bg-ember/10 px-2.5 py-1.5 font-mono text-[10px] uppercase tracking-[0.1em] whitespace-nowrap text-peach transition hover:bg-ember hover:text-ink"
                            >
                              {s.label}
                            </button>
                          ))}
                        </div>
                      ) : null}

                      {/* input */}
                      <form
                        onSubmit={submit}
                        className="relative flex items-center gap-2 border-t border-ember/30 bg-surface/80 p-3"
                      >
                        <label htmlFor="misa-input" className="sr-only">
                          Ask M.I.S.A.
                        </label>
                        <input
                          id="misa-input"
                          ref={inputRef}
                          value={input}
                          onChange={(e) => setInput(e.target.value)}
                          placeholder="Ask, or drop files on me…"
                          autoComplete="off"
                          spellCheck={false}
                          className="chamfer-sm min-w-0 flex-1 bg-ink/80 px-3 py-2.5 font-mono text-sm text-cream outline-none placeholder:text-dim focus:bg-ember/[0.06]"
                        />
                        <button
                          type="submit"
                          aria-label="Send"
                          disabled={!input.trim()}
                          className="chamfer-sm flex h-10 w-10 shrink-0 items-center justify-center bg-gold-gradient text-ink transition hover:brightness-110 disabled:opacity-40"
                        >
                          <Send className="h-4 w-4" />
                        </button>
                      </form>
                    </>
                  )}
                </div>
              </div>
              <HudCorners size="h-3 w-3" className="-m-1.5" />
            </motion.div>
          ) : null}
        </AnimatePresence>

        {/* Put away: a camera hanging from the menu bar */}
        {layout.mode === "docked" && layout.camera ? (
          <MenuCamera
            x={layout.camera.x}
            y={layout.camera.y}
            retracting={retracting}
            timer={timer}
            unread={unread}
            onClick={() => {
              setRetracting(true);
              playMechaOpen();
            }}
            onMenu={() => send({ type: "menu" })}
            onRetracted={() => send({ type: "undock" })}
          />
        ) : null}

        {/* The halo: draggable, click to open/close */}
        {layout.mode !== "docked" ? (
          <motion.div
            key={spawn}
            initial={reduce ? { opacity: 0 } : "hidden"}
            animate={
              reduce ? { opacity: leaving ? 0 : 1 } : leaving ? "gone" : "shown"
            }
            onAnimationComplete={() => {
              if (leaving && reduce) send({ type: "teleportedOut" });
            }}
            className="absolute"
            style={{
              left: layout.halo.x,
              top: layout.halo.y,
              width: HALO,
              height: HALO,
            }}
          >
            <div className="relative h-full w-full p-3.5">
              {!reduce ? (
                <>
                  <motion.span
                    variants={shock}
                    aria-hidden
                    className="pointer-events-none absolute inset-3.5 rounded-full border-2 border-peach"
                  />
                  {SPARKS.map((s, i) => (
                    <motion.span
                      key={i}
                      variants={spark(s)}
                      aria-hidden
                      className="pointer-events-none absolute left-1/2 top-1/2 -ml-1 -mt-1 h-2 w-2 rotate-45 bg-peach shadow-[0_0_8px_rgb(var(--peach-rgb)/1)]"
                    />
                  ))}
                </>
              ) : null}

              <motion.button
                type="button"
                data-drag
                variants={reduce ? undefined : body}
                onAnimationComplete={(def) => {
                  if (def === "gone" && leavingRef.current)
                    send({ type: "teleportedOut" });
                }}
                onPointerDown={startDrag}
                onClick={onHaloClick}
                aria-label={panelShown ? "Close M.I.S.A." : "Open M.I.S.A."}
                aria-expanded={panelShown}
                className="group relative block h-full w-full cursor-pointer rounded-full outline-none"
              >
                <motion.span
                  className="relative block h-full w-full"
                  animate={reduce ? undefined : { y: [0, -4, 0] }}
                  transition={{
                    duration: 3.2,
                    repeat: Infinity,
                    ease: "easeInOut",
                  }}
                >
                  {/* Round glow (a CSS drop-shadow renders as a square in WebKit) */}
                  <span
                    aria-hidden
                    className={`pointer-events-none absolute -inset-3 rounded-full bg-[radial-gradient(circle,rgb(var(--ember-rgb)/0.45)_0%,rgb(var(--ember-rgb)/0.15)_45%,transparent_70%)] transition-opacity duration-300 group-hover:opacity-100 ${
                      panelShown || hover ? "opacity-100" : "opacity-60"
                    }`}
                  />
                  <MechaHalo
                    compact
                    charged={panelShown || hover}
                    surge={surge}
                    className="relative h-full w-full"
                  />
                </motion.span>
              </motion.button>
            </div>
            <TimerRing timer={timer} />
            {unread && !panelShown ? (
              <span className="pointer-events-none absolute right-[30px] top-[22px] flex h-3 w-3">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-ember opacity-75" />
                <span className="relative inline-flex h-3 w-3 rounded-full border-2 border-ink bg-ember" />
              </span>
            ) : null}
          </motion.div>
        ) : null}
      </div>
    </SkinContext.Provider>
  );
}
