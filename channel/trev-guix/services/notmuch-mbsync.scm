(define-module (trev-guix services notmuch-mbsync)
  #:use-module (gnu home services)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu packages base)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (notmuch-mbsync-gmail-plugin notmuch-mbsync-configuration
            notmuch-mbsync-configuration?
            notmuch-mbsync-configuration-schedule
            notmuch-mbsync-configuration-dry-run
            notmuch-mbsync-configuration-verbose
            notmuch-mbsync-configuration-accounts
            notmuch-mbsync-configuration-plugins
            notmuch-mbsync-configuration-mbsync-command
            notmuch-mbsync-configuration-notmuch-command
            notmuch-mbsync-configuration-mbsyncrc-file
            notmuch-mbsync-configuration-notmuch-config-file
            notmuch-mbsync-configuration-tag-command
            notmuch-mbsync-configuration-tag-rules
            notmuch-mbsync-configuration-max-duration
            notmuch-mbsync-service-type))

(define-record-type* <notmuch-mbsync-configuration>
                     notmuch-mbsync-configuration
                     make-notmuch-mbsync-configuration
  notmuch-mbsync-configuration?
  (enabled notmuch-mbsync-configuration-enabled
           (default #t))
  (schedule notmuch-mbsync-configuration-schedule
            (default "*/10 * * * *"))
  (dry-run notmuch-mbsync-configuration-dry-run
           (default #f))
  (verbose notmuch-mbsync-configuration-verbose
           (default #f))
  (plugins notmuch-mbsync-configuration-plugins
           (default '()))
  (accounts notmuch-mbsync-configuration-accounts
            (default '()))
  (mbsync-command notmuch-mbsync-configuration-mbsync-command
                  (default "mbsync"))
  (notmuch-command notmuch-mbsync-configuration-notmuch-command
                   (default "notmuch"))
  (mbsyncrc-file notmuch-mbsync-configuration-mbsyncrc-file
                 (default #f))
  (notmuch-config-file notmuch-mbsync-configuration-notmuch-config-file
                       (default #f))
  (tag-command notmuch-mbsync-configuration-tag-command
               (default #f))
  (tag-rules notmuch-mbsync-configuration-tag-rules
             (default '()))
  (max-duration notmuch-mbsync-configuration-max-duration
                (default 900)))

;; Gmail plugin file for notmuch-mbsync
(define notmuch-mbsync-gmail-plugin
  (local-file "../files/scripts/notmuch-mbsync-plugins/gmail.scm"))

(define (notmuch-mbsync-service-program config)
  (let ((script (local-file "../files/scripts/notmuch-mbsync.scm"))
        (plugin-list (notmuch-mbsync-configuration-plugins config)))
    (program-file "notmuch-mbsync-runner"
                  #~(begin
                      (load #$script)
                      (let ((notmuch-mbsync-main (module-ref (resolve-module '
                                                                             (trev-guix
                                                                              files
                                                                              scripts
                                                                              notmuch-mbsync))
                                                             'notmuch-mbsync-main)))
                        (notmuch-mbsync-main (list (cons 'plugins
                                                         '#$plugin-list)
                                                   (cons 'accounts
                                                         '#$(notmuch-mbsync-configuration-accounts
                                                             config))
                                                   (cons 'dry-run
                                                         #$(notmuch-mbsync-configuration-dry-run
                                                            config))
                                                   (cons 'verbose
                                                         #$(notmuch-mbsync-configuration-verbose
                                                            config))
                                                   (cons 'mbsync-command
                                                         '#$(notmuch-mbsync-configuration-mbsync-command
                                                             config))
                                                   (cons 'notmuch-command
                                                         '#$(notmuch-mbsync-configuration-notmuch-command
                                                             config))
                                                   (cons 'tag-command
                                                         '#$(notmuch-mbsync-configuration-tag-command
                                                             config))
                                                   (cons 'tag-rules
                                                         '#$(notmuch-mbsync-configuration-tag-rules
                                                             config)))
                                             (cdr (command-line))))))))

(define (notmuch-mbsync-shepherd-service config)
  (if (not (notmuch-mbsync-configuration-enabled config))
      '()
      (let ((schedule (notmuch-mbsync-configuration-schedule config)))
        (list (shepherd-service (provision '(notmuch-mbsync
                                             notmuch-mbsync-service))
                                (modules '((shepherd service timer)))
                                (start #~(make-timer-constructor #$(if (string?
                                                                        schedule)
                                                                    #~(cron-string->calendar-event #$schedule)
                                                                    schedule)
                                                                 (command (list #$
                                                                           (notmuch-mbsync-service-program
                                                                            config)
                                                                           "sync"))
                                                                 #:wait-for-termination?
                                                                 #t
                                                                 #:log-file (string-append
                                                                             (or
                                                                              (getenv
                                                                               "XDG_STATE_HOME")

                                                                              
                                                                              (string-append
                                                                               (or
                                                                                (getenv
                                                                                 "HOME")
                                                                                "/tmp")
                                                                               "/.local/state"))
                                                                             "/shepherd/notmuch-mbsync.log")
                                                                 #:max-duration #$
                                                                 (notmuch-mbsync-configuration-max-duration
                                                                  config)))
                                (stop #~(make-timer-destructor))
                                (actions (list shepherd-trigger-action))
                                (documentation
                                 "Synchronize Maildir accounts and sync notmuch tags."))))))

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
        (let ((home (getenv "HOME")))
          (define (home-directory)
            (or home
                (error
                 "notmuch-mbsync: HOME is required to create config symlinks")))
          (ensure-symlink #$mbsyncrc-source
                          (string-append (home-directory) "/.mbsyncrc"))
          (ensure-symlink #$notmuch-config-source
                          (string-append (home-directory) "/.notmuch-config"))))))

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
