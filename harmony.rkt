#! /usr/bin/env racket
#lang racket

(require "hyperbolic.rkt")
(require "palettes.rkt")
(require racket/draw)

(define (atanh x) (* 0.5 (log (/ (+ 1 x) (- 1 x)))))

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
(define model-name   (make-parameter "poincare"))
(define highlight-name (make-parameter #f))    ; #f or "fundamental"
(define label-gens?    (make-parameter #f))
(define animate-motion   (make-parameter #f))    ; #f, "rotate", "translate", "both"
(define animate-frames   (make-parameter 60))
(define animate-turns    (make-parameter 1.0))
(define animate-dist     (make-parameter 0.7))
(define animate-dir      (make-parameter 0.0))   ; degrees
(define out-dir          (make-parameter "frames"))
(define dpi              (make-parameter 96))
(define bleed-inches     (make-parameter 0.0))
(define pan-spec         (make-parameter #f))   ; "REAL,IMAG" string or #f

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
 [("--model") NAME "Projection model: poincare, klein, halfplane, band"
  (model-name NAME)]
 [("--highlight") NAME "Educational: dim everything except NAME. Values: fundamental"
  (highlight-name NAME)]
 [("--label-generators") "Number the p sides of the fundamental polygon 1..p"
  (label-gens? #t)]
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
 [("--dpi") N "Output resolution in pixels-per-inch for PNG (default 96)"
  (dpi (string->number N))]
 [("--bleed") IN "Print bleed in inches on each side (default 0)"
  (bleed-inches (string->number IN))]
 [("--pan") RE-IM "Pan center to disk coord REAL,IMAG before rendering (e.g. 0.3,-0.1)"
  (pan-spec RE-IM)]
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

(define VALID-MODELS '("poincare" "klein" "halfplane" "band"))

(unless (member (model-name) VALID-MODELS)
  (eprintf "Unknown model '~a'. Available: ~a~n"
           (model-name)
           (string-join VALID-MODELS ", "))
  (exit 1))

(define VALID-HIGHLIGHTS '("fundamental"))

(when (highlight-name)
  (unless (member (highlight-name) VALID-HIGHLIGHTS)
    (eprintf "Unknown highlight '~a'. Available: ~a~n"
             (highlight-name)
             (string-join VALID-HIGHLIGHTS ", "))
    (exit 1)))

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

;; ---- Model projection ----
;; All geometry is computed in the Poincaré disk. `to-model` projects a
;; Poincaré point into the currently-selected model's coordinate system.
(define (to-model z)
  (case (model-name)
    [("poincare")  z]
    [("klein")     (/ (* 2 z) (+ 1 (sqr (magnitude z))))]
    [("halfplane") (* +i (/ (+ 1 z) (- 1 z)))]
    [("band")      (- (log (* +i (/ (+ 1 z) (- 1 z)))) (* +i (/ pi 2)))]))

;; view-apply = Möbius view transform then model projection.
(define (view-apply z) (to-model (mobius-apply (VIEW-A) (VIEW-B) z)))

;; Warp every point of every polyline using this tile's reflection axes,
;; then apply the current view transform.
(define (warp-polylines polylines axes)
  (for/list ([pl (in-list polylines)])
    (for/list ([z (in-list pl)])
      (view-apply (warp-point z axes)))))

;; Precompute a full tile list with vertices already pushed through the
;; current view transform (Möbius + model projection). Axes are left
;; original — motif rendering runs through warp-point on the originals and
;; then re-applies view-apply.
(define (transform-tiles-for-view tiles)
  (cond
    [(and (= (VIEW-A) 1) (= (VIEW-B) 0) (equal? (model-name) "poincare"))
     tiles]
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

;; UHP: given two points z1, z2 in the upper half-plane, geodesics are either
;; a vertical line (if real parts match) or the upper arc of a circle whose
;; center lies on the real axis. Returns (values c r vertical?) where c is
;; complex-valued (imaginary part is 0 when vertical? is #f).
(define (uhp-geodesic z1 z2)
  (define x1 (real-part z1)) (define y1 (imag-part z1))
  (define x2 (real-part z2)) (define y2 (imag-part z2))
  (cond
    [(< (abs (- x1 x2)) 1e-9)
     (values 0 0 #t)]
    [else
     (define cr (/ (- (+ (sqr x2) (sqr y2)) (+ (sqr x1) (sqr y1)))
                   (* 2 (- x2 x1))))
     (define r  (sqrt (+ (sqr (- x1 cr)) (sqr y1))))
     (values (make-rectangular cr 0) r #f)]))

;; Undo the band projection back into UHP so we can walk along a UHP
;; geodesic and re-project each sample.
(define (band->uhp w) (exp (+ w (* +i (/ pi 2)))))

(define (arc-segment z1 z2 cx cy scale)
  (case (model-name)
    [("klein")     (arc-segment-line z2 cx cy scale)]
    [("halfplane") (arc-segment-uhp  z1 z2 cx cy scale)]
    [("band")      (arc-segment-band z1 z2 cx cy scale)]
    [else          (arc-segment-poincare z1 z2 cx cy scale)]))

(define (arc-segment-line z2 cx cy scale)
  (define p2s (z->screen z2 cx cy scale))
  (format "L ~a ~a" (fmt (car p2s)) (fmt (cdr p2s))))

(define (arc-segment-poincare z1 z2 cx cy scale)
  (define p2s (z->screen z2 cx cy scale))
  (define x2  (fmt (car p2s)))
  (define y2  (fmt (cdr p2s)))
  (if (diameter? z1 z2)
      (format "L ~a ~a" x2 y2)
      (let-values ([(c r) (geodesic-circle z1 z2)])
        (define sr    (* scale r))
        (define sweep (arc-sweep-flag z1 z2 c r cx cy scale))
        (format "A ~a ~a 0 0 ~a ~a ~a" (fmt sr) (fmt sr) sweep x2 y2))))

(define (arc-segment-uhp z1 z2 cx cy scale)
  (define p2s (z->screen z2 cx cy scale))
  (define x2s (fmt (car p2s)))
  (define y2s (fmt (cdr p2s)))
  (define-values (c r vert?) (uhp-geodesic z1 z2))
  (cond
    [vert? (format "L ~a ~a" x2s y2s)]
    [else
     (define sr    (* scale r))
     (define sweep (arc-sweep-flag z1 z2 c r cx cy scale))
     (format "A ~a ~a 0 0 ~a ~a ~a" (fmt sr) (fmt sr) sweep x2s y2s)]))

(define (arc-segment-band z1 z2 cx cy scale)
  ;; Walk the geodesic in UHP, project each sample back to band coords.
  (define uz1 (band->uhp z1))
  (define uz2 (band->uhp z2))
  (define-values (c r vert?) (uhp-geodesic uz1 uz2))
  (define N 16)
  (cond
    [vert?
     ;; Rare case: vertical line in UHP → curved line in band.
     (define y1 (imag-part uz1))
     (define y2 (imag-part uz2))
     (define x0 (real-part uz1))
     (string-join
      (for/list ([i (in-range 1 (+ N 1))])
        (define t (/ i (* 1.0 N)))
        (define uhp-pt (make-rectangular x0 (+ y1 (* (- y2 y1) t))))
        (define band-pt (- (log uhp-pt) (* +i (/ pi 2))))
        (define ps (z->screen band-pt cx cy scale))
        (format "L ~a ~a" (fmt (car ps)) (fmt (cdr ps))))
      " ")]
    [else
     (define cr (real-part c))
     (define a1 (angle (make-rectangular (- (real-part uz1) cr) (imag-part uz1))))
     (define a2 (angle (make-rectangular (- (real-part uz2) cr) (imag-part uz2))))
     (define diff (- a2 a1))
     (string-join
      (for/list ([i (in-range 1 (+ N 1))])
        (define t (/ i (* 1.0 N)))
        (define theta (+ a1 (* diff t)))
        (define uhp-pt (+ cr (* r (make-polar 1 theta))))
        (define band-pt (- (log uhp-pt) (* +i (/ pi 2))))
        (define ps (z->screen band-pt cx cy scale))
        (format "L ~a ~a" (fmt (car ps)) (fmt (cdr ps))))
      " ")]))

(define DIM-OPACITY 0.22)

(define (tile-opacity depth)
  (cond
    [(and (equal? (highlight-name) "fundamental") (> depth 0)) DIM-OPACITY]
    [else 1.0]))

(define (polygon-fill-svg verts depth sector cx cy scale)
  (define n   (length verts))
  (define p0s (z->screen (car verts) cx cy scale))
  (define segs (for/list ([i (in-range n)])
                 (arc-segment (list-ref verts i)
                              (list-ref verts (modulo (+ i 1) n))
                              cx cy scale)))
  (define d (string-append (format "M ~a ~a" (fmt (car p0s)) (fmt (cdr p0s)))
                            " " (string-join segs " ") " Z"))
  (define op (tile-opacity depth))
  (if (= op 1.0)
      (format "  <path d=\"~a\" fill=\"~a\" stroke=\"none\"/>" d (tile-color depth sector))
      (format "  <path d=\"~a\" fill=\"~a\" fill-opacity=\"~a\" stroke=\"none\"/>"
              d (tile-color depth sector) (fmt op))))

(define (polygon-stroke-svg verts depth cx cy scale)
  (define n   (length verts))
  (define p0s (z->screen (car verts) cx cy scale))
  (define segs (for/list ([i (in-range n)])
                 (arc-segment (list-ref verts i)
                              (list-ref verts (modulo (+ i 1) n))
                              cx cy scale)))
  (define d  (string-append (format "M ~a ~a" (fmt (car p0s)) (fmt (cdr p0s)))
                             " " (string-join segs " ") " Z"))
  (define sw (* STROKE-SCALE (max 0.3 (- 1.2 (* depth 0.15)))))
  (define op (tile-opacity depth))
  (if (= op 1.0)
      (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\"/>"
              d STROKE-COLOR (fmt sw))
      (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\" stroke-opacity=\"~a\"/>"
              d STROKE-COLOR (fmt sw) (fmt op))))

(define (spokes-svg verts p cx cy scale)
  (define c  (tile-centroid verts p))
  (define cs (z->screen c cx cy scale))
  (define segs (for/list ([v verts])
                 (define vs (z->screen v cx cy scale))
                 (format "M ~a ~a L ~a ~a"
                         (fmt (car cs)) (fmt (cdr cs))
                         (fmt (car vs)) (fmt (cdr vs)))))
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\" stroke-opacity=\"0.7\"/>"
          (string-join segs " ") SPOKE-COLOR (fmt (* STROKE-SCALE 0.5))))

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
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>"
          (string-join paths " ") STROKE-COLOR (fmt (* STROKE-SCALE 1.4))))

(define (model-background-svg! out cx cy scale W H)
  (case (model-name)
    [("poincare" "klein")
     (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"~a\" stroke=\"none\"/>~n"
              (fmt cx) (fmt cy) (fmt scale) DISK-COLOR)]
    [("halfplane")
     ;; Fill the upper half-plane region (above real axis) with DISK-COLOR.
     (fprintf out "  <rect x=\"0\" y=\"0\" width=\"~a\" height=\"~a\" fill=\"~a\"/>~n"
              W (fmt cy) DISK-COLOR)]
    [("band")
     (define y-top (- cy (* scale (/ pi 2))))
     (define y-bot (+ cy (* scale (/ pi 2))))
     (fprintf out "  <rect x=\"0\" y=\"~a\" width=\"~a\" height=\"~a\" fill=\"~a\"/>~n"
              (fmt y-top) W (fmt (- y-bot y-top)) DISK-COLOR)]))

(define (model-boundary-svg! out cx cy scale W H)
  (define bw (fmt (* STROKE-SCALE 2)))
  (case (model-name)
    [("poincare" "klein")
     (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"~a\"/>~n"
              (fmt cx) (fmt cy) (fmt scale) STROKE-COLOR bw)]
    [("halfplane")
     (fprintf out "  <line x1=\"0\" y1=\"~a\" x2=\"~a\" y2=\"~a\" stroke=\"~a\" stroke-width=\"~a\"/>~n"
              (fmt cy) W (fmt cy) STROKE-COLOR bw)]
    [("band")
     (define y-top (- cy (* scale (/ pi 2))))
     (define y-bot (+ cy (* scale (/ pi 2))))
     (fprintf out "  <line x1=\"0\" y1=\"~a\" x2=\"~a\" y2=\"~a\" stroke=\"~a\" stroke-width=\"~a\"/>~n"
              (fmt y-top) W (fmt y-top) STROKE-COLOR bw)
     (fprintf out "  <line x1=\"0\" y1=\"~a\" x2=\"~a\" y2=\"~a\" stroke=\"~a\" stroke-width=\"~a\"/>~n"
              (fmt y-bot) W (fmt y-bot) STROKE-COLOR bw)]))

;; Returns a list of (label-string . (screen-x . screen-y)) for the
;; fundamental polygon's sides in the current view. Label i is placed near
;; side i, offset from the side's Euclidean midpoint toward the tile
;; centroid so the number sits just inside the tile.
(define (generator-label-positions tiles p cx cy scale)
  (define fund (findf (lambda (t) (= 0 (second t))) tiles))
  (cond
    [(not fund) '()]
    [else
     (define verts (first fund))
     (define centroid (/ (apply + verts) p))
     (for/list ([i (in-range p)])
       (define v1  (list-ref verts i))
       (define v2  (list-ref verts (modulo (+ i 1) p)))
       (define mid (/ (+ v1 v2) 2))
       (define pos (+ (* 0.78 mid) (* 0.22 centroid)))
       (define ps  (z->screen pos cx cy scale))
       (cons (number->string (+ i 1)) ps))]))

(define (label-font-size scale)
  (max 12 (min 40 (inexact->exact (round (* scale 0.055))))))

(define (write-svg! tiles p cx cy scale W H out)
  (define sorted (sort tiles > #:key second))
  (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\">\n" W H)
  (fprintf out "  <rect width=\"~a\" height=\"~a\" fill=\"~a\"/>\n" W H OUTER-COLOR)
  (model-background-svg! out cx cy scale W H)
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
  (model-boundary-svg! out cx cy scale W H)
  ;; Pass 4: generator labels
  (when (label-gens?)
    (define fs (label-font-size scale))
    (for ([lbl (in-list (generator-label-positions tiles p cx cy scale))])
      (fprintf out "  <text x=\"~a\" y=\"~a\" font-family=\"sans-serif\" font-size=\"~a\" font-weight=\"bold\" fill=\"~a\" text-anchor=\"middle\" dominant-baseline=\"central\">~a</text>~n"
               (fmt (cadr lbl)) (fmt (cddr lbl)) fs STROKE-COLOR (car lbl))))
  (fprintf out "</svg>\n"))

;; ---- PNG output (racket/draw) ----

(define (hex->color hex)
  (make-object color%
    (string->number (substring hex 1 3) 16)
    (string->number (substring hex 3 5) 16)
    (string->number (substring hex 5 7) 16)))

;; Append the geodesic from z1 to z2 (in the current model's coordinates)
;; to a dc-path%. Poincaré and UHP use Bézier-approximated circular arcs;
;; Klein is a straight line; band walks the UHP geodesic and re-projects.
(define (add-arc-to-path! path z1 z2 cx cy scale)
  (case (model-name)
    [("klein")     (add-line-to-path! path z2 cx cy scale)]
    [("halfplane") (add-uhp-arc-to-path! path z1 z2 cx cy scale)]
    [("band")      (add-band-arc-to-path! path z1 z2 cx cy scale)]
    [else          (add-poincare-arc-to-path! path z1 z2 cx cy scale)]))

(define (add-line-to-path! path z2 cx cy scale)
  (define p2s (z->screen z2 cx cy scale))
  (send path line-to (car p2s) (cdr p2s)))

;; Bézier-approximate the arc of a circle (c, r) from z1 to z2.
;; Splits arcs > π/2 into sub-arcs for accuracy.
(define (bezier-arc-onto! path c r z1 z2 cx cy scale)
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
    (define k    (* (/ 4.0 3.0) (tan (/ dang 4))))
    (define q1   (+ c (make-polar r ang1)))
    (define cp0  (+ (+ c (make-polar r ang0)) (* +i k r (make-polar 1 ang0))))
    (define cp1  (- (+ c (make-polar r ang1)) (* +i k r (make-polar 1 ang1))))
    (define sq1  (z->screen q1  cx cy scale))
    (define scp0 (z->screen cp0 cx cy scale))
    (define scp1 (z->screen cp1 cx cy scale))
    (send path curve-to
          (car scp0) (cdr scp0)
          (car scp1) (cdr scp1)
          (car sq1)  (cdr sq1))))

(define (add-poincare-arc-to-path! path z1 z2 cx cy scale)
  (if (diameter? z1 z2)
      (add-line-to-path! path z2 cx cy scale)
      (let-values ([(c r) (geodesic-circle z1 z2)])
        (bezier-arc-onto! path c r z1 z2 cx cy scale))))

(define (add-uhp-arc-to-path! path z1 z2 cx cy scale)
  (define-values (c r vert?) (uhp-geodesic z1 z2))
  (if vert?
      (add-line-to-path! path z2 cx cy scale)
      (bezier-arc-onto! path c r z1 z2 cx cy scale)))

(define (add-band-arc-to-path! path z1 z2 cx cy scale)
  (define uz1 (band->uhp z1))
  (define uz2 (band->uhp z2))
  (define-values (c r vert?) (uhp-geodesic uz1 uz2))
  (define N 16)
  (define (emit! t-max)
    (define x0 (real-part uz1))
    (define y1 (imag-part uz1))
    (define y2 (imag-part uz2))
    (for ([i (in-range 1 (+ N 1))])
      (define t (/ i (* 1.0 N)))
      (define uhp-pt (make-rectangular x0 (+ y1 (* (- y2 y1) t))))
      (define band-pt (- (log uhp-pt) (* +i (/ pi 2))))
      (define ps (z->screen band-pt cx cy scale))
      (send path line-to (car ps) (cdr ps))))
  (cond
    [vert? (emit! 1)]
    [else
     (define cr (real-part c))
     (define a1 (angle (make-rectangular (- (real-part uz1) cr) (imag-part uz1))))
     (define a2 (angle (make-rectangular (- (real-part uz2) cr) (imag-part uz2))))
     (define diff (- a2 a1))
     (for ([i (in-range 1 (+ N 1))])
       (define t (/ i (* 1.0 N)))
       (define theta (+ a1 (* diff t)))
       (define uhp-pt (+ cr (* r (make-polar 1 theta))))
       (define band-pt (- (log uhp-pt) (* +i (/ pi 2))))
       (define ps (z->screen band-pt cx cy scale))
       (send path line-to (car ps) (cdr ps)))]))

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

;; Shared drawing routine for any dc<%> (bitmap-dc% or pdf-dc%). The dc is
;; expected to be freshly-configured (any prior content is cleared for raster
;; targets via set-background/clear at the start).
(define (draw-tessellation! dc tiles p cx cy scale W H)
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))

  (send dc set-smoothing 'aligned)
  ;; Clear to OUTER-COLOR. For pdf-dc%, set-background/clear is a no-op,
  ;; so we paint a full-canvas rectangle instead.
  (send dc set-background (hex->color OUTER-COLOR))
  (send dc clear)
  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color OUTER-COLOR) 'solid))
  (send dc draw-rectangle 0 0 W H)

  ;; Model-specific background: fills the visible model region with DISK-COLOR.
  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color DISK-COLOR) 'solid))
  (case (model-name)
    [("poincare" "klein")
     (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))]
    [("halfplane")
     (send dc draw-rectangle 0 0 W cy)]
    [("band")
     (define y-top (- cy (* scale (/ pi 2))))
     (define y-bot (+ cy (* scale (/ pi 2))))
     (send dc draw-rectangle 0 y-top W (- y-bot y-top))])

  ;; Pass 1: fills
  (send dc set-pen no-pen)
  (for ([tile (in-list (sort tiles > #:key second))])
    (send dc set-alpha (tile-opacity (second tile)))
    (send dc set-brush (make-object brush% (hex->color (tile-color (second tile) (third tile))) 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))
  (send dc set-alpha 1.0)

  ;; Pass 2: spokes (suppressed when motif is active)
  (when (and (draw-spokes?) (not ACTIVE-MOTIF))
    (send dc set-pen (make-object pen% (hex->color SPOKE-COLOR) (* STROKE-SCALE 1) 'solid))
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
      (new pen% [color (hex->color STROKE-COLOR)] [width (* STROKE-SCALE 1.4)] [style 'solid]
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
    (define sw    (* STROKE-SCALE (max 0.3 (- 1.2 (* depth 0.15)))))
    (send dc set-alpha (tile-opacity depth))
    (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) sw 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))
  (send dc set-alpha 1.0)

  ;; Boundary
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) (* STROKE-SCALE 2) 'solid))
  (send dc set-brush no-brush)
  (case (model-name)
    [("poincare" "klein")
     (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))]
    [("halfplane")
     (send dc draw-line 0 cy W cy)]
    [("band")
     (define y-top (- cy (* scale (/ pi 2))))
     (define y-bot (+ cy (* scale (/ pi 2))))
     (send dc draw-line 0 y-top W y-top)
     (send dc draw-line 0 y-bot W y-bot)])

  ;; Generator labels
  (when (label-gens?)
    (define fs (label-font-size scale))
    (define fnt (make-font #:size fs #:family 'swiss #:weight 'bold))
    (send dc set-font fnt)
    (send dc set-text-foreground (hex->color STROKE-COLOR))
    (for ([lbl (in-list (generator-label-positions tiles p cx cy scale))])
      (define s (car lbl))
      (define-values (tw th td ta) (send dc get-text-extent s fnt))
      (send dc draw-text s
            (- (cadr lbl) (/ tw 2))
            (- (cddr lbl) (/ th 2))))))

(define (write-png! tiles p cx cy scale W H file)
  (define bm (make-object bitmap%
               (inexact->exact (ceiling W))
               (inexact->exact (ceiling H))))
  (define dc (new bitmap-dc% [bitmap bm]))
  (draw-tessellation! dc tiles p cx cy scale W H)
  (send bm save-file file 'png))

(define (write-pdf! tiles p cx cy scale W H file)
  ;; racket/draw's pdf-dc% draws with 1 unit = 1/96 inch, but the constructor's
  ;; width/height are in points (1/72 inch), so the page size is W * 72/96.
  (define dc (new pdf-dc%
                  [interactive #f]
                  [use-paper-bbox #f]
                  [width  (* W 72/96)]
                  [height (* H 72/96)]
                  [output file]))
  (send dc start-doc "harmony")
  (send dc start-page)
  (draw-tessellation! dc tiles p cx cy scale W H)
  (send dc end-page)
  (send dc end-doc))

;; ---- Main ----

;; Detect the target output format from the file extension.
(define OUTPUT-FMT
  (cond
    [(string-suffix? (image-file) ".pdf") 'pdf]
    [(string-suffix? (image-file) ".png") 'png]
    [else                                  'svg]))

;; All drawing is done in "logical pixels at 96 DPI". PNG scales those up
;; to real pixels for high-DPI output. SVG and PDF stay in logical units:
;; SVG is vector and viewers pick their own DPI; racket/draw's pdf-dc%
;; already treats drawing coordinates as 1/96 inch (converts to points at
;; the page level via 72/96 = 0.75).
(define DPI-SCALE (/ (dpi) 96.0))

(define OUTPUT-COORD-SCALE
  (case OUTPUT-FMT
    [(png) DPI-SCALE]
    [else  1.0]))

(define STROKE-SCALE OUTPUT-COORD-SCALE)

(define TRIM-W   (* (image-width)  OUTPUT-COORD-SCALE))
(define TRIM-H   (* (image-height) OUTPUT-COORD-SCALE))
(define BLEED-PX (* (bleed-inches) 96 OUTPUT-COORD-SCALE))
(define W        (+ TRIM-W (* 2 BLEED-PX)))
(define H        (+ TRIM-H (* 2 BLEED-PX)))

;; Per-model viewport. cx, cy is the canvas-space point where the model
;; origin lands. scale is model-units-per-canvas-unit. The tessellation is
;; sized to the TRIM area and centred within the (possibly bleeded) CANVAS
;; so the model boundary sits at the trim line.
(define-values (cx cy scale)
  (case (model-name)
    [("poincare" "klein")
     (values (/ W 2.0) (/ H 2.0) (* 0.47 (min TRIM-W TRIM-H)))]
    [("halfplane")
     ;; Real ∈ [-2.5, 2.5], Imag ∈ [0, 4.5]. Place real axis near trim bottom.
     (define s  (min (/ TRIM-W 5.5) (/ TRIM-H 5.0)))
     (values (/ W 2.0) (- H BLEED-PX (* 0.08 TRIM-H)) s)]
    [("band")
     ;; Real ∈ [-π, π], Imag ∈ [-π/2, π/2]. Centred.
     (define s (min (/ TRIM-W (* 2.1 pi)) (/ TRIM-H (* 1.05 pi))))
     (values (/ W 2.0) (/ H 2.0) s)]))
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
    [(string-suffix? filename ".pdf")
     (write-pdf! tiles-for-frame p cx cy scale W H filename)
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
   ;; If --pan REAL,IMAG was given, set the view Möbius so the given
   ;; disk point ends up at visual centre.
   (define-values (pan-a pan-b)
     (cond
       [(pan-spec) =>
        (lambda (spec)
          (define parts (string-split spec ","))
          (unless (= (length parts) 2)
            (eprintf "--pan expects REAL,IMAG (got ~a)~n" spec)
            (exit 1))
          (define c (make-rectangular (string->number (first parts))
                                      (string->number (second parts))))
          (define c-mag (magnitude c))
          (cond
            [(< c-mag 1e-12) (values 1 0)]
            [else
             (define d-mag (* 2 (atanh (min 0.9999999 c-mag))))
             (define theta (angle c))
             (values (cosh (/ d-mag 2))
                     (- (* (sinh (/ d-mag 2)) (make-polar 1 theta))))]))]
       [else (values 1 0)]))
   (printf "Writing ~a...~n" (image-file))
   (parameterize ([VIEW-A pan-a] [VIEW-B pan-b])
     (render-to! (image-file) (transform-tiles-for-view tiles)))
   (printf "Done.~n")])
