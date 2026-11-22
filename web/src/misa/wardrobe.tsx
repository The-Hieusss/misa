import { useState } from "react";
import type { ReactNode } from "react";
import { Check, RotateCcw } from "lucide-react";
import { useAnimationFrame, useMotionValue, useReducedMotion } from "framer-motion";
import { ARMS, CLAMPS, DEFAULT_SKIN, IRISES, COGS, PALETTES, PUPILS, RINGS, SCANNERS, eyeColors, paletteFor } from "./skin";
import { IrisPattern, Pupil } from "./eye-parts";
import type { Palette, Skin } from "./skin";
import { ArmArt } from "./mecha-arms";
import { C, CLAMP_ART, CogArt, GYRO, RING_SPECS, Scanner, platePath, spikePaths } from "./shell-parts";

/**
 * Pick her colors, inner cog, ring, clamps, arms and scanner. Every change shows on her right
 * away (the caller renders the draft); Save keeps it, Cancel puts the old look back.
 */
export function Wardrobe({
  draft,
  onChange,
  onSave,
  onCancel,
}: {
  draft: Skin;
  onChange: (s: Skin) => void;
  onSave: () => void;
  onCancel: () => void;
}) {
  const p = paletteFor(draft);
  const eye = eyeColors(draft, p);
  const set = <K extends keyof Skin>(k: K, v: Skin[K]) => onChange({ ...draft, [k]: v });
  const [tab, setTab] = useState<"shell" | "eye">("shell");
  // One shared clock turns every scanner preview, at her idle speed.
  const scan = useMotionValue(30);
  const still = useReducedMotion();
  useAnimationFrame((_, dt) => {
    if (!still) scan.set((scan.get() + (70 * dt) / 1000) % 360);
  });

  return (
    <div className="relative flex min-h-0 flex-1 flex-col">
      <div role="tablist" className="relative flex gap-1 border-b border-ember/20 px-4 pt-3">
        {(["shell", "eye"] as const).map((t) => (
          <button
            key={t}
            type="button"
            role="tab"
            aria-selected={tab === t}
            onClick={() => setTab(t)}
            className={`chamfer-sm -mb-px px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.18em] transition ${
              tab === t ? "bg-ember/25 text-peach" : "text-dim hover:text-sand"
            }`}
          >
            {t}
          </button>
        ))}
      </div>
      <div className="messages flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4 py-4">
        {tab === "eye" ? (
          <>
            <Section title="Iris color">
              <ColorRow
                value={draft.eye}
                lead={[{ id: "shell", label: "Match shell", swatch: p }]}
                custom={draft.eyeCustom}
                onPick={(id) => set("eye", id as Skin["eye"])}
                onCustom={(hex) => onChange({ ...draft, eye: "custom", eyeCustom: hex })}
              />
            </Section>

            <Section title="Two-tone (right half)">
              <ColorRow
                value={draft.eye2}
                lead={[
                  { id: "off", label: "Off" },
                  { id: "shell", label: "Match shell", swatch: p },
                ]}
                onPick={(id) => set("eye2", id as Skin["eye2"])}
              />
            </Section>

            <Section title="Iris pattern">
              <div className="grid grid-cols-4 gap-2">
                {(Object.keys(IRISES) as Skin["iris"][]).map((id) => (
                  <Tile key={id} on={draft.iris === id} onClick={() => set("iris", id)} label={IRISES[id]}>
                    <EyeIcon iris={eye.iris} zoom>
                      {/* stacked so the faint markings read at icon size */}
                      {[0, 1, 2].map((k) => (
                        <IrisPattern key={k} cx={200} cy={200} kind={id} c={{ ink: p.ink, hot: eye.iris.hot, light: eye.iris.light }} origin={{ transformOrigin: "200px 200px" }} />
                      ))}
                      <circle cx={200} cy={200} r={14} fill={p.ink} />
                    </EyeIcon>
                  </Tile>
                ))}
              </div>
            </Section>

            <Section title="Pupil">
              <div className="grid grid-cols-5 gap-2">
                {(Object.keys(PUPILS) as Skin["pupil"][]).map((id) => (
                  <Tile key={id} on={draft.pupil === id} onClick={() => set("pupil", id)} label={PUPILS[id]}>
                    <EyeIcon iris={eye.iris}>
                      <Pupil cx={200} cy={200} kind={id} c={{ ink: p.ink, main: eye.iris.main, core: eye.core }} />
                    </EyeIcon>
                  </Tile>
                ))}
              </div>
            </Section>

            <Section title="Center light">
              <ColorRow
                value={draft.core}
                lead={[{ id: "eye", label: "Match iris", dot: eye.iris.light }]}
                custom={draft.coreCustom}
                onPick={(id) => set("core", id as Skin["core"])}
                onCustom={(hex) => onChange({ ...draft, core: "custom", coreCustom: hex })}
                dots
              />
            </Section>
          </>
        ) : (
          <>
        <Section title="Color">
          <div className="grid grid-cols-5 gap-2">
            {(Object.keys(PALETTES) as (keyof typeof PALETTES)[]).map((id) => {
              const c = PALETTES[id];
              return (
                <Tile key={id} on={draft.color === id} onClick={() => set("color", id)} label={c.name}>
                  <span className="flex h-7 w-7 items-center justify-center rounded-full" style={{ background: c.plateB, boxShadow: `inset 0 0 0 2px ${c.main}` }}>
                    <span className="h-3 w-3 rounded-full" style={{ background: c.light }} />
                  </span>
                </Tile>
              );
            })}
            <label
              className={`chamfer-sm relative flex cursor-pointer flex-col items-center gap-1 px-1 py-2 transition ${
                draft.color === "custom" ? "bg-ember/25 ring-1 ring-inset ring-peach" : "bg-ember/[0.07] hover:bg-ember/15"
              }`}
              title="Pick any color"
            >
              <span className="relative flex h-7 w-7 items-center justify-center rounded-full" style={{ background: `conic-gradient(#f43f5e, #e0a526, #84cc16, #22c3ee, #8b5cf6, #f472b6, #f43f5e)` }}>
                <span className="h-4 w-4 rounded-full ring-2 ring-ink" style={{ background: draft.custom }} />
              </span>
              <span className="font-mono text-[9px] uppercase tracking-[0.08em] text-sand">Custom</span>
              <input
                type="color"
                value={draft.custom}
                onChange={(e) => onChange({ ...draft, color: "custom", custom: e.target.value })}
                onClick={() => draft.color !== "custom" && set("color", "custom")}
                className="absolute inset-0 cursor-pointer opacity-0"
                aria-label="Custom color"
              />
            </label>
          </div>
        </Section>

        <Section title="Ring">
          <div className="grid grid-cols-4 gap-2">
            {(Object.keys(RINGS) as Skin["ring"][]).map((id) => (
              <Tile key={id} on={draft.ring === id} onClick={() => set("ring", id)} label={RINGS[id]}>
                <RingIcon ring={id} color={p.main} fill={p.plateA} />
              </Tile>
            ))}
          </div>
        </Section>

        <Section title="Inner cog">
          <div className="grid grid-cols-4 gap-2">
            {(Object.keys(COGS) as Skin["cog"][]).map((id) => (
              <Tile key={id} on={draft.cog === id} onClick={() => set("cog", id)} label={COGS[id]}>
                {/* a zoomed slice of the top of the cog */}
                <svg viewBox={`${C - 24} 39.5 48 25.7`} className="h-[30px] w-[56px]" aria-hidden>
                  <CogArt kind={id} p={p} />
                </svg>
              </Tile>
            ))}
          </div>
        </Section>

        <Section title="Clamps">
          <div className="grid grid-cols-4 gap-2">
            {(Object.keys(CLAMPS) as Skin["clamp"][]).map((id) => (
              <Tile key={id} on={draft.clamp === id} onClick={() => set("clamp", id)} label={CLAMPS[id]}>
                <svg viewBox={`${C - 18} -3 36 48`} className="h-[34px] w-[26px]" aria-hidden>
                  {id === "none" ? (
                    <path d={`M${C - 9} 4 H${C + 9} V40 H${C - 9} Z`} fill="none" stroke={p.main} strokeOpacity="0.5" strokeWidth="1.4" strokeDasharray="3 3" />
                  ) : (
                    <>
                      <path d={CLAMP_ART[id].outline} fill={p.socket} stroke={p.main} strokeWidth="1.8" strokeLinejoin="round" />
                      {CLAMP_ART[id].detail({ p, compact: true, charged: true, i: 0 })}
                    </>
                  )}
                </svg>
              </Tile>
            ))}
          </div>
        </Section>

        <Section title="Arms">
          <div className="grid grid-cols-4 gap-2">
            {(Object.keys(ARMS) as Skin["arms"][]).map((id) => (
              <Tile key={id} on={draft.arms === id} onClick={() => set("arms", id)} label={ARMS[id]}>
                {id === "off" ? (
                  <svg viewBox="0 0 60 34" className="h-[30px] w-[52px]" aria-hidden>
                    <circle cx="30" cy="17" r="11" fill={p.socket} stroke={p.main} strokeWidth="1.6" />
                    <circle cx="30" cy="17" r="3.5" fill={p.light} />
                  </svg>
                ) : (
                  // the arm raised in a wave, shoulder at bottom left
                  <svg viewBox="-8 -40 96 52" className="h-[30px] w-[56px]" aria-hidden>
                    <ArmArt p={p} kind={id} pose={{ x: 0, y: 4, th1: -10, th2: -62, grip: 30 }} />
                  </svg>
                )}
              </Tile>
            ))}
          </div>
        </Section>

        <Section title="Scanner">
          <div className="grid grid-cols-4 gap-2">
            {(Object.keys(SCANNERS) as Skin["scanner"][]).map((id) => (
              <Tile key={id} on={draft.scanner === id} onClick={() => set("scanner", id)} label={SCANNERS[id]}>
                {/* the dial band, in her light color so it reads at tile size */}
                <svg viewBox={`${C - 149} ${C - 149} 298 298`} className="h-[34px] w-[34px]" aria-hidden>
                  <circle cx={C} cy={C} r="146" fill={p.ink} stroke={p.main} strokeOpacity="0.4" strokeWidth="5" />
                  <Scanner kind={id} p={{ ...p, main: p.light }} angle={scan} />
                  <circle cx={C} cy={C} r="104" fill={p.plateB} stroke={p.main} strokeOpacity="0.6" strokeWidth="5" />
                </svg>
              </Tile>
            ))}
          </div>
        </Section>
          </>
        )}
      </div>

      <div className="relative flex items-center gap-2 border-t border-ember/30 bg-surface/80 p-3">
        <button
          type="button"
          onClick={() => onChange({ ...DEFAULT_SKIN, custom: draft.custom })}
          title="Back to her original look"
          className="chamfer-sm flex h-10 items-center gap-1.5 bg-ember/10 px-3 font-mono text-[10px] uppercase tracking-[0.12em] text-peach transition hover:bg-ember/20"
        >
          <RotateCcw className="h-3.5 w-3.5" />
          Original
        </button>
        <span className="flex-1" />
        <button
          type="button"
          onClick={onCancel}
          className="chamfer-sm h-10 bg-ember/10 px-4 font-mono text-[11px] uppercase tracking-[0.12em] text-peach transition hover:bg-ember/20"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onSave}
          className="chamfer-sm flex h-10 items-center gap-1.5 bg-gold-gradient px-4 font-mono text-[11px] font-semibold uppercase tracking-[0.12em] text-ink transition hover:brightness-110"
        >
          <Check className="h-4 w-4" />
          Save
        </button>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h3 className="mb-2 font-mono text-[10px] uppercase tracking-[0.2em] text-ember">{title}</h3>
      {children}
    </section>
  );
}

function Tile({ on, onClick, label, children }: { on: boolean; onClick: () => void; label: string; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={on}
      title={label}
      className={`chamfer-sm flex min-w-0 flex-col items-center gap-1 px-1 py-2 transition ${
        on ? "bg-ember/25 ring-1 ring-inset ring-peach" : "bg-ember/[0.07] hover:bg-ember/15"
      }`}
    >
      <span className="flex h-[34px] items-center justify-center">{children}</span>
      <span className="w-full truncate text-center font-mono text-[9px] uppercase tracking-[0.06em] text-sand">{label}</span>
    </button>
  );
}

/** A flat drawing of a ring design, built from the same geometry as the real shell. */
function RingIcon({ ring, color, fill }: { ring: Skin["ring"]; color: string; fill: string }) {
  const spec = RING_SPECS[ring];
  return (
    <svg viewBox="0 0 400 400" className="h-[34px] w-[34px]" aria-hidden>
      <circle cx={C} cy={C} r="104" fill="none" stroke={color} strokeOpacity="0.6" strokeWidth="14" />
      {spec.gyro
        ? [-GYRO.tilt, GYRO.tilt].map((t) => (
            <ellipse key={t} cx={C} cy={C} rx={GYRO.rx} ry={GYRO.ry} transform={`rotate(${t} ${C} ${C})`} fill="none" stroke={color} strokeWidth="18" />
          ))
        : null}
      {spec.track ? <circle cx={C} cy={C} r={spec.track.r} fill="none" stroke={color} strokeWidth={Math.max(14, spec.track.w + 8)} /> : null}
      {spec.segs.map((s) => (
        <g key={`${s.mid}-${s.index}`} fill={fill} stroke={color} strokeWidth="12" strokeLinejoin="round" fillRule="evenodd">
          {spec.spikes ? spikePaths(s).map((d) => <path key={d} d={d} />) : null}
          <path d={spec.shape ? spec.shape(s) : platePath(s.r1 - 6, s.r2 + 4, s.a0, s.a1, spec.chamfer)} />
        </g>
      ))}
    </svg>
  );
}

type Lead = { id: string; label: string; swatch?: Palette; dot?: string };

/** A row of color choices: optional leading tiles, the eight theme colors, then (optionally) a custom picker. */
function ColorRow({
  value,
  lead,
  custom,
  onPick,
  onCustom,
  dots = false,
}: {
  value: string;
  lead: Lead[];
  custom?: string;
  onPick: (id: string) => void;
  onCustom?: (hex: string) => void;
  /** Show each color as a single glowing dot (for the pupil light). */
  dots?: boolean;
}) {
  const swatch = (c: Palette) =>
    dots ? (
      <span className="h-3.5 w-3.5 rounded-full" style={{ background: c.light, boxShadow: `0 0 8px ${c.light}` }} />
    ) : (
      <span className="flex h-7 w-7 items-center justify-center rounded-full" style={{ background: c.plateB, boxShadow: `inset 0 0 0 2px ${c.main}` }}>
        <span className="h-3 w-3 rounded-full" style={{ background: c.light }} />
      </span>
    );
  return (
    <div className="grid grid-cols-5 gap-2">
      {lead.map((l) => (
        <Tile key={l.id} on={value === l.id} onClick={() => onPick(l.id)} label={l.label}>
          {l.swatch ? (
            <span className="relative">
              {swatch(l.swatch)}
              <span className="absolute -right-1 -top-1 font-mono text-[9px] text-peach">=</span>
            </span>
          ) : l.dot ? (
            <span className="h-3.5 w-3.5 rounded-full ring-1 ring-peach/60" style={{ background: l.dot }} />
          ) : (
            <span className="h-6 w-6 rounded-full border border-dashed border-dim" />
          )}
        </Tile>
      ))}
      {(Object.keys(PALETTES) as (keyof typeof PALETTES)[]).map((id) => (
        <Tile key={id} on={value === id} onClick={() => onPick(id)} label={PALETTES[id].name}>
          {swatch(PALETTES[id])}
        </Tile>
      ))}
      {onCustom && custom ? (
        <label
          className={`chamfer-sm relative flex cursor-pointer flex-col items-center gap-1 px-1 py-2 transition ${
            value === "custom" ? "bg-ember/25 ring-1 ring-inset ring-peach" : "bg-ember/[0.07] hover:bg-ember/15"
          }`}
          title="Pick any color"
        >
          <span
            className="relative flex h-[34px] w-7 items-center justify-center"
          >
            <span className="flex h-7 w-7 items-center justify-center rounded-full" style={{ background: "conic-gradient(#f43f5e, #e0a526, #84cc16, #22c3ee, #8b5cf6, #f472b6, #f43f5e)" }}>
              <span className="h-4 w-4 rounded-full ring-2 ring-ink" style={{ background: custom }} />
            </span>
          </span>
          <span className="font-mono text-[9px] uppercase tracking-[0.06em] text-sand">Custom</span>
          <input
            type="color"
            value={custom}
            onChange={(e) => onCustom(e.target.value)}
            onClick={() => value !== "custom" && onCustom(custom)}
            className="absolute inset-0 cursor-pointer opacity-0"
            aria-label="Custom color"
          />
        </label>
      ) : null}
    </div>
  );
}

/** A small iris disc to preview an iris pattern or pupil on. */
function EyeIcon({ iris, zoom = false, children }: { iris: Palette; zoom?: boolean; children: ReactNode }) {
  return (
    <svg viewBox={zoom ? "148 148 104 104" : "140 140 120 120"} className="h-[34px] w-[34px]" aria-hidden>
      <circle cx={200} cy={200} r={58} fill={iris.irisDeep} />
      <circle cx={200} cy={200} r={50} fill={iris.main} fillOpacity="0.85" />
      <circle cx={200} cy={200} r={30} fill={iris.light} fillOpacity="0.5" />
      {children}
    </svg>
  );
}
