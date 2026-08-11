#! /usr/bin/env racket
#lang racket/gui

;; sphere.rkt — Möbius rotation of a {p,q} tessellation.
;;
;; This is a 2D viewer whose transformation is BROADER than the
;; hyperbolic isometry group. The "sphere" is a mechanism, not a view:
;;
;;   1. Lift each Poincaré-disk vertex (x, y) to the upper hemisphere
;;      via (x, y, +√(1 − x² − y²)), then mirror to fill the lower
;;      hemisphere. The result is a tessellated 2-sphere in ℝ³ — the
;;      Riemann sphere with the tessellation drawn on it.
;;   2. Apply a 3D rotation to that sphere (mouse drag controls this).
;;   3. Project stereographically from the south pole back to the
;;      extended plane. The tessellation reappears as a 2D image.
;;
;; Because stereographic projection turns 3D sphere rotations into
;; Möbius transformations of the extended plane, dragging the "sphere"
;; applies Möbius maps to the 2D tessellation — including maps that do
;; NOT preserve the unit disk. Tiles carry from the interior to the
;; exterior of the disk and vice versa.
;;
;; The vertical-axis rotations (drag horizontally) are exactly the
;; hyperbolic rotations of the Poincaré disk. Everything else is new.
;;
;; See "Möbius Transformations Revealed" (Arnold–Rogness, 2007).

(require racket/draw)
(require "hyperbolic.rkt")
(require "palettes.rkt")

;; ---- CLI ----

(define cli-p (make-parameter 7))
(define cli-q (make-parameter 3))
(define cli-depth (make-parameter 6))
(define cli-palette (make-parameter "harmony"))
(define cli-size (make-parameter 800))
(define cli-snapshot (make-parameter #f))
(define cli-y-turns (make-parameter 0.0))
(define cli-x-turns (make-parameter 0.0))
(define cli-animate (make-parameter #f))
(define cli-frames (make-parameter 60))
(define cli-out-dir (make-parameter "frames"))

(command-line
 #:usage-help "Roll a {p,q} tessellation on the Riemann sphere"
 #:once-each
 [("-p") P "Polygon sides (default 7)"
  (cli-p (string->number P))]
 [("-q") Q "Polygons meeting at each vertex (default 3)"
  (cli-q (string->number Q))]
 [("--depth") D "BFS depth (default 6; tiles are doubled by the mirror step)"
  (cli-depth (string->number D))]
 [("--palette") NAME "Palette name (default harmony)"
  (cli-palette NAME)]
 [("--size") N "Window size in pixels (default 800)"
  (cli-size (string->number N))]
 [("--snapshot") FILE "Render one PNG and exit (no window)"
  (cli-snapshot FILE)]
 [("--y-turns") T "Initial rotation around vertical (Y) axis, in full turns"
  (cli-y-turns (string->number T))]
 [("--x-turns") T "Initial rotation around horizontal (X) axis, in full turns"
  (cli-x-turns (string->number T))]
 [("--animate") AXIS "Emit frames of a full-loop rotation: 'y', 'x', or 'both'"
  (cli-animate AXIS)]
 [("--frames") N "Frames per loop (default 60)"
  (cli-frames (string->number N))]
 [("--out-dir") D "Directory for animation frames (default 'frames')"
  (cli-out-dir D)]
 #:args () (void))

(unless (> (* (- (cli-p) 2) (- (cli-q) 2)) 4)
  (eprintf "{~a,~a} is not hyperbolic; sphere viewer requires (p-2)(q-2) > 4~n"
           (cli-p) (cli-q))
  (exit 1))

;; ---- State ----

(define STATE-P     (cli-p))
(define STATE-Q     (cli-q))
(define STATE-DEPTH (cli-depth))
(define STATE-ZOOM  1.0)
(define STATE-PALETTE-NAME (cli-palette))

;; 3×3 rotation matrix, stored as a vector of three 3-vectors. The identity
;; matrix; --y-turns / --x-turns override it below once the rot-x / rot-y
;; helpers are defined.
(define STATE-ROTATION (vector (vector 1.0 0.0 0.0)
                               (vector 0.0 1.0 0.0)
                               (vector 0.0 0.0 1.0)))

(define STATE-SPHERE-TILES '())  ; list of (verts3d depth sector hemisphere)

(define ACTIVE-PALETTE (lookup-palette STATE-PALETTE-NAME))
(define CENTER-COLOR (palette-center ACTIVE-PALETTE))
(define STROKE-COLOR (palette-stroke ACTIVE-PALETTE))
(define DISK-COLOR   (palette-disk   ACTIVE-PALETTE))
(define OUTER-COLOR  (palette-outer  ACTIVE-PALETTE))

(define (set-palette! name)
  (set! STATE-PALETTE-NAME name)
  (set! ACTIVE-PALETTE (lookup-palette name))
  (set! CENTER-COLOR (palette-center ACTIVE-PALETTE))
  (set! STROKE-COLOR (palette-stroke ACTIVE-PALETTE))
  (set! DISK-COLOR   (palette-disk   ACTIVE-PALETTE))
  (set! OUTER-COLOR  (palette-outer  ACTIVE-PALETTE)))

(define PALETTE-CYCLE '("harmony" "sunset" "ocean" "forest" "mono"
                        "autumn" "frost" "berry"))

(define (cycle-palette!)
  (define idx (or (index-of PALETTE-CYCLE STATE-PALETTE-NAME) -1))
  (define next (list-ref PALETTE-CYCLE (modulo (+ idx 1) (length PALETTE-CYCLE))))
  (set-palette! next)
  (printf "palette: ~a~n" next))

(define (tile-color depth sector)
  (if (= sector -1)
      CENTER-COLOR
      (let* ([families (palette-families ACTIVE-PALETTE)]
             [family   (modulo sector 3)]
             [pal      (vector-ref families family)]
             [idx      (min (max 0 depth) (- (vector-length pal) 1))])
        (vector-ref pal idx))))

(define (hex->color hex)
  (make-object color%
    (string->number (substring hex 1 3) 16)
    (string->number (substring hex 3 5) 16)
    (string->number (substring hex 5 7) 16)))

;; ---- Lift Poincaré to sphere ----

;; Inverse stereographic lift. Chosen so that lift-then-project (below)
;; is the identity for the upper hemisphere — that way, at zero rotation,
;; the on-screen image IS the Poincaré tessellation. The lower hemisphere
;; (sign = −1) is the mirror, which projects to the inversion of the disk
;; in the unit circle.
(define (lift-vertex v sign)
  (define x (real-part v))
  (define y (imag-part v))
  (define r2 (+ (sqr x) (sqr y)))
  (define denom (+ 1 r2))
  (vector (/ (* 2 x) denom)
          (/ (* 2 y) denom)
          (* sign (/ (- 1 r2) denom))))

;; Interpolate a point on the sphere between v1 and v2 at parameter t.
;; Linear interpolation between two unit-sphere points, renormalised. For
;; small angles this closely approximates true spherical interpolation.
(define (interp-sphere v1 v2 t)
  (define x (+ (* (- 1 t) (vector-ref v1 0)) (* t (vector-ref v2 0))))
  (define y (+ (* (- 1 t) (vector-ref v1 1)) (* t (vector-ref v2 1))))
  (define z (+ (* (- 1 t) (vector-ref v1 2)) (* t (vector-ref v2 2))))
  (define mag (sqrt (+ (sqr x) (sqr y) (sqr z))))
  (cond
    [(< mag 1e-9) v1]
    [else (vector (/ x mag) (/ y mag) (/ z mag))]))

;; How many sub-vertices per original tile edge. The projected polygon is
;; then a many-sided approximation of the true curved boundary, which lets
;; tiles near the projection pole be drawn correctly (each sub-vertex
;; projects to a bounded point, connecting them traces the actual arc).
;; Higher values reduce the sub-pixel mismatch between adjacent tiles'
;; polygonal approximations — that mismatch was the main source of colour
;; flicker as tiles rotated past each other.
(define EDGE-SUBDIVISION 12)

(define (subdivide-edges base-verts)
  (define count (length base-verts))
  (apply append
         (for/list ([i (in-range count)])
           (define v0 (list-ref base-verts i))
           (define v1 (list-ref base-verts (modulo (+ i 1) count)))
           (for/list ([j (in-range EDGE-SUBDIVISION)])
             (define t (/ j (* 1.0 EDGE-SUBDIVISION)))
             (interp-sphere v0 v1 t)))))

(define (regen-tiles!)
  (define disk-tiles (tessellate STATE-P STATE-Q STATE-DEPTH))
  (define (lift-tile tile sign hemisphere)
    (define base (map (lambda (v) (lift-vertex v sign)) (first tile)))
    (define subdiv (subdivide-edges base))
    (list subdiv
          (second tile)
          (third tile)
          hemisphere))
  (set! STATE-SPHERE-TILES
        (append
         (for/list ([t (in-list disk-tiles)]) (lift-tile t +1 'upper))
         (for/list ([t (in-list disk-tiles)]) (lift-tile t -1 'lower))))
  (printf "sphere: ~a tiles × ~a sub-vertices~n"
          (length STATE-SPHERE-TILES) (* STATE-P EDGE-SUBDIVISION)))

(regen-tiles!)

;; ---- 3-D linear algebra ----

;; Matrix–vector multiply. m is a 3×3 (vector of 3-vectors); v is a 3-vector.
(define (mat-vec m v)
  (define (row i)
    (define r (vector-ref m i))
    (+ (* (vector-ref r 0) (vector-ref v 0))
       (* (vector-ref r 1) (vector-ref v 1))
       (* (vector-ref r 2) (vector-ref v 2))))
  (vector (row 0) (row 1) (row 2)))

;; 3×3 matrix multiply.
(define (mat-mul a b)
  (define (entry i j)
    (+ (* (vector-ref (vector-ref a i) 0) (vector-ref (vector-ref b 0) j))
       (* (vector-ref (vector-ref a i) 1) (vector-ref (vector-ref b 1) j))
       (* (vector-ref (vector-ref a i) 2) (vector-ref (vector-ref b 2) j))))
  (vector (vector (entry 0 0) (entry 0 1) (entry 0 2))
          (vector (entry 1 0) (entry 1 1) (entry 1 2))
          (vector (entry 2 0) (entry 2 1) (entry 2 2))))

(define (rot-x theta)
  (define c (cos theta)) (define s (sin theta))
  (vector (vector 1.0 0.0 0.0)
          (vector 0.0 c    (- s))
          (vector 0.0 s    c)))

(define (rot-y theta)
  (define c (cos theta)) (define s (sin theta))
  (vector (vector c    0.0 s)
          (vector 0.0  1.0 0.0)
          (vector (- s) 0.0 c)))

;; ---- Rendering ----

;; Stereographic projection from the south pole (0, 0, -1) to the equatorial
;; plane. Turns a sphere point into a 2D point in the extended plane; z = -1
;; blows up to infinity, so we floor the denominator so near-pole vertices
;; get very-large-but-finite coordinates instead of ∞. Adjacent-to-pole
;; tiles are then drawn as polygons that extend off the canvas — the parts
;; inside the window still trace correct boundary lines.
(define DENOM-FLOOR 1e-4)
(define VISIBLE-RADIUS 3.0)

(define (stereographic v3)
  (define z (vector-ref v3 2))
  (define denom (max (+ 1 z) DENOM-FLOOR))
  (cons (/ (vector-ref v3 0) denom)
        (/ (vector-ref v3 1) denom)))

;; Average of a tile's sub-vertex positions on the sphere. Used only to
;; identify which tile is currently nearest the projection pole — that
;; tile's polygonal representation in the plane is misleading (its
;; "interior" ought to be unbounded), so we skip it.
(define (sphere-centroid verts3d)
  (define n (length verts3d))
  (vector (/ (for/sum ([v (in-list verts3d)]) (vector-ref v 0)) n)
          (/ (for/sum ([v (in-list verts3d)]) (vector-ref v 1)) n)
          (/ (for/sum ([v (in-list verts3d)]) (vector-ref v 2)) n)))

(define (paint-canvas! dc W H)
  (define cx (/ W 2.0))
  (define cy (/ H 2.0))
  ;; Scale so that Poincaré's unit disk fills ~0.5 of the canvas, leaving
  ;; room outside to show tiles that Möbius-rotate to the disk exterior.
  (define scale (* STATE-ZOOM 0.32 (min W H)))
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))

  (send dc set-smoothing 'smoothed)
  ;; Canvas gets the palette's centre colour as a fixed neutral base.
  ;; It doesn't change with rotation → no colour popping in the
  ;; "outside" area of the visualisation.
  (send dc set-background (hex->color CENTER-COLOR))
  (send dc clear)

  ;; Find the tile whose rotated centroid is closest to the projection
  ;; pole. Its polygon in the plane is a bounded shape but its actual
  ;; topological region is unbounded — Cairo would fill the wrong region.
  ;; Skip it entirely; the neighbouring tiles' outlines already trace the
  ;; boundary of its region correctly, and the canvas colour fills the
  ;; interior.
  (define pole-tile
    (for/fold ([best #f] [best-dist +inf.0]
               #:result best)
              ([t (in-list STATE-SPHERE-TILES)])
      (define c (mat-vec STATE-ROTATION (sphere-centroid (first t))))
      (define d (+ (sqr (vector-ref c 0))
                   (sqr (vector-ref c 1))
                   (sqr (+ (vector-ref c 2) 1))))
      (if (< d best-dist) (values t d) (values best best-dist))))

  (define transformed
    (for/list ([t (in-list STATE-SPHERE-TILES)]
               #:when (not (eq? t pole-tile)))
      (define rotated (map (lambda (v) (mat-vec STATE-ROTATION v)) (first t)))
      (define projected (map stereographic rotated))
      (list projected (second t) (third t))))

  ;; Two conditions to draw a tile:
  ;;   (a) At least one vertex is within the visible radius.
  ;;   (b) NO vertex is absurdly far out (which would mean the tile is
  ;;       straddling the projection pole — its polygonal fill would blob
  ;;       across the whole canvas). Skipping such tiles removes the
  ;;       "washed-out" frames where a single degenerate polygon fills the
  ;;       screen with one color. The tessellation boundary in that region
  ;;       is still traced by neighboring tiles' outlines.
  (define MAX-VERTEX-MAG 15.0)
  (define (any-visible pts)
    (ormap (lambda (p) (< (+ (sqr (car p)) (sqr (cdr p))) (sqr VISIBLE-RADIUS))) pts))
  (define (any-runaway pts)
    (ormap (lambda (p) (> (+ (sqr (car p)) (sqr (cdr p))) (sqr MAX-VERTEX-MAG))) pts))
  (define visible
    (for/list ([t (in-list transformed)]
               #:when (and (any-visible (first t))
                           (not (any-runaway (first t)))))
      t))

  (define (p->pt p)
    (make-object point%
      (+ cx (* scale (car p)))
      (- cy (* scale (cdr p)))))

  (send dc set-pen no-pen)
  (for ([t (in-list visible)])
    (send dc set-brush
          (make-object brush% (hex->color (tile-color (second t) (third t))) 'solid))
    (send dc draw-polygon (map p->pt (first t))))

  (send dc set-brush no-brush)
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 0.6 'solid))
  (for ([t (in-list visible)])
    (send dc draw-polygon (map p->pt (first t)))))

;; ---- Interaction ----

;; Mouse drag rotates the sphere. Horizontal pixels → rotation about the
;; screen's vertical (Y) axis; vertical pixels → rotation about the screen's
;; horizontal (X) axis. Composed left, so the rotation feels like the
;; sphere is being physically pushed.
(define (rotate-by! dx dy scale)
  (define ax (* dy (/ 1.0 scale) 2.0))
  (define ay (* dx (/ 1.0 scale) 2.0))
  (define delta (mat-mul (rot-x ax) (rot-y ay)))
  (set! STATE-ROTATION (mat-mul delta STATE-ROTATION)))

(define (reset-view!)
  (set! STATE-ROTATION (vector (vector 1.0 0.0 0.0)
                               (vector 0.0 1.0 0.0)
                               (vector 0.0 0.0 1.0)))
  (set! STATE-ZOOM 1.0))

(define (zoom-by! factor)
  (set! STATE-ZOOM (max 0.2 (min 20.0 (* STATE-ZOOM factor)))))

(define (adjust-depth! delta)
  (define new-depth (max 0 (min 8 (+ STATE-DEPTH delta))))
  (unless (= new-depth STATE-DEPTH)
    (set! STATE-DEPTH new-depth)
    (regen-tiles!)))

(define (save-snapshot! W H)
  (define bm (make-object bitmap%
               (inexact->exact (ceiling W))
               (inexact->exact (ceiling H))))
  (define dc (new bitmap-dc% [bitmap bm]))
  (paint-canvas! dc W H)
  (define ts (number->string (current-seconds)))
  (define file (format "sphere-~a.png" ts))
  (send bm save-file file 'png)
  (printf "wrote ~a~n" file))

;; ---- GUI ----

(define sphere-canvas%
  (class canvas%
    (super-new)
    (inherit refresh get-dc get-client-size)

    (define drag? #f)
    (define drag-last-x 0)
    (define drag-last-y 0)

    (define/override (on-paint)
      (define-values (w h) (get-client-size))
      (paint-canvas! (get-dc) w h))

    (define/override (on-event ev)
      (define-values (w h) (get-client-size))
      (define scale (* STATE-ZOOM 0.45 (min w h)))
      (case (send ev get-event-type)
        [(left-down)
         (set! drag? #t)
         (set! drag-last-x (send ev get-x))
         (set! drag-last-y (send ev get-y))]
        [(left-up)
         (set! drag? #f)]
        [(motion)
         (when drag?
           (define x (send ev get-x))
           (define y (send ev get-y))
           (rotate-by! (- x drag-last-x) (- y drag-last-y) scale)
           (set! drag-last-x x)
           (set! drag-last-y y)
           (refresh))]))

    (define/override (on-char ev)
      (define-values (w h) (get-client-size))
      (case (send ev get-key-code)
        [(#\r)     (reset-view!) (refresh)]
        [(#\s)     (save-snapshot! w h)]
        [(#\+ #\=) (adjust-depth! +1) (refresh)]
        [(#\-)     (adjust-depth! -1) (refresh)]
        [(#\p)     (cycle-palette!)   (refresh)]
        [(wheel-up)   (zoom-by! 1.12) (refresh)]
        [(wheel-down) (zoom-by! (/ 1.0 1.12)) (refresh)]))))

;; Apply initial rotation (used by --y-turns/--x-turns and by --animate).
(define (compose-initial-rotation!)
  (define ay (* 2 pi (cli-y-turns)))
  (define ax (* 2 pi (cli-x-turns)))
  (set! STATE-ROTATION (mat-mul (rot-x ax) (rot-y ay))))

(compose-initial-rotation!)

(define (snapshot-to! path w h)
  (define bm (make-object bitmap%
               (inexact->exact (ceiling w))
               (inexact->exact (ceiling h))))
  (define dc (new bitmap-dc% [bitmap bm]))
  (paint-canvas! dc w h)
  (send bm save-file path 'png))

(define (render-animation!)
  (define w (cli-size))
  (define h (cli-size))
  (define n (cli-frames))
  (define dir (cli-out-dir))
  (unless (directory-exists? dir) (make-directory* dir))
  (define axis (cli-animate))
  (for ([i (in-range n)])
    (define t (/ i (* 1.0 n)))
    (define ay (case (string->symbol axis)
                 [(y both) (* 2 pi t)]
                 [else 0.0]))
    (define ax (case (string->symbol axis)
                 [(x both) (* 2 pi t)]
                 [else 0.0]))
    ;; Compose so we end where we started (identity at t=1).
    (set! STATE-ROTATION (mat-mul (rot-x ax) (rot-y ay)))
    (define path (format "~a/frame_~a.png" dir (~a i #:width 4 #:pad-string "0" #:align 'right)))
    (snapshot-to! path w h)
    (when (zero? (modulo i 10))
      (printf "frame ~a/~a~n" i n)))
  (printf "wrote ~a frames to ~a/~n" n dir))

(cond
  [(cli-animate)
   (render-animation!)]
  [(cli-snapshot)
   (snapshot-to! (cli-snapshot) (cli-size) (cli-size))
   (printf "wrote ~a~n" (cli-snapshot))]
  [else
   (define frame
     (new frame%
          [label (format "harmony--{~a,~a} moebius" STATE-P STATE-Q)]
          [width  (cli-size)]
          [height (cli-size)]))
   (define canvas
     (new sphere-canvas%
          [parent frame]
          [style '()]))
   (send canvas focus)
   (send frame show #t)])
