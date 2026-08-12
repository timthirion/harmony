# Regenerate every image and animation under examples/ from source.
#
# Usage:
#   make gallery         # rebuild everything
#   make hero            # just the {p,q} hero images
#   make motifs models educational euclidean print viewer animation sphere moebius
#   make clean-gallery   # delete regenerated outputs (keeps source)
#
# Every recipe below matches the reproducer command in the README so the
# gallery is exactly what a user reading the docs would produce.

RACKET ?= racket
HARMONY = $(RACKET) harmony.rkt
EUCLIDEAN = $(RACKET) euclidean.rkt
VIEWER = $(RACKET) viewer.rkt
SPHERE = $(RACKET) sphere.rkt

EX = examples

.PHONY: gallery hero motifs models educational euclidean print viewer animation \
        sphere moebius clean-gallery

gallery: hero motifs models educational euclidean print viewer animation sphere moebius

# ---- Hero gallery (README top) ----
hero: $(EX)/tiling-7-3-harmony.png \
      $(EX)/tiling-8-3-ocean.png \
      $(EX)/tiling-5-4-sunset.png \
      $(EX)/tiling-4-5-forest.png

$(EX)/tiling-7-3-harmony.png:
	$(HARMONY) -p 7 -q 3 --depth 9 --palette harmony -d 1200 1200 -f $@

$(EX)/tiling-8-3-ocean.png:
	$(HARMONY) -p 8 -q 3 --depth 7 --palette ocean   -d 1200 1200 -f $@

$(EX)/tiling-5-4-sunset.png:
	$(HARMONY) -p 5 -q 4 --depth 8 --palette sunset  -d 1200 1200 -f $@

$(EX)/tiling-4-5-forest.png:
	$(HARMONY) -p 4 -q 5 --depth 8 --palette forest  -d 1200 1200 -f $@

# ---- Motifs ----
motifs: $(EX)/motifs/nested-7-3-harmony.png \
        $(EX)/motifs/star-5-4-sunset.png \
        $(EX)/motifs/curves-8-3-ocean.png

$(EX)/motifs/nested-7-3-harmony.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 5 --palette harmony --motif nested -d 1200 1200 -f $@

$(EX)/motifs/star-5-4-sunset.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 5 -q 4 --depth 5 --palette sunset  --motif star   -d 1200 1200 -f $@

$(EX)/motifs/curves-8-3-ocean.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 8 -q 3 --depth 5 --palette ocean   --motif curves -d 1200 1200 -f $@

# ---- Alternate models (same {7,3} projected four ways) ----
models: $(EX)/models/model-poincare-7-3.png \
        $(EX)/models/model-klein-7-3.png \
        $(EX)/models/model-halfplane-7-3.png \
        $(EX)/models/model-band-7-3.png

$(EX)/models/model-poincare-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 8 --palette harmony --model poincare  -d 900 900 -f $@

$(EX)/models/model-klein-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 6 --palette harmony --model klein     -d 900 900 -f $@

$(EX)/models/model-halfplane-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 8 --palette harmony --model halfplane -d 900 900 -f $@

$(EX)/models/model-band-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 8 --palette harmony --model band      -d 1200 600 -f $@

# ---- Educational (fundamental-domain viewer flags) ----
educational: $(EX)/educational/highlight-7-3.png \
             $(EX)/educational/labels-7-3.png \
             $(EX)/educational/explain-7-3.png

$(EX)/educational/highlight-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 6 --palette harmony -d 900 900 --highlight fundamental                       -f $@

$(EX)/educational/labels-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 6 --palette harmony -d 900 900                        --label-generators     -f $@

$(EX)/educational/explain-7-3.png:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 6 --palette harmony -d 900 900 --highlight fundamental --label-generators    -f $@

# ---- Euclidean companion ----
euclidean: $(EX)/euclidean/hex-6-3.png \
           $(EX)/euclidean/square-4-4.png \
           $(EX)/euclidean/triangle-3-6.png

$(EX)/euclidean/hex-6-3.png:
	@mkdir -p $(dir $@)
	$(EUCLIDEAN) --tiling hex      --extent 8  -d 1000 1000 --palette harmony -f $@

$(EX)/euclidean/square-4-4.png:
	@mkdir -p $(dir $@)
	$(EUCLIDEAN) --tiling square   --extent 8  -d 1000 1000 --palette sunset  -f $@

$(EX)/euclidean/triangle-3-6.png:
	@mkdir -p $(dir $@)
	$(EUCLIDEAN) --tiling triangle --extent 10 -d 1000 1000 --palette ocean   -f $@

# ---- Print sample (small PDF) ----
print: $(EX)/print/poster-4in-7-3.pdf

$(EX)/print/poster-4in-7-3.pdf:
	@mkdir -p $(dir $@)
	$(HARMONY) -p 7 -q 3 --depth 6 --palette harmony -d 384 384 -f $@

# ---- Viewer snapshot (uses viewer's headless mode) ----
viewer: $(EX)/viewer/viewer-7-3.png

$(EX)/viewer/viewer-7-3.png:
	@mkdir -p $(dir $@)
	$(VIEWER) --snapshot $@ --size 700 --depth 6 --palette sunset

# ---- Animation (frames + GIF + MP4) ----
# ffmpeg required. Generates 40 frames of {7,3} sunset translating along
# the real axis, then packs them into a small GIF and an MP4.
animation: $(EX)/animation/translate-7-3-sunset.gif \
           $(EX)/animation/translate-7-3-sunset.mp4

$(EX)/animation/translate-7-3-sunset.gif $(EX)/animation/translate-7-3-sunset.mp4:
	@mkdir -p $(dir $@) /tmp/harmony-frames
	@rm -f /tmp/harmony-frames/frame_*.png
	$(HARMONY) -p 7 -q 3 --depth 7 --palette sunset -d 400 400 \
	  --animate translate --frames 40 --translate-dist 1.2 --out-dir /tmp/harmony-frames
	ffmpeg -y -framerate 20 -i /tmp/harmony-frames/frame_%04d.png \
	  -vf "fps=15,scale=300:300:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
	  -loop 0 $(EX)/animation/translate-7-3-sunset.gif
	ffmpeg -y -framerate 20 -i /tmp/harmony-frames/frame_%04d.png \
	  -vf "scale=400:400" -c:v libx264 -pix_fmt yuv420p -movflags +faststart -crf 22 \
	  $(EX)/animation/translate-7-3-sunset.mp4

# ---- Möbius / Riemann-sphere viewer (still + animation) ----
sphere: $(EX)/sphere/moebius-7-3-harmony.png

$(EX)/sphere/moebius-7-3-harmony.png:
	@mkdir -p $(dir $@)
	$(SPHERE) -p 7 -q 3 --depth 8 --palette harmony --size 1200 \
	  --y-turns 0.13 --x-turns 0.19 --snapshot $@

moebius: $(EX)/animation/moebius-7-3-harmony.gif $(EX)/animation/moebius-7-3-harmony.mp4

$(EX)/animation/moebius-7-3-harmony.gif $(EX)/animation/moebius-7-3-harmony.mp4:
	@mkdir -p $(dir $@) /tmp/moebius-frames
	@rm -f /tmp/moebius-frames/frame_*.png
	$(SPHERE) -p 7 -q 3 --depth 6 --palette harmony --size 500 \
	  --animate x --frames 90 --out-dir /tmp/moebius-frames
	ffmpeg -y -framerate 15 -i /tmp/moebius-frames/frame_%04d.png \
	  -vf "fps=15,scale=320:320:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=48:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4" \
	  -loop 0 $(EX)/animation/moebius-7-3-harmony.gif
	ffmpeg -y -framerate 15 -i /tmp/moebius-frames/frame_%04d.png \
	  -vf "scale=500:500" -c:v libx264 -pix_fmt yuv420p -movflags +faststart -crf 22 \
	  $(EX)/animation/moebius-7-3-harmony.mp4

# ---- Cleanup ----
clean-gallery:
	rm -f $(EX)/tiling-*.png
	rm -rf $(EX)/motifs $(EX)/models $(EX)/educational $(EX)/euclidean
	rm -rf $(EX)/print $(EX)/viewer $(EX)/animation $(EX)/sphere
