(define-module (trev-guix packages emacs)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix utils)
  #:use-module (gnu packages)
  #:use-module (gnu packages emacs))

(define-public emacs-next-next-pgtk
  (let* ((commit "0a5e69eaef780e66a88bb6eca4e369b5e337245b")
         (version (git-version "31.0.50" "1" commit)))
    (package
      (inherit emacs-next-pgtk)
      (name "emacs-next-next-pgtk")
      (version version)
      (arguments
       (substitute-keyword-arguments (package-arguments emacs-next-pgtk)
         ((#:tests? tests? #f)
          #f)))
      (source
       (origin
         (inherit (package-source emacs-next-minimal))
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/emacs-mirror/emacs.git")
               (commit commit)))
         (file-name (git-file-name "emacs-next-next-pgtk" commit))
         (sha256
          (base32 "1fb6yb0kid5vcx73phwp1ifxiifv9l3jbjr1ip7hxald2wmml5la")))))))
