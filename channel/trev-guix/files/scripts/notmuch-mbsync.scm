(define-module (trev-guix files scripts notmuch-mbsync)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:declarative? #f)

(define (notmuch-mbsync-log level account stage message . args)
  (format #t "[notmuch-mbsync] account=~a stage=~a level=~a "
          (or account "global") stage level)
  (apply format #t message args)
  (newline))

(define (notmuch-mbsync-run dry-run command . args)
  (notmuch-mbsync-log "info"
                      "global"
                      "command-start"
                      "running ~a ~a"
                      command
                      (string-join args " "))
  (if dry-run
      (begin
        (notmuch-mbsync-log "info" "global" "command-skipped"
                            "dry-run prevents execution") #t)
      (let ((status (apply system* command args)))
        (notmuch-mbsync-log "info"
                            "global"
                            "command-result"
                            "finished ~a ~a with status ~a"
                            command
                            (string-join args " ")
                            status)
        (unless (zero? status)
          (error (format #f "command failed: ~a ~a (status ~a)" command
                         (string-join args " ") status))) #t)))

(define (notmuch-mbsync-normalize-command value fallback)
  (cond
    ((string? value)
     (list value))
    ((and (list? value)
          (pair? value)
          (every string? value))
     value)
    (else fallback)))

(define (notmuch-mbsync-append-command-arg command arg)
  (let ((resolved (notmuch-mbsync-normalize-command command #f)))
    (if (or (not resolved)
            (null? resolved))
        (list arg)
        (append resolved
                (list arg)))))

(define (notmuch-mbsync-run-command dry-run value fallback)
  (let ((command (notmuch-mbsync-normalize-command value fallback)))
    (when (and (list? command)
               (pair? command))
      (apply notmuch-mbsync-run dry-run
             (car command)
             (cdr command)))))

(define (notmuch-mbsync-trim-right value)
  (if (string? value)
      (let loop
        ((path value))
        (if (and (positive? (string-length path))
                 (char=? (string-ref path
                                     (- (string-length path) 1)) #\/))
            (loop (substring path 0
                             (- (string-length path) 1))) path)) value))

(define (notmuch-mbsync-ensure-maildir maildir dry-run)
  (let ((maildir-base (notmuch-mbsync-trim-right maildir)))
    (for-each (lambda (path)
                (notmuch-mbsync-run dry-run "mkdir" "-p" path))
              (list maildir-base
                    (string-append maildir-base "/cur")
                    (string-append maildir-base "/new")
                    (string-append maildir-base "/tmp")))))

;;; Tag rules.  Merge config-level and account-level rules (the account wins on
;;; a duplicate query), then apply each as `notmuch tag TAGS -- QUERY'.

(define (notmuch-mbsync-find-rule query rules key-proc)
  (find (lambda (entry)
          (let ((value (key-proc entry)))
            (and (string? value)
                 (string=? query value)))) rules))

(define (notmuch-mbsync-merge-rules-by-key config-rules account-rules key-proc)
  (append account-rules
          (filter (lambda (entry)
                    (not (notmuch-mbsync-find-rule (key-proc entry)
                                                   account-rules key-proc)))
                  config-rules)))

(define (notmuch-mbsync-resolve-tag-rules account config)
  (let ((config-rules (or (assoc-ref config
                                     'tag-rules)
                          '()))
        (account-rules (or (assoc-ref account
                                      'tag-rules)
                           '())))
    (notmuch-mbsync-merge-rules-by-key config-rules account-rules
                                       (lambda (rule)
                                         (assoc-ref rule
                                                    'query)))))

;; Normalize a tags value to a list of strings.  Accepts a list of symbols like
;; '(+emacs-devel +lists), a list of strings, or a single space-separated string.
(define (notmuch-mbsync-normalize-tags tags)
  (cond
    ((null? tags)
     '())
    ((symbol? tags)
     (list (symbol->string tags)))
    ((string? tags)
     (filter (negate string-null?)
             (string-split tags #\space)))
    ((list? tags)
     (append-map (lambda (t)
                   (cond
                     ((symbol? t)
                      (list (symbol->string t)))
                     ((string? t)
                      (list t))
                     (else (error "invalid tag element" t)))) tags))
    (else (error "invalid tags value" tags))))

(define (notmuch-mbsync-apply-tag-rules rules notmuch-command account-id
                                        dry-run)
  (if (null? rules)
      (notmuch-mbsync-log "info" account-id "tag-rules-empty"
                          "no tag rules to apply")
      (begin
        (notmuch-mbsync-log "info" account-id "tag-rules-start"
                            "applying ~a tag rule(s)"
                            (length rules))
        (for-each (lambda (rule)
                    (let ((query (assoc-ref rule
                                            'query))
                          (tags (assoc-ref rule
                                           'tags)))
                      (unless (and query tags)
                        (error "tag rule requires both query and tags keys"
                               rule))
                      (let ((tag-args (notmuch-mbsync-normalize-tags tags)))
                        (notmuch-mbsync-log "info"
                                            account-id
                                            "tag-rule-apply"
                                            "notmuch tag ~a -- ~a"
                                            (string-join tag-args " ")
                                            query)
                        (apply notmuch-mbsync-run dry-run notmuch-command
                               "tag"
                               (append tag-args
                                       (list "--" query)))))) rules)
        (notmuch-mbsync-log "info" account-id "tag-rules-end"
                            "finished applying tag rules"))))

(define (notmuch-mbsync-run-account-sync account-id
                                         channel-name
                                         mbsync-command
                                         notmuch-command
                                         tag-command
                                         tag-rules
                                         maildir
                                         dry-run)
  (notmuch-mbsync-ensure-maildir maildir dry-run)
  (notmuch-mbsync-run-command dry-run
                              (notmuch-mbsync-append-command-arg
                               mbsync-command channel-name) "mbsync")
  (notmuch-mbsync-run-command dry-run
                              (list notmuch-command "new") "notmuch")
  (when tag-command
    (notmuch-mbsync-run-command dry-run tag-command #f))
  ;; Reindex after `tag-command' (e.g. mail-stage-deleted renames files to add
  ;; the Maildir `T' flag) so the final tag pass and push see the new state.
  (notmuch-mbsync-run-command dry-run
                              (list notmuch-command "new") "notmuch")
  (notmuch-mbsync-apply-tag-rules tag-rules notmuch-command account-id dry-run)
  (notmuch-mbsync-run-command dry-run
                              (notmuch-mbsync-append-command-arg
                               mbsync-command channel-name) "mbsync"))

(define (notmuch-mbsync-run-account account config dry-run)
  (let* ((account-id (or (assoc-ref account
                                    'id) "<unnamed>"))
         (channel-name (or (assoc-ref account
                                      'channel)
                           (error "missing channel for account" account-id)))
         (mbsync (or (assoc-ref account
                                'mbsync-command)
                     (assoc-ref config
                                'mbsync-command) "mbsync"))
         (notmuch-command (or (assoc-ref account
                                         'notmuch-command)
                              (assoc-ref config
                                         'notmuch-command) "notmuch"))
         (tag-command (or (assoc-ref account
                                     'tag-command)
                          (assoc-ref config
                                     'tag-command)))
         (maildir (or (assoc-ref account
                                 'maildir)
                      (error "missing maildir for account" account-id)))
         (tag-rules (notmuch-mbsync-resolve-tag-rules account config))
         (enabled? (or (assoc-ref account
                                  'enabled) #t)))
    (notmuch-mbsync-log "info"
                        account-id
                        "account-start"
                        "processing account ~a (enabled=~a, dry-run=~a)"
                        account-id
                        enabled?
                        dry-run)
    (if (not enabled?)
        (notmuch-mbsync-log "info" account-id "skip" "account disabled")
        (begin
          (notmuch-mbsync-run-account-sync account-id
                                           channel-name
                                           mbsync
                                           notmuch-command
                                           tag-command
                                           tag-rules
                                           maildir
                                           dry-run)
          (notmuch-mbsync-log "info" account-id "complete" "done")))))

(define (notmuch-mbsync-run-accounts accounts config dry-run)
  (for-each (lambda (account)
              (notmuch-mbsync-run-account account config dry-run)) accounts))

(define (notmuch-mbsync-main config args)
  (let ((accounts (or (assoc-ref config
                                 'accounts)
                      '()))
        (dry-run (assoc-ref config
                            'dry-run))
        (verbose (assoc-ref config
                            'verbose)))
    (notmuch-mbsync-log "info"
     "global"
     "start"
     "starting notmuch-mbsync with ~a accounts (dry-run=~a, verbose=~a)"
     (length accounts)
     dry-run
     verbose)
    (notmuch-mbsync-log "info" "global" "invocation" "command-line args: ~s"
                        args)
    (match args
      (() (notmuch-mbsync-run-accounts accounts config dry-run))
      (("sync")
       (notmuch-mbsync-run-accounts accounts config dry-run))
      (("--help")
       (display "usage: notmuch-mbsync [sync|--help]\n"))
      (_ (error (format #f "unknown command: ~a"
                        (car args)))))))
