(define-module (trev-guix packages guix)
  #:use-module (gnu packages guile)
  #:use-module (guix build-system copy)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix search-paths)
  #:use-module ((guix licenses)
                #:prefix license:))

(define-public guixboy
  (package
    (name "guixboy")
    (version "0.1.0-5d02a6a")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/trevarj/guixboy.git")
             (commit "5d02a6ad5cc0a9f6b070bd2fb16d7a0bc3468514")))
       (file-name (git-file-name name version))
       (hash (content-hash
              "07ldh6y2xb7jxvqjza746myvlvb6f7hzn1745k0r2vz5qhl622yk"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("bin/guixboy" "bin/guixboy")
          ("modules/" "share/guile/site/3.0/")
          ("extensions/guix/extensions/boy.scm"
           "share/guix/extensions/boy.scm")
          ("completions/zsh/_guixboy" "share/zsh/site-functions/_guixboy")
          ("README.md" "share/doc/guixboy/README.md")
          ("assets/" "share/doc/guixboy/assets/")
          ("doc/guixboy.texi" "share/doc/guixboy/guixboy.texi")
          ("doc/guixboy.info" "share/info/guixboy.info"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'wrap-guixboy
            (lambda _
              ;; Keep modules discoverable when running the standalone binary.
              (let ((guile-path (string-append #$output
                                               "/share/guile/site/3.0")))
                (chmod (string-append #$output "/bin/guixboy") #o755)
                (wrap-program (string-append #$output "/bin/guixboy")
                  `("GUILE_LOAD_PATH" ":" prefix
                    (,guile-path)))))))))
    (inputs (list guile-3.0 guile-json-4))
    (native-search-paths
     (list (search-path-specification
            (variable "GUILE_LOAD_PATH")
            (files '("share/guile/site/3.0")))
           (search-path-specification
            (variable "GUIX_EXTENSIONS_PATH")
            (files '("share/guix/extensions")))))
    (home-page "https://example.invalid/guixboy")
    (synopsis "Guix System helper megatool")
    (description
     "Guixboy provides a Guile command-line interface for common Guix System
maintenance workflows, including configured reconfiguration targets, update
checks, substitute URL aliases, garbage-collection recipes, profile discovery,
and beginner-oriented explanations.")
    (license license:gpl3+)))
