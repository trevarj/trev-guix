(define-module (trev-guix packages emacs)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix utils)
  #:use-module (gnu packages)
  #:use-module (gnu packages emacs))

(define-public emacs-next-next-pgtk
  (let* ((commit "d0b693e3e9bab30b558962991c55a2f07721fb3f")
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
          (base32 "0aa9jylmsbrdk2k4x7pd79bqjv91k68nxafbp74fwh3h56v5hvbs")))))))
