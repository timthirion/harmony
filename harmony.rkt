#! /usr/bin/env racket
#lang racket

(require racket/draw)
(require racket/include)

(include "point.rkt")

; Command line parameters
(define image-width (make-parameter 512))
(define image-height (make-parameter 512))
(define image-file (make-parameter "output.svg"))

; Command line parser
(define parser
  (command-line
   #:usage-help
   "Harmony generates hyperbolic diagrams"

   #:once-each
   [("-d" "--dimensions") WIDTH HEIGHT
    "The dimensions of the image"
    (image-width (string->number WIDTH))
    (image-height (string->number HEIGHT))]

   [("-f" "--file") FILE
    "Write image to file on disk"
    (image-file FILE)]

   #:args() (void)))

(define ellipse-brush
  (new brush%
       [gradient
        (new radial-gradient%
             [x0 256] [y0 256] [r0 0]
             [x1 256] [y1 256] [r1 256]
             [stops
              (list (list 0   (make-object color% 0 0 255))
                    (list 0.5 (make-object color% 0 255 0))
                    (list 1   (make-object color% 0 0 255)))])]))

(define random-point-in-unit-circle (list (random) (random)))


(define (draw-hyperbolic-line dc scale)
    (send dc draw-arc (/ scale 2) (/ scale 2) 50 50 0 3.14159))

(define dc (new svg-dc%
                [width (image-width)]
                [height (image-height)]
                [output (image-file)]
                [exists 'replace]))

(send dc start-doc "")
(send dc start-page)
;(send dc set-brush ellipse-brush)
(send dc set-smoothing 'smoothed)
(send dc draw-ellipse 0 0 (image-width) (image-height))
(draw-hyperbolic-line dc (image-width))
(send dc end-page)
(send dc end-doc)
