(define-module (trev-guix packages desktop)
  #:use-module (gnu packages)
  #:use-module (gnu packages base)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages guile)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages vulkan)
  #:use-module (gnu packages wm)
  #:use-module (gnu packages xdisorg)
  #:use-module (guix build-system cargo)
  #:use-module (guix build-system trivial)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix import crate)
  #:use-module (guix packages)
  #:use-module ((guix licenses)
                #:prefix license:))

(define (trev-guix-file file)
  (let loop
    ((dirs %load-path))
    (if (null? dirs)
        (error "missing trev-guix file" file)
        (let ((candidate (string-append (car dirs) "/trev-guix/files/" file)))
          (if (file-exists? candidate)
              (canonicalize-path candidate)
              (loop (cdr dirs)))))))

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
       (hash (content-hash
              "1pzlqm9wc4papm1iqv2zqrawz2yfsqb62cgm9xkrcxs73afmapbs"))))
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
    (version "1.0.0-9e538b6")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/gnome-topbar.git")
             (commit "9e538b6b208968a431ec4bd47f79e01732bc4b88")))
       (file-name (git-file-name name version))
       (hash (content-hash
              "0qwdpsw2rrvswdir54q2npn3m7h0apiqlqxm22036cpizr4xls5n"))))
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
    (version "0.1.0")
    (source
     (local-file (trev-guix-file "pinentry-fuzzguy")))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils))
      #:builder
      #~(begin
          (use-modules (guix build utils))
          (let* ((bin (string-append #$output "/bin"))
                 (target (string-append bin "/pinentry-fuzzguy")))
            (mkdir-p bin)
            (copy-file #$source target)
            (substitute* target
              (("@GUILE@")
               #$(file-append guile-3.0 "/bin/guile"))
              (("@FUZZEL@")
               #$(file-append fuzzel "/bin/fuzzel"))
              (("@PINENTRY_TTY@")
               #$(file-append pinentry-tty "/bin/pinentry-tty"))
              (("@TIMEOUT@")
               #$(file-append coreutils "/bin/timeout")))
            (chmod target #o555)))))
    (inputs (list coreutils fuzzel guile-3.0 pinentry-tty))
    (home-page "https://example.invalid/pinentry-fuzzguy")
    (synopsis "Fuzzel-based pinentry with protocol context")
    (description
     "Pinentry Fuzzguy is a small Guile pinentry implementation for Wayland.  It
uses Fuzzel for passphrase prompts, displays context supplied by gpg-agent, and
falls back to pinentry-tty when a graphical prompt is unavailable.")
    (license license:gpl3+)))
