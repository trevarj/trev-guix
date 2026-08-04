(define-module (trev-guix home base)
  #:use-module (gnu)
  #:use-module (gnu home)
  #:use-module (gnu home services desktop)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu home services shells)
  #:use-module (gnu home services sound)
  #:use-module (gnu packages)
  #:use-module (gnu services)
  #:use-module (guix gexp)
  #:use-module (nongnu packages firmware)
  #:use-module (trev-guix files notmuch-config)
  #:use-module (trev-guix packages ai)
  #:use-module (trev-guix packages desktop)
  #:use-module (trev-guix packages emacs)
  #:use-module (trev-guix packages fonts)
  #:use-module (trev-guix packages guix)
  #:use-module (trev-guix packages mail)
  #:use-module (trev-guix packages music)
  #:use-module (trev-guix packages networking)
  #:use-module (trev-guix services flatpak)
  #:use-module (trev-guix services fontconfig)
  #:use-module (trev-guix services networking)
  #:use-module (trev-guix services notmuch-mbsync))

(use-package-modules admin
                     aspell
                     audio
                     compression
                     containers
                     curl
                     emacs-xyz
                     file-systems
                     fonts
                     freedesktop
                     glib
                     gnome
                     gnome-xyz
                     gnupg
                     gnu-doc
                     guile
                     hardware
                     image-viewers
                     linux
                     mail
                     mpd
                     package-management
                     rust-apps
                     shells
                     shellutils
                     ssh
                     terminals
                     tls
                     tor
                     version-control
                     video
                     vim
                     vpn
                     web
                     xdisorg)

(eval-when (expand load eval)
           (define-public %dotfiles-directory
             "/home/trev/Workspace/dotfiles")

           (define-public %home-base-packages
             (list adwaita-icon-theme
                   aspell
                   aspell-dict-en
                   aspell-dict-ru
                   btop
                   byedpi
                   claude-code
                   codex
                   curl
                   difftastic
                   direnv
                   distrobox
                   ddcutil
                   ;; easyeffects
                   ;; emacs-next-next-pgtk
                   ;; (list emacs-next-next-pgtk "doc")
                   emacs-wlshm
                   (list emacs-wlshm "doc")
                   emacs-guix
                   emacs-vterm
                   eza
                   fd
                   flatpak
                   font-cryptofont
                   font-google-noto
                   font-google-noto-emoji
                   font-google-noto-sans-cjk
                   font-iosevka-ss12
                   font-nerd-symbols
                   font-terminus
                   forgejo-cli
                   fzf
                   fzf-tab
                   ;; fwupd-nonfree ; bringing in a lot of weird packages
                   gac
                   git
                   (list git "send-email")
                   (list glib "bin")
                   github-cli
                   gnupg
                   gnu-standards
                   guile-next
                   guixboy
                   guix-weather-plus
                   headsetcontrol
                   hicolor-icon-theme
                   imv
                   isync
                   jq
                   kg
                   kitty
                   mail-scripts
                   mpd
                   mpv
                   msmtp
                   nautilus
                   neofetch
                   netcat
                   notmuch
                   ollama
                   papirus-icon-theme
                   pinentry-tty
                   pinentry-fuzzguy
                   ripgrep
                   rmpc
                   stow
                   tlp
                   torsocks
                   unzip
                   wireguard-tools
                   wl-clipboard
                   xdg-utils
                   yoink
                   yt-dlp
                   zsh
                   zsh-autopair
                   zsh-autosuggestions
                   zsh-completions
                   zsh-syntax-highlighting))

           ;; Guix has no home-mpd-service-type (only home-beets in (gnu home
           ;; services music)), so the config and the daemon are declared here.
           ;; The Nix host gets the equivalent from Home Manager's services.mpd.
           (define %mpd-configuration-file
             (plain-file "mpd.conf"
                         "\
music_directory \"~/Music\"
playlist_directory \"~/.local/share/mpd/playlists\"
db_file \"~/.cache/mpd/database\"
state_file \"~/.cache/mpd/state\"
sticker_file \"~/.cache/mpd/sticker.sql\"
log_file \"~/.cache/mpd/log\"
bind_to_address \"127.0.0.1\"
port \"6600\"
auto_update \"yes\"
restore_paused \"yes\"
audio_output {
  type \"pipewire\"
  name \"PipeWire\"
}
"))

           ;; Unlike the niri session daemons this needs no Wayland session, so
           ;; it auto-starts with Shepherd.  It expects ~/.cache/mpd and
           ;; ~/.local/share/mpd/playlists to exist; mpd does not create them.
           (define %mpd-shepherd-service
             (shepherd-service (provision '(mpd))
                               (documentation "Run the MPD music daemon.")
                               (respawn? #t)
                               (start #~(make-forkexec-constructor
                                         (list "mpd" "--no-daemon"
                                               #$%mpd-configuration-file)))
                               (stop #~(make-kill-destructor))))

           (define-public %home-base-services
             (list (service home-dbus-service-type)
                   (simple-service 'mpd
                                   home-shepherd-service-type
                                   (list %mpd-shepherd-service))
                   (service home-pipewire-service-type)
                   (service home-zsh-service-type
                            (home-zsh-configuration (xdg-flavor? #f)
                                                    (zshenv (list (local-file (string-append
                                                                               %dotfiles-directory
                                                                               "/zsh/.zshenv")
                                                                   "zshenv")))
                                                    (zshrc (list (local-file (string-append
                                                                              %dotfiles-directory
                                                                              "/zsh/.zshrc")
                                                                  "zshrc")))
                                                    (zprofile (list (local-file
                                                                     (string-append
                                                                      %dotfiles-directory
                                                                      "/zsh/.zprofile")
                                                                     "zprofile")))
                                                    (environment-variables '(("ASPELL_DICT_DIR" . "${HOME}/.guix-home/profile/lib/aspell")))))
                   (service home-flatpak-service-type
                            (home-flatpak-configuration (applications '("com.bambulab.BambuStudio"
                                                                        "com.brave.Browser"
                                                                        "com.github.tchx84.Flatseal"
                                                                        "com.transmissionbt.Transmission"
                                                                        "org.freecad.FreeCAD"
                                                                        "org.gimp.GIMP"
                                                                        "org.telegram.desktop"))))
                   (service byedpi-service-type)
                   (service notmuch-mbsync-service-type
                            %notmuch-mbsync-configuration)
                   %home-fontconfig-service-extension)))
