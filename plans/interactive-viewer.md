# Plan: interactive viewer

## Goal

A real-time GUI window that lets the user pan and zoom through a `{p,q}` tessellation. As the view moves, the tessellation re-computes with adaptive depth so boundary tiles stay roughly one pixel across. The static renderer becomes a snapshot mode of the same tool.

This is the biggest swing in `plans/` — it's a rewrite of the top-level control loop, not an extension of the CLI. It's worth doing only if the interactivity itself is the goal.

## Approach

Racket has `racket/gui` and `racket/draw`, both already in use for PNG output. A `canvas%` inside a `frame%` can host the tessellation; mouse events pan/zoom the view; a redraw callback re-tessellates and draws.

Pan and zoom are Möbius transformations of the disk:
- **Pan** by a screen-space vector: convert to a hyperbolic translation and apply as a Möbius map (see the `mobius-animator` plan for the formula).
- **Zoom** in the Poincaré disk is subtle — the disk is finite. What users expect is "make things near the pointer bigger" which is a hyperbolic translation of the pointer to the origin combined with a rescaling of the *viewport* radius (not a hyperbolic dilation, which doesn't exist).

Adaptive depth:
- After each view change, compute the minimum tile size on screen (approximately: the Euclidean radius of the smallest tile the viewport shows).
- Increase depth until the smallest tile is around 1 pixel; decrease if the viewport shrinks.

Rendering per frame:
- Transform tile vertices by current view Möbius.
- Cull tiles fully outside the viewport.
- Reuse the 3-pass draw (fills → spokes → outlines) from `write-png!`.

## API surface

```
racket viewer.rkt [-p P -q Q --palette NAME]
```

Optional keyboard controls:
- `+` / `-` : depth manual override
- `s` : save snapshot to PNG
- `r` : reset view to origin
- Arrow keys: pan
- Mouse drag: pan
- Scroll: zoom

## Milestones

1. Static viewer: render `{p,q}` in a window at fixed view. No interaction. Just proves the GUI path works.
2. Pan via mouse drag. No depth adaptation yet — fixed high depth.
3. Zoom via scroll wheel.
4. Adaptive depth (this is where most of the perf tuning happens).
5. Keyboard shortcuts, snapshot export.

## Open questions / risks

- **Performance.** The current renderer redraws every tile as a `dc-path%`. For interactive fps, this needs to be fast enough at each frame — likely OK at ~1000-2000 tiles but not at 30k. Adaptive depth is the escape valve, but the depth-1-pixel target needs tuning.
- **Racket GUI limitations.** `racket/draw` is Cairo-backed; it's fine for hundreds of tiles at 60fps, questionable for thousands. Fallback: draw to an offscreen bitmap and blit only when the view changes (drop live-drag redraws for a still preview + full redraw on release).
- **Distribution.** A GUI app is harder to share than a CLI. Consider whether the intended audience will actually build and run this.

## Scope guard

- Single-file GUI (`viewer.rkt`). Don't turn harmony into a multi-window IDE-like thing.
- No networking, no plugins, no scripting console. Just a canvas and a view.
- WebGL / browser port is a *different* plan (and a much bigger project).
