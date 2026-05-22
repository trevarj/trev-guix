(define-module (trev-guix systems substitutes)
  #:use-module (srfi srfi-1)
  #:export (%stinkpad-substitute-urls
            stinkpad-substitute-urls))

(define %stinkpad-substitute-urls
  '(("https://ci.guix.gnu.org" . #f)
    ("https://bordeaux.guix.gnu.org" . #f)
    ("https://ci.guix.trop.in" . #t)
    ("https://cache-sg.guix.moe" . #t)
    ("https://cache-cdn.guix.moe" . #f)
    ("https://cache-fi.guix.moe" . #f)
    ("https://bordeaux-singapore-mirror.cbaines.net" . #t)
    ("https://guix.bordeaux.inria.fr" . #t)
    ("https://mirror.yandex.ru/mirrors/guix" . #f)
    ("https://nonguix-proxy.ditigal.xyz" . #t)
    ("https://substitutes.nonguix.org" . #t)
    ("https://ci.guix.trevs.site" . #f)))

(define (stinkpad-substitute-urls)
  (filter-map (lambda (entry)
                (and (cdr entry)
                     (car entry)))
              %stinkpad-substitute-urls))
