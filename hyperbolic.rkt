#lang racket

(provide polygon-vertices tessellate geodesic-circle diameter?
         fundamental-radius warp-point reflect-through-geodesic
         mobius-apply)

;; ---- Complex helpers ----

(define (unit-invert z) (/ 1 (conjugate z)))

;; Circumcircle of 3 complex points -> (values center radius)
(define (circumcircle z1 z2 z3)
  (define ax (real-part z1)) (define ay (imag-part z1))
  (define bx (real-part z2)) (define by (imag-part z2))
  (define cx (real-part z3)) (define cy (imag-part z3))
  (define D (* 2 (+ (* ax (- by cy)) (* bx (- cy ay)) (* cx (- ay by)))))
  (define ux (/ (+ (* (+ (sqr ax) (sqr ay)) (- by cy))
                   (* (+ (sqr bx) (sqr by)) (- cy ay))
                   (* (+ (sqr cx) (sqr cy)) (- ay by)))
                D))
  (define uy (/ (+ (* (+ (sqr ax) (sqr ay)) (- cx bx))
                   (* (+ (sqr bx) (sqr by)) (- ax cx))
                   (* (+ (sqr cx) (sqr cy)) (- bx ax)))
                D))
  (define center (make-rectangular ux uy))
  (values center (magnitude (- z1 center))))

;; Is the geodesic through z1, z2 a diameter (passes through origin)?
(define (diameter? z1 z2)
  (< (abs (- (* (real-part z1) (imag-part z2))
             (* (imag-part z1) (real-part z2))))
     1e-9))

;; Geodesic circle through two interior disk points -> (values center radius)
(define (geodesic-circle z1 z2)
  (circumcircle z1 z2 (unit-invert z1)))

;; Reflect z through the geodesic defined by p and q
(define (reflect-through-geodesic p q z)
  (if (diameter? p q)
      ;; Reflect through line through origin at angle of p (or q)
      (let ([theta (angle (if (> (magnitude p) 1e-10) p q))])
        (* (make-polar 1 (* 2 theta)) (conjugate z)))
      ;; Inversion in geodesic circle
      (let-values ([(c r) (geodesic-circle p q)])
        (+ c (/ (sqr r) (conjugate (- z c)))))))

;; ---- Fundamental polygon ----

;; Euclidean circumradius of regular {p,q} polygon in Poincare disk.
;; Valid only for hyperbolic tilings: (p-2)*(q-2) > 4
(define (fundamental-radius p q)
  (sqrt (/ (cos (+ (/ pi p) (/ pi q)))
           (cos (- (/ pi p) (/ pi q))))))

;; Vertices of the central {p,q} polygon, first vertex at angle pi/2 (top)
(define (polygon-vertices p q)
  (define r (fundamental-radius p q))
  (for/list ([k (in-range p)])
    (make-polar r (+ (/ pi 2) (* 2 pi k (/ 1.0 p))))))

;; ---- Möbius transformations preserving the unit disk ----
;; f(z) = (a·z + b) / (conj(b)·z + conj(a))     with |a|² − |b|² = 1
;; Identity: a=1, b=0.
;; Hyperbolic translation by distance d along direction θ:
;;   a = cosh(d/2), b = sinh(d/2) · e^{iθ}
;; Rotation by angle φ around origin:
;;   a = e^{iφ/2}, b = 0

(define (mobius-apply a b z)
  (/ (+ (* a z) b)
     (+ (* (conjugate b) z) (conjugate a))))

;; ---- Warping via reflection sequence ----

;; Apply a sequence of geodesic reflections to a point, in order.
;; Each axis is a pair (v1 . v2) of complex-number endpoints.
(define (warp-point z axes)
  (for/fold ([w z]) ([axis (in-list axes)])
    (reflect-through-geodesic (car axis) (cdr axis) w)))

;; ---- Tessellation via BFS ----

;; Returns list of (vertices depth sector axes) where:
;;  - sector is the side-index of the first reflection from the central tile
;;    (-1 for the central tile itself);
;;  - axes is the list of (v1 . v2) reflection axes used to reach this tile
;;    from the central tile ('() for the central tile).
(define (tessellate p q depth)
  (define verts0 (polygon-vertices p q))
  (define visited (make-hash))
  (define result '())

  (define (tile-key vs)
    (define c (/ (apply + vs) p))
    (cons (inexact->exact (round (* 10000 (real-part c))))
          (inexact->exact (round (* 10000 (imag-part c))))))

  (define (reflect-tile vs i)
    (define v1 (list-ref vs i))
    (define v2 (list-ref vs (modulo (+ i 1) p)))
    (values (cons v1 v2)
            (map (lambda (v) (reflect-through-geodesic v1 v2 v)) vs)))

  ;; Each queue item: (vertices depth sector axes)
  (let loop ([queue (list (list verts0 0 -1 '()))])
    (unless (null? queue)
      (define item (car queue))
      (define vs   (first item))
      (define d    (second item))
      (define sec  (third item))
      (define axes (fourth item))
      (define key  (tile-key vs))
      (define rest (cdr queue))
      (cond
        [(hash-has-key? visited key) (loop rest)]
        [else
         (hash-set! visited key #t)
         (set! result (cons item result))
         (loop (if (< d depth)
                   (append rest
                           (for/list ([i (in-range p)])
                             (define-values (axis vs2) (reflect-tile vs i))
                             (list vs2
                                   (+ d 1)
                                   (if (= sec -1) i sec)
                                   (append axes (list axis)))))
                   rest))])))
  result)
