import { createContext, useContext } from "react";

/**
 * M.I.S.A.'s outfit: shell colors, inner cog, ring design, clamp design and plate badges.
 * The ids must match app/Sources/MISA/Skin.swift, which saves the choice and parses chat requests.
 */

export type Palette = {
  name: string;
  main: string; // the glow color (ember in the original)
  light: string; // highlights
  hot: string; // white-hot accents when charged
  ink: string; // near-black background
  surface: string;
  plateA: string; // plate gradient
  plateB: string;
  deep: string; // plate thickness, socket floor
  socket: string;
  bolt: string;
  irisDark: string;
  irisDeep: string;
  cream: string; // chat text
  sand: string;
  dim: string;
};

export const PALETTES = {
  ember: {
    name: "Ember", main: "#fa7636", light: "#ffb48a", hot: "#fff1e6", ink: "#0b0705", surface: "#140d0a",
    plateA: "#2e1f16", plateB: "#140d0a", deep: "#120a06", socket: "#1c140f", bolt: "#3a2a20",
    irisDark: "#8a3410", irisDeep: "#2a1208", cream: "#f6ece5", sand: "#c3aa9a", dim: "#8d7465",
  },
  arc: {
    name: "Arc reactor", main: "#22c3ee", light: "#a5f3fc", hot: "#ecfeff", ink: "#04090c", surface: "#08131a",
    plateA: "#13252e", plateB: "#08131a", deep: "#060f14", socket: "#0c1a21", bolt: "#1d3440",
    irisDark: "#0e6f8a", irisDeep: "#06222b", cream: "#e6f6fa", sand: "#9fc0cb", dim: "#6b8a95",
  },
  toxic: {
    name: "Toxic", main: "#84cc16", light: "#d9f99d", hot: "#f7fee7", ink: "#070a04", surface: "#0f1509",
    plateA: "#1e2a12", plateB: "#0f1509", deep: "#0b1006", socket: "#141c0c", bolt: "#2a3a19",
    irisDark: "#4d7c0f", irisDeep: "#1a2806", cream: "#eef6e2", sand: "#b3c49a", dim: "#7d8d66",
  },
  crimson: {
    name: "Crimson", main: "#f43f5e", light: "#fda4af", hot: "#fff1f2", ink: "#0c0405", surface: "#16090b",
    plateA: "#2e1418", plateB: "#16090b", deep: "#120607", socket: "#1d0c0f", bolt: "#3d1a1f",
    irisDark: "#9f1239", irisDeep: "#2d070f", cream: "#f8e8ea", sand: "#cfa3aa", dim: "#957077",
  },
  void: {
    name: "Void", main: "#8b5cf6", light: "#c4b5fd", hot: "#f5f3ff", ink: "#07050c", surface: "#110c1c",
    plateA: "#1f1830", plateB: "#110c1c", deep: "#0d0916", socket: "#161024", bolt: "#2c2242",
    irisDark: "#5b21b6", irisDeep: "#1c0f38", cream: "#eeeaf8", sand: "#b0a6cc", dim: "#7d7496",
  },
  brass: {
    name: "Brass", main: "#e0a526", light: "#fcd98a", hot: "#fffbeb", ink: "#0a0804", surface: "#15110a",
    plateA: "#2c2414", plateB: "#15110a", deep: "#110d06", socket: "#1b160c", bolt: "#3b311b",
    irisDark: "#92620a", irisDeep: "#2b1d05", cream: "#f7f0de", sand: "#cbb98f", dim: "#93835e",
  },
  chrome: {
    name: "Chrome", main: "#a8b4c4", light: "#e2e8f0", hot: "#ffffff", ink: "#07080a", surface: "#121417",
    plateA: "#262a30", plateB: "#121417", deep: "#0e1012", socket: "#181b1f", bolt: "#343a42",
    irisDark: "#5a6575", irisDeep: "#1c2026", cream: "#f1f3f6", sand: "#b6bdc7", dim: "#7f8793",
  },
  sakura: {
    name: "Sakura", main: "#f472b6", light: "#fbcfe8", hot: "#fdf2f8", ink: "#0b0509", surface: "#170b12",
    plateA: "#2e1624", plateB: "#170b12", deep: "#12080e", socket: "#1e0e18", bolt: "#3d1d30",
    irisDark: "#9d2b6b", irisDeep: "#2d0a1e", cream: "#f8e9f1", sand: "#cfa5bc", dim: "#956f84",
  },
} satisfies Record<string, Palette>;

export const COGS = {
  classic: "Classic teeth",
  honeycomb: "Honeycomb",
  carbon: "Carbon weave",
  circuit: "Circuit traces",
  hazard: "Hazard stripes",
  dots: "Bearing dots",
  topo: "Topographic",
  meander: "Greek key",
};

export const RINGS = {
  plates4: "4 armor plates",
  segments6: "6 segments",
  blades8: "8 blades",
  band: "Vented band",
  crescents: "Twin crescents",
  crown: "Spiked crown",
  shards: "Floating shards",
  gyro: "Gyro rings",
  hex: "Hex frame",
  saw: "Sawblade",
  visor: "Visor arc",
  petals: "Petal plates",
  chain: "Chain links",
  pods: "Satellite pods",
  tiers: "Double tier",
  cross: "Cross arms",
};

export const CLAMPS = {
  bracket: "Bracket",
  talon: "Talon claw",
  piston: "Piston",
  fin: "Arrow fin",
  lug: "Round lug",
  prongs: "Twin prongs",
  rune: "Rune tablet",
  crown: "Crown",
  hammer: "Hammerhead",
  shield: "Kite shield",
  pincer: "Pincer",
  turbine: "Turbine",
  ziggurat: "Ziggurat",
  spear: "Spearhead",
  knuckle: "Knuckles",
  none: "No clamps",
};

/** Her body: the classic armored ring, or a solid shape around the eye. */
export const SHELLS = {
  ring: "Armored ring",
  pyramid: "Pyramid",
  cube: "Cube",
  sphere: "Sphere",
};

export const ARMS = {
  claw: "Claw",
  hydraulic: "Hydraulic",
  slim: "Slim rods",
  blade: "Arm blade",
  cannon: "Arm cannon",
  tentacle: "Tentacle",
  magnet: "Magnet",
  off: "No arms",
};

/** What sweeps around the dial ring between her eye and the plates. */
export const SCANNERS = {
  radar: "Radar sweep",
  twin: "Twin beams",
  quad: "Quad beams",
  comet: "Comet",
  loader: "Loader arc",
  laser: "Laser line",
  pulse: "Pulse rings",
  none: "Off",
};

export const IRISES = {
  fibers: "Fibers",
  rings: "Rings",
  spiral: "Spiral",
  hex: "Hex lens",
  starburst: "Starburst",
  reticle: "Reticle",
  circuit: "Circuit",
  nebula: "Nebula",
  tomoe: "Triple tomoe",
  pinwheel: "Pinwheel",
  petals: "Crest petals",
  ripple: "Ripple rings",
};

export const PUPILS = {
  aperture: "Aperture",
  slit: "Cat slit",
  ring: "Ring core",
  diamond: "Diamond",
  cross: "Cross",
  star: "Star",
  hexagon: "Hexagon",
  heart: "Heart",
  dots: "Triple dot",
  crescent: "Crescent",
  delta: "Delta",
  keyhole: "Keyhole",
  gear: "Gear",
  clover: "Clover",
  bolt: "Bolt",
  sparkle: "Sparkle",
  bar: "Goat bar",
  hourglass: "Hourglass",
};

export type ColorId = keyof typeof PALETTES | "custom";

export type Skin = {
  color: ColorId;
  /** Main color when color is "custom" (#rrggbb). */
  custom: string;
  /** The ring, or a solid shape (the ring, cog, clamp and scanner choices are ring parts). */
  shell: keyof typeof SHELLS;
  /** The spinning cog inside the shell. */
  cog: keyof typeof COGS;
  ring: keyof typeof RINGS;
  clamp: keyof typeof CLAMPS;
  scanner: keyof typeof SCANNERS;
  /** The two arms on her sides (collapsed only). */
  arms: keyof typeof ARMS;
  /** Iris color: "shell" follows the shell color. */
  eye: ColorId | "shell";
  eyeCustom: string;
  /** Two-tone iris: the right half's color, or "off". */
  eye2: keyof typeof PALETTES | "shell" | "off";
  iris: keyof typeof IRISES;
  pupil: keyof typeof PUPILS;
  /** The glowing dot in the pupil: "eye" follows the iris color. */
  core: ColorId | "eye";
  coreCustom: string;
};

export const DEFAULT_SKIN: Skin = { color: "ember", custom: "#4ade80", shell: "ring", cog: "classic", ring: "plates4", clamp: "bracket", scanner: "radar", arms: "claw",
  eye: "shell", eyeCustom: "#38bdf8", eye2: "off", iris: "fibers", pupil: "aperture", core: "eye", coreCustom: "#ffffff" };

/** Drops unknown values (e.g. from an older or newer version) back to the default. */
const hexOr = (v: string | undefined, fallback: string) => (v && /^#[0-9a-f]{6}$/i.test(v) ? v.toLowerCase() : fallback);

export function sanitize(s: Partial<Record<keyof Skin, string>> | undefined): Skin {
  const pick = <K extends keyof Skin>(k: K, table: object): Skin[K] =>
    (s?.[k] && s[k]! in table ? s[k] : DEFAULT_SKIN[k]) as Skin[K];
  return {
    color: s?.color === "custom" ? "custom" : (pick("color", PALETTES) as ColorId),
    custom: hexOr(s?.custom, DEFAULT_SKIN.custom),
    shell: pick("shell", SHELLS),
    cog: pick("cog", COGS),
    ring: pick("ring", RINGS),
    clamp: pick("clamp", CLAMPS),
    scanner: pick("scanner", SCANNERS),
    arms: pick("arms", ARMS),
    eye: s?.eye === "shell" || s?.eye === "custom" ? s.eye : (pick("eye", PALETTES) as Skin["eye"]),
    eyeCustom: hexOr(s?.eyeCustom, DEFAULT_SKIN.eyeCustom),
    eye2: s?.eye2 === "shell" ? "shell" : (pick("eye2", PALETTES) as Skin["eye2"]),
    iris: pick("iris", IRISES),
    pupil: pick("pupil", PUPILS),
    core: s?.core === "custom" ? "custom" : (pick("core", PALETTES) as Skin["core"]),
    coreCustom: hexOr(s?.coreCustom, DEFAULT_SKIN.coreCustom),
  };
}

export const rgb = (hex: string) => {
  const n = parseInt(hex.slice(1), 16);
  return `${(n >> 16) & 255} ${(n >> 8) & 255} ${n & 255}`;
};

/** Recolors the whole chat UI (Tailwind reads these variables). */
export function applyPaletteToPage(p: Palette) {
  const s = document.documentElement.style;
  s.setProperty("--color-ember", p.main);
  s.setProperty("--color-peach", p.light);
  s.setProperty("--color-ink", p.ink);
  s.setProperty("--color-surface", p.surface);
  s.setProperty("--color-cream", p.cream);
  s.setProperty("--color-sand", p.sand);
  s.setProperty("--color-dim", p.dim);
  s.setProperty("--color-line", `rgb(${rgb(p.main)} / 0.2)`);
  s.setProperty("--ember-rgb", rgb(p.main));
  s.setProperty("--peach-rgb", rgb(p.light));
}

/** Builds a full palette around one color: same hue, darker metals, lighter highlights. */
export function customPalette(hex: string): Palette {
  const n = parseInt(hex.slice(1), 16);
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => v / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
  const sat = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  let h = 0;
  if (d !== 0) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  h = (h * 60 + 360) % 360;
  const S = sat * 100;
  const hsl = (s: number, l: number) => {
    const c = (1 - Math.abs((2 * l) / 100 - 1)) * (s / 100), x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l / 100 - c / 2;
    const [rr, gg, bb] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return "#" + [rr, gg, bb].map((v) => Math.round((v + m) * 255).toString(16).padStart(2, "0")).join("");
  };
  const tint = Math.min(S, 45);
  return {
    name: "Custom", main: hex, light: hsl(Math.min(100, S), Math.min(88, l * 100 + 25)), hot: hsl(Math.min(100, S), 96),
    ink: hsl(tint, 3), surface: hsl(tint, 6), plateA: hsl(tint * 0.8, 13), plateB: hsl(tint, 6), deep: hsl(tint, 5),
    socket: hsl(tint, 8), bolt: hsl(tint * 0.7, 18), irisDark: hsl(S, 30), irisDeep: hsl(S, 10),
    cream: hsl(Math.min(S, 40), 94), sand: hsl(Math.min(S, 20), 70), dim: hsl(Math.min(S, 15), 48),
  };
}

export const paletteFor = (s: Skin): Palette => (s.color === "custom" ? customPalette(s.custom) : PALETTES[s.color]);

/** The iris palette, the two-tone half (or null), and the pupil light color. */
export function eyeColors(s: Skin, shell: Palette) {
  const byId = (id: string, custom: string): Palette =>
    id === "shell" ? shell : id === "custom" ? customPalette(custom) : PALETTES[id as keyof typeof PALETTES];
  const iris = byId(s.eye, s.eyeCustom);
  const half = s.eye2 === "off" ? null : byId(s.eye2, "");
  const core = s.core === "eye" ? iris.light : s.core === "custom" ? s.coreCustom : PALETTES[s.core].light;
  return { iris, half, core };
}

export const SkinContext = createContext<Skin>(DEFAULT_SKIN);

export function useSkin() {
  const skin = useContext(SkinContext);
  return { skin, p: paletteFor(skin) };
}
