# harmony

Harmony renders regular `{p,q}` hyperbolic tessellations in the Poincaré disk model. It is a small Racket program that writes SVG or PNG.

<p align="center">
  <img src="examples/tiling-7-3-harmony.png" width="45%" alt="{7,3} tiling, harmony palette">
  <img src="examples/tiling-8-3-ocean.png"   width="45%" alt="{8,3} tiling, ocean palette">
</p>
<p align="center">
  <img src="examples/tiling-5-4-sunset.png"  width="45%" alt="{5,4} tiling, sunset palette">
  <img src="examples/tiling-4-5-forest.png"  width="45%" alt="{4,5} tiling, forest palette">
</p>

## What is a `{p,q}` tiling?

A regular tessellation `{p,q}` fills the plane with regular `p`-gons meeting `q` around each vertex. Three cases exist:

| condition            | geometry    | examples                  |
|----------------------|-------------|---------------------------|
| `(p-2)(q-2) < 4`     | spherical   | `{3,3}`, `{3,4}`, `{3,5}` |
| `(p-2)(q-2) = 4`     | Euclidean   | `{3,6}`, `{4,4}`, `{6,3}` |
| `(p-2)(q-2) > 4`     | hyperbolic  | `{7,3}`, `{5,4}`, `{4,5}` |

Harmony renders the hyperbolic case, projecting the tiling onto the Poincaré disk. Sides of tiles are geodesic arcs (arcs of circles orthogonal to the boundary), and tiles shrink toward the boundary as an artifact of the projection — hyperbolically they are all congruent.

## Requirements

- [Racket](https://racket-lang.org/) 8+ (tested on 9.1).

## Usage

```
racket harmony.rkt [options]
```

Common options:

| flag                         | default        | notes                                             |
|------------------------------|----------------|---------------------------------------------------|
| `-p P`                       | `9`            | Polygon sides                                     |
| `-q Q`                       | `3`            | Polygons meeting at each vertex                   |
| `--depth D`                  | `4`            | Recursion depth of the reflection tessellation    |
| `-d W H`, `--dimensions W H` | `800 800`      | Image dimensions in pixels                        |
| `-f FILE`, `--file FILE`     | `output.svg`   | Output path. `.png` extension writes PNG          |
| `--palette NAME`             | `harmony`      | One of: `harmony`, `sunset`, `ocean`, `forest`, `mono`, `autumn`, `frost`, `berry` |
| `--motif NAME`               | (none)         | One of: `nested`, `star`, `curves` — see below   |
| `--model NAME`               | `poincare`     | Projection: `poincare`, `klein`, `halfplane`, `band` — see Models |
| `--highlight NAME`           | (none)         | Educational: `fundamental` — dim everything except the depth-0 tile |
| `--label-generators`         | (off)          | Number the `p` sides of the fundamental polygon 1..p |
| `--no-spokes`                | (spokes on)    | Omit the white vertex spokes                      |
| `--animate MOTION`           | (single frame) | `rotate`, `translate`, or `both` — see Animation |
| `--frames N`                 | `60`           | Frames per loop (animation only)                  |
| `--out-dir PATH`             | `frames`       | Directory for animation frames                    |
| `--dpi N`                    | `96`           | Output resolution for PNG (see Printing)          |
| `--bleed IN`                 | `0`            | Print bleed in inches on each side                |

Invalid `{p,q}` (spherical or Euclidean) is rejected with a message.

### Examples

Reproduce the hero gallery images above:

```sh
racket harmony.rkt -p 7 -q 3 --depth 9 --palette harmony -d 1200 1200 -f tiling-7-3.png
racket harmony.rkt -p 8 -q 3 --depth 7 --palette ocean   -d 1200 1200 -f tiling-8-3.png
racket harmony.rkt -p 5 -q 4 --depth 8 --palette sunset  -d 1200 1200 -f tiling-5-4.png
racket harmony.rkt -p 4 -q 5 --depth 8 --palette forest  -d 1200 1200 -f tiling-4-5.png
```

Line-art variant (no white spokes) as SVG:

```sh
racket harmony.rkt -p 6 -q 4 --depth 5 --palette mono --no-spokes -f tiling-6-4.svg
```

Tile counts scale roughly as `(p-1)(q-1)` per level. Depth 5–6 renders in well under a second; higher depths grow to a few seconds.

## Motifs

`--motif NAME` replaces the plain solid-tile look with a small geometric figure drawn inside every tile. The motif is defined in the coordinate system of the fundamental polygon, and harmony warps it through the same reflection sequence that generated each tile — so the motif "lives" inside the hyperbolic geometry, not on top of it.

<p align="center">
  <img src="examples/motifs/nested-7-3-harmony.png" width="30%" alt="nested motif in {7,3}, harmony">
  <img src="examples/motifs/star-5-4-sunset.png"    width="30%" alt="star motif in {5,4}, sunset">
  <img src="examples/motifs/curves-8-3-ocean.png"   width="30%" alt="curves motif in {8,3}, ocean">
</p>

| motif    | description                                                                     |
|----------|---------------------------------------------------------------------------------|
| `nested` | A smaller similar `p`-gon inscribed in each tile.                               |
| `star`   | A `2p`-pointed star with outer points at the tile's vertices.                   |
| `curves` | A rosette of `p` quadratic-Bezier arcs between adjacent side midpoints. Because arc endpoints sit on side midpoints (shared between adjacent tiles), reflected copies join up naturally to form a continuous filigree across the whole tessellation. |

Reproduce the motif gallery:

```sh
racket harmony.rkt -p 7 -q 3 --depth 5 --palette harmony --motif nested -d 1200 1200 -f nested.png
racket harmony.rkt -p 5 -q 4 --depth 5 --palette sunset  --motif star   -d 1200 1200 -f star.png
racket harmony.rkt -p 8 -q 3 --depth 5 --palette ocean   --motif curves -d 1200 1200 -f curves.png
```

Spokes are automatically suppressed when a motif is active.

## Understanding a `{p,q}` tessellation

Two flags turn harmony into a small teaching tool for the group-theoretic structure behind a `{p,q}` tiling. They compose with palettes, motifs, and models.

<p align="center">
  <img src="examples/educational/highlight-7-3.png" width="30%" alt="fundamental polygon highlighted">
  <img src="examples/educational/labels-7-3.png"    width="30%" alt="fundamental sides numbered">
  <img src="examples/educational/explain-7-3.png"   width="30%" alt="highlight + labels">
</p>

- **`--highlight fundamental`** — dims every tile except the depth-0 one. The bright polygon at the centre is the *fundamental domain* of the reflection group; every other tile in the picture is an image of it under some finite composition of side-reflections.
- **`--label-generators`** — numbers the `p` sides of the fundamental polygon. Each numbered side corresponds to one of the group's `p` generators (the reflection across that side). The full symmetry group is generated by these `p` reflections subject to the Coxeter relations `(g_i g_{i+1})^q = 1`.

Combine them (`--highlight fundamental --label-generators`) to get a clean diagram usable in a talk or write-up. Reproduce the images above:

```sh
racket harmony.rkt -p 7 -q 3 --depth 6 --palette harmony -d 900 900 --highlight fundamental                       -f highlight.png
racket harmony.rkt -p 7 -q 3 --depth 6 --palette harmony -d 900 900                        --label-generators     -f labels.png
racket harmony.rkt -p 7 -q 3 --depth 6 --palette harmony -d 900 900 --highlight fundamental --label-generators    -f explain.png
```

## Models

The same `{p,q}` tessellation lives in the abstract hyperbolic plane; each model is one way of drawing it inside a Euclidean picture. Different models highlight different structural features.

<p align="center">
  <img src="examples/models/model-poincare-7-3.png"  width="45%" alt="{7,3} in Poincaré disk">
  <img src="examples/models/model-klein-7-3.png"     width="45%" alt="{7,3} in Klein disk">
</p>
<p align="center">
  <img src="examples/models/model-halfplane-7-3.png" width="45%" alt="{7,3} in upper half-plane">
  <img src="examples/models/model-band-7-3.png"      width="45%" alt="{7,3} in band model">
</p>

| model       | coordinate transform (from Poincaré `z`)                | geodesics                                          |
|-------------|---------------------------------------------------------|----------------------------------------------------|
| `poincare`  | identity                                                | Arcs of circles orthogonal to the boundary         |
| `klein`     | `2z / (1 + \|z\|²)`                                     | Straight line segments (chords)                    |
| `halfplane` | `i(1 + z) / (1 − z)` (Cayley transform)                 | Vertical lines or semicircles centered on the real axis |
| `band`      | `log(halfplane(z)) − iπ/2`                              | Curves (in general); sampled and drawn as polylines |

Reproduce the gallery:

```sh
racket harmony.rkt -p 7 -q 3 --depth 8 --palette harmony -d 900 900  --model poincare  -f model-poincare.png
racket harmony.rkt -p 7 -q 3 --depth 6 --palette harmony -d 900 900  --model klein     -f model-klein.png
racket harmony.rkt -p 7 -q 3 --depth 8 --palette harmony -d 900 900  --model halfplane -f model-halfplane.png
racket harmony.rkt -p 7 -q 3 --depth 8 --palette harmony -d 1200 600 --model band      -f model-band.png
```

Notes:
- `poincare` and `klein` both fit in the unit disk; use square dimensions.
- `halfplane` fills the upper half-plane; use a rectangular canvas with the real axis at the bottom. The central tile lands at the imaginary unit `i`.
- `band` uses a wide strip (`|Im| < π/2`). Use a wide rectangular canvas.
- The Poincaré and half-plane models are *conformal* (angle-preserving); Klein is not (angles distort but geodesics become chords).

Models compose with palettes and motifs. Animations are still Möbius maps applied in the Poincaré disk before projection, so `--animate` also works with `--model` — the tessellation slides or spins in hyperbolic space and you see the effect in whatever model you chose.

## Animation

`--animate MOTION` emits a sequence of PNG frames showing the tessellation transformed by a smooth hyperbolic isometry. The motion loops seamlessly — frame N equals frame 0 — so the output feeds directly into `ffmpeg` for GIF or MP4.

<p align="center">
  <img src="examples/animation/translate-7-3-sunset.gif" alt="{7,3} sunset translating back and forth" width="400">
</p>

Three motions:

| motion      | what it does                                                                    |
|-------------|---------------------------------------------------------------------------------|
| `rotate`    | Rotates the tessellation around the origin. Fits `--rotate-turns` full turns.   |
| `translate` | Hyperbolic translation with a sinusoidal envelope: tiles slide out, come back, slide the other way, come back. `--translate-dist` sets amplitude, `--translate-dir` the axis in degrees. |
| `both`      | Composition of rotation and translation.                                        |

Reproduce the demo above:

```sh
racket harmony.rkt -p 7 -q 3 --depth 7 --palette sunset -d 400 400 \
  --animate translate --frames 40 --translate-dist 1.2 --out-dir frames/

ffmpeg -framerate 20 -i frames/frame_%04d.png \
  -vf "fps=15,scale=300:300,split[s0][s1];[s0]palettegen=max_colors=64[p];[s1][p]paletteuse" \
  -loop 0 translate-7-3-sunset.gif
```

For MP4 output instead:

```sh
ffmpeg -framerate 20 -i frames/frame_%04d.png -c:v libx264 -pix_fmt yuv420p out.mp4
```

Animation notes:
- Increase `--depth` beyond your usual static value. When tiles slide across the disk, previously off-screen tiles rotate into view and would otherwise "pop in" as gaps. Depth 6–8 works well for `{7,3}`.
- Each frame takes about the same time as a single-frame render. 60 frames at depth 7 is ~15 s on a modern laptop.

## Printing

Harmony can produce high-DPI PNG, vector PDF, and print-safe canvases with bleed.

**Units and DPI.** `-d W H` is stated in "logical pixels at 96 DPI" (so `-d 800 800` means an 8.33" image at screen resolution). Three flags then adapt the output:

- **`--dpi N`** (PNG only) scales both pixel dimensions and stroke widths by `N/96`. Everything looks the same as at 96 DPI, just crisper on paper. E.g. `-d 768 768 --dpi 300` → 2400×2400 pixel PNG, an 8"×8" print.
- **`--bleed IN`** adds `IN` inches of bleed on every side. The tessellation stays sized to the trim area (unaffected) and the bleed is filled with the palette's outer color, so a printer trimming slightly off the mark still cuts through colored material.
- **`-f out.pdf`** switches to PDF output. The page size is `(-d W)/96 × (-d H)/96` inches (harmony uses `racket/draw`'s `pdf-dc%`, which pairs 1/96" drawing units with a 72-point page). `--dpi` is a no-op for PDF because vectors render at whatever DPI the printer/viewer wants; `--bleed` still applies.

**Worked example — 8"×8" poster at 300 DPI:**

```sh
# PNG
racket harmony.rkt -p 7 -q 3 --depth 8 --palette harmony -d 768 768 --dpi 300 --bleed 0.125 -f poster.png

# PDF (vector, resolution-independent)
racket harmony.rkt -p 7 -q 3 --depth 8 --palette harmony -d 768 768 --bleed 0.125 -f poster.pdf
```

Both produce an 8"×8" trim area with 0.125" of bleed on every side (10.5" × 10.5" total when trimmed for standard bleed). The PNG is 2500×2500 pixels; the PDF is a 648×648-point page (about 9"×9" including bleed). See [`examples/print/poster-4in-7-3.pdf`](examples/print/poster-4in-7-3.pdf) for a smaller sample.

Color note: palettes are RGB. Print shops will CMYK-convert on their end; deep saturations may shift slightly on paper. If exact colors matter, ask your print shop for their ICC profile and preview locally.

## Companion: interactive viewer

`viewer.rkt` opens a live GUI window on a `{p,q}` tiling. Mouse-drag pans by hyperbolic translation; the scroll wheel adjusts a Euclidean zoom multiplier.

<p align="center">
  <img src="examples/viewer/viewer-7-3.png" width="45%" alt="viewer snapshot, {7,3} sunset">
</p>

```sh
racket viewer.rkt -p 7 -q 3 --palette sunset
```

The renderer is intentionally simpler than harmony's — Poincaré model only, straight-line polygons (no geodesic arcs), no motifs or highlights — so redraws stay interactive. For the polished still, snapshot the current view with `s` and re-render the same `{p,q}` through `harmony.rkt`.

**Model.** The tessellation is computed once at startup (default depth 8 → ~11k tiles). The only per-frame state is the viewer's world position, which is clamped to keep the disk-preserving Möbius numerically stable. Pans apply that Möbius to the fixed pre-computed vertices — no drift, no flicker, no accumulated numerical error, but the explorable area is bounded. Drag toward the boundary and the view gently sticks at the clamp. For truly unbounded navigation through a hyperbolic tessellation, see [HyperRogue](https://www.roguetemple.com/z/hyper/) or [MagicTile](https://superliminal.com/andrey/MagicTile.html) — that requires a graph-based tessellation with orientation-reversing frame swaps on every tile-boundary crossing, a substantially bigger project.

| control          | action                                                     |
|------------------|------------------------------------------------------------|
| Mouse drag       | Pan (hyperbolic translation, clamped near the boundary)    |
| Scroll wheel     | Euclidean zoom                                             |
| `r`              | Reset view                                                 |
| `s`              | Save `snapshot-<time>.png` to the working directory        |
| `p`              | Cycle palette (harmony → sunset → ocean → forest → mono)   |
| `m`              | Cycle projection model (poincare → klein → halfplane → band). Same tessellation, different projection — same tile set is reprojected every frame, no re-tessellation. |
| `c`              | Print the equivalent `harmony.rkt` command line to stdout, including the current pan position via `--pan REAL,IMAG` and `--model NAME` if not Poincaré — a "polish this view" bridge to the main renderer |
| `+` / `-`        | Increase / decrease BFS depth (regenerates tiles)          |

Changing `{p,q}` in the viewer would require re-tessellating on every keypress, which locks up the paint loop for larger tilings. It's left as a command-line concern (`-p` / `-q` on relaunch), which composes naturally with `c` above: explore in the viewer, hit `c`, tweak the `-p`/`-q` in the printed command, re-render through `harmony.rkt` for the polished still.

The window also supports `--snapshot FILE` for headless single-frame rendering — the image above was produced with `racket viewer.rkt --snapshot examples/viewer/viewer-7-3.png --size 700 --depth 6 --palette sunset`.

## Companion: Euclidean tiler

`euclidean.rkt` is a small sibling binary that renders the three regular Euclidean tessellations — the ones harmony refuses to tile because they aren't hyperbolic. Different math (translational lattice, no geodesic arcs, no reflection group), same palettes, same aesthetic.

<p align="center">
  <img src="examples/euclidean/hex-6-3.png"      width="30%" alt="{6,3} hexagonal tiling">
  <img src="examples/euclidean/square-4-4.png"   width="30%" alt="{4,4} square tiling">
  <img src="examples/euclidean/triangle-3-6.png" width="30%" alt="{3,6} triangular tiling">
</p>

Three tilings, one binary:

```sh
racket euclidean.rkt --tiling hex      --extent 8  -d 1000 1000 --palette harmony -f hex.png
racket euclidean.rkt --tiling square   --extent 8  -d 1000 1000 --palette sunset  -f square.png
racket euclidean.rkt --tiling triangle --extent 10 -d 1000 1000 --palette ocean   -f triangle.png
```

`--extent N` sets the lattice half-width (how many rings from the origin). Because these tilings are strictly translational there's no natural "depth from origin" the way harmony has — coloring uses lattice-distance from origin and a three-family cycle indexed by `(n1 − n2) mod 3` (hex, triangle) or `(n1 + n2) mod 3` (square), which gives the classic hexagonal three-colour theorem for hex tilings and diagonal stripes for the others.

Palettes are shared with harmony via `palettes.rkt`, so `--palette harmony|sunset|ocean|forest|mono` all work.

## How it works

- `hyperbolic.rkt` — geometry: computes the fundamental polygon's Euclidean circumradius `sqrt(cos(π/p+π/q)/cos(π/p−π/q))`, the geodesic circle through two disk points (via inversion in the unit circle), and reflections across geodesics. Tessellation is a BFS: from the central tile, each side reflects the tile to a neighbor; duplicates are pruned by rounded centroid. Each tile carries the ordered list of reflection axes that produced it, so a motif point can be replayed through the same sequence.
- `harmony.rkt` — CLI and rendering. Tiles are rendered in three passes:
  1. filled polygons (deepest first, so shallow tiles paint on top),
  2. white "spokes" from each tile's centroid to its vertices, *or* a warped motif (mutually exclusive),
  3. outlines (thinner with depth).
  SVG uses `<path>` elliptical arcs; PNG uses `racket/draw` with a cubic-Bézier approximation of each geodesic arc.

## Reproducing the gallery

Every image in `examples/` is generated by a single command documented in a `Makefile`:

```sh
make gallery          # rebuild everything
make hero             # just the hero {p,q} images
make motifs models educational euclidean print viewer animation
make clean-gallery    # remove regenerated outputs
```

Each target matches the reproducer command in the section above, so running `make hero` and running the four commands from the "Examples" section are equivalent. Handy for validating changes to the renderer — bump a color, run `make gallery`, diff the outputs.

## License

Apache 2.0 — see [LICENSE](LICENSE).
