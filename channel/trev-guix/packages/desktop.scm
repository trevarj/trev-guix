(define-module (trev-guix packages desktop)
  #:use-module (gnu packages)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages gnupg)
  #:use-module (gnu packages llvm)
  #:use-module (gnu packages pkg-config)
  #:use-module (gnu packages python)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages vulkan)
  #:use-module (gnu packages window-management)
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

(define %topbar-cargo-lock
  (or (search-path %load-path "trev-guix/files/topbar-Cargo.lock")
      (error "could not find topbar-Cargo.lock in load path")))

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

(define-public topbar
  (package
    (name "topbar")
    (version "2.0.0-904b7c4")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/topbar.git")
             (commit "904b7c4120888f25544b6aec135a5da1d69200b9")))
       (file-name (git-file-name name version))
       (hash (content-hash "0bxz169mnxxg4afdhb1l6bgjdmwwhp1lgrs8w1wfczybfv0a30sp"))))
    (build-system cargo-build-system)
    (arguments
     (list
      #:install-source? #f
      #:cargo-install-paths ''("crates/topbar")
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'unpack 'patch-test-fixture-shebang
            (lambda _
              ;; The headset test writes a fake tool and execs it, but the
              ;; build container has no /bin/sh for its shebang to resolve.
              (substitute* "crates/topbar-services/src/headset/task.rs"
                (("#!/bin/sh")
                 (string-append "#!" (which "sh"))))))
          (add-before 'build 'set-bindgen-clang-path
            (lambda* (#:key native-inputs inputs #:allow-other-keys)
              ;; libspa-sys generates the PipeWire bindings with bindgen, which
              ;; dlopens libclang instead of shelling out to clang.
              (setenv "LIBCLANG_PATH"
                      (dirname (search-input-file (or native-inputs inputs)
                                                  "lib/libclang.so"))))))))
    ;; Pin the clang major version: the unversioned `clang' tracks the newest
    ;; LLVM, which regularly lacks substitutes and would drag a multi-hour
    ;; source build into every rebuild of this package.
    (native-inputs (list clang-20 pkg-config))
    (inputs (append (cargo-inputs-from-lockfile %topbar-cargo-lock)
                    (map specification->package
                         '("gtk" "gtk4-layer-shell"
                           "glib"
                           "dbus"
                           "eudev"
                           "pango"
                           "gdk-pixbuf"
                           "cairo"
                           "graphene"
                           "pipewire"
                           "pulseaudio"
                           "upower"
                           "network-manager"
                           "bluez"))))
    (home-page "https://github.com/trevarj/topbar")
    (synopsis "GNOME Shell-inspired GTK top bar for Wayland")
    (description
     "Topbar is a Wayland-only GTK top bar inspired by GNOME Shell.  It provides
a continuous system panel with notifications, quick settings, media controls,
workspaces, and custom script modules.")
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
