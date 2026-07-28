# Plan: Euclidean tiler (companion program)

## Goal

A sibling program that renders the Euclidean analogs of harmony's output: the three regular Euclidean tessellations `{3,6}` (triangles), `{4,4}` (squares), and `{6,3}` (hexagons), and — as a natural extension — some or all of the 17 wallpaper groups.

Same aesthetic (palettes, spokes, sharp SVG/PNG output), completely different math (translations and glide reflections in the plane, no hyperbolic geometry).

## Approach

Two levels of ambition. Start small; grow if it stays fun.

### Level 1: regular Euclidean tilings

`{3,6}`, `{4,4}`, `{6,3}` — each has a fundamental polygon and two translation vectors. Generate a grid of copies covering the viewport. Trivial geometry, mostly a rendering exercise.

### Level 2: wallpaper groups

The 17 wallpaper groups. Each has:
- A fundamental domain (usually a triangle or a quadrilateral).
- A finite set of generators (translations, rotations, reflections, glide reflections).
- A Conway/orbifold notation.

Same BFS approach as harmony works: from the fundamental domain, apply generators to reach neighbors, dedupe by centroid position (rounded), stop at some depth. Rendering is straight lines everywhere — no geodesic arcs.

Start with maybe 4-6 aesthetically distinct groups (p1, p2, p4mm, p6mm, cm, p3m1).

## CLI / API surface

New binary `euclidean.rkt` (or `wallpaper.rkt` if Level 2 is the focus):

```
racket euclidean.rkt [options]

  --tiling triangle|square|hex        Regular Euclidean tiling
  --group NAME                        Wallpaper group (Level 2)
  -d W H                              Image dimensions
  -f FILE                             Output SVG/PNG
  --palette NAME                      Reuse harmony's palettes
  --extent N                          How far from origin to tile
```

If the shared code grows, factor palette definitions into `palettes.rkt` used by both binaries.

## Milestones

1. Level 1: hex tiling first — visually the most striking. Copy-paste palette code from harmony.
2. Level 1: add triangle and square.
3. Level 2 (optional): pick 4 wallpaper groups, encode their generators, share BFS.
4. Extract `palettes.rkt` if duplication becomes annoying.

## Open questions / risks

- Wallpaper groups are a *lot* of machinery for a small tool. The line between "focused companion" and "sprawling group theory library" is easy to cross. Cap the group count.
- Rendering hexagons/squares at the edges of the viewport needs clipping. SVG handles this with `viewBox`; PNG needs manual clipping via `dc`.
- Palettes designed for hyperbolic depth-based tinting need rethinking here — there's no natural "depth" in a translation lattice. Either color by (row + col) mod K, or introduce a new palette style.

## Scope guard

- Separate binary from harmony. Do not merge them.
- Level 1 first. Level 2 only if Level 1 was fun and the palette story translates cleanly.
- No spherical tiler yet (that would be a third plan).
