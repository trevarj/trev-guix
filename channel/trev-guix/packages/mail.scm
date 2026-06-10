(define-module (trev-guix packages mail)
  #:use-module (gnu packages guile)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix build-system trivial)
  #:use-module ((guix licenses)
                #:prefix license:)
  #:export (mail-scripts))

;; Helpers that drive the notmuch + mbsync + Gmail flow.  The sources live
;; alongside the service code in ../files/mail/bin; this package installs them
;; onto PATH (the home profile's bin/).  Configs and the scripts themselves
;; refer to one another via ~/.guix-home/profile/bin/<script>.
;;
;; mail-authinfo-password and mail-stage-deleted are Guile scripts; their
;; `exec guile' trampoline is rewritten here to the store guile so they have no
;; PATH dependency.  mail-sync and mail-fetch-gnu-archive are POSIX shell.
(define-public mail-scripts
  (package
    (name "mail-scripts")
    (version "1.0")
    (source
     #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let ((bin (string-append #$output "/bin"))
                (guile (string-append #$guile-3.0 "/bin/guile"))
                (scripts (list (cons "mail-authinfo-password.scm"
                                     #$(local-file
                                        "../files/mail/bin/mail-authinfo-password.scm"))
                               (cons "mail-stage-deleted.scm"
                                     #$(local-file
                                        "../files/mail/bin/mail-stage-deleted.scm"))
                               (cons "mail-sync"
                                     #$(local-file
                                        "../files/mail/bin/mail-sync"))
                               (cons "mail-fetch-gnu-archive"
                                     #$(local-file
                                        "../files/mail/bin/mail-fetch-gnu-archive")))))
            (mkdir-p bin)
            (for-each (lambda (entry)
                        (let ((dest (string-append bin "/"
                                                   (car entry))))
                          (copy-file (cdr entry) dest)
                          (chmod dest #o755))) ;writable for the substitution below
                      scripts)
            ;; Point the Guile scripts at the store guile (no PATH dependency).
            (substitute* (list (string-append bin
                                              "/mail-authinfo-password.scm")
                               (string-append bin "/mail-stage-deleted.scm"))
              (("^exec guile ")
               (string-append "exec " guile " ")))
            (for-each (lambda (entry)
                        (chmod (string-append bin "/"
                                              (car entry)) #o555)) scripts)))))
    (synopsis "Helper scripts for the notmuch + mbsync + Gmail mail setup")
    (description
     "Helpers that drive the personal mail flow: credential lookup from
@file{authinfo.gpg} and staging deletions as Maildir flags (Guile), plus manual
sync and GNU list archive imports (POSIX shell).  Notmuch tagging is handled by
the @code{notmuch-mbsync} service's tag rules.")
    (home-page "https://example.invalid/mail-scripts")
    (license license:gpl3+)))
