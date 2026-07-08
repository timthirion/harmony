#! /usr/bin/env racket
#lang racket

(require "hyperbolic.rkt")

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
 [("-f" "--file") FILE "Output SVG file path"
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
  ;; Each entry: vector of colors lightest->darkest per depth band
  (vector
   (vector "#B8CCE0" "#9DB8D5" "#82A4CA" "#6890BF" "#507CAE")   ; blue family
   (vector "#E0B8B8" "#D5A0A0" "#CA8888" "#BF7070" "#AE5858")   ; rose family
   (vector "#C0C0CC" "#ABABBA" "#9696A8" "#818196" "#6C6C84"))) ; grey family

(define CENTER-COLOR "#D0DCE8")
(define STROKE-COLOR "#778899")

(define (tile-color depth sector)
  (if (= sector -1)
      CENTER-COLOR
      (let* ([family (modulo sector 3)]
             [pal    (vector-ref PALETTES family)]
             [idx    (min depth (- (vector-length pal) 1))])
        (vector-ref pal idx))))

;; ---- SVG helpers ----

(define (fmt x) (~r (exact->inexact x) #:precision 3))

(define (z->screen z cx cy scale)
  (cons (+ cx (* scale (real-part z)))
        (- cy (* scale (imag-part z)))))   ; flip y for screen coords

;; SVG arc sweep-flag for the arc from z1->z2 that stays inside the unit disk.
;; Strategy: compute the midpoint of the SHORT arc from z1 to z2 on the geodesic
;; circle (by averaging their angles from c, taking the short-way-around diff).
;; That midpoint is always on the correct geodesic segment.  Then check whether
;; z1->mid->z2 is CW or CCW in screen coords to get the SVG sweep flag.
;;
;; Bug with the previous approach: c - r*(c/|c|) is the innermost point of the
;; full geodesic circle, which lies on the LONG arc when both z1 and z2 are on
;; the same angular half of the circle (common for reflected tiles).
(define (arc-sweep-flag z1 z2 c r cx cy scale)
  (define a1   (angle (- z1 c)))
  (define a2   (angle (- z2 c)))
  ;; Normalize angular difference to (-pi, pi] to get the short arc direction
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

;; One "A" or "L" SVG path segment going from z1 to z2
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

;; Full SVG <path> for one polygon tile
(define (polygon-svg-path verts depth sector cx cy scale)
  (define n (length verts))
  (define p0s (z->screen (car verts) cx cy scale))
  (define move (format "M ~a ~a" (fmt (car p0s)) (fmt (cdr p0s))))
  (define segs (for/list ([i (in-range n)])
                 (arc-segment (list-ref verts i)
                              (list-ref verts (modulo (+ i 1) n))
                              cx cy scale)))
  (define d-attr (string-append move " " (string-join segs " ") " Z"))
  (define fill  (tile-color depth sector))
  (define sw    (max 0.3 (- 1.2 (* depth 0.15))))
  (format "  <path d=\"~a\" fill=\"~a\" stroke=\"~a\" stroke-width=\"~a\"/>"
          d-attr fill STROKE-COLOR (fmt sw)))

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

(call-with-output-file (image-file) #:exists 'replace
  (lambda (out)
    (fprintf out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
    (fprintf out "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"~a\" height=\"~a\">\n" W H)
    (fprintf out "  <rect width=\"~a\" height=\"~a\" fill=\"white\"/>\n" W H)
    ;; Background disk
    (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"#eef2f5\" stroke=\"none\"/>\n"
             (fmt cx) (fmt cy) (fmt scale))
    ;; Tiles (sorted back-to-front: deepest first so shallower tiles render on top)
    (for ([tile (in-list (sort tiles > #:key second))])
      (fprintf out "~a\n" (polygon-svg-path (first tile) (second tile) (third tile) cx cy scale)))
    ;; Boundary circle
    (fprintf out "  <circle cx=\"~a\" cy=\"~a\" r=\"~a\" fill=\"none\" stroke=\"#445566\" stroke-width=\"2\"/>\n"
             (fmt cx) (fmt cy) (fmt scale))
    (fprintf out "</svg>\n")))

(printf "Done.\n")
