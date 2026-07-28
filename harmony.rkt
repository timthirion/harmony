#! /usr/bin/env racket
#lang racket

(require "hyperbolic.rkt")
(require racket/draw)

;; ---- Parameters ----

(define image-width  (make-parameter 800))
(define image-height (make-parameter 800))
(define image-file   (make-parameter "output.svg"))
(define tiling-p     (make-parameter 9))
(define tiling-q     (make-parameter 3))
(define tiling-depth (make-parameter 4))
(define palette-name (make-parameter "harmony"))
(define draw-spokes? (make-parameter #t))
(define motif-name   (make-parameter #f))
(define animate-motion   (make-parameter #f))    ; #f, "rotate", "translate", "both"
(define animate-frames   (make-parameter 60))
(define animate-turns    (make-parameter 1.0))
(define animate-dist     (make-parameter 0.7))
(define animate-dir      (make-parameter 0.0))   ; degrees
(define out-dir          (make-parameter "frames"))

;; ---- Color palettes ----
;; Each palette = 3 families (cycled by sector mod 3), tinted darker with depth,
;; plus a center color, stroke color, spoke color, and disk background.

(struct palette (families center stroke spoke disk outer) #:transparent)

(define PALETTES
  (hash
   "harmony"
   (palette
    (vector
     (vector "#B8CCE0" "#9DB8D5" "#82A4CA" "#6890BF" "#507CAE")   ; blue
     (vector "#E0B8B8" "#D5A0A0" "#CA8888" "#BF7070" "#AE5858")   ; rose
     (vector "#C0C0CC" "#ABABBA" "#9696A8" "#818196" "#6C6C84"))  ; grey
    "#D0DCE8" "#778899" "#FFFFFF" "#3F4A5E" "#3F4A5E")

   "sunset"
   (palette
    (vector
     (vector "#FFD9A8" "#FFC17F" "#FFA455" "#F1852C" "#D46A15")   ; amber
     (vector "#F7B7B7" "#EE8F8F" "#DE6B6B" "#C64D4D" "#A63838")   ; coral
     (vector "#C9A5CB" "#B282B5" "#98639C" "#7C4A82" "#5F3466"))  ; violet
    "#FFE8CC" "#3A1F1F" "#FFF6E8" "#3F2028" "#3F2028")

   "ocean"
   (palette
    (vector
     (vector "#BCE3E5" "#95CFD3" "#6BBAC1" "#3EA3AD" "#218893")   ; teal
     (vector "#B7D0EB" "#8FB4DE" "#6798CE" "#3F7CBB" "#255E9E")   ; blue
     (vector "#C6C9E6" "#A2A7D8" "#7C86C7" "#5865B4" "#39479A"))  ; indigo
    "#DFF3F4" "#0F2A38" "#EAF7FA" "#153549" "#153549")

   "forest"
   (palette
    (vector
     (vector "#CFE3B5" "#B4D28E" "#95BE64" "#749F41" "#556F27")   ; leaf
     (vector "#D9D2A6" "#C4BB78" "#A89F4E" "#847E31" "#5E5A20")   ; olive
     (vector "#B9C7A3" "#95AB84" "#728C63" "#527048" "#385331"))  ; moss
    "#E9EFD8" "#1F2A18" "#F6F7EA" "#2B311D" "#2B311D")

   "mono"
   (palette
    (vector
     (vector "#DADADA" "#BCBCBC" "#9E9E9E" "#7E7E7E" "#5F5F5F")
     (vector "#CFCFCF" "#B0B0B0" "#909090" "#707070" "#525252")
     (vector "#C4C4C4" "#A4A4A4" "#848484" "#646464" "#464646"))
    "#E5E5E5" "#2A2A2A" "#FFFFFF" "#404040" "#404040")))

(define (lookup-palette name)
  (hash-ref PALETTES name
            (lambda ()
              (eprintf "Unknown palette '~a'. Available: ~a~n"
                       name
                       (string-join (sort (hash-keys PALETTES) string<?) ", "))
              (exit 1))))

(command-line
 #:usage-help "Harmony generates hyperbolic tessellation diagrams"
 #:once-each
 [("-d" "--dimensions") W H "Image dimensions in pixels"
  (image-width  (string->number W))
  (image-height (string->number H))]
 [("-f" "--file") FILE "Output file path (.png for PNG, else SVG)"
  (image-file FILE)]
 [("-p") P "Polygon sides (e.g. 9 for nonagons)"
  (tiling-p (string->number P))]
 [("-q") Q "Polygons meeting at each vertex"
  (tiling-q (string->number Q))]
 [("--depth") D "Tessellation recursion depth"
  (tiling-depth (string->number D))]
 [("--palette") NAME "Color palette: harmony, sunset, ocean, forest, mono"
  (palette-name NAME)]
 [("--no-spokes") "Omit the white vertex spokes"
  (draw-spokes? #f)]
 [("--motif") NAME "Draw a per-tile motif: nested, star, or curves"
  (motif-name NAME)]
 [("--animate") MOTION "Emit a loop of frames. MOTION: rotate, translate, or both"
  (animate-motion MOTION)]
 [("--frames") N "Number of frames per loop (default 60)"
  (animate-frames (string->number N))]
 [("--rotate-turns") X "Full turns per loop for rotation (default 1)"
  (animate-turns (string->number X))]
 [("--translate-dist") X "Hyperbolic distance amplitude for translation (default 0.7)"
  (animate-dist (string->number X))]
 [("--translate-dir") DEG "Translation direction in degrees (default 0)"
  (animate-dir (string->number DEG))]
 [("--out-dir") PATH "Directory to write frames into (default 'frames')"
  (out-dir PATH)]
 #:args () (void))

;; ---- Input validation ----

(define (validate-tiling! p q depth)
  (define (die msg . args)
    (apply eprintf msg args)
    (eprintf "~n")
    (exit 1))
  (unless (and (integer? p) (>= p 3))
    (die "p must be an integer ≥ 3 (got ~a)" p))
  (unless (and (integer? q) (>= q 3))
    (die "q must be an integer ≥ 3 (got ~a)" q))
  (unless (and (integer? depth) (>= depth 0))
    (die "depth must be a non-negative integer (got ~a)" depth))
  (define product (* (- p 2) (- q 2)))
  (cond
    [(= product 4)
     (die "{~a,~a} is Euclidean (p-2)(q-2)=4; harmony only tiles the hyperbolic plane." p q)]
    [(< product 4)
     (die "{~a,~a} is spherical (p-2)(q-2)<4; harmony only tiles the hyperbolic plane." p q)]))

(validate-tiling! (tiling-p) (tiling-q) (tiling-depth))

(define VALID-MOTIONS '("rotate" "translate" "both"))

(when (animate-motion)
  (unless (member (animate-motion) VALID-MOTIONS)
    (eprintf "Unknown motion '~a'. Available: ~a~n"
             (animate-motion)
             (string-join VALID-MOTIONS ", "))
    (exit 1))
  (unless (and (integer? (animate-frames)) (>= (animate-frames) 2))
    (eprintf "--frames must be an integer ≥ 2~n")
    (exit 1)))

(define ACTIVE-PALETTE (lookup-palette (palette-name)))
(define CENTER-COLOR (palette-center ACTIVE-PALETTE))
(define STROKE-COLOR (palette-stroke ACTIVE-PALETTE))
(define SPOKE-COLOR  (palette-spoke  ACTIVE-PALETTE))
(define DISK-COLOR   (palette-disk   ACTIVE-PALETTE))
(define OUTER-COLOR  (palette-outer  ACTIVE-PALETTE))

(define (tile-color depth sector)
  (if (= sector -1)
      CENTER-COLOR
      (let* ([families (palette-families ACTIVE-PALETTE)]
             [family   (modulo sector 3)]
             [pal      (vector-ref families family)]
             [idx      (min depth (- (vector-length pal) 1))])
        (vector-ref pal idx))))

;; ---- Motifs ----
;; A motif is a procedure (p q) -> list of polylines, where each polyline is a
;; list of complex-number points in the fundamental polygon's local coordinates.
;; Segments between successive points are drawn as straight lines after warping,
;; so motif definitions subdivide curves into enough points to look smooth.

(define (fund-vertices p q) (polygon-vertices p q))

(define (side-midpoint verts i p)
  (define v1 (list-ref verts i))
  (define v2 (list-ref verts (modulo (+ i 1) p)))
  (/ (+ v1 v2) 2))

(define (subdivide-segment a b n)
  (for/list ([i (in-range (+ n 1))])
    (define t (/ i (* 1.0 n))) (+ (* (- 1 t) a) (* t b))))

(define (bezier-sample p0 p1 p2 n)
  (for/list ([i (in-range (+ n 1))])
    (define t (/ i (* 1.0 n)))
    (+ (* (sqr (- 1 t)) p0)
       (* 2 (- 1 t) t p1)
       (* (sqr t) p2))))

;; Nested inscribed polygon at 0.62 of fundamental radius.
;; Subdivide each side so warped edges stay smooth-looking.
(define (motif-nested p q)
  (define r (fundamental-radius p q))
  (define inner-r (* 0.62 r))
  (define pts (for/list ([k (in-range p)])
                (make-polar inner-r (+ (/ pi 2) (* 2 pi k (/ 1.0 p))))))
  (define closed (append pts (list (car pts))))
  (list
   (apply append
          (for/list ([i (in-range p)])
            (define a (list-ref closed i))
            (define b (list-ref closed (+ i 1)))
            (define seg (subdivide-segment a b 16))
            (if (= i 0) seg (cdr seg))))))

;; 2p-pointed star: outer points at fundamental vertex angles, inner points at
;; side-midpoint angles. Subdivided along each edge.
(define (motif-star p q)
  (define r (fundamental-radius p q))
  (define outer-r (* 0.90 r))
  (define inner-r (* 0.35 r))
  (define pts (for/list ([k (in-range (* 2 p))])
                (define angle (+ (/ pi 2) (* pi k (/ 1.0 p))))
                (define rad (if (even? k) outer-r inner-r))
                (make-polar rad angle)))
  (define closed (append pts (list (car pts))))
  (list
   (apply append
          (for/list ([i (in-range (* 2 p))])
            (define a (list-ref closed i))
            (define b (list-ref closed (+ i 1)))
            (define seg (subdivide-segment a b 6))
            (if (= i 0) seg (cdr seg))))))

;; Rosette: p quadratic-Bezier arcs, each from side-midpoint i to
;; side-midpoint i+1, bulging inward. When rendered, the ring of arcs
;; forms a flower inside every tile.
(define (motif-curves p q)
  (define verts (fund-vertices p q))
  (for/list ([i (in-range p)])
    (define a (side-midpoint verts i p))
    (define b (side-midpoint verts (modulo (+ i 1) p) p))
    (define ctrl (* 0.35 (/ (+ a b) 2)))
    (bezier-sample a ctrl b 18)))

(define MOTIFS
  (hash "nested" motif-nested
        "star"   motif-star
        "curves" motif-curves))

(define (lookup-motif name)
  (hash-ref MOTIFS name
            (lambda ()
              (eprintf "Unknown motif '~a'. Available: ~a~n"
                       name
                       (string-join (sort (hash-keys MOTIFS) string<?) ", "))
              (exit 1))))

(define ACTIVE-MOTIF (and (motif-name) (lookup-motif (motif-name))))

;; ---- View transform (Möbius applied per frame) ----
;; Identity by default. The animation loop parameterizes these per frame.
(define VIEW-A (make-parameter 1))
(define VIEW-B (make-parameter 0))

(define (view-apply z) (mobius-apply (VIEW-A) (VIEW-B) z))

;; Warp every point of every polyline using this tile's reflection axes,
;; then apply the current view transform.
(define (warp-polylines polylines axes)
  (for/list ([pl (in-list polylines)])
    (for/list ([z (in-list pl)])
      (view-apply (warp-point z axes)))))

;; Precompute a full tile list with vertices already pushed through the
;; current view transform. Axes are left original — motif rendering runs
;; through warp-point on the originals and then re-applies view-apply.
(define (transform-tiles-for-view tiles)
  (cond
    [(and (= (VIEW-A) 1) (= (VIEW-B) 0)) tiles]  ; identity, no-op
    [else
     (for/list ([tile (in-list tiles)])
       (list (map view-apply (first tile))
             (second tile)
             (third tile)
             (fourth tile)))]))

;; ---- Animation frame parameters ----
;; For frame t in [0, 1), produce the (a, b) Möbius pair for the requested
;; motion. Rotation is monotonic; translation uses sin so the loop is smooth.
(define (frame-mobius t motion turns dist dir-rad)
  (define (m-rotate phi)
    (values (make-polar 1 (/ phi 2)) 0))
  (define (m-translate d theta)
    (values (cosh (/ d 2)) (* (sinh (/ d 2)) (make-polar 1 theta))))
  (define (m-compose a1 b1 a2 b2)
    (values (+ (* a1 a2) (* b1 (conjugate b2)))
            (+ (* a1 b2) (* b1 (conjugate a2)))))
  (cond
    [(equal? motion "rotate")
     (m-rotate (* 2 pi t turns))]
    [(equal? motion "translate")
     (m-translate (* dist (sin (* 2 pi t))) dir-rad)]
    [(equal? motion "both")
     (define-values (a1 b1) (m-rotate    (* 2 pi t turns)))
     (define-values (a2 b2) (m-translate (* dist (sin (* 2 pi t))) dir-rad))
     (m-compose a1 b1 a2 b2)]))

;; ---- Shared geometry ----

(define (fmt x) (~r (exact->inexact x) #:precision 3))

(define (z->screen z cx cy scale)
  (cons (+ cx (* scale (real-part z)))
        (- cy (* scale (imag-part z)))))

(define (tile-centroid verts p)
  (/ (apply + verts) p))

;; ---- SVG output ----

;; SVG arc sweep-flag for the short arc from z1->z2 on the geodesic circle.
;; Uses angular average to find the short-arc midpoint (robust for all tiles).
(define (arc-sweep-flag z1 z2 c r cx cy scale)
  (define a1   (angle (- z1 c)))
  (define a2   (angle (- z2 c)))
  (define diff (let ([d (- a2 a1)])
                 (cond [(> d pi)  (- d (* 2 pi))]
                       [(< d (- pi)) (+ d (* 2 pi))]
                       [else d])))
  (define mid-math (+ c (make-polar r (+ a1 (/ diff 2)))))
  (define p1s  (z->screen z1      cx cy scale))
  (define mids (z->screen mid-math cx cy scale))
  (define cs   (z->screen c       cx cy scale))
  (define v1x (- (car p1s)  (car cs))) (define v1y (- (cdr p1s)  (cdr cs)))
  (define vmx (- (car mids) (car cs))) (define vmy (- (cdr mids) (cdr cs)))
  (if (> (- (* v1x vmy) (* v1y vmx)) 0) 1 0))

(define (arc-segment z1 z2 cx cy scale)
  (define p2s (z->screen z2 cx cy scale))
  (define x2  (fmt (car p2s)))
  (define y2  (fmt (cdr p2s)))
  (if (diameter? z1 z2)
      (format "L ~a ~a" x2 y2)
      (let-values ([(c r) (geodesic-circle z1 z2)])
        (define sr    (* scale r))
        (define sweep (arc-sweep-flag z1 z2 c r cx cy scale))
        (format "A ~a ~a 0 0 ~a ~a ~a" (fmt sr) (fmt sr) sweep x2 y2))))

(define (polygon-fill-svg verts depth sector cx cy scale)
  (define n   (length verts))
  (define p0s (z->screen (car verts) cx cy scale))
  (define segs (for/list ([i (in-range n)])
                 (arc-segment (list-ref verts i)
                              (list-ref verts (modulo (+ i 1) n))
                              cx cy scale)))
  (define d (string-append (format "M ~a ~a" (fmt (car p0s)) (fmt (cdr p0s)))
                            " " (string-join segs " ") " Z"))
  (format "  <path d=\"~a\" fill=\"~a\" stroke=\"none\"/>" d (tile-color depth sector)))

(define (polygon-stroke-svg verts depth cx cy scale)
  (define n   (length verts))
  (define p0s (z->screen (car verts) cx cy scale))
  (define segs (for/list ([i (in-range n)])
                 (arc-segment (list-ref verts i)
                              (list-ref verts (modulo (+ i 1) n))
                              cx cy scale)))
  (define d  (string-append (format "M ~a ~a" (fmt (car p0s)) (fmt (cdr p0s)))
                             " " (string-join segs " ") " Z"))
  (define sw (max 0.3 (- 1.2 (* depth 0.15))))
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\"/>"
          d STROKE-COLOR (fmt sw)))

(define (spokes-svg verts p cx cy scale)
  (define c  (tile-centroid verts p))
  (define cs (z->screen c cx cy scale))
  (define segs (for/list ([v verts])
                 (define vs (z->screen v cx cy scale))
                 (format "M ~a ~a L ~a ~a"
                         (fmt (car cs)) (fmt (cdr cs))
                         (fmt (car vs)) (fmt (cdr vs)))))
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"0.5\" stroke-opacity=\"0.7\"/>"
          (string-join segs " ") SPOKE-COLOR))

(define (motif-svg polylines cx cy scale)
  (define paths
    (for/list ([pl (in-list polylines)])
      (define fp (z->screen (car pl) cx cy scale))
      (define moves
        (string-join
         (for/list ([z (in-list (cdr pl))])
           (define ps (z->screen z cx cy scale))
           (format "L ~a ~a" (fmt (car ps)) (fmt (cdr ps))))
         " "))
      (format "M ~a ~a ~a" (fmt (car fp)) (fmt (cdr fp)) moves)))
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"1.4\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>"
          (string-join paths " ") STROKE-COLOR))

(define (write-svg! tiles p cx cy scale W H out)
  (define sorted (sort tiles > #:key second))
  (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\">\n" W H)
  (fprintf out "  <rect width=\"~a\" height=\"~a\" fill=\"~a\"/>\n" W H OUTER-COLOR)
  (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"~a\" stroke=\"none\"/>\n"
           (fmt cx) (fmt cy) (fmt scale) DISK-COLOR)
  ;; Pass 1: fills
  (for ([tile sorted])
    (fprintf out "~a\n" (polygon-fill-svg (first tile) (second tile) (third tile) cx cy scale)))
  ;; Pass 2: spokes (on top of fills, under outlines)
  (when (and (draw-spokes?) (not ACTIVE-MOTIF))
    (for ([tile tiles])
      (fprintf out "~a\n" (spokes-svg (first tile) p cx cy scale))))
  ;; Pass 2b: motifs
  (when ACTIVE-MOTIF
    (define motif-lines (ACTIVE-MOTIF p (tiling-q)))
    (for ([tile tiles])
      (fprintf out "~a\n" (motif-svg (warp-polylines motif-lines (fourth tile)) cx cy scale))))
  ;; Pass 3: outlines
  (for ([tile sorted])
    (fprintf out "~a\n" (polygon-stroke-svg (first tile) (second tile) cx cy scale)))
  (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"2\"/>\n"
           (fmt cx) (fmt cy) (fmt scale) STROKE-COLOR)
  (fprintf out "</svg>\n"))

;; ---- PNG output (racket/draw) ----

(define (hex->color hex)
  (make-object color%
    (string->number (substring hex 1 3) 16)
    (string->number (substring hex 3 5) 16)
    (string->number (substring hex 5 7) 16)))

;; Append a bezier-approximated geodesic arc from z1->z2 to a dc-path%.
;; Splits arcs > pi/2 into sub-arcs for accuracy.
(define (add-arc-to-path! path z1 z2 cx cy scale)
  (if (diameter? z1 z2)
      (let ([p2s (z->screen z2 cx cy scale)])
        (send path line-to (car p2s) (cdr p2s)))
      (let-values ([(c r) (geodesic-circle z1 z2)])
        (define a1   (angle (- z1 c)))
        (define a2   (angle (- z2 c)))
        (define diff (let ([d (- a2 a1)])
                       (cond [(> d pi)  (- d (* 2 pi))]
                             [(< d (- pi)) (+ d (* 2 pi))]
                             [else d])))
        (define N (max 1 (exact-ceiling (/ (abs diff) (/ pi 2)))))
        (for ([seg (in-range N)])
          (define ang0 (+ a1 (* (/ seg N) diff)))
          (define ang1 (+ a1 (* (/ (+ seg 1) N) diff)))
          (define dang (- ang1 ang0))
          ;; k = (4/3)*tan(dang/4) handles both CCW (dang>0) and CW (dang<0)
          (define k    (* (/ 4.0 3.0) (tan (/ dang 4))))
          (define q1   (+ c (make-polar r ang1)))
          ;; Bezier control points: offset by k*r in tangent direction (i * unit-radial)
          (define cp0  (+ (+ c (make-polar r ang0)) (* +i k r (make-polar 1 ang0))))
          (define cp1  (- (+ c (make-polar r ang1)) (* +i k r (make-polar 1 ang1))))
          (define sq1  (z->screen q1  cx cy scale))
          (define scp0 (z->screen cp0 cx cy scale))
          (define scp1 (z->screen cp1 cx cy scale))
          (send path curve-to
                (car scp0) (cdr scp0)
                (car scp1) (cdr scp1)
                (car sq1)  (cdr sq1))))))

(define (tile-dc-path verts cx cy scale)
  (define n    (length verts))
  (define path (new dc-path%))
  (define p0s  (z->screen (car verts) cx cy scale))
  (send path move-to (car p0s) (cdr p0s))
  (for ([i (in-range n)])
    (add-arc-to-path! path
                      (list-ref verts i)
                      (list-ref verts (modulo (+ i 1) n))
                      cx cy scale))
  (send path close)
  path)

(define (write-png! tiles p cx cy scale W H file)
  (define bm (make-object bitmap% W H))
  (define dc (new bitmap-dc% [bitmap bm]))
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))

  (send dc set-smoothing 'aligned)
  (send dc set-background (hex->color OUTER-COLOR))
  (send dc clear)

  ;; Background disk
  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color DISK-COLOR) 'solid))
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))

  ;; Pass 1: fills
  (send dc set-pen no-pen)
  (for ([tile (in-list (sort tiles > #:key second))])
    (send dc set-brush (make-object brush% (hex->color (tile-color (second tile) (third tile))) 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))

  ;; Pass 2: spokes (suppressed when motif is active)
  (when (and (draw-spokes?) (not ACTIVE-MOTIF))
    (send dc set-pen (make-object pen% (hex->color SPOKE-COLOR) 1 'solid))
    (send dc set-brush no-brush)
    (for ([tile (in-list tiles)])
      (define c  (tile-centroid (first tile) p))
      (define cs (z->screen c cx cy scale))
      (for ([v (first tile)])
        (define vs (z->screen v cx cy scale))
        (send dc draw-line (car cs) (cdr cs) (car vs) (cdr vs)))))

  ;; Pass 2b: motifs
  (when ACTIVE-MOTIF
    (define motif-lines (ACTIVE-MOTIF p (tiling-q)))
    (define motif-pen
      (new pen% [color (hex->color STROKE-COLOR)] [width 1.4] [style 'solid]
                [cap 'round] [join 'round]))
    (send dc set-pen motif-pen)
    (send dc set-brush no-brush)
    (for ([tile (in-list tiles)])
      (define warped (warp-polylines motif-lines (fourth tile)))
      (for ([pl (in-list warped)])
        (define pts (for/list ([z (in-list pl)]) (z->screen z cx cy scale)))
        (define path (new dc-path%))
        (send path move-to (car (car pts)) (cdr (car pts)))
        (for ([pt (in-list (cdr pts))])
          (send path line-to (car pt) (cdr pt)))
        (send dc draw-path path))))

  ;; Pass 3: outlines
  (send dc set-brush no-brush)
  (for ([tile (in-list (sort tiles > #:key second))])
    (define depth (second tile))
    (define sw    (max 0.3 (- 1.2 (* depth 0.15))))
    (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) sw 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))

  ;; Boundary circle
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 2 'solid))
  (send dc set-brush no-brush)
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))

  (send bm save-file file 'png))

;; ---- Main ----

(define W     (image-width))
(define H     (image-height))
(define cx    (/ W 2.0))
(define cy    (/ H 2.0))
(define scale (* 0.47 (min W H)))
(define p     (tiling-p))
(define q     (tiling-q))

(printf "Tessellating {~a,~a} to depth ~a...~n" p q (tiling-depth))
(define tiles (tessellate p q (tiling-depth)))
(printf "Generated ~a tiles.~n" (length tiles))

(define (render-to! filename tiles-for-frame)
  (cond
    [(string-suffix? filename ".png")
     (write-png! tiles-for-frame p cx cy scale W H filename)
     (void)]
    [else
     (call-with-output-file filename #:exists 'replace
       (lambda (out) (write-svg! tiles-for-frame p cx cy scale W H out)))]))

(cond
  [(animate-motion)
   (define n     (animate-frames))
   (define motion (animate-motion))
   (define turns (animate-turns))
   (define dist  (animate-dist))
   (define dir-rad (* (animate-dir) (/ pi 180)))
   (define dir (out-dir))
   (unless (directory-exists? dir) (make-directory* dir))
   (define digits (max 4 (string-length (number->string n))))
   (printf "Rendering ~a frames (~a) into ~a/~n" n motion dir)
   (for ([i (in-range n)])
     (define t (/ i (* 1.0 n)))
     (define-values (a b) (frame-mobius t motion turns dist dir-rad))
     (parameterize ([VIEW-A a] [VIEW-B b])
       (define transformed (transform-tiles-for-view tiles))
       (define frame-file
         (build-path dir
                     (format "frame_~a.png"
                             (~a (+ i 1) #:width digits #:align 'right #:pad-string "0"))))
       (render-to! (path->string frame-file) transformed)
       (printf "  frame ~a/~a~n" (+ i 1) n)))
   (printf "Done. ffmpeg tip:~n")
   (printf "  ffmpeg -framerate 30 -i ~a/frame_%0~ad.png -c:v libx264 -pix_fmt yuv420p out.mp4~n" dir digits)]
  [else
   (printf "Writing ~a...~n" (image-file))
   (render-to! (image-file) tiles)
   (printf "Done.~n")])
