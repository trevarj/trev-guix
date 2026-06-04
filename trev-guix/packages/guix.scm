(define-module (trev-guix packages guix)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages base)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages guile)
  #:use-module (guix build-system copy)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix packages)
  #:use-module (guix search-paths)
  #:use-module ((guix licenses) #:prefix license:))

(define-public trev-secrets
  (package
    (name "trev-secrets")
    (version "0.1.0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((bin (string-append #$output "/bin"))
                 (share (string-append #$output "/share/trev-guix"))
                 (script (string-append bin "/trev-secrets"))
                 (path (string-append
                        #$(file-append bash "/bin") ":"
                        #$(file-append coreutils "/bin") ":"
                        #$(file-append gnupg "/bin") ":"
                        "/run/current-system/profile/bin")))
            (mkdir-p bin)
            (mkdir-p share)
            (copy-file #$(local-file "../files/scripts/trev-secrets")
                       script)
            (copy-file #$(local-file "../files/secrets.env.gpg")
                       (string-append share "/secrets.env.gpg"))
            (chmod script #o755)
            (wrap-program script `("PATH" ":" prefix (,path)))))))
    (inputs (list bash coreutils gnupg))
    (home-page "https://example.invalid/trev-secrets")
    (synopsis "Local encrypted secrets unlock helper")
    (description
     "trev-secrets decrypts a committed GPG-encrypted environment file into
root-only local system state and applies local machine settings.")
    (license license:gpl3+)))

(define-public guixboy
  (package
    (name "guixboy")
    (version "0.1.0-573d550")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://codeberg.org/trevarj/guixboy.git")
             (commit "573d550717a7529c2f3b6652356bde2b92db0ce0")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "0a76fyh4vp1xjbz3gfawhr4c3za1n5zkm4zp6pkafshb55x0zzpp"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("bin/guixboy" "bin/guixboy")
          ("modules/" "share/guile/site/3.0/")
          ("extensions/guix/extensions/boy.scm"
           "share/guix/extensions/boy.scm")
          ("completions/zsh/_guixboy"
           "share/zsh/site-functions/_guixboy")
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
                  `("GUILE_LOAD_PATH" ":" prefix (,guile-path)))))))))
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
