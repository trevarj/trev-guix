(define-module (trev-guix packages desktop)
  #:use-module (gnu packages)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages wm)
  #:use-module (guix build-system cargo)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix import crate)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:))

(define %gnome-topbar-cargo-lock
  (string-append (dirname (current-filename))
                 "/../files/gnome-topbar-Cargo.lock"))

(define-public gnome-topbar
  (package
    (name "gnome-topbar")
    (version "0.14.1-b6117b7")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/gnome-topbar.git")
             (commit "b6117b787ed77dfabf5bf914d68c99381b6faa68")))
       (file-name (git-file-name name version))
       (sha256
        (base32 "035sjm2lkplzli80j3xa3i2s8azlpsks5nnwnc8yj863dimcxcaq"))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f
      #:cargo-install-paths ''("crates/gnome-topbar")))
    (native-inputs
     (list pkg-config))
    (inputs
     (append (cargo-inputs-from-lockfile
              %gnome-topbar-cargo-lock)
             (map specification->package
                  '("gtk"
                    "gtk4-layer-shell"
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

(define-public trevarj/swaynotificationcenter
  (package
    (inherit swaynotificationcenter)
    (name "swaynotificationcenter")
    (version "0.12.6")
    (source (origin
              (method git-fetch)
              (uri (git-reference
                     (url "https://github.com/trevarj/SwayNotificationCenter")
                     (commit "524fbcf621d02dbbe63be5833da56e2eb930ea6c")))
              (file-name (git-file-name "SwayNotificationCenter" "0.12.6"))
              (sha256
               (base32
                "1m49sdc1jg26maj686p7ixzpi7y5s91mw6ljyl84f5wrd8ixi9b7"))))))
