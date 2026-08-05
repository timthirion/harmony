#! /usr/bin/env racket
#lang racket/gui

;; viewer.rkt — interactive Poincaré-disk viewer for {p,q} tessellations.
;;
;; Runs a GUI window over the tiling produced by harmony's tessellate.
;; Mouse-drag pans the view by hyperbolic translation, scroll-wheel adjusts
;; a Euclidean zoom multiplier, and a few keyboard shortcuts round it out.
;;
;; The renderer is intentionally simpler than harmony.rkt's:
;;   - Poincaré model only (no Klein/UHP/band).
;;   - Straight-line polygons (no geodesic arcs). Fast enough for interactive
;;     redraws at typical tessellation depths.
;;   - No motifs, spokes, highlights, or animation.
;; For those, produce a snapshot with 's' and render the same {p,q} through
;; harmony.rkt.

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

(command-line
 #:usage-help "Interactive Poincaré-disk viewer for {p,q} tessellations"
 #:once-each
 [("-p") P "Polygon sides (default 7)"
  (cli-p (string->number P))]
 [("-q") Q "Polygons meeting at each vertex (default 3)"
  (cli-q (string->number Q))]
 [("--depth") D "BFS depth (default 6; bump for zoomed-in detail)"
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
(define STATE-A     1+0i)     ; Möbius a
(define STATE-B     0+0i)     ; Möbius b
(define STATE-ZOOM  1.0)      ; Euclidean scale multiplier
(define STATE-TILES '())      ; cached tessellation

(define (regen-tiles!)
  (set! STATE-TILES (tessellate STATE-P STATE-Q STATE-DEPTH))
  (printf "depth ~a → ~a tiles~n" STATE-DEPTH (length STATE-TILES)))

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
             [idx      (min depth (- (vector-length pal) 1))])
        (vector-ref pal idx))))

(define (hex->color hex)
  (make-object color%
    (string->number (substring hex 1 3) 16)
    (string->number (substring hex 3 5) 16)
    (string->number (substring hex 5 7) 16)))

;; ---- Rendering ----

;; Möbius view transform of a disk point.
(define (view-apply z) (mobius-apply STATE-A STATE-B z))

(define (paint-canvas! dc W H)
  (define cx (/ W 2.0))
  (define cy (/ H 2.0))
  (define scale (* STATE-ZOOM 0.47 (min W H)))
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))

  (send dc set-smoothing 'aligned)
  (send dc set-background (hex->color OUTER-COLOR))
  (send dc clear)

  ;; Poincaré disk background
  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color DISK-COLOR) 'solid))
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))

  ;; Precompute transformed vertices for each tile so we don't reapply the
  ;; Möbius per edge.
  (define transformed
    (for/list ([tile (in-list STATE-TILES)])
      (list (map view-apply (first tile))
            (second tile)
            (third tile))))

  ;; Pass 1: solid polygon fills, deepest first (so shallow paint on top).
  (send dc set-pen no-pen)
  (for ([tile (in-list (sort transformed > #:key second))])
    (define depth (second tile))
    (define sector (third tile))
    (define pts (for/list ([z (in-list (first tile))])
                  (define x (+ cx (* scale (real-part z))))
                  (define y (- cy (* scale (imag-part z))))
                  (make-object point% x y)))
    (send dc set-brush (make-object brush% (hex->color (tile-color depth sector)) 'solid))
    (send dc draw-polygon pts))

  ;; Pass 2: thin outlines (single pass over all tiles).
  (send dc set-brush no-brush)
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 0.6 'solid))
  (for ([tile (in-list transformed)])
    (define pts (for/list ([z (in-list (first tile))])
                  (define x (+ cx (* scale (real-part z))))
                  (define y (- cy (* scale (imag-part z))))
                  (make-object point% x y)))
    (send dc draw-polygon pts))

  ;; Boundary circle
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 2 'solid))
  (send dc set-brush no-brush)
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale)))

;; ---- Interaction ----

(define (reset-view!)
  (set! STATE-A 1+0i)
  (set! STATE-B 0+0i)
  (set! STATE-ZOOM 1.0))

;; Apply a hyperbolic translation of screen delta (dx, dy) at the given
;; pixel scale, composing with the current view.
(define (pan! dx dy scale)
  (define d-real (/ dx scale))
  (define d-imag (/ (- dy) scale))    ; screen y is flipped
  (define d (sqrt (+ (sqr d-real) (sqr d-imag))))
  (when (> d 1e-9)
    (define theta (angle (make-rectangular d-real d-imag)))
    (define a-delta (cosh (/ d 2)))
    (define b-delta (* (sinh (/ d 2)) (make-polar 1 theta)))
    ;; Compose (a-delta, b-delta) ∘ (STATE-A, STATE-B) in SU(1,1).
    (define a-new (+ (* a-delta STATE-A) (* b-delta (conjugate STATE-B))))
    (define b-new (+ (* a-delta STATE-B) (* b-delta (conjugate STATE-A))))
    (set! STATE-A a-new)
    (set! STATE-B b-new)))

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

(define frame
  (new frame%
       [label (format "harmony viewer — {~a,~a}" STATE-P STATE-Q)]
       [width  (cli-size)]
       [height (cli-size)]))

(define canvas
  (new harmony-canvas%
       [parent frame]
       [style '()]))

(cond
  [(cli-snapshot)
   ;; Headless: render to a bitmap and exit without opening the window.
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
   (send canvas focus)
   (send frame show #t)])
