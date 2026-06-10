(define-module (trev-guix services notmuch-mbsync)
  #:use-module (gnu home services)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu packages base)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (notmuch-mbsync-configuration notmuch-mbsync-configuration?
            notmuch-mbsync-configuration-dry-run
            notmuch-mbsync-configuration-verbose
            notmuch-mbsync-configuration-accounts
            notmuch-mbsync-configuration-tag-rules
            notmuch-mbsync-configuration-mbsync-command
            notmuch-mbsync-configuration-notmuch-command
            notmuch-mbsync-configuration-tag-command
            notmuch-mbsync-configuration-mbsyncrc-file
            notmuch-mbsync-configuration-notmuch-config-file
            notmuch-mbsync-configuration-interval-seconds
            notmuch-mbsync-configuration-credentials
            notmuch-mbsync-service-type))

(define-record-type* <notmuch-mbsync-configuration>
                     notmuch-mbsync-configuration
                     make-notmuch-mbsync-configuration
  notmuch-mbsync-configuration?
  (enabled notmuch-mbsync-configuration-enabled
           (default #t))
  (dry-run notmuch-mbsync-configuration-dry-run
           (default #f))
  (verbose notmuch-mbsync-configuration-verbose
           (default #f))

  ;; Accounts to sync, plus the tag rules applied to them.
  (accounts notmuch-mbsync-configuration-accounts
            (default '()))
  (tag-rules notmuch-mbsync-configuration-tag-rules
             (default '()))

  ;; External commands the sync driver invokes.
  (mbsync-command notmuch-mbsync-configuration-mbsync-command
                  (default "mbsync"))
  (notmuch-command notmuch-mbsync-configuration-notmuch-command
                   (default "notmuch"))
  (tag-command notmuch-mbsync-configuration-tag-command
               (default #f))

  ;; Config files symlinked into $HOME on activation.
  (mbsyncrc-file notmuch-mbsync-configuration-mbsyncrc-file
                 (default #f))
  (notmuch-config-file notmuch-mbsync-configuration-notmuch-config-file
                       (default #f))

  ;; Daemon behaviour: how long to sleep between sync passes, and the
  ;; credentials to decrypt ONCE and cache in the environment so that mbsync
  ;; children can read them without re-prompting gpg.  Each credential is
  ;; (ENV-VAR COMMAND ARG ...); COMMAND is run once and its trimmed stdout
  ;; becomes the value of ENV-VAR for the daemon's lifetime.
  (interval-seconds notmuch-mbsync-configuration-interval-seconds
                    (default 600))
  (credentials notmuch-mbsync-configuration-credentials
               (default '())))

(define (notmuch-mbsync-service-program config)
  (let ((script (local-file "../files/scripts/notmuch-mbsync.scm"))
        (accounts (notmuch-mbsync-configuration-accounts config))
        (dry-run (notmuch-mbsync-configuration-dry-run config))
        (verbose (notmuch-mbsync-configuration-verbose config))
        (mbsync-command (notmuch-mbsync-configuration-mbsync-command config))
        (notmuch-command (notmuch-mbsync-configuration-notmuch-command config))
        (tag-command (notmuch-mbsync-configuration-tag-command config))
        (tag-rules (notmuch-mbsync-configuration-tag-rules config))
        (interval (notmuch-mbsync-configuration-interval-seconds config))
        (credentials (notmuch-mbsync-configuration-credentials config)))
    (program-file "notmuch-mbsync-runner"
                  #~(begin
                      (use-modules (ice-9 popen)
                                   (ice-9 rdelim)
                                   (ice-9 match))
                      (load #$script)

                      ;; Run COMMAND once and return its trimmed stdout, or #f on failure
                      ;; / empty output.
                      (define (capture-command command args)
                        (catch #t
                               (lambda ()
                                 (let* ((port (apply open-pipe* OPEN_READ
                                                     command args))
                                        (output (read-string port))
                                        (status (close-pipe port))
                                        (trimmed (and (string? output)
                                                      (string-trim-both output))))
                                   (if (and (zero? (status:exit-val status))
                                            trimmed
                                            (not (string-null? trimmed)))
                                       trimmed
                                       (begin
                                         (format (current-error-port)
                                          "notmuch-mbsync: credential command failed: ~a ~s (status ~a)~%"
                                          command args status) #f))))
                               (lambda (key . args)
                                 (format (current-error-port)
                                  "notmuch-mbsync: credential command error: ~a ~s: ~a ~s~%"
                                  command
                                  args
                                  key
                                  args) #f)))

                      ;; Decrypt each credential at most once and cache it in the daemon's
                      ;; environment.  Failures are not cached, so the next pass retries
                      ;; (e.g. if pinentry was dismissed).
                      (define (ensure-credentials!)
                        (for-each (match-lambda
                                    ((env command . args) (unless (getenv env)
                                                            (let ((value (capture-command
                                                                          command
                                                                          args)))
                                                              (when value
                                                                (setenv env
                                                                        value))))))
                                  '#$credentials))

                      (define notmuch-mbsync-main
                        (module-ref (resolve-module '(trev-guix files scripts
                                                      notmuch-mbsync))
                                    'notmuch-mbsync-main))

                      (define config
                        (list (cons 'accounts
                                    '#$accounts)
                              (cons 'dry-run
                                    #$dry-run)
                              (cons 'verbose
                                    #$verbose)
                              (cons 'mbsync-command
                                    '#$mbsync-command)
                              (cons 'notmuch-command
                                    '#$notmuch-command)
                              (cons 'tag-command
                                    '#$tag-command)
                              (cons 'tag-rules
                                    '#$tag-rules)))

                      ;; Long-lived daemon: decrypt-once, sync, sleep, repeat.  Each pass is
                      ;; wrapped so a transient failure never kills the daemon (and thus
                      ;; never drops the cached secret).
                      (let loop
                        ()
                        (ensure-credentials!)
                        (catch #t
                               (lambda ()
                                 (notmuch-mbsync-main config
                                                      '("sync")))
                               (lambda (key . args)
                                 (format (current-error-port)
                                  "notmuch-mbsync: sync pass failed: ~a ~s~%"
                                  key args)))
                        (sleep #$interval)
                        (loop))))))

(define (notmuch-mbsync-shepherd-service config)
  (if (not (notmuch-mbsync-configuration-enabled config))
      '()
      (list (shepherd-service (provision '(notmuch-mbsync
                                           notmuch-mbsync-service))
                              (modules '((shepherd support))) ;for %user-log-dir
                              ;; Long-lived daemon that holds the decrypted app password in
                              ;; memory between sync passes.  On-demand sync remains available
                              ;; via the `mail-sync' script.
                              (start #~(make-forkexec-constructor (list #$(notmuch-mbsync-service-program
                                                                           config))
                                                                  #:log-file (string-append
                                                                              %user-log-dir
                                                                              "/notmuch-mbsync.log")))
                              (stop #~(make-kill-destructor))
                              (documentation
                               "Synchronize Maildir accounts and sync notmuch tags.")))))

(define (notmuch-mbsync-activate-config-files config)
  (let ((mbsyncrc-source (notmuch-mbsync-configuration-mbsyncrc-file config))
        (notmuch-config-source (notmuch-mbsync-configuration-notmuch-config-file
                                config)))
    #~(begin
        (define (ensure-symlink source target)
          (when source
            (unless (file-exists? source)
              (error (format #f "notmuch-mbsync: missing config source ~a"
                             source)))
            (system* #$(file-append coreutils "/bin/ln") "-sfn" source target)))
        (let ((home (or (getenv "HOME")
                        (error
                         "notmuch-mbsync: HOME is required to create config symlinks"))))
          (ensure-symlink #$mbsyncrc-source
                          (string-append home "/.mbsyncrc"))
          (ensure-symlink #$notmuch-config-source
                          (string-append home "/.notmuch-config"))))))

(define-public notmuch-mbsync-service-type
  (service-type (name 'notmuch-mbsync)
                (extensions (list (service-extension
                                   home-shepherd-service-type
                                   notmuch-mbsync-shepherd-service)
                                  (service-extension
                                   home-activation-service-type
                                   notmuch-mbsync-activate-config-files)))
                (default-value (notmuch-mbsync-configuration))
                (description
                 "Synchronize Maildir accounts with mbsync and notmuch.")))
