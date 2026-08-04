(define-module (trev-guix packages desktop)
  #:use-module (gnu packages)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages vulkan)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system cargo)
  #:use-module (guix build-system copy)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix import crate)
  #:use-module (guix packages)
  #:use-module ((guix licenses)
                #:prefix license:))

(define %spacesniffer1000-cargo-lock
  (or (search-path %load-path "trev-guix/files/spacesniffer1000-Cargo.lock")
      (error "could not find spacesniffer1000-Cargo.lock in load path")))

(define %gnome-topbar-cargo-lock
  (or (search-path %load-path "trev-guix/files/gnome-topbar-Cargo.lock")
      (error "could not find gnome-topbar-Cargo.lock in load path")))

(define-public spacesniffer1000
  (package
    (name "spacesniffer1000")
    (version "0.1.0-498c3d2")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/spacesniffer1000.git")
             (commit "498c3d2805ce6dc09a9b5478730439ae401e4532")))
       (file-name (git-file-name name version))
       (hash (content-hash "0fq6y8m37ba4ldmhx5glwd66xvasdajclplc6b32l8ya0b69fmri"))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f))
    (native-inputs (list pkg-config rust))
    (inputs (append (cargo-inputs-from-lockfile %spacesniffer1000-cargo-lock)
                    (list libxkbcommon wayland wayland-protocols vulkan-loader)))
    (home-page "https://github.com/trevarj/spacesniffer1000")
    (synopsis "Native graphical disk space visualizer")
    (description
     "SpaceSniffer1000 is an egui desktop application for exploring filesystem
usage with a clickable treemap.")
    (license license:expat)))

(define-public gnome-topbar
  (package
    (name "gnome-topbar")
    (version "1.0.0-0eb98d5")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/gnome-topbar.git")
             (commit "0eb98d5154bc6de270d5ebc8444f048c7c72785b")))
       (file-name (git-file-name name version))
       (hash (content-hash
              "1yd0628qjmmsxkv2rsmjwm8vhqprsv9a4as6kxp2b8b53h8sb6j0"))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f
      #:cargo-install-paths ''("crates/gnome-topbar")))
    (native-inputs (list pkg-config))
    (inputs (append (cargo-inputs-from-lockfile %gnome-topbar-cargo-lock)
                    (map specification->package
                         '("gtk" "gtk4-layer-shell"
                           "glib"
                           "dbus"
                           "eudev"
                           "pango"
                           "gdk-pixbuf"
                           "cairo"
                           "graphene"
                           "pulseaudio"
                           "upower"
                           "network-manager"
                           "bluez"))))
    (home-page "https://github.com/trevarj/gnome-topbar")
    (synopsis "GNOME Shell-inspired GTK top bar for Wayland")
    (description
     "GNOME Topbar is a Wayland-only GTK top bar inspired by GNOME Shell.  It
provides a continuous system panel with notifications, quick settings, media
controls, workspaces, and custom script modules.")
    (license license:expat)))

(define-public pinentry-fuzzguy
  (package
    (name "pinentry-fuzzguy")
    (version "1.0.1-a9a33a5")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/pinentry-fuzzguy.git")
             (commit "a9a33a5eb8201463f79e1e38b0d3cb442295a763")))
       (file-name (git-file-name name version))
       (hash (content-hash
              "0vdk9l5xwaxl0v9hbn0j6hsmn9k15j2y8qxrr5wh9qyx8mlzh1d8"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan #~'(("pinentry-fuzzguy" "bin/pinentry-fuzzguy"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'configure-paths
            (lambda _
              (substitute* "pinentry-fuzzguy"
                (("/usr/bin/env python3")
                 #$(file-append python "/bin/python3"))
                (("@FUZZEL@")
                 #$(file-append fuzzel "/bin/fuzzel"))
                (("@PINENTRY_TTY@")
                 #$(file-append pinentry-tty "/bin/pinentry-tty")))))
          (add-before 'install 'check
            (lambda _
              (invoke #$(file-append python "/bin/python3")
                      "-m" "unittest" "discover" "-s" "tests" "-v"))))))
    (inputs (list fuzzel pinentry-tty python))
    (home-page "https://github.com/trevarj/pinentry-fuzzguy")
    (synopsis "Fuzzel-based pinentry with protocol context")
    (description
     "Pinentry Fuzzguy is a small pinentry implementation for Wayland.  It uses
Fuzzel for passphrase prompts, displays context supplied by gpg-agent, and falls
back to pinentry-tty when a graphical prompt is unavailable.")
    (license license:gpl3+)))
