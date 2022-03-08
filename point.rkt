#lang typed/racket

(struct point ([x : Real] [y : Real]))

(: distance (-> point point Real))
(define (distance p q)
  (sqrt (+ (sqr (- (point-x q) (point-x p)))
           (sqr (- (point-y q) (point-y p))))))

; Coefficients (a, b, c) of a 2D line, s.t., ax + by = c
(struct line ([a : Real] [b : Real] [c : Real]))

; Line through points p and q
(: line-through-points (-> point point line))
(define (line-through-points p q)
  (let* ([px (point-x p)]
         [py (point-y p)]
         [qx (point-x q)]
         [qy (point-y q)]
         [a (- py qy)]
         [b (- px qx)]
         [c (- (* px qy) (* qx py))])
    (if (> b 0.001)
        (line (/ a b) (/ b b) (/ c b))
        (line a b c))))

; Orthogonal line to line l through point p
(: orthogonal-line (-> line point line))
(define (orthogonal-line l p)
  (let ([a (line-a l)]
        [b (line-b l)]
        [c (line-c l)]
        [px (point-x p)]
        [py (point-y p)])
    (line b (- a) (+ (* (- px) b) (* py a)))))

; Midpoint between points p and q
(: midpoint (-> point point point))
(define (midpoint p q)
  (point (/ (+ (point-x p) (point-x q)) 2)
         (/ (+ (point-y p) (point-y q)) 2)))
