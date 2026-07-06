(define-module (trev-guix packages emacs)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix modules)
  #:use-module (guix utils)
  #:use-module (guix build-system gnu)
  #:use-module (guix import crate)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages emacs)
  #:use-module (gnu packages freedesktop)
  #:use-module (gnu packages rust)
  #:use-module (gnu packages rust-apps)
  #:use-module (gnu packages xdisorg))

(define-public kg
  (let* ((commit "f8ef750ace4b79c26838a79461298a0ac3934696")
         (version (git-version "1.1.0" "0" commit)))
    (package
      (name "kg")
      (version version)
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/troglobit/kg")
               (commit commit)))
         (file-name (git-file-name name version))
         (sha256
          (base32 "1418a81mla65ljriaqzr4kz496vr91kjgh9pwx1szidh4s5wgr8q"))))
      (build-system gnu-build-system)
      (arguments
       (list
        #:make-flags
        #~(list (string-append "CC=" #$(cc-for-target))
                (string-append "prefix=" #$output))
        #:test-target "check"
        #:phases
        #~(modify-phases %standard-phases
            (delete 'configure)
            (add-after 'unpack 'patch-shell-path
              (lambda* (#:key inputs #:allow-other-keys)
                (substitute* "src/shell.c"
                  (("\"/bin/sh\"")
                   (string-append "\""
                                  (search-input-file inputs "/bin/sh")
                                  "\"")))))
            (add-after 'unpack 'do-not-strip-during-install
              (lambda _
                (substitute* "Makefile"
                  (("install -m 755 -s")
                   "install -m 755")))))))
      (inputs (list bash-minimal))
      (home-page "https://github.com/troglobit/kg")
      (synopsis "Lightweight UTF-8 terminal text editor with Emacs keybindings")
      (description
       "kg is a small terminal text editor with pure Emacs-style keybindings,
syntax highlighting, multiple buffers, split windows, incremental search, undo,
and VT100 terminal support without a curses dependency.")
      (license license:bsd-2))))

(define-public emacs-next-next-pgtk
  (let* ((commit "d0b693e3e9bab30b558962991c55a2f07721fb3f")
         (version (git-version "31.0.50" "1" commit)))
    (package
      (inherit emacs-next-pgtk)
      (name "emacs-next-next-pgtk")
      (version version)
      (arguments
       (substitute-keyword-arguments (package-arguments emacs-next-pgtk)
         ((#:tests? tests? #f)
          #f)))
      (source
       (origin
         (inherit (package-source emacs-next-minimal))
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/emacs-mirror/emacs.git")
               (commit commit)))
         (file-name (git-file-name "emacs-next-next-pgtk" commit))
         (sha256
          (base32 "0aa9jylmsbrdk2k4x7pd79bqjv91k68nxafbp74fwh3h56v5hvbs")))))))

(define %emacs-wlshm-cargo-lock
  (or (search-path %load-path "trev-guix/files/emacs-wlshm-Cargo.lock")
      (error "could not find emacs-wlshm-Cargo.lock in load path")))

(define-public emacs-wlshm
  ;; Raw Wayland + CPU Cairo-on-wl_shm backend, from trevarj's fork branch
  ;; wlshm-backend.  Inherits emacs-next and swaps in the fork source, the
  ;; --with-wlshm flag, and the backend's extra build inputs.  The build also
  ;; compiles a small Rust staticlib via cargo, so we vendor its crate
  ;; dependencies (from Cargo.lock) and build cargo offline.
  (let* ((commit "9c56fc8595eeb3a2474beae744227b5d5c96d206")
         (version (git-version "31.0.50" "0" commit)))
    (package
      (inherit emacs-next)
      (name "emacs-wlshm")
      (version version)
      (source
       (origin
         (inherit (package-source emacs-next-minimal))
         (method git-fetch)
         (uri (git-reference
               (url "https://github.com/trevarj/emacs.git")
               (commit commit)))
         (file-name (git-file-name "emacs-wlshm" commit))
         (sha256
          (base32 "03bdk2amk6jfpmbidvxccmbp32cs4w6gkqi6grahzfjr0y7vs0ym"))))
      (arguments
       (substitute-keyword-arguments (package-arguments emacs-next)
         ((#:tests? tests? #f)
          #f)
         ((#:configure-flags flags
           #~'())
          #~(cons "--with-wlshm"
                  #$flags))
         ;; Make the cargo-build-system's vendoring phases available so the
         ;; Rust staticlib can build without network access.
         ((#:imported-modules imported-modules
           (source-module-closure '((guix build glib-or-gtk-build-system))))
          (append imported-modules
                  (source-module-closure '((guix build cargo-build-system)))))
         ((#:modules modules
           '())
          (append modules
                  '(((guix build cargo-build-system)
                     #:prefix cargo:))))
         ((#:phases phases)
          #~(modify-phases #$phases
              (add-after 'unpack 'vendor-rust-crates
                (lambda* (#:key inputs #:allow-other-keys)
                  ;; Vendor every crate listed in Cargo.lock (provided as
                  ;; inputs) into a local directory and point cargo at it.
                  (let ((vendor (string-append (getcwd) "/guix-vendor"))
                        (unpack-crates (assoc-ref cargo:%standard-phases
                                                  'unpack-rust-crates))
                        (patch-checksums (assoc-ref cargo:%standard-phases
                                                    'patch-cargo-checksums)))
                    (unpack-crates #:inputs inputs
                                   #:vendor-dir vendor
                                   #:source (assoc-ref inputs "source"))
                    (patch-checksums #:vendor-dir vendor)
                    (when (file-exists? "rust/wlshm-backend/Cargo.lock")
                      (delete-file "rust/wlshm-backend/Cargo.lock"))
                    (mkdir-p ".cargo")
                    (call-with-output-file ".cargo/config.toml"
                      (lambda (port)
                        (display (string-append "[source.crates-io]\n"
                                  "replace-with = \"vendored-sources\"\n\n"
                                  "[source.vendored-sources]\n"
                                  "directory = \""
                                  vendor
                                  "\"\n") port)))
                    (setenv "CARGO_HOME"
                            (string-append (getcwd) "/.cargo"))
                    (setenv "CARGO_NET_OFFLINE" "true")
                    (setenv "RUSTFLAGS"
                            (string-append (or (getenv "RUSTFLAGS") "")
                                           " --cap-lints allow")))))))))
      ;; The backend builds a Rust staticlib (cargo) and generates its FFI
      ;; header (cbindgen) at build time.
      (native-inputs (modify-inputs (package-native-inputs emacs-next)
                       (prepend rust
                                `(,rust "cargo") rust-cbindgen)))
      ;; cargo-inputs-from-lockfile supplies every crate from Cargo.lock;
      ;; the vendor-rust-crates phase makes cargo use them offline.
      (inputs (append (map (@@ (guix packages) add-input-label)
                           (cargo-inputs-from-lockfile %emacs-wlshm-cargo-lock))
                      (modify-inputs (package-inputs emacs-next)
                        (prepend wayland wayland-protocols libxkbcommon))))
      (synopsis "Emacs with the experimental wlshm (Wayland + wl_shm) backend")
      (description
       "Emacs built from the @code{wlshm-backend} branch of
trevarj's fork, which adds a raw Wayland plus CPU Cairo-on-wl_shm rendering
backend enabled with @code{--with-wlshm}.  Inherits @code{emacs-next}."))))
