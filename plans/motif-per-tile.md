# Plan: motif per tile (Escher-style)

## Goal

Instead of filling each tile with a solid color, fill it with a user-supplied vector motif that has been geometrically warped to fit the tile. This is the essence of Escher's *Circle Limit* series: one fish/bat/angel per fundamental polygon, repeated into every reflected copy.

The math is already in `hyperbolic.rkt`. Rendering already reflects tile *vertices* through side geodesics — we just extend that to reflecting arbitrary motif points.

## Approach

Each non-central tile was produced by a sequence of reflections from the fundamental polygon. If we record that sequence during BFS (currently we only record the first-reflection sector), we can replay it on any point of the motif to warp it into the destination tile.

- Motif input: an SVG path (or a small set of paths) specified in the *local coordinate system of the fundamental polygon* — i.e. the same coordinate space `polygon-vertices` returns.
- For each generated tile, keep the list of side-indices used to reach it from the center.
- To render the motif into a tile, apply that list of `reflect-through-geodesic` calls to every path control point.
- Straight lines between control points become geodesic arcs after reflection, so use enough subdivision or explicit arc primitives.

Bitmap motifs (raster images) are out of scope for a first pass — the correct treatment requires resampling under a Möbius mapping and is a much bigger project.

## CLI / API surface

```
--motif FILE.svg     Path to a small SVG containing motif paths in disk coords
--motif-inline STR   Inline SVG path string, e.g. "M 0 0 L 0.1 0 A ..."
--motif-color HEX    Override motif stroke/fill (default: current palette)
```

Composes with existing `--palette`, `--depth`, etc. Solid-tile mode remains the default when `--motif` is absent.

## Milestones

1. Extend BFS in `tessellate` to record the full reflection sequence per tile (not just the first sector).
2. Add a `warp-point` helper: given a sequence of side indices and a point, apply the reflections.
3. Parse a minimal SVG path grammar (M, L, C, Z suffice for motifs).
4. Render warped motif inside a solid-fill background for readability.
5. Ship 2–3 example motifs in `examples/motifs/`.

## Open questions / risks

- Motif orientation flips after an odd number of reflections; that's actually what Escher wanted (mirrored fish). Confirm before "fixing" it.
- Subdividing straight motif segments into geodesic arcs looks correct but is expensive at high depth. Consider an option `--motif-detail N` to control subdivision.
- Escher's motifs interlock across tile edges. Achieving that requires designing motifs on the fundamental polygon such that boundary crossings match — a user problem, not a code problem, but the CLI should document this.

## Scope guard

- Vector motifs only. No bitmap warping.
- No motif editor. Users bring their own SVG.
- No interlock helpers. Give users control points; they design the motif.
