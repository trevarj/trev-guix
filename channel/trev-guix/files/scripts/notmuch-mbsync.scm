(define-module (trev-guix files scripts notmuch-mbsync)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 ftw)
  #:use-module (srfi srfi-1)
  #:declarative? #f)

(define *notmuch-mbsync-plugins*
  '())

(define (notmuch-mbsync-register-plugin plugin)
  (define backend
    (assoc-ref plugin
               'backend))
  (unless backend
    (error "plugin registration requires a backend identifier"))
  (set! *notmuch-mbsync-plugins*
        (cons plugin *notmuch-mbsync-plugins*)))

(define (notmuch-mbsync-plugin-path plugin-entry)
  (cond
    ((string? plugin-entry)
     plugin-entry)
    ((and (pair? plugin-entry)
          (string? (cdr plugin-entry)))
     (cdr plugin-entry))
    (else (error
           "invalid plugin entry: expected a string path or (KEY . PATH) pair"
           plugin-entry))))

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

(define (notmuch-mbsync-find-plugin backend)
  (find (lambda (plugin)
          (eq? (assoc-ref plugin
                          'backend) backend)) *notmuch-mbsync-plugins*))

(define (notmuch-mbsync-load-plugins plugin-files)
  (notmuch-mbsync-log "info" "global" "plugins-load-start"
                      "loading ~a plugin file(s)"
                      (length plugin-files))
  (set! *notmuch-mbsync-plugins*
        '())
  (let loop
    ((entries plugin-files))
    (unless (null? entries)
      (let ((entry (car entries))
            (rest (cdr entries)))
        (let ((path (notmuch-mbsync-plugin-path entry)))
          (unless (file-exists? path)
            (error "plugin file not found: ~a" path))
          (notmuch-mbsync-log "info" "global" "plugins-load"
                              "loading plugin file ~a" path)
          (save-module-excursion (lambda ()
                                   (set-current-module (resolve-module '(trev-guix
                                                                         files
                                                                         scripts
                                                                         notmuch-mbsync)))
                                   (load path))))
        (loop rest))))
  (notmuch-mbsync-log "info" "global" "plugins-load-end"
                      "loaded ~a plugin file(s) total"
                      (length *notmuch-mbsync-plugins*))
  *notmuch-mbsync-plugins*)

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

(define (notmuch-mbsync-ensure-maildir maildir dry-run)
  (let ((maildir-base (notmuch-mbsync-trim-right maildir)))
    (for-each (lambda (path)
                (notmuch-mbsync-run dry-run "mkdir" "-p" path))
              (list maildir-base
                    (string-append maildir-base "/cur")
                    (string-append maildir-base "/new")
                    (string-append maildir-base "/tmp")))))

(define (notmuch-mbsync-run-command dry-run value fallback)
  (let ((command (notmuch-mbsync-normalize-command value fallback)))
    (when (and (list? command)
               (pair? command))
      (apply notmuch-mbsync-run dry-run
             (car command)
             (cdr command)))))

(define (notmuch-mbsync-lookup-rule query rules)
  (find (lambda (entry)
          (and (string? (car entry))
               (string=? query
                         (car entry)))) rules))

(define (notmuch-mbsync-find-rule query rules key-proc)
  (find (lambda (entry)
          (let ((value (key-proc entry)))
            (and (string? value)
                 (string=? query value)))) rules))

(define (notmuch-mbsync-merge-rules-by-key plugin-rules account-rules key-proc)
  (append account-rules
          (filter (lambda (entry)
                    (not (notmuch-mbsync-find-rule (key-proc entry)
                                                   account-rules key-proc)))
                  plugin-rules)))

(define (notmuch-mbsync-merge-rules plugin-rules account-rules)
  (notmuch-mbsync-merge-rules-by-key plugin-rules account-rules car))

(define (notmuch-mbsync-lookup-tag-rule query rules)
  (notmuch-mbsync-find-rule query rules
                            (lambda (rule)
                              (assoc-ref rule
                                         'query))))

(define (notmuch-mbsync-merge-tag-rules config-rules account-rules)
  (notmuch-mbsync-merge-rules-by-key config-rules account-rules
                                     (lambda (rule)
                                       (assoc-ref rule
                                                  'query))))

(define (notmuch-mbsync-resolve-tag-rules account config)
  (let ((config-rules (or (assoc-ref config
                                     'tag-rules)
                          '()))
        (account-rules (or (assoc-ref account
                                      'tag-rules)
                           '())))
    (notmuch-mbsync-merge-tag-rules config-rules account-rules)))

;; Normalize tags value to a list of strings.
;; Accepts a list of symbols like '(+emacs-devel +lists), a list of strings,
;; or a single space-separated string.
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

;; Apply tag rules by normalizing tags and passing each as a separate
;; argument to `notmuch tag`.
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

(define (notmuch-mbsync-collect-notmuch-files query notmuch-command)
  (notmuch-mbsync-log "info" "global" "collect-start"
                      "collecting files for query: ~a" query)
  (let ((port (open-pipe* OPEN_READ
                          notmuch-command
                          "search"
                          "--output=files"
                          "--"
                          query)))
    (let loop
      ((files '())
       (line (read-line port)))
      (if (eof-object? line)
          (begin
            (let ((status (close-pipe port)))
              (unless (zero? (status:exit-val status))
                (error (format #f "notmuch search failed for ~a" query)))
              (let ((results (reverse files)))
                (notmuch-mbsync-log "info"
                                    "global"
                                    "collect-end"
                                    "query ~a returned ~a file(s)"
                                    query
                                    (length results)) results)))
          (loop (if (string-null? line) files
                    (cons line files))
                (read-line port))))))

(define (notmuch-mbsync-trim-right value)
  (if (string? value)
      (let loop
        ((path value))
        (if (and (positive? (string-length path))
                 (char=? (string-ref path
                                     (- (string-length path) 1)) #\/))
            (loop (substring path 0
                             (- (string-length path) 1))) path)) value))

(define (notmuch-mbsync-join-path a b)
  (let ((a-trimmed (notmuch-mbsync-trim-right a))
        (b-trimmed (if (string-prefix? "/" b)
                       (substring b 1) b)))
    (string-append a-trimmed "/" b-trimmed)))

(define (notmuch-mbsync-basename path)
  (let ((parts (string-split path #\/)))
    (if (null? parts) path
        (last parts))))

(define (notmuch-mbsync-resolve-target target)
  (let loop
    ((index 0)
     (candidate (if (file-exists? target)
                    (string-append target ".1") target)))
    (if (not (file-exists? candidate)) candidate
        (loop (+ index 1)
              (string-append target "."
                             (number->string (+ index 1)))))))

(define (notmuch-mbsync-move-message path maildir target-folder dry-run)
  (let* ((subdir (if (string-suffix? "/new" path) "new" "cur"))
         (target-dir (notmuch-mbsync-join-path (notmuch-mbsync-join-path
                                                maildir target-folder) subdir))
         (target (notmuch-mbsync-join-path target-dir
                                           (notmuch-mbsync-basename path)))
         (target-resolved (notmuch-mbsync-resolve-target target)))
    (if (string=? path target)
        (notmuch-mbsync-log "info" maildir "move-skip" "already in target ~a"
                            target)
        (if dry-run
            (notmuch-mbsync-log "info"
                                maildir
                                "move-dry-run"
                                "would move ~a -> ~a"
                                path
                                target-resolved)
            (begin
              (notmuch-mbsync-run #f "mkdir" "-p" target-dir)
              (when (not (string=? target target-resolved))
                (notmuch-mbsync-log "warn"
                                    maildir
                                    "move-target-conflict"
                                    "target exists, using ~a instead of ~a"
                                    target-resolved
                                    target))
              (rename-file path target-resolved)
              (notmuch-mbsync-log "info"
                                  maildir
                                  "move-ok"
                                  "moved ~a -> ~a"
                                  path
                                  target-resolved))))))

(define (notmuch-mbsync-move-query-rules rules maildir account-id
                                         notmuch-command dry-run)
  (for-each (lambda (rule)
              (let* ((query (car rule))
                     (folder (cdr rule))
                     (files (notmuch-mbsync-collect-notmuch-files query
                             notmuch-command)))
                (if (null? files)
                    (notmuch-mbsync-log "info" account-id "move-empty"
                                        "no matches for query ~a" query)
                    (begin
                      (notmuch-mbsync-log "info"
                       account-id
                       "move-start"
                       "moving ~a files for query ~a to ~a"
                       (length files)
                       query
                       folder)
                      (for-each (lambda (path)
                                  (notmuch-mbsync-move-message path maildir
                                                               folder dry-run))
                                files))))) rules))

(define (notmuch-mbsync-run-account-sync account-id
                                         channel-name
                                         mbsync-command
                                         notmuch-command
                                         tag-command
                                         tag-rules
                                         rules
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
  (notmuch-mbsync-move-query-rules rules maildir account-id notmuch-command
                                   dry-run)
  (notmuch-mbsync-run-command dry-run
                              (list notmuch-command "new") "notmuch")
  ;; Apply tag rules after post-move reindex so the final DB state is normalized.
  (notmuch-mbsync-apply-tag-rules tag-rules notmuch-command account-id dry-run)
  (notmuch-mbsync-run-command dry-run
                              (notmuch-mbsync-append-command-arg
                               mbsync-command channel-name) "mbsync"))

(define (notmuch-mbsync-resolve-account-rules account)
  (match (notmuch-mbsync-find-plugin (assoc-ref account
                                                'backend))
    (#f (error "unknown backend"
               (assoc-ref account
                          'backend)))
    (plugin (notmuch-mbsync-merge-rules (or (assoc-ref plugin
                                                       'default-move-rules)
                                            '())
                                        (or (assoc-ref account
                                                       'move-rules)
                                            '())))))

(define (notmuch-mbsync-run-account account config dry-run)
  (let* ((account-id (or (assoc-ref account
                                    'id) "<unnamed>"))
         (channel-name (assoc-ref account
                                  'channel))
         (channel-name (or channel-name
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
         (rules (notmuch-mbsync-resolve-account-rules account))
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
                                           rules
                                           maildir
                                           dry-run)
          (notmuch-mbsync-log "info" account-id "complete" "done")))))

(define (notmuch-mbsync-run-accounts accounts config dry-run)
  (for-each (lambda (account)
              (notmuch-mbsync-run-account account config dry-run)) accounts))

(define (notmuch-mbsync-main config args)
  (let* ((plugins (or (assoc-ref config
                                 'plugins)
                      '()))
         (accounts (or (assoc-ref config
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
    (notmuch-mbsync-load-plugins plugins)
    (match args
      (() (notmuch-mbsync-run-accounts accounts config dry-run))
      (("sync")
       (notmuch-mbsync-run-accounts accounts config dry-run))
      (("--help")
       (display "usage: notmuch-mbsync [sync|--help]\n"))
      (_ (error (format #f "unknown command: ~a"
                        (car args)))))))
