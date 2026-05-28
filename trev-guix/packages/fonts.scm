(define-module (trev-guix packages fonts)
  #:use-module (gnu)
  #:use-module (gnu packages fonts)
  #:use-module (guix)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix build-system font)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses) #:prefix license:))

(define-public font-iosevka-jbm
  (package
    (name "font-iosevka-jbm")
    (version "1.0.0")
    (source (local-file "../files/fonts-IosevkaJbm" #:recursive? #t))
    (build-system font-build-system)
    (description "My custom Iosevka font inspired by JetBrains Mono.")
    (home-page "https://www.nerdfonts.com/")
    (synopsis "Jetbrains Mono Iosevka variant")
    (license license:expat)))

(define-public font-cryptofont
  (package
    (name "font-cryptofonts")
    (version "1.0.0")
    (source (local-file "../files/cryptofont.ttf"))
    (build-system font-build-system)
    (description "A font for cryptocurrency symbols")
    (home-page "N/A")
    (synopsis "A font for cryptocurrency symbols")
    (license license:expat)))
