import type { Skin } from "./skin";

/* Swappable iris patterns and pupil shapes, drawn around (cx, cy). The iris disc is r = 56. */

const at = (cx: number, cy: number, r: number, deg: number) => {
  const a = (deg * Math.PI) / 180;
  return [cx + r * Math.cos(a), cy + r * Math.sin(a)] as const;
};
const poly = (pts: (readonly [number, number])[]) => pts.map(([x, y]) => `${x},${y}`).join(" ");
const range = (n: number, step = 360 / n, from = 0) => Array.from({ length: n }, (_, i) => from + i * step);

// Fixed "random" star field for the nebula, so it doesn't jump between renders.
const STARS = range(22).map((i) => ({ r: 24 + ((i * 37) % 29), a: (i * 137.5) % 360, s: 0.6 + ((i * 7) % 5) * 0.25 }));

/** A tomoe (the traditional comma crest) sitting on a circle of radius r at angle a, tail trailing back. */
function tomoe(cx: number, cy: number, r: number, a: number, size: number) {
  const P = (rr: number, d: number) => at(cx, cy, rr, d).join(" ");
  const tail = (size / r) * 400; // degrees the tail trails, scaled to the head
  return `M${P(r + size, a)} Q${P(r + size * 0.9, a - tail * 0.55)} ${P(r, a - tail)} Q${P(r - size * 0.45, a - tail * 0.45)} ${P(r - size, a)} Z`;
}

type IrisColors = { ink: string; hot: string; light: string };

/**
 * Markings on the iris. `spin` patterns turn slowly (CSS classes from index.css); the caller
 * passes a transform origin at the eye's center.
 */
export function IrisPattern({ cx, cy, kind, c, origin }: { cx: number; cy: number; kind: Skin["iris"]; c: IrisColors; origin: object }) {
  const ink = { stroke: c.ink, fill: "none" };
  switch (kind) {
    case "fibers":
      return (
        <>
          <g className="animate-spin-slow" style={origin}>
            {range(16).map((a) => {
              const [x1, y1] = at(cx, cy, 26, a);
              const [x2, y2] = at(cx, cy, 46, a);
              return <line key={a} x1={x1} y1={y1} x2={x2} y2={y2} {...ink} strokeOpacity="0.45" strokeWidth="1.5" />;
            })}
          </g>
          <g className="animate-spin-rev" style={origin}>
            <circle cx={cx} cy={cy} r={36} fill="none" stroke={c.hot} strokeOpacity="0.35" strokeWidth="1" strokeDasharray="14 6 2 6" />
          </g>
        </>
      );
    case "rings":
      return (
        <g className="animate-spin-slow" style={origin}>
          <circle cx={cx} cy={cy} r={30} {...ink} strokeOpacity="0.5" strokeWidth="1.5" />
          <circle cx={cx} cy={cy} r={38} {...ink} strokeOpacity="0.45" strokeWidth="2.5" strokeDasharray="4 3" />
          <circle cx={cx} cy={cy} r={46} {...ink} strokeOpacity="0.4" strokeWidth="1.2" />
          <circle cx={cx} cy={cy} r={42} fill="none" stroke={c.hot} strokeOpacity="0.3" strokeWidth="0.8" strokeDasharray="20 8" />
        </g>
      );
    case "spiral":
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(8).map((a0) => {
            const pts = range(12, 1 / 11, 0).map((t) => at(cx, cy, 22 + t * 30, a0 + t * 100));
            return <polyline key={a0} points={poly(pts)} {...ink} strokeOpacity="0.5" strokeWidth="1.6" strokeLinecap="round" />;
          })}
          <circle cx={cx} cy={cy} r={34} fill="none" stroke={c.hot} strokeOpacity="0.25" strokeWidth="0.8" />
        </g>
      );
    case "hex": {
      const hx = (x: number, y: number, r: number) => poly(range(6, 60, 30).map((a) => at(x, y, r, a)));
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(6, 60, 0).map((a) => {
            const [x, y] = at(cx, cy, 34, a);
            return <polygon key={`a${a}`} points={hx(x, y, 9)} {...ink} strokeOpacity="0.5" strokeWidth="1.3" />;
          })}
          {range(12, 30, 15).map((a) => {
            const [x, y] = at(cx, cy, 48, a);
            return <polygon key={`b${a}`} points={hx(x, y, 6)} {...ink} strokeOpacity="0.4" strokeWidth="1" />;
          })}
          {range(6, 60, 30).map((a) => {
            const [x, y] = at(cx, cy, 34, a);
            return <circle key={`c${a}`} cx={x} cy={y} r="1.2" fill={c.hot} fillOpacity="0.5" />;
          })}
        </g>
      );
    }
    case "starburst":
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(24).map((a, i) => {
            const long = i % 2 === 0;
            return (
              <polygon
                key={a}
                points={poly([at(cx, cy, 22, a - 3.5), at(cx, cy, long ? 53 : 42, a), at(cx, cy, 22, a + 3.5)])}
                fill={c.ink}
                fillOpacity={long ? 0.4 : 0.28}
              />
            );
          })}
          <circle cx={cx} cy={cy} r={30} fill="none" stroke={c.hot} strokeOpacity="0.3" strokeWidth="0.8" />
        </g>
      );
    case "reticle":
      return (
        <g>
          <circle cx={cx} cy={cy} r={40} {...ink} strokeOpacity="0.55" strokeWidth="1.5" />
          {range(4, 90, 0).map((a) => {
            const [x1, y1] = at(cx, cy, 28, a);
            const [x2, y2] = at(cx, cy, 54, a);
            return <line key={a} x1={x1} y1={y1} x2={x2} y2={y2} {...ink} strokeOpacity="0.6" strokeWidth="2.2" />;
          })}
          <g className="animate-spin-rev" style={origin}>
            {range(12, 30, 15).map((a) => {
              const [x1, y1] = at(cx, cy, 45, a);
              const [x2, y2] = at(cx, cy, 51, a);
              return <line key={a} x1={x1} y1={y1} x2={x2} y2={y2} stroke={c.hot} strokeOpacity="0.4" strokeWidth="1" />;
            })}
          </g>
          {range(4, 90, 45).map((a) => {
            const [x0, y0] = at(cx, cy, 33, a - 12);
            const [x1, y1] = at(cx, cy, 33, a + 12);
            return <path key={a} d={`M${x0} ${y0} A33 33 0 0 1 ${x1} ${y1}`} {...ink} strokeOpacity="0.55" strokeWidth="2" />;
          })}
        </g>
      );
    case "circuit":
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(8).map((a, i) => {
            const turn = i % 2 ? 18 : -18;
            const p0 = at(cx, cy, 23, a);
            const p1 = at(cx, cy, 34, a);
            const p2 = at(cx, cy, 34, a + turn);
            const p3 = at(cx, cy, 48, a + turn);
            return (
              <g key={a}>
                <path
                  d={`M${p0[0]} ${p0[1]} L${p1[0]} ${p1[1]} A34 34 0 0 ${turn > 0 ? 1 : 0} ${p2[0]} ${p2[1]} L${p3[0]} ${p3[1]}`}
                  {...ink}
                  strokeOpacity="0.55"
                  strokeWidth="1.4"
                />
                <circle cx={p3[0]} cy={p3[1]} r="2.2" fill={c.ink} fillOpacity="0.6" stroke={c.hot} strokeOpacity="0.5" strokeWidth="0.7" />
              </g>
            );
          })}
        </g>
      );
    case "nebula":
      return (
        <g className="animate-spin-slow" style={origin}>
          {[0, 180].map((rot) => (
            <path
              key={rot}
              d={`M${cx - 44} ${cy + 6} C${cx - 30} ${cy - 30} ${cx + 10} ${cy - 40} ${cx + 30} ${cy - 18}`}
              transform={`rotate(${rot} ${cx} ${cy})`}
              fill="none"
              stroke={c.light}
              strokeOpacity="0.35"
              strokeWidth="5"
              strokeLinecap="round"
              style={{ filter: "blur(2px)" }}
            />
          ))}
          {STARS.map((st, i) => {
            const [x, y] = at(cx, cy, st.r, st.a);
            return <circle key={i} cx={x} cy={y} r={st.s} fill={c.hot} fillOpacity="0.8" />;
          })}
        </g>
      );
    case "tomoe":
      return (
        <g className="animate-spin-slow" style={origin}>
          <circle cx={cx} cy={cy} r={36} {...ink} strokeOpacity="0.55" strokeWidth="1.4" />
          {range(3, 120, -90).map((a) => {
            const [x, y] = at(cx, cy, 36, a);
            return (
              <g key={a} fill={c.ink} fillOpacity="0.85">
                <path d={tomoe(cx, cy, 36, a, 6.5)} />
                <circle cx={x} cy={y} r={6.5} />
              </g>
            );
          })}
          <circle cx={cx} cy={cy} r={50} fill="none" stroke={c.hot} strokeOpacity="0.25" strokeWidth="0.8" />
        </g>
      );
    case "pinwheel":
      // Five slim blades sweeping out from the pupil.
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(5).map((a) => (
            <path
              key={a}
              d={`M${at(cx, cy, 22, a).join(" ")} Q${at(cx, cy, 40, a + 8).join(" ")} ${at(cx, cy, 53, a + 46).join(" ")} Q${at(cx, cy, 37, a + 22).join(" ")} ${at(cx, cy, 23, a + 13).join(" ")} Z`}
              fill={c.ink}
              fillOpacity="0.7"
            />
          ))}
          <circle cx={cx} cy={cy} r={22.5} {...ink} strokeOpacity="0.6" strokeWidth="1.2" />
          <circle cx={cx} cy={cy} r={47} fill="none" stroke={c.hot} strokeOpacity="0.22" strokeWidth="0.8" strokeDasharray="3 5" />
        </g>
      );
    case "petals":
      // Eight pointed petals around the pupil, with a bead between each tip.
      return (
        <g className="animate-spin-slow" style={origin}>
          {range(8, 45, -90).map((a) => (
            <path
              key={a}
              d={`M${at(cx, cy, 24, a).join(" ")} Q${at(cx, cy, 37, a - 12).join(" ")} ${at(cx, cy, 51, a).join(" ")} Q${at(cx, cy, 37, a + 12).join(" ")} ${at(cx, cy, 24, a).join(" ")} Z`}
              fill={c.ink}
              fillOpacity="0.5"
              stroke={c.ink}
              strokeOpacity="0.8"
              strokeWidth="1"
            />
          ))}
          {range(8, 45, -67.5).map((a) => {
            const [x, y] = at(cx, cy, 45, a);
            return <circle key={a} cx={x} cy={y} r="1.6" fill={c.hot} fillOpacity="0.6" />;
          })}
          <circle cx={cx} cy={cy} r={24} {...ink} strokeOpacity="0.55" strokeWidth="1.2" />
        </g>
      );
    case "ripple": {
      // Wavy rings spreading out, with tomoe beads riding the middle one the other way.
      const wave = (base: number, phase: number) =>
        poly(range(73, 5).map((d) => at(cx, cy, base + 1.5 * Math.sin(((d * 6 + phase) * Math.PI) / 180), d)));
      return (
        <>
          <g className="animate-spin-slow" style={origin}>
            {[28, 37.5, 47].map((b, i) => (
              <polyline key={b} points={wave(b, i * 30)} {...ink} strokeOpacity={0.55 - i * 0.08} strokeWidth="1.4" />
            ))}
          </g>
          <g className="animate-spin-rev" style={origin}>
            {range(4, 90, 45).map((a) => {
              const [x, y] = at(cx, cy, 42, a);
              return (
                <g key={a} fill={c.ink} fillOpacity="0.85">
                  <path d={tomoe(cx, cy, 42, a, 3.6)} />
                  <circle cx={x} cy={y} r={3.6} />
                </g>
              );
            })}
          </g>
        </>
      );
    }
  }
}

type PupilColors = { ink: string; main: string; core: string };

/** The pupil, centered on (cx, cy). The caller scales and rotates it for dilation. */
export function Pupil({ cx, cy, kind, c }: { cx: number; cy: number; kind: Skin["pupil"]; c: PupilColors }) {
  const body = { fill: c.ink, stroke: c.main, strokeWidth: 2, strokeLinejoin: "round" as const };
  const core = <circle cx={cx} cy={cy} r={3.2} fill={c.core} className="animate-pulse" />;
  switch (kind) {
    case "aperture":
      return (
        <>
          {range(6).map((a) => {
            const rad = (a * Math.PI) / 180;
            return (
              <line
                key={a}
                x1={cx + 19 * Math.cos(rad)}
                y1={cy + 19 * Math.sin(rad)}
                x2={cx + 27 * Math.cos(rad + 0.5)}
                y2={cy + 27 * Math.sin(rad + 0.5)}
                stroke={c.ink}
                strokeOpacity="0.75"
                strokeWidth="2"
              />
            );
          })}
          <circle cx={cx} cy={cy} r={19} {...body} />
          <circle cx={cx} cy={cy} r={9} fill="none" stroke={c.main} strokeOpacity="0.55" strokeWidth="1" />
          {core}
        </>
      );
    case "slit":
      return (
        <>
          <path d={`M${cx} ${cy - 24} C${cx + 9} ${cy - 10} ${cx + 9} ${cy + 10} ${cx} ${cy + 24} C${cx - 9} ${cy + 10} ${cx - 9} ${cy - 10} ${cx} ${cy - 24} Z`} {...body} />
          {core}
        </>
      );
    case "ring":
      return (
        <>
          <circle cx={cx} cy={cy} r={17} fill="none" stroke={c.ink} strokeWidth="8" />
          <circle cx={cx} cy={cy} r={21.5} fill="none" stroke={c.main} strokeWidth="1.6" />
          <circle cx={cx} cy={cy} r={12.5} fill="none" stroke={c.main} strokeOpacity="0.7" strokeWidth="1" />
          {core}
        </>
      );
    case "diamond":
      return (
        <>
          <polygon points={poly([[cx, cy - 23], [cx + 17, cy], [cx, cy + 23], [cx - 17, cy]])} {...body} />
          {core}
        </>
      );
    case "cross":
      return (
        <>
          <path
            d={`M${cx - 6} ${cy - 21} H${cx + 6} V${cy - 6} H${cx + 21} V${cy + 6} H${cx + 6} V${cy + 21} H${cx - 6} V${cy + 6} H${cx - 21} V${cy - 6} H${cx - 6} Z`}
            {...body}
          />
          {core}
        </>
      );
    case "star":
      return (
        <>
          <polygon points={poly(range(10, 36, -90).map((a, i) => at(cx, cy, i % 2 ? 9.5 : 23, a)))} {...body} />
          {core}
        </>
      );
    case "hexagon":
      return (
        <>
          <polygon points={poly(range(6, 60, -90).map((a) => at(cx, cy, 21, a)))} {...body} />
          {core}
        </>
      );
    case "heart":
      return (
        <>
          <path
            d={`M${cx} ${cy + 19} C${cx - 4} ${cy + 15} ${cx - 22} ${cy + 4} ${cx - 22} ${cy - 7} C${cx - 22} ${cy - 16} ${cx - 10} ${cy - 21} ${cx} ${cy - 10} C${cx + 10} ${cy - 21} ${cx + 22} ${cy - 16} ${cx + 22} ${cy - 7} C${cx + 22} ${cy + 4} ${cx + 4} ${cy + 15} ${cx} ${cy + 19} Z`}
            {...body}
          />
          {core}
        </>
      );
    case "dots":
      return (
        <>
          {[-90, 30, 150].map((a) => {
            const [x, y] = at(cx, cy, 11, a);
            return <circle key={a} cx={x} cy={y} r={8} {...body} />;
          })}
          {core}
        </>
      );
  }
}
