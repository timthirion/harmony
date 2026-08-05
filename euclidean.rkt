#! /usr/bin/env racket
#lang racket

;; euclidean.rkt — companion to harmony.rkt for the three regular Euclidean
;; tessellations {3,6}, {4,4}, {6,3}. Shares palettes with harmony but nothing
;; else — the geometry is purely translational, no geodesic arcs.

(require "palettes.rkt")
(require racket/draw)

;; ---- Parameters ----

(define image-width  (make-parameter 900))
(define image-height (make-parameter 900))
(define image-file   (make-parameter "output.svg"))
(define tiling-name  (make-parameter "hex"))     ; hex | square | triangle
(define extent       (make-parameter 10))
(define palette-name (make-parameter "harmony"))

(command-line
 #:usage-help "Euclidean regular tilings: {3,6}, {4,4}, {6,3}"
 #:once-each
 [("-d" "--dimensions") W H "Image dimensions in pixels"
  (image-width  (string->number W))
  (image-height (string->number H))]
 [("-f" "--file") FILE "Output file path (.png for PNG, else SVG)"
  (image-file FILE)]
 [("-t" "--tiling") T "Tiling: hex ({6,3}), square ({4,4}), triangle ({3,6})"
  (tiling-name T)]
 [("--extent") N "Lattice half-width (larger = more tiles)"
  (extent (string->number N))]
 [("--palette") NAME "Color palette (see harmony palettes)"
  (palette-name NAME)]
 #:args () (void))

(define VALID-TILINGS '("hex" "square" "triangle"))
(unless (member (tiling-name) VALID-TILINGS)
  (eprintf "Unknown tiling '~a'. Available: ~a~n"
           (tiling-name) (string-join VALID-TILINGS ", "))
  (exit 1))

(define ACTIVE-PALETTE (lookup-palette (palette-name)))
(define STROKE-COLOR (palette-stroke ACTIVE-PALETTE))
(define DISK-COLOR   (palette-disk   ACTIVE-PALETTE))
(define OUTER-COLOR  (palette-outer  ACTIVE-PALETTE))

(define (tile-color depth sector)
  (let* ([families (palette-families ACTIVE-PALETTE)]
         [family   (modulo sector 3)]
         [pal      (vector-ref families family)]
         [idx      (min depth (- (vector-length pal) 1))])
    (vector-ref pal idx)))

;; ---- Geometry ----

(define SQRT3 (sqrt 3))

;; Each generator returns a list of tiles. A tile is:
;;   (list of complex vertices, depth, sector)
;; matching the shape used by harmony's renderer.

;; {6,3}: pointy-top hexagons of radius r (center-to-vertex).
;; Lattice: e1=(r√3, 0), e2=(r√3/2, 3r/2).
;; Hex distance: max(|n1|, |n2|, |n1+n2|).
;; Three-color scheme: sector = (n1 − n2) mod 3.
(define (hex-tiles r n)
  (define e1  (make-rectangular (* r SQRT3) 0))
  (define e2  (make-rectangular (* r SQRT3 0.5) (* r 1.5)))
  (define hexverts
    (for/list ([k (in-range 6)])
      (make-polar r (+ (/ pi 6) (* k pi 1/3)))))
  (for*/list ([n1 (in-range (- n) (+ n 1))]
              [n2 (in-range (- n) (+ n 1))]
              #:when (<= (max (abs n1) (abs n2) (abs (+ n1 n2))) n))
    (define center (+ (* n1 e1) (* n2 e2)))
    (define depth  (max (abs n1) (abs n2) (abs (+ n1 n2))))
    (define sector (modulo (- n1 n2) 3))
    (list (map (lambda (v) (+ center v)) hexverts) depth sector)))

;; {4,4}: unit squares of side s, aligned to axes.
;; Lattice: e1=(s, 0), e2=(0, s).
(define (square-tiles s n)
  (define half (* s 0.5))
  (define sqverts (list (make-rectangular (- half) (- half))
                        (make-rectangular    half  (- half))
                        (make-rectangular    half     half)
                        (make-rectangular (- half)    half)))
  (for*/list ([n1 (in-range (- n) (+ n 1))]
              [n2 (in-range (- n) (+ n 1))])
    (define center (make-rectangular (* n1 s) (* n2 s)))
    (define depth  (max (abs n1) (abs n2)))
    (define sector (modulo (+ n1 n2) 3))
    (list (map (lambda (v) (+ center v)) sqverts) depth sector)))

;; {3,6}: equilateral triangles of side s. Two triangles per lattice cell.
;; Base lattice: e1=(s, 0), e2=(s/2, s√3/2). The e2 shear pushes rows
;; horizontally, so we shift each row's n1 range by round(n2/2) to keep
;; the tessellation centered horizontally.
(define (triangle-tiles s n)
  (define e1 (make-rectangular s 0))
  (define e2 (make-rectangular (* s 0.5) (* s SQRT3 0.5)))
  (define zero (make-rectangular 0 0))
  (apply
   append
   (for/list ([n2 (in-range (- n) (+ n 1))])
     (define shift (exact-round (/ n2 2)))
     (for*/list ([n1 (in-range (- (- shift) n) (+ (- shift) n 1))]
                 [orient (in-list '(up down))])
       (define base (+ (* n1 e1) (* n2 e2)))
       (define verts
         (case orient
           [(up)   (map (lambda (v) (+ base v)) (list zero e1 e2))]
           [(down) (map (lambda (v) (+ base v)) (list e1 e2 (+ e1 e2)))]))
       (define depth  (max (abs (+ n1 shift)) (abs n2)))
       (define sector (modulo (+ (- n1 n2) (if (eq? orient 'up) 0 1)) 3))
       (list verts depth sector)))))

;; ---- Rendering ----

(define (fmt x) (~r (exact->inexact x) #:precision 3))

(define W (image-width))
(define H (image-height))

;; Fit the tessellated area to the image. The lattice extent chosen above
;; produces a tessellation roughly N tiles wide; we pick a scale that fills
;; the image comfortably.
(define (viewport-scale)
  (define n (extent))
  (case (tiling-name)
    [("hex")
     ;; Hex-lattice half-width is n·√3 tile-units.
     (/ (* 0.9 (min W H)) (* 2 (max 1 n) SQRT3))]
    [("square")
     (/ (* 0.9 (min W H)) (* 2 (max 1 n)))]
    [("triangle")
     ;; The lattice half-width is roughly n * s in x and n * s√3/2 in y.
     (/ (* 0.9 (min W H)) (* 2 (max 1 n)))]))

(define SCALE (viewport-scale))
(define CX (/ W 2.0))
(define CY (/ H 2.0))

(define (z->screen z)
  (cons (+ CX (* SCALE (real-part z)))
        (- CY (* SCALE (imag-part z)))))

(define (generate-tiles)
  (case (tiling-name)
    [("hex")      (hex-tiles      1.0 (extent))]
    [("square")   (square-tiles   1.0 (extent))]
    [("triangle") (triangle-tiles 1.0 (extent))]))

;; ---- SVG ----

(define (polygon-svg verts depth sector)
  (define n   (length verts))
  (define p0  (z->screen (car verts)))
  (define lines
    (for/list ([v (in-list (cdr verts))])
      (define ps (z->screen v))
      (format "L ~a ~a" (fmt (car ps)) (fmt (cdr ps)))))
  (define d (string-append (format "M ~a ~a" (fmt (car p0)) (fmt (cdr p0)))
                            " " (string-join lines " ") " Z"))
  (format "  <path d=\"~a\" fill=\"~a\" stroke=\"none\"/>" d (tile-color depth sector)))

(define (polygon-stroke-svg verts)
  (define p0 (z->screen (car verts)))
  (define lines
    (for/list ([v (in-list (cdr verts))])
      (define ps (z->screen v))
      (format "L ~a ~a" (fmt (car ps)) (fmt (cdr ps)))))
  (define d (string-append (format "M ~a ~a" (fmt (car p0)) (fmt (cdr p0)))
                            " " (string-join lines " ") " Z"))
  (format "  <path d=\"~a\" fill=\"none\" stroke=\"~a\" stroke-width=\"1\"/>" d STROKE-COLOR))

(define (write-svg! tiles out)
  (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~n")
  (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\">~n" W H)
  (fprintf out "  <rect width=\"~a\" height=\"~a\" fill=\"~a\"/>~n" W H DISK-COLOR)
  (for ([tile (in-list tiles)])
    (fprintf out "~a~n" (polygon-svg (first tile) (second tile) (third tile))))
  (for ([tile (in-list tiles)])
    (fprintf out "~a~n" (polygon-stroke-svg (first tile))))
  (fprintf out "</svg>~n"))

;; ---- PNG ----

(define (hex->color hex)
  (make-object color%
    (string->number (substring hex 1 3) 16)
    (string->number (substring hex 3 5) 16)
    (string->number (substring hex 5 7) 16)))

(define (make-dc-path verts)
  (define path (new dc-path%))
  (define p0 (z->screen (car verts)))
  (send path move-to (car p0) (cdr p0))
  (for ([v (in-list (cdr verts))])
    (define ps (z->screen v))
    (send path line-to (car ps) (cdr ps)))
  (send path close)
  path)

(define (write-png! tiles file)
  (define bm (make-object bitmap% W H))
  (define dc (new bitmap-dc% [bitmap bm]))
  (define no-pen   (make-object pen%   "black" 0 'transparent))
  (define no-brush (make-object brush% "black" 'transparent))
  (send dc set-smoothing 'aligned)
  (send dc set-background (hex->color DISK-COLOR))
  (send dc clear)

  ;; Fills
  (send dc set-pen no-pen)
  (for ([tile (in-list tiles)])
    (send dc set-brush (make-object brush% (hex->color (tile-color (second tile) (third tile))) 'solid))
    (send dc draw-path (make-dc-path (first tile))))

  ;; Outlines
  (send dc set-brush no-brush)
  (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) 1 'solid))
  (for ([tile (in-list tiles)])
    (send dc draw-path (make-dc-path (first tile))))

  (send bm save-file file 'png))

;; ---- Main ----

(printf "Generating ~a tiling (extent ~a)...~n" (tiling-name) (extent))
(define tiles (generate-tiles))
(printf "Generated ~a tiles. Writing ~a...~n" (length tiles) (image-file))

(cond
  [(string-suffix? (image-file) ".png")
   (write-png! tiles (image-file))
   (void)]
  [else
   (call-with-output-file (image-file) #:exists 'replace
     (lambda (out) (write-svg! tiles out)))])

(printf "Done.~n")
