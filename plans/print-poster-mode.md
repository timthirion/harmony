# Plan: print / poster mode

## Goal

Make harmony's PNG output suitable for physical printing at poster sizes. Currently the renderer targets screen resolution and RGB. Print wants:

- **High DPI** (300 DPI is standard for photo prints; 150 acceptable for large posters).
- **Print-safe colors** — approximate CMYK gamut, avoiding oversaturated hues that shift on paper.
- **Bleed margins** — 0.125" extra on each side that the printer trims.
- **PDF output** — many print shops prefer PDF over PNG for vector-quality edges.

## Approach

### DPI

Add a `--dpi` flag (default 96 = current behavior). Multiply output pixel dimensions by `dpi / 96` and scale the drawing accordingly. Existing rendering is resolution-agnostic (arcs and lines scale), so the change is essentially a viewport size multiplier plus font/pen scaling.

### Print-safe palettes

Two options:

1. **Hand-tune print variants.** Add `--palette harmony-print`, `--palette sunset-print`, etc. with slightly desaturated versions of each palette that survive CMYK conversion cleanly. Fastest to implement, no dependencies.
2. **Convert on export.** Use an ICC profile to convert RGB → CMYK. Racket has `racket/draw/gl` and image-processing but not native ICC — would need to shell out to `ImageMagick` or `Ghostscript`. Higher fidelity, external dependency.

Recommend option 1 for a first pass.

### Bleed

Add `--bleed INCHES` (default 0). Extends the drawing area by `bleed * dpi` pixels on each side, with the tessellation continuing into the bleed (so trimming doesn't reveal white paper). The boundary circle stroke should sit *inside* the trim line.

### PDF output

Racket's `pict` library and `racket/draw` both support PDF via `pdf-dc%`. Instead of `bitmap-dc%`, use `pdf-dc%` when the output file ends in `.pdf`. All existing drawing calls transfer.

## CLI / API surface

```
--dpi N                      Output DPI (default 96)
--bleed INCHES               Extra edge for print trim (default 0)
--palette NAME-print         Print-safe variant of NAME (harmony-print, etc.)
-f FILE.pdf                  Automatically use PDF output for .pdf extension
```

## Milestones

1. `--dpi` flag scaling PNG output. Verify a 300 DPI 8"×8" render (2400×2400) still looks sharp.
2. Add print-safe palette variants — mostly a color re-tune, no code.
3. `--bleed` flag with correct positioning of the boundary stroke.
4. PDF output via `pdf-dc%`. Test with a real print shop's file requirements.
5. README section on printing (dimensions in inches, DPI, common paper sizes).

## Open questions / risks

- PDF from `pdf-dc%` embeds fonts and drawing state; verify the output is small enough for large posters. If not, produce SVG and use `rsvg-convert --format pdf` externally.
- Racket's Cairo backend doesn't natively speak CMYK. Even option 1 (hand-tuned palettes) is approximate — the real target color depends on the printer's ICC profile. Fine for a hobbyist workflow.
- Very high DPI + high tessellation depth means large files. A 24" × 24" poster at 300 DPI is 7200×7200 pixels — PNG will be ~50MB. Warn users.

## Scope guard

- No color management ambitions. Hand-tune print palettes; don't build an ICC pipeline.
- No print layout DSL (multi-panel posters, captions, etc.). Just one tiling per output file.
- No integration with specific print services. Users take the file to their preferred shop.
