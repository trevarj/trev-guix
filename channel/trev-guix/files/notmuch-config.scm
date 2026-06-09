(define-module (trev-guix files notmuch-config)
  #:use-module (trev-guix services notmuch-mbsync)
  #:export (%notmuch-mbsync-configuration %notmuch-tag-rules))

(define (notmuch-config-default-home)
  (or (getenv "HOME")
      (error "notmuch-config: HOME environment variable is required")))

(define (notmuch-config-path env-var fallback)
  (or (getenv env-var) fallback))

(define %notmuch-dotfiles-dir
  (notmuch-config-path "NOTMUCH_DOTFILES_DIR"
                       (string-append (notmuch-config-default-home)
                                      "/Workspace/dotfiles")))

(define %notmuch-mail-dir
  (notmuch-config-path "NOTMUCH_MAIL_DIR"
                       (string-append (notmuch-config-default-home) "/Mail")))

(define %notmuch-dotmail-dir
  (string-append %notmuch-dotfiles-dir "/mail"))

(define %notmuch-tag-rules
  '(((query . "tag:account-main and not path:main/**") (tags -account-main))
    ((query . "tag:account-lists and not path:lists/**") (tags -account-lists))
    ((query . "path:main/**") (tags +account-main))
    ((query . "path:lists/**") (tags +account-lists +lists))
    ((query . "to:guix-devel@gnu.org or cc:guix-devel@gnu.org") (tags
                                                                 +guix-devel
                                                                 +lists))
    ((query . "to:help-guix@gnu.org or cc:help-guix@gnu.org") (tags +guix-help
                                                               +lists))
    ((query . "to:emacs-devel@gnu.org or cc:emacs-devel@gnu.org") (tags
                                                                   +emacs-devel
                                                                   +lists))
    ((query . "to:bug-gnu-emacs@gnu.org or cc:bug-gnu-emacs@gnu.org or to:debbugs.gnu.org or cc:debbugs.gnu.org")
     (tags +emacs-bugs +lists))
    ((query . "path:archive/gnu/guix-devel/**") (tags +guix-devel +lists))
    ((query . "path:archive/gnu/help-guix/**") (tags +guix-help +lists))
    ((query . "path:archive/gnu/emacs-devel/**") (tags +emacs-devel +lists))
    ((query . "path:archive/gnu/bug-gnu-emacs/**") (tags +emacs-bugs +lists))
    ((query . "from:notifications@github.com or from:*noreply.github.com or to:*noreply.github.com or cc:*noreply.github.com")
     (tags +github))
    ((query . "from:noreply@codeberg.org or from:notifications@codeberg.org") (tags
                                                                               +codeberg))
    ((query . "tag:new") (tags -new))))

(define %notmuch-mbsync-configuration
  (notmuch-mbsync-configuration (accounts (list (list (cons 'id "main-gmail")
                                                      (cons 'backend
                                                            'gmail)
                                                      (cons 'channel "main")
                                                      (cons 'maildir
                                                            (string-append
                                                             %notmuch-mail-dir
                                                             "/main/")))
                                                (list (cons 'id "lists-gmail")
                                                      (cons 'backend
                                                            'gmail)
                                                      (cons 'channel "lists")
                                                      (cons 'maildir
                                                            (string-append
                                                             %notmuch-mail-dir
                                                             "/lists/")))))
                                (plugins (list notmuch-mbsync-gmail-plugin))
                                (tag-rules %notmuch-tag-rules)
                                (mbsyncrc-file (string-append
                                                %notmuch-dotmail-dir
                                                "/.mbsyncrc"))
                                (notmuch-config-file (string-append
                                                      %notmuch-dotmail-dir
                                                      "/.notmuch-config"))))
