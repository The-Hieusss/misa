/**
 * The only channel between M.I.S.A.'s face (this web view) and the Swift app.
 * The web side can ask for things; only Swift can act on the Mac.
 */

import type { Skin } from "./misa/skin";

export type Suggestion = { label: string; prompt: string };

/** Web view → Swift */
export type ToSwift =
  | { type: "ready" }
  | { type: "open" } // grow the window into chat mode
  | { type: "close" } // shrink back to just the halo
  | { type: "ask"; text: string }
  | { type: "confirm"; id: string } // clicked the button on a confirm card
  | { type: "cancel"; id: string }
  | { type: "timerSeen" } // the "time's up" state was seen
  | { type: "dock" } // put her away into the menu bar
  | { type: "teleportedOut" } // her teleport-out animation finished; Swift can move the window
  | { type: "undock" } // the camera finished retracting; Swift can bring her back
  | { type: "menu" } // right-clicked the camera
  | { type: "dragStart" } // the mouse went down on a drag handle
  | { type: "hot"; rects: number[][] } // where her arms are ([x, y, w, h]), so only they take clicks
  | { type: "skin"; skin: Skin }; // saved from the wardrobe; Swift remembers it

export type TimerState = {
  state: "idle" | "running" | "paused" | "done";
  label: string; // "Focus", "Break" or "Timer"
  total: number; // seconds
  remaining: number; // seconds (used while paused)
  endsAt: number; // ms since 1970 (used while running)
};

/** A card shown before anything risky runs. Nothing happens until it's clicked. */
export type Confirm = { id: string; title: string; items: string[]; button: string; danger: boolean };

/** Swift → web view */
export type FromSwift =
  | {
      type: "layout";
      mode: "open" | "collapsed" | "docked";
      /** Docked: the camera's center in window coordinates. */
      camera?: { x: number; y: number };
      /** Top-left of the 140×140 halo box, in window coordinates. */
      halo: { x: number; y: number };
      /** Which side of the screen she's on, so the panel opens toward the middle. */
      right: boolean;
      bottom: boolean;
      /** Collapsed: which sides have screen room for an arm. */
      arms?: { left: boolean; right: boolean };
    }
  | { type: "reply"; text: string; suggestions?: Suggestion[]; confirm?: Confirm }
  | { type: "dragHover"; on: boolean } // files are being dragged over her
  | ({ type: "timer" } & TimerState)
  | { type: "teleportOut" } // play the teleport-out, then reply "teleportedOut"
  | { type: "retract" } // pull the camera up into the menu bar, then reply "undock"
  | { type: "toggle" } // global shortcut pressed
  | { type: "voice"; state: "listening" | "heard" | "idle"; text: string } // "Hey MISA": what she's hearing
  | { type: "skin"; skin: Partial<Record<keyof Skin, string>> }; // her saved outfit, sent on "ready"

type Handler = { postMessage(m: unknown): void };

declare global {
  interface Window {
    webkit?: { messageHandlers?: { misa?: Handler } };
    misa?: { receive(m: FromSwift): void; pointer?(x: number, y: number): void };
  }
}

const listeners = new Set<(m: FromSwift) => void>();

window.misa = {
  receive: (m) => listeners.forEach((l) => l(m)),
  // Swift sends the global mouse position so her eye can follow the cursor outside the window.
  pointer: (x, y) => window.dispatchEvent(new PointerEvent("pointermove", { clientX: x, clientY: y, pointerType: "mouse" })),
};

export function onMessage(l: (m: FromSwift) => void) {
  listeners.add(l);
  return () => {
    listeners.delete(l);
  };
}

export const inApp = () => Boolean(window.webkit?.messageHandlers?.misa);

export function send(m: ToSwift) {
  const h = window.webkit?.messageHandlers?.misa;
  if (h) h.postMessage(m);
  else browserFallback(m);
}

/** Lets `bun run dev` work in a normal browser tab for styling work. */
function browserFallback(m: ToSwift) {
  const emit = (r: FromSwift) => setTimeout(() => window.misa?.receive(r), 10);
  switch (m.type) {
    case "open":
      emit({ type: "layout", mode: "open", halo: { x: 260, y: 516 }, right: true, bottom: true, arms: { left: true, right: true } });
      break;
    case "close":
      emit({ type: "layout", mode: "collapsed", halo: { x: 90, y: 64 }, right: true, bottom: true, arms: { left: true, right: true } });
      break;
    case "ask":
      if (/^hey misa/i.test(m.text)) {
        // Preview the "Hey MISA" strip: words arriving, then the request.
        const words = m.text.replace(/^hey misa,?\s*/i, "").split(" ");
        words.forEach((_, i) => emit({ type: "voice", state: "listening", text: words.slice(0, i).join(" ") }));
        setTimeout(() => window.misa?.receive({ type: "voice", state: "heard", text: words.join(" ") }), 1600);
        break;
      }
      if (/focus|timer/i.test(m.text)) {
        emit({ type: "timer", state: "running", label: "Focus", total: 90, remaining: 90, endsAt: Date.now() + 90_000 });
        emit({ type: "reply", text: "(browser preview) Focus timer started: 1 min 30 sec." });
      } else if (/trash|tidy/i.test(m.text)) {
        emit({
          type: "reply",
          text: "(browser preview) Found 3 old screenshots.",
          confirm: { id: "demo", title: "Move them to the Trash?", items: ["Screenshot 1.png", "Screenshot 2.png", "Screenshot 3.png"], button: "Trash 3", danger: true },
        });
      } else {
        emit({ type: "reply", text: `(browser preview) You said: ${m.text}` });
      }
      break;
    case "confirm":
      emit({ type: "reply", text: "(browser preview) Done." });
      break;
    case "timerSeen":
      break;
    case "dock":
      emit({ type: "teleportOut" });
      break;
    case "teleportedOut":
      emit({ type: "layout", mode: "docked", camera: { x: 160, y: 36 }, halo: { x: 0, y: 0 }, right: true, bottom: false });
      break;
    case "undock":
      emit({ type: "layout", mode: "collapsed", halo: { x: 90, y: 64 }, right: true, bottom: true, arms: { left: true, right: true } });
      break;
    case "cancel":
      emit({ type: "reply", text: "(browser preview) Okay, I left everything as it was." });
      break;
  }
}
