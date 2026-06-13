(define-module (trev-guix services notmuch-mbsync)
  #:use-module (gnu home services)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu packages base)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:use-module (srfi srfi-13)
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
            notmuch-mbsync-configuration-notmuch-settings
            notmuch-mbsync-configuration-read-only-paths
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

  ;; Config files symlinked into $HOME on activation.  When #f (the default)
  ;; they are GENERATED from this record (accounts/credentials -> .mbsyncrc,
  ;; notmuch-settings -> .notmuch-config); set them to a file-like or path to
  ;; override the generated output with a hand-written file.
  (mbsyncrc-file notmuch-mbsync-configuration-mbsyncrc-file
                 (default #f))
  (notmuch-config-file notmuch-mbsync-configuration-notmuch-config-file
                       (default #f))

  ;; Settings serialized into the generated ~/.notmuch-config.  An alist of
  ;; (KEY . VALUE); list-valued KEYs are joined with `;'.  Recognized keys:
  ;; database-path, user-name, primary-email, other-email (list), new-tags
  ;; (list), new-ignore (list), exclude-tags (list), synchronize-flags (bool).
  (notmuch-settings notmuch-mbsync-configuration-notmuch-settings
                    (default '()))

  ;; Absolute Maildir path prefixes whose physical message copies the delete
  ;; staging must never flag for deletion (e.g. a read-only "forum" account that
  ;; shares deduplicated messages with another account).  Serialized into the
  ;; generated ~/.notmuch-config as `[mailsync] read_only_paths' so both the
  ;; daemon and the manual `mail-sync' read the same single source of truth.
  (read-only-paths notmuch-mbsync-configuration-read-only-paths
                   (default '()))

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

;;; Generate ~/.mbsyncrc and ~/.notmuch-config from the configuration record so
;;; the structured account/credential/notmuch data is the single source of
;;; truth instead of hand-maintained dotfiles.

(define %mbsync-certificate-file
  "/etc/ssl/certs/ca-certificates.crt")
(define %mbsync-group-name
  "mail")

(define (strip-trailing-slash path)
  (if (and (string? path)
           (> (string-length path) 1)
           (char=? (string-ref path
                               (- (string-length path) 1)) #\/))
      (strip-trailing-slash (substring path 0
                                       (- (string-length path) 1))) path))

;; PassCmd that prefers the daemon-exported ENV var and falls back to FALLBACK
;; (the gpg lookup) for manual mbsync / mail-sync runs.  Inner double quotes are
;; escaped because the whole command is itself double-quoted in the rc file.
(define (mbsync-passcmd env fallback)
  (string-append "\"sh -c 'if [ -n \\\"$"
                 env
                 "\\\" ]; then printf %s \\\"$"
                 env
                 "\\\"; else "
                 fallback
                 "; fi'\""))

;; The gpg-lookup command for ENV, taken from the `credentials' list so the
;; PassCmd fallback can never drift from the secret the daemon caches.
(define (credential-fallback-command credentials env)
  (let ((entry (assoc env credentials)))
    (if entry
        (string-join (cdr entry) " ")
        (error "notmuch-mbsync: no credential for pass-env" env))))

;; An mbsync section is a list of (KEY VALUE) directives; a block is a list
;; of sections separated by blank lines.
(define (mbsync-section->string section)
  (string-join (map (lambda (directive)
                      (string-append (car directive) " "
                                     (cadr directive))) section) "\n"))

(define (mbsync-sections->string sections)
  (string-join (map mbsync-section->string sections) "\n\n"))

(define (mbsync-quote-pattern pattern)
  (string-append "\"" pattern "\""))

(define (account->mbsyncrc-block account credentials)
  (let* ((ref (lambda (key)
                (assoc-ref account key)))
         (id (ref 'id))
         (channel (ref 'channel))
         (maildir (ref 'maildir))
         (pass-env (ref 'pass-env))
         (patterns (or (ref 'patterns)
                       '()))
         (base (strip-trailing-slash maildir))
         (remote (string-append channel "-remote"))
         (local (string-append channel "-local")))
    (mbsync-sections->string `((("IMAPAccount" ,id)
                                ("Host" ,(ref 'host))
                                ("User" ,(ref 'user))
                                ("PassCmd" ,(mbsync-passcmd pass-env
                                                            (credential-fallback-command
                                                             credentials
                                                             pass-env)))
                                ("TLSType" "IMAPS")
                                ("CertificateFile" ,%mbsync-certificate-file))
                               (("IMAPStore" ,remote)
                                ("Account" ,id))
                               (("MaildirStore" ,local)
                                ("SubFolders" "Verbatim")
                                ("Path" ,maildir)
                                ("Inbox" ,(string-append base "/INBOX")))
                               (("Channel" ,channel)
                                ("Far" ,(string-append ":" remote ":"))
                                ("Near" ,(string-append ":" local ":"))
                                ("Patterns" ,(string-join (map
                                                           mbsync-quote-pattern
                                                           patterns) " "))
                                ("Create" "Both")
                                ("Expunge" "Both")
                                ("SyncState" "*"))))))

(define (notmuch-mbsync-mbsyncrc config)
  (let* ((accounts (notmuch-mbsync-configuration-accounts config))
         (credentials (notmuch-mbsync-configuration-credentials config))
         (blocks (map (lambda (account)
                        (account->mbsyncrc-block account credentials))
                      accounts))
         (group (mbsync-section->string (cons (list "Group"
                                                    %mbsync-group-name)
                                              (map (lambda (account)
                                                     (list "Channel"
                                                           (assoc-ref account
                                                                      'channel)))
                                                   accounts)))))
    (plain-file "mbsyncrc"
                (string-append (string-join blocks "\n\n") "\n\n" group "\n"))))

;; "a;b;" form notmuch uses for multi-valued fields; "" for the empty list.
(define (notmuch-semicolon-list items)
  (if (null? items) ""
      (string-append (string-join items ";") ";")))

(define (notmuch-config-section name pairs)
  (string-join (cons (string-append "[" name "]")
                     (map (lambda (kv)
                            (string-append (car kv) "="
                                           (cdr kv))) pairs)) "\n"))

(define (notmuch-mbsync-notmuch-config config)
  (let* ((settings (notmuch-mbsync-configuration-notmuch-settings config))
         (get (lambda (key default)
                (let ((value (assoc key settings)))
                  (if value
                      (cdr value) default)))))
    (plain-file "notmuch-config"
                (string-append (notmuch-config-section "database"
                                                       `(("path" unquote
                                                          (get 'database-path
                                                           "/home/trev/Mail"))))
                               "\n\n"
                               (notmuch-config-section "user"
                                                       `(("name" unquote
                                                          (get 'user-name ""))
                                                         ("primary_email"
                                                          unquote
                                                          (get 'primary-email
                                                               ""))
                                                         ("other_email"
                                                          unquote
                                                          (notmuch-semicolon-list
                                                           (get 'other-email
                                                                '())))))
                               "\n\n"
                               (notmuch-config-section "new"
                                                       `(("tags" unquote
                                                          (notmuch-semicolon-list
                                                           (get 'new-tags
                                                                '("new"
                                                                  "unread"))))
                                                         ("ignore" unquote
                                                          (notmuch-semicolon-list
                                                           (get 'new-ignore
                                                                '(".uidvalidity"
                                                                  ".mbsyncstate"))))))
                               "\n\n"
                               (notmuch-config-section "search"
                                                       `(("exclude_tags"
                                                          unquote
                                                          (notmuch-semicolon-list
                                                           (get 'exclude-tags
                                                                '("deleted"
                                                                  "spam"))))))
                               "\n\n"
                               (notmuch-config-section "maildir"
                                                       `(("synchronize_flags"
                                                          unquote
                                                          (if (get 'synchronize-flags
                                                                   #t) "true"
                                                              "false"))))
                               "\n"
                               ;; Custom section read by mail-stage-deleted (via
                               ;; `notmuch config get'): physical copies under
                               ;; these paths are never staged for deletion.
                               (let ((read-only (notmuch-mbsync-configuration-read-only-paths
                                                 config)))
                                 (if (null? read-only) ""
                                     (string-append "\n"
                                                    (notmuch-config-section
                                                     "mailsync"
                                                     `(("read_only_paths" unquote
                                                        (string-join read-only
                                                                     ";"))))
                                                    "\n")))))))

(define (notmuch-mbsync-activate-config-files config)
  (let ((mbsyncrc-source (or (notmuch-mbsync-configuration-mbsyncrc-file
                              config)
                             (notmuch-mbsync-mbsyncrc config)))
        (notmuch-config-source (or (notmuch-mbsync-configuration-notmuch-config-file
                                    config)
                                   (notmuch-mbsync-notmuch-config config))))
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
