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
 #:args () (void))

;; ---- Color palette ----
;; Three families cycling by (sector mod 3), tinted darker with depth

(define PALETTES
  (vector
   (vector "#B8CCE0" "#9DB8D5" "#82A4CA" "#6890BF" "#507CAE")   ; blue family
   (vector "#E0B8B8" "#D5A0A0" "#CA8888" "#BF7070" "#AE5858")   ; rose family
   (vector "#C0C0CC" "#ABABBA" "#9696A8" "#818196" "#6C6C84"))) ; grey family

(define CENTER-COLOR "#D0DCE8")
(define STROKE-COLOR "#778899")
(define SPOKE-COLOR  "#FFFFFF")

(define (tile-color depth sector)
  (if (= sector -1)
      CENTER-COLOR
      (let* ([family (modulo sector 3)]
             [pal    (vector-ref PALETTES family)]
             [idx    (min depth (- (vector-length pal) 1))])
        (vector-ref pal idx))))

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

(define (write-svg! tiles p cx cy scale W H out)
  (define sorted (sort tiles > #:key second))
  (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\">\n" W H)
  (fprintf out "  <rect width=\"~a\" height=\"~a\" fill=\"white\"/>\n" W H)
  (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"#eef2f5\" stroke=\"none\"/>\n"
           (fmt cx) (fmt cy) (fmt scale))
  ;; Pass 1: fills
  (for ([tile sorted])
    (fprintf out "~a\n" (polygon-fill-svg (first tile) (second tile) (third tile) cx cy scale)))
  ;; Pass 2: spokes (on top of fills, under outlines)
  (for ([tile tiles])
    (fprintf out "~a\n" (spokes-svg (first tile) p cx cy scale)))
  ;; Pass 3: outlines
  (for ([tile sorted])
    (fprintf out "~a\n" (polygon-stroke-svg (first tile) (second tile) cx cy scale)))
  (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"none\" stroke=\"#445566\" stroke-width=\"2\"/>\n"
           (fmt cx) (fmt cy) (fmt scale))
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

  (send dc set-background (make-object color% 255 255 255))
  (send dc clear)

  ;; Background disk
  (send dc set-pen no-pen)
  (send dc set-brush (make-object brush% (hex->color "#eef2f5") 'solid))
  (send dc draw-ellipse (- cx scale) (- cy scale) (* 2 scale) (* 2 scale))

  ;; Pass 1: fills
  (send dc set-pen no-pen)
  (for ([tile (in-list (sort tiles > #:key second))])
    (send dc set-brush (make-object brush% (hex->color (tile-color (second tile) (third tile))) 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))

  ;; Pass 2: spokes
  (send dc set-pen (make-object pen% (hex->color SPOKE-COLOR) 1 'solid))
  (send dc set-brush no-brush)
  (for ([tile (in-list tiles)])
    (define c  (tile-centroid (first tile) p))
    (define cs (z->screen c cx cy scale))
    (for ([v (first tile)])
      (define vs (z->screen v cx cy scale))
      (send dc draw-line (car cs) (cdr cs) (car vs) (cdr vs))))

  ;; Pass 3: outlines
  (send dc set-brush no-brush)
  (for ([tile (in-list (sort tiles > #:key second))])
    (define depth (second tile))
    (define sw    (max 0.3 (- 1.2 (* depth 0.15))))
    (send dc set-pen (make-object pen% (hex->color STROKE-COLOR) sw 'solid))
    (send dc draw-path (tile-dc-path (first tile) cx cy scale)))

  ;; Boundary circle
  (send dc set-pen (make-object pen% (hex->color "#445566") 2 'solid))
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
(printf "Generated ~a tiles. Writing ~a...~n" (length tiles) (image-file))

(if (string-suffix? ".png" (image-file))
    (write-png! tiles p cx cy scale W H (image-file))
    (call-with-output-file (image-file) #:exists 'replace
      (lambda (out) (write-svg! tiles p cx cy scale W H out))))

(printf "Done.\n")
