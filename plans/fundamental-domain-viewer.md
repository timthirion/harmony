# Plan: fundamental-domain viewer

## Goal

An educational rendering mode that makes the group-theoretic structure of a `{p,q}` tessellation visible. Instead of just "look at the pretty tiling", show:

- **The fundamental polygon** highlighted, everything else dimmed.
- **Generators**: which side reflections produce which neighboring tiles.
- **Reflection tree**: how each tile was derived from the center by a sequence of reflections.

Turns harmony from a picture-maker into a teaching tool without changing the geometry code.

## Approach

The BFS in `tessellate` already tracks depth and the first-reflection sector. Extend it to track the full sequence of side-indices used to reach each tile. Then add rendering modes that use this metadata:

### Mode 1: highlight fundamental polygon
- Render the depth-0 tile at full opacity in a vivid accent color.
- Render all other tiles at reduced opacity (say 30%).
- Draw arrows or numbered labels on the fundamental polygon's sides showing which generator each side corresponds to.

### Mode 2: color by generator sequence length
- Instead of coloring by depth (already implicit), color by *word length* in the free product of reflections. For `{p,q}`, this is usually the same as depth for shallow tiles but diverges as reflections start canceling.

### Mode 3: label a specific orbit
- User picks a target tile (by depth, sector, or click if we ever add interactivity). Highlight the tiles along the reflection path from center to target.

## CLI / API surface

```
--highlight fundamental                Dim everything except tile 0
--label-generators                      Draw g_1..g_p labels on fundamental sides
--path-to DEPTH SECTOR                  Highlight the reflection path to that tile
--color-by depth|word-length            Coloring scheme (default: depth)
```

Only one highlight mode active at a time; `--color-by` is orthogonal.

## Milestones

1. Extend BFS to record `(list-of-side-indices)` per tile.
2. Add `--highlight fundamental` (rendering change only — dim everything but tile 0).
3. Add `--label-generators` (text labels on the fundamental polygon).
4. Add `--path-to` (given a target, walk the reflection path and highlight).
5. Add example renders in `examples/educational/` and reference them from a short "understanding {p,q} tilings" section in the README (or a new `docs/` page).

## Open questions / risks

- Text placement inside curved geodesic tiles is fiddly. Simplest: place at the tile centroid; if too small, elide.
- "Word length" and "depth" are only distinct once relations kick in (when reflected paths return to already-visited tiles). For low-depth renders they'll match exactly — mode may look identical to depth-coloring at first glance. Document this.
- Non-technical viewers won't know what "generator" means. The plan is a *tool*, not an *explainer*; README can point at Coxeter/Wikipedia for background.

## Scope guard

- Static SVG/PNG output only. No interactive click-to-highlight.
- No general group-theory library. Just the specific `{p,q}` Coxeter group structure that BFS already exposes.
- No animation of the reflection process — that could be its own plan.
