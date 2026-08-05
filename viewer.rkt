#! /usr/bin/env racket
#lang racket/gui

;; viewer.rkt — interactive Poincaré-disk viewer for {p,q} tessellations.
;;
;; Model:
;;   - Tessellate ONCE at startup, at a generous depth (default 8 → ~11k
;;     tiles for {7,3}). This is the "world"; it never changes.
;;   - Track a single piece of state: the viewer's world position `c`.
;;     Pans update `c` by a hyperbolic translation; magnitude is clamped
;;     to a safe range so the Möbius stays numerically stable.
;;   - On each frame, apply the Möbius sending `c` → 0 to every stored
;;     vertex and render.
;;
;; The tessellation is bounded (you can only wander so far from origin
;; before hitting the clamp), but within that region: no drift, no flicker,
;; no doubled geometry, no accumulated Möbius. It's the correct trade-off
;; for a hobby viewer — a full "truly endless" viewer needs a graph-based
;; tessellation with boundary-crossing frame swaps, which is a substantial
;; refactor. See MagicTile or HyperRogue for that.

(require racket/draw)
(require "hyperbolic.rkt")
(require "palettes.rkt")

;; ---- CLI ----

(define cli-p (make-parameter 7))
(define cli-q (make-parameter 3))
(define cli-depth (make-parameter 8))
(define cli-palette (make-parameter "harmony"))
(define cli-size (make-parameter 800))
(define cli-snapshot (make-parameter #f))

(command-line
 #:usage-help "Interactive Poincaré-disk viewer for {p,q} tessellations"
 #:once-each
 [("-p") P "Polygon sides (default 7)"
  (cli-p (string->number P))]
 [("-q") Q "Polygons meeting at each vertex (default 3)"
  (cli-q (string->number Q))]
 [("--depth") D "BFS depth (default 8; higher = larger explorable area)"
  (cli-depth (string->number D))]
 [("--palette") NAME "Palette name (default harmony)"
  (cli-palette NAME)]
 [("--size") N "Window size in pixels (default 800)"
  (cli-size (string->number N))]
 [("--snapshot") FILE "Render one PNG at the default view and exit (no window)"
  (cli-snapshot FILE)]
 #:args () (void))

(unless (> (* (- (cli-p) 2) (- (cli-q) 2)) 4)
  (eprintf "{~a,~a} is not hyperbolic; viewer requires (p-2)(q-2) > 4~n"
           (cli-p) (cli-q))
  (exit 1))

;; ---- State ----

(define STATE-P     (cli-p))
(define STATE-Q     (cli-q))
(define STATE-DEPTH (cli-depth))
(define STATE-ZOOM  1.0)
(define STATE-VIEWER 0+0i)
(define VIEWER-CLAMP 0.92)  ; max |viewer|; above this the Möbius destabilizes

(define STATE-TILES '())    ; precomputed once
(define (regen-tiles!)
  (printf "tessellating ~a to depth ~a...~n" (list STATE-P STATE-Q) STATE-DEPTH)
  (set! STATE-TILES (tessellate STATE-P STATE-Q STATE-DEPTH))
  (printf "  ~a tiles~n" (length STATE-TILES)))

(regen-tiles!)

(define ACTIVE-PALETTE (lookup-palette (cli-palette)))
(define CENTER-COLOR (palette-center ACTIVE-PALETTE))
(define STROKE-COLOR (palette-stroke ACTIVE-PALETTE))
(define DISK-COLOR   (palette-disk   ACTIVE-PALETTE))
(define OUTER-COLOR  (palette-outer  ACTIVE-PALETTE))

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

;; ---- Möbius helpers ----

(define (atanh x) (* 0.5 (log (/ (+ 1 x) (- 1 x)))))

;; Möbius sending c → 0. Uses the (cosh d/2, ±sinh d/2 · e^{iθ}) form which
;; is more numerically stable at moderate translations than the 1/√(1-|c|²)
;; normalisation.
(define (translation-from c)
  (define c-mag (magnitude c))
  (cond
    [(< c-mag 1e-12) (values 1 0)]
    [else
     (define d (* 2 (atanh (min 0.9999999 c-mag))))
     (define theta (angle c))
     (values (cosh (/ d 2))
             (- (* (sinh (/ d 2)) (make-polar 1 theta))))]))

;; ---- Rendering ----

(define (paint-canvas! dc W H)
  (define cx (/ W 2.0))
  (define cy (/ H 2.0))
  (define scale (* STATE-ZOOM 0.47 (min W H)))
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))

  (send dc set-smoothing 'aligned)
  (send dc set-background (hex->color OUTER-COLOR))
  (send dc clear)

  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color DISK-COLOR) 'solid))
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))

  (define-values (va vb) (translation-from STATE-VIEWER))
  (define (v->screen z)
    (define zt (mobius-apply va vb z))
    (make-object point%
      (+ cx (* scale (real-part zt)))
      (- cy (* scale (imag-part zt)))))

  ;; Cull tiles whose visual centroid is essentially at the boundary — they
  ;; are sub-pixel and dominate the render time.
  (define visible
    (for/list ([tile (in-list STATE-TILES)]
               #:when (let ([ctr (mobius-apply va vb
                                               (/ (apply + (first tile)) STATE-P))])
                        (< (magnitude ctr) 0.998)))
      tile))

  ;; Deepest first so shallow tiles paint on top.
  (send dc set-pen no-pen)
  (for ([tile (in-list (sort visible > #:key second))])
    (define depth (second tile))
    (define sector (third tile))
    (send dc set-brush
          (make-object brush% (hex->color (tile-color depth sector)) 'solid))
    (send dc draw-polygon (map v->screen (first tile))))

  (send dc set-brush no-brush)
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 0.6 'solid))
  (for ([tile (in-list visible)])
    (send dc draw-polygon (map v->screen (first tile))))

  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 2 'solid))
  (send dc set-brush no-brush)
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale)))

;; ---- Interaction ----

;; Screen delta (dx, dy) at pixel scale s becomes a hyperbolic translation
;; of the viewer position by the *negation* of the disk-space delta (drag
;; right = viewer moves left = world content shifts right visually). Clamps
;; the result to keep the Möbius from exploding at the boundary.
(define (pan! dx dy scale)
  (define delta (make-rectangular (/ dx scale) (/ (- dy) scale)))
  (define d-mag (magnitude delta))
  (when (> d-mag 1e-9)
    (define shift-mag (min 0.85 d-mag))
    (define shift (if (= shift-mag d-mag) delta (* delta (/ shift-mag d-mag))))
    ;; c_new = (c - shift) / (1 - conj(shift) * c) — hyperbolic translation.
    (define candidate
      (/ (- STATE-VIEWER shift)
         (- 1 (* (conjugate shift) STATE-VIEWER))))
    ;; Clamp magnitude.
    (define cand-mag (magnitude candidate))
    (set! STATE-VIEWER
          (if (< cand-mag VIEWER-CLAMP)
              candidate
              (* candidate (/ VIEWER-CLAMP cand-mag))))))

(define (reset-view!)
  (set! STATE-VIEWER 0+0i)
  (set! STATE-ZOOM 1.0))

(define (zoom-by! factor)
  (set! STATE-ZOOM (max 0.2 (min 20.0 (* STATE-ZOOM factor)))))

(define (adjust-depth! delta)
  (define new-depth (max 0 (min 10 (+ STATE-DEPTH delta))))
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
  (define file (format "snapshot-~a.png" ts))
  (send bm save-file file 'png)
  (printf "wrote ~a~n" file))

;; ---- GUI ----

(define harmony-canvas%
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
      (define scale (* STATE-ZOOM 0.47 (min w h)))
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
           (pan! (- x drag-last-x) (- y drag-last-y) scale)
           (set! drag-last-x x)
           (set! drag-last-y y)
           (refresh))]))

    (define/override (on-char ev)
      (define-values (w h) (get-client-size))
      (case (send ev get-key-code)
        [(#\r)
         (reset-view!)
         (refresh)]
        [(#\s)
         (save-snapshot! w h)]
        [(#\+ #\=)
         (adjust-depth! +1)
         (refresh)]
        [(#\-)
         (adjust-depth! -1)
         (refresh)]
        [(wheel-up)
         (zoom-by! 1.12)
         (refresh)]
        [(wheel-down)
         (zoom-by! (/ 1.0 1.12))
         (refresh)]))))

(cond
  [(cli-snapshot)
   (define w (cli-size))
   (define h (cli-size))
   (define bm (make-object bitmap%
                (inexact->exact (ceiling w))
                (inexact->exact (ceiling h))))
   (define dc (new bitmap-dc% [bitmap bm]))
   (paint-canvas! dc w h)
   (send bm save-file (cli-snapshot) 'png)
   (printf "wrote ~a~n" (cli-snapshot))]
  [else
   (define frame
     (new frame%
          [label (format "harmony — {~a,~a}" STATE-P STATE-Q)]
          [width  (cli-size)]
          [height (cli-size)]))
   (define canvas
     (new harmony-canvas%
          [parent frame]
          [style '()]))
   (send canvas focus)
   (send frame show #t)])
