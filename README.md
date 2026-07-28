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
| `--palette NAME`             | `harmony`      | One of: `harmony`, `sunset`, `ocean`, `forest`, `mono` |
| `--no-spokes`                | (spokes on)    | Omit the white vertex spokes                      |

Invalid `{p,q}` (spherical or Euclidean) is rejected with a message.

### Examples

Reproduce the gallery images above:

```sh
racket harmony.rkt -p 7 -q 3 --depth 5 --palette harmony -d 1200 1200 -f tiling-7-3.png
racket harmony.rkt -p 8 -q 3 --depth 5 --palette ocean   -d 1200 1200 -f tiling-8-3.png
racket harmony.rkt -p 5 -q 4 --depth 5 --palette sunset  -d 1200 1200 -f tiling-5-4.png
racket harmony.rkt -p 4 -q 5 --depth 6 --palette forest  -d 1200 1200 -f tiling-4-5.png
```

Line-art variant (no white spokes) as SVG:

```sh
racket harmony.rkt -p 6 -q 4 --depth 5 --palette mono --no-spokes -f tiling-6-4.svg
```

Tile counts scale roughly as `(p-1)(q-1)` per level. Depth 5–6 renders in well under a second; higher depths grow quickly.

## How it works

- `hyperbolic.rkt` — geometry: computes the fundamental polygon's Euclidean circumradius `sqrt(cos(π/p+π/q)/cos(π/p−π/q))`, the geodesic circle through two disk points (via inversion in the unit circle), and reflections across geodesics. Tessellation is a BFS: from the central tile, each side reflects the tile to a neighbor; duplicates are pruned by rounded centroid.
- `harmony.rkt` — CLI and rendering. Tiles are rendered in three passes:
  1. filled polygons (deepest first, so shallow tiles paint on top),
  2. white "spokes" from each tile's centroid to its vertices,
  3. outlines (thinner with depth).
  SVG uses `<path>` elliptical arcs; PNG uses `racket/draw` with a cubic-Bézier approximation of each geodesic arc.

## License

MIT — see [LICENSE](LICENSE).
