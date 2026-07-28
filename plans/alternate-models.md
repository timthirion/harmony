# Plan: alternate models

## Goal

Render the same `{p,q}` tessellation projected onto three additional models of the hyperbolic plane besides the Poincaré disk:

- **Klein disk** — geodesics become straight chords. Angles are distorted, so tiles don't look conformal.
- **Upper half-plane** — geodesics are vertical lines or half-circles orthogonal to the real axis. Familiar to complex-analysis and modular-forms folks.
- **Band model** — the strip `{|Im z| < π/2}`. Geodesics are curves; horizontal translation is a hyperbolic isometry.

Every model has the same underlying tessellation combinatorics; only the visualization changes.

## Approach

Given Poincaré-disk complex coordinates `z_poincare` for each tile vertex, transform to the target model:

- **Klein**: `z_klein = 2·z / (1 + |z|²)` (radial). Chords replace arcs; boundary is still the unit circle.
- **Upper half-plane**: `z_uhp = i·(1 + z)/(1 − z)` (Cayley transform). Boundary maps to the real axis. Rendering needs a viewport (finite window) since UHP is unbounded above.
- **Band**: `z_band = log(z_uhp)` (complex log of the Cayley image). Boundary maps to `Im z = ±π/2`. Also unbounded but naturally strip-shaped.

Then the per-model renderer needs geodesic primitives:
- Klein: straight lines between transformed vertices.
- UHP: for a chord between two boundary/interior points, the geodesic is a half-circle orthogonal to the real axis, or a vertical line. Reuse the existing arc logic with the axis playing the role of the boundary.
- Band: geodesics are more complex curves; approximate with Bézier subdivisions.

## CLI / API surface

```
--model poincare|klein|halfplane|band     Projection model (default: poincare)
```

For half-plane and band, add `--viewport X Y W H` to specify the window in model coords, since these models are unbounded.

## Milestones

1. Extract Poincaré-specific rendering into a per-model dispatch. Introduce `write-<model>!` variants sharing pass structure.
2. Klein first (simplest — just transform vertices, use lines instead of arcs).
3. Upper half-plane, with viewport support and axis rendered as the model boundary.
4. Band model, likely last.
5. Add a `--model` gallery: same `{p,q}` rendered in all four for the README.

## Open questions / risks

- The stroke widths that look good in the Poincaré disk (tapered by depth) look wrong in other models where "far from origin" doesn't mean "small tile."
- Half-plane and band need clipping to a viewport; tiles near the model boundary can be extremely large in world coords and expensive to render.
- The current palette's "deeper = darker" rule is depth-based (BFS distance), not distance-based. That's fine in Poincaré but might look off in Klein where the visual "depth" gradient doesn't match BFS depth. Consider a `--color-by depth|distance` option in a future plan.

## Scope guard

- Four models, one file, one flag. No custom projections.
- No cross-model animations (that would be its own plan).
- Poincaré remains the default and the most polished model.
