# Plan: Möbius animator

## Goal

Emit a sequence of PNG frames showing the tessellation transformed by a smooth hyperbolic isometry (translation, rotation, or a composition). Piped through `ffmpeg` externally, the output is a looping animation of tiles sliding across the disk — a familiar and beautiful hyperbolic-geometry demo.

## Approach

Every orientation-preserving isometry of the Poincaré disk is a Möbius transformation of the form

```
z ↦ (a·z + b) / (b̄·z + ā)     with |a|² − |b|² = 1
```

Two natural motions:
- **Hyperbolic translation** by real distance `d` along direction `θ`: pick `a = cosh(d/2)`, `b = sinh(d/2) · e^{iθ}`.
- **Rotation** by angle `φ` around the origin: `z ↦ e^{iφ} · z`.

For an animation, parameterize `t ∈ [0, 1)` and apply the transformation with `d(t) = d_max · t` (translation) or `φ(t) = 2π · t` (rotation). For a looping translation, use `d(t) = d_max · sin(2πt)` so the tiling drifts and returns.

Rendering flow per frame: tessellate once, transform each tile's vertices with the current Möbius map, then feed to existing `write-png!` / `write-svg!`.

## CLI / API surface

```
--animate translate|rotate|both       Motion type
--frames N                             Number of frames (default 60)
--speed X                              Peak distance (translate) or turns (rotate)
--direction DEG                        Direction of translation in degrees
--out-dir PATH                         Directory for frame_0001.png ... frame_NNNN.png
```

`--file` becomes ignored (or repurposed as an ffmpeg command hint) when `--animate` is set.

## Milestones

1. Add a `mobius-transform` procedure in `hyperbolic.rkt` taking `(a, b)` and applying to a point.
2. Extract the current single-frame render path into a `render-frame` helper.
3. Add the animation loop: compute `(a(t), b(t))`, transform tiles, call `render-frame`.
4. Write frames as `frame_0001.png` etc. into `--out-dir`.
5. Document the recommended `ffmpeg` invocation in README.

## Open questions / risks

- Tiles near the boundary get so small they alias badly under motion. Anti-aliasing would help — perhaps enable `smoothing` on the `dc` (already partially done).
- The boundary filigree shifts with each frame; at large translations, the depth we're rendering at is no longer sufficient because tiles that were "just off-screen" translate into view. Either (a) tessellate at higher depth for animations, or (b) tessellate from the *moved* center.
- Should the "camera" move (isometry applied to view) or the "tiling" move (isometry applied to tiles)? Mathematically equivalent; pick one for the code.

## Scope guard

- Output frames only. No built-in video encoding — users run ffmpeg themselves.
- Two motion types (translate, rotate) plus composition. No custom Möbius scripting.
- No easing / keyframe DSL. Linear parameterization only.
