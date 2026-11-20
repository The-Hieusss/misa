import { cn } from "@/lib/utils";

/** Orange bracket corners that make any `relative` box look like a HUD frame (from the portfolio). */
export function HudCorners({ className, size = "h-3 w-3" }: { className?: string; size?: string }) {
  const base = cn("pointer-events-none absolute border-ember", size, className);
  return (
    <>
      <span aria-hidden className={cn(base, "left-0 top-0 border-l-2 border-t-2")} />
      <span aria-hidden className={cn(base, "right-0 top-0 border-r-2 border-t-2")} />
      <span aria-hidden className={cn(base, "bottom-0 left-0 border-b-2 border-l-2")} />
      <span aria-hidden className={cn(base, "bottom-0 right-0 border-b-2 border-r-2")} />
    </>
  );
}
