(define-module (trev-guix packages mail)
  #:use-module (gnu packages guile)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses)
                #:prefix license:)
  #:export (mail-scripts))

;; Helpers that drive the notmuch + mbsync + Gmail flow.  The sources live
;; alongside the service code in ../files/mail/bin and are installed onto PATH
;; (the home profile's bin/).  Configs and the scripts refer to one another via
;; ~/.guix-home/profile/bin/<script>.
;;
;; mail-authinfo-password.scm and mail-stage-deleted.scm are plain Guile
;; *modules* (so the channel compiles cleanly); this package turns each into an
;; executable by prepending an `sh' + store-guile trampoline whose entry point
;; is the module's exported `main'.  mail-sync and mail-fetch-gnu-archive are
;; POSIX shell and are installed verbatim.
(define-public mail-scripts
  (package
    (name "mail-scripts")
    (version "1.0")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin (string-append #$output "/bin"))
                (guile (string-append #$guile-3.0 "/bin/guile")))
            (mkdir-p bin)

            ;; Install a Guile module SRC as an executable BIN/NAME: an sh
            ;; trampoline execs the store guile with the module's `main' as the
            ;; entry point, then the module source follows after `!#'.
            (define (install-guile-script name module src)
              (let ((dest (string-append bin "/" name)))
                (call-with-output-file dest
                  (lambda (out)
                    (format out "#!/bin/sh\n")
                    (format out "exec ~a --no-auto-compile -e '(@ (~a) main)' -s \"$0\" \"$@\"\n"
                            guile module)
                    (format out "!#\n")
                    (call-with-input-file src
                      (lambda (in) (dump-port in out)))))
                (chmod dest #o555)))

            (define (install-shell-script name src)
              (let ((dest (string-append bin "/" name)))
                (copy-file src dest)
                (chmod dest #o555)))

            (install-guile-script
             "mail-authinfo-password.scm"
             "trev-guix files mail bin mail-authinfo-password"
             #$(local-file "../files/mail/bin/mail-authinfo-password.scm"))
            (install-guile-script
             "mail-stage-deleted.scm"
             "trev-guix files mail bin mail-stage-deleted"
             #$(local-file "../files/mail/bin/mail-stage-deleted.scm"))
            (install-shell-script
             "mail-sync"
             #$(local-file "../files/mail/bin/mail-sync"))
            (install-shell-script
             "mail-fetch-gnu-archive"
             #$(local-file "../files/mail/bin/mail-fetch-gnu-archive"))))))
    (synopsis "Helper scripts for the notmuch + mbsync + Gmail mail setup")
    (description
     "Helpers that drive the personal mail flow: credential lookup from
@file{authinfo.gpg} and staging deletions as Maildir flags (Guile), plus manual
sync and GNU list archive imports (POSIX shell).  Notmuch tagging is handled by
the @code{notmuch-mbsync} service's tag rules.")
    (home-page "https://example.invalid/mail-scripts")
    (license license:gpl3+)))
