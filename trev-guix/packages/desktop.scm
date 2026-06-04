(define-module (trev-guix packages desktop)
  #:use-module (gnu packages)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages vulkan)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system cargo)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix import crate)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:))

(define %spacesniffer1000-cargo-lock
  (or (search-path %load-path "trev-guix/files/spacesniffer1000-Cargo.lock")
      (error "could not find spacesniffer1000-Cargo.lock in load path")))

(define %gnome-topbar-cargo-lock
  (or (search-path %load-path "trev-guix/files/gnome-topbar-Cargo.lock")
      (error "could not find gnome-topbar-Cargo.lock in load path")))

(define-public spacesniffer1000
  (package
    (name "spacesniffer1000")
    (version "0.1.0-9fc2136")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/spacesniffer1000.git")
             (commit "9fc21368f6693936998855cfbd2708ab6fd31ae9")))
       (file-name (git-file-name name version))
       (hash (content-hash "1pzlqm9wc4papm1iqv2zqrawz2yfsqb62cgm9xkrcxs73afmapbs"))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f))
    (native-inputs
     (list pkg-config rust))
    (inputs
     (append (cargo-inputs-from-lockfile
              %spacesniffer1000-cargo-lock)
             (list libxkbcommon
                   wayland
                   wayland-protocols
                   vulkan-loader)))
    (home-page "https://github.com/trevarj/spacesniffer1000")
    (synopsis "Native graphical disk space visualizer")
    (description
     "SpaceSniffer1000 is an egui desktop application for exploring filesystem
usage with a clickable treemap.")
    (license license:expat)))

(define-public gnome-topbar
  (package
    (name "gnome-topbar")
    (version "1.0.0-a4439b7")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/gnome-topbar.git")
             (commit "a4439b7da5779f62deb11ebca6d5cd4423e3ffb2")))
       (file-name (git-file-name name version))
       (hash (content-hash "0i7m8apl0x82fd1hnhbav8iskpyrdmq3mzx7fr4nzffn9284m8bz"))))
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
