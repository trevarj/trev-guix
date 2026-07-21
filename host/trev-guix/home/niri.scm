(define-module (trev-guix home niri)
  #:use-module (gnu)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu home services dotfiles)
  #:use-module (gnu packages)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (trev-guix home base)
  #:use-module (trev-guix services udiskie))

(define codex-engineering-skill-directory
  (local-file (string-append
               %dotfiles-directory
               "/agents/.codex/skills/orchestrate-engineering")
              "codex-engineering-skill"
              #:recursive? #t))

(define-public %home-niri-environment
  (home-environment
    (packages %home-base-packages)
    (services
     (cons* (simple-service
             'codex-engineering-skill-directory-link
             home-activation-service-type
             ;; Codex ignores a SKILL.md that is itself a Guix Home symlink.
             (with-imported-modules '((guix build utils))
               #~(begin
                   (use-modules (guix build utils))
                   (let ((target (string-append
                                  (getenv "HOME")
                                  "/.codex/skills/orchestrate-engineering")))
                     (mkdir-p (dirname target))
                     (let ((target-stat (false-if-exception (lstat target))))
                       (when target-stat
                         (if (eq? 'directory (stat:type target-stat))
                             (delete-file-recursively target)
                             (delete-file target))))
                     (symlink #$codex-engineering-skill-directory target)))))
            (service home-dotfiles-service-type
                     (home-dotfiles-configuration (source-directory
                                                   %dotfiles-directory)
                                                  (directories (list
                                                                %dotfiles-directory))
                                                  (layout 'stow)
                                                  (packages '("agents" "zsh"
                                                              "guix"
                                                              "guixboy"
                                                              "niri"
                                                              "gnome-topbar"
                                                              "icons"
                                                              "fuzzel"
                                                              "gnupg"
                                                              "hypr"
                                                              "wallpapers"
                                                              "X"
                                                              "mpd"
                                                              "mpv"
                                                              "rmpc"
                                                              "yt-dlp"))
                                                  (excluded '("\\.zshenv"
                                                              "\\.zshrc"
                                                              "\\.zprofile"
                                                              "\\.codex/skills/orchestrate-engineering/.*"))))
            (service udiskie-service-type) %home-base-services))))
