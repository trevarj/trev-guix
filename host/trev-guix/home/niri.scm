(define-module (trev-guix home niri)
  #:use-module (gnu)
  #:use-module (gnu home)
  #:use-module (gnu home services)
  #:use-module (gnu home services dotfiles)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu packages)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (trev-guix home base)
  #:use-module (trev-guix services udiskie))

(define (graphical-daemon name command)
  "Return a Shepherd service called NAME running COMMAND.

These daemons need a live Wayland session, which does not exist when Shepherd
starts at login, so they are not auto-started.  Niri's spawn-at-startup runs
\"svc session-start\", which pushes WAYLAND_DISPLAY and friends into Shepherd
and then starts them.  COMMAND is resolved through Shepherd's PATH, which
already covers both the home and system profiles."
  (shepherd-service (provision (list name))
                    (documentation (string-append "Run "
                                                  (symbol->string name) "."))
                    (auto-start? #f)
                    (respawn? #t)
                    (start #~(make-forkexec-constructor '#$command))
                    (stop #~(make-kill-destructor))))

(define %niri-session-daemons
  (list (graphical-daemon 'topbar '("topbar"))
        (graphical-daemon 'hypridle '("hypridle"))
        (graphical-daemon 'awww-normal '("awww-daemon" "-n" "normal"))
        (graphical-daemon 'awww-overview '("awww-daemon" "-n" "overview"))))

(define-public %home-niri-environment
  (home-environment
    (packages %home-base-packages)
    (services
     (append (list (service home-dotfiles-service-type
                            (home-dotfiles-configuration (source-directory
                                                          %dotfiles-directory)
                                                         (directories (list
                                                                       %dotfiles-directory))
                                                         (layout 'stow)
                                                         (packages '("git"
                                                                     "zsh"
                                                                     "guix"
                                                                     "guixboy"
                                                                     "niri"
                                                                     "topbar"
                                                                     "icons"
                                                                     "fuzzel"
                                                                     "gnupg"
                                                                     "hypr"
                                                                     "wallpapers"
                                                                     "X"
                                                                     "bin"
                                                                     "mpv"
                                                                     "rmpc"
                                                                     "yt-dlp"))
                                                         (excluded '("\\.zshenv"
                                                                     "\\.zshrc"
                                                                     "\\.zprofile"))))
                   (service udiskie-service-type)
                   (simple-service 'niri-session-daemons
                                   home-shepherd-service-type
                                   %niri-session-daemons))
             %home-base-services))))
