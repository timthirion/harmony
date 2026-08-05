#lang racket

;; Shared color palettes used by harmony (hyperbolic) and euclidean (regular
;; Euclidean tilings). Each palette carries:
;;
;;   families  vector of 3 shade-families, each a 5-shade vector from light
;;             to dark. Consumers pick a family by `sector mod 3` and a
;;             shade by `min(depth, 4)`.
;;   center    the "hero" tile color (single distinguished tile).
;;   stroke    tile outlines and other UI ink.
;;   spoke     the light overlay color (spokes / motifs).
;;   disk      background fill for the "tessellated region" (interior of
;;             the Poincaré disk, or the Euclidean canvas).
;;   outer     background fill outside the tessellated region (frame).

(provide (struct-out palette) PALETTES lookup-palette)

(struct palette (families center stroke spoke disk outer) #:transparent)

(define PALETTES
  (hash
   "harmony"
   (palette
    (vector
     (vector "#B8CCE0" "#9DB8D5" "#82A4CA" "#6890BF" "#507CAE")   ; blue
     (vector "#E0B8B8" "#D5A0A0" "#CA8888" "#BF7070" "#AE5858")   ; rose
     (vector "#C0C0CC" "#ABABBA" "#9696A8" "#818196" "#6C6C84"))  ; grey
    "#D0DCE8" "#778899" "#FFFFFF" "#3F4A5E" "#3F4A5E")

   "sunset"
   (palette
    (vector
     (vector "#FFD9A8" "#FFC17F" "#FFA455" "#F1852C" "#D46A15")   ; amber
     (vector "#F7B7B7" "#EE8F8F" "#DE6B6B" "#C64D4D" "#A63838")   ; coral
     (vector "#C9A5CB" "#B282B5" "#98639C" "#7C4A82" "#5F3466"))  ; violet
    "#FFE8CC" "#3A1F1F" "#FFF6E8" "#3F2028" "#3F2028")

   "ocean"
   (palette
    (vector
     (vector "#BCE3E5" "#95CFD3" "#6BBAC1" "#3EA3AD" "#218893")   ; teal
     (vector "#B7D0EB" "#8FB4DE" "#6798CE" "#3F7CBB" "#255E9E")   ; blue
     (vector "#C6C9E6" "#A2A7D8" "#7C86C7" "#5865B4" "#39479A"))  ; indigo
    "#DFF3F4" "#0F2A38" "#EAF7FA" "#153549" "#153549")

   "forest"
   (palette
    (vector
     (vector "#CFE3B5" "#B4D28E" "#95BE64" "#749F41" "#556F27")   ; leaf
     (vector "#D9D2A6" "#C4BB78" "#A89F4E" "#847E31" "#5E5A20")   ; olive
     (vector "#B9C7A3" "#95AB84" "#728C63" "#527048" "#385331"))  ; moss
    "#E9EFD8" "#1F2A18" "#F6F7EA" "#2B311D" "#2B311D")

   "mono"
   (palette
    (vector
     (vector "#DADADA" "#BCBCBC" "#9E9E9E" "#7E7E7E" "#5F5F5F")
     (vector "#CFCFCF" "#B0B0B0" "#909090" "#707070" "#525252")
     (vector "#C4C4C4" "#A4A4A4" "#848484" "#646464" "#464646"))
    "#E5E5E5" "#2A2A2A" "#FFFFFF" "#404040" "#404040")

   "autumn"
   (palette
    (vector
     (vector "#F4C48C" "#E5A16A" "#D07E4A" "#B25D2D" "#8B4318")   ; rust
     (vector "#E0A79A" "#C9846A" "#A9603F" "#8A3F1A" "#6B2810")   ; copper
     (vector "#E4C87A" "#C9A55A" "#A7833F" "#83612B" "#5F401C"))  ; ochre
    "#FFEEDA" "#3C1E10" "#FFF4E4" "#3D2013" "#3D2013")

   "frost"
   (palette
    (vector
     (vector "#E8F1F8" "#C4D9E8" "#97BCD4" "#6A9EBE" "#4383A6")   ; ice
     (vector "#DAE0E5" "#B4BFC7" "#8D9DAA" "#66798A" "#43596E")   ; steel
     (vector "#DDD3E5" "#B7A9CD" "#907FB1" "#6B5990" "#4B3B6C"))  ; lavender
    "#F7FCFF" "#253848" "#FFFFFF" "#253848" "#253848")

   "berry"
   (palette
    (vector
     (vector "#E0B0BE" "#C88192" "#AE5468" "#8C334A" "#661C34")   ; plum
     (vector "#D4A5C6" "#B47AA6" "#8F5285" "#6B3364" "#481B45")   ; magenta
     (vector "#E0AFAD" "#C4837F" "#A55A54" "#813B34" "#5E211E"))  ; wine
    "#F4DAE0" "#2A1220" "#FFF0F4" "#3A1D2F" "#3A1D2F")))

(define (lookup-palette name)
  (hash-ref PALETTES name
            (lambda ()
              (eprintf "Unknown palette '~a'. Available: ~a~n"
                       name
                       (string-join (sort (hash-keys PALETTES) string<?) ", "))
              (exit 1))))
