(define-module (trev-guix systems installer)
  #:use-module (gnu)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module (nongnu packages linux)
  #:use-module (nongnu system install)
  #:use-module (srfi srfi-13)
  #:use-module (trev-guix systems substitutes))

(use-service-modules base guix)

(use-package-modules bash version-control)

(define %nonguix-pubkey-file
  (plain-file "nonguix.pub"
   "(public-key
     (ecc (curve Ed25519)
          (q #C1FD53E5D4CE971933EC50C9F307AE2171A2D3B52C804642A7A35F84F3A4EA98#)))"))

(define (path-component? component file)
  (or (string-suffix? (string-append "/" component) file)
      (string-contains file
                       (string-append "/" component "/"))))

(define (dotfiles-file? file stat)
  (not (or (path-component? ".git" file)
           (string-suffix? "/stinkpad-installer.iso" file)
           (path-component? "stinkpad-target-system" file))))

(define (trev-guix-file? file stat)
  (not (or (path-component? ".git" file)
           (string-suffix? "/stinkpad-installer.iso" file))))

(define %dotfiles-checkout
  (local-file "/home/trev/Workspace/dotfiles"
              "trev-dotfiles"
              #:recursive? #t
              #:select? dotfiles-file?))

(define %trev-guix-checkout
  (local-file "../../.."
              "trev-guix"
              #:recursive? #t
              #:select? trev-guix-file?))

(define %channels-file
  (local-file "/home/trev/Workspace/dotfiles/guix/.config/guix/channels.scm"
              "channels.scm"))

(define %substitute-urls-file
  (plain-file "substitute-urls"
              (string-append (string-join (stinkpad-substitute-urls) " ") "\n")))

(define %host-torrc
  (local-file "/home/trev/.config/tor/torrc" "torrc"))

(define %install-stinkpad-script
  (local-file "../../../channel/trev-guix/files/scripts/install-stinkpad-guix"
   "install-stinkpad-guix"))

(define %finish-stinkpad-install-script
  (local-file
   "../../../channel/trev-guix/files/scripts/finish-stinkpad-install"
   "finish-stinkpad-install"))

(define %install-stinkpad-command
  (program-file "install-stinkpad"
                #~(apply execl
                         #$(file-append bash "/bin/bash") "bash"
                         #$%install-stinkpad-script
                         (cdr (command-line)))))

(define %finish-stinkpad-install-command
  (program-file "finish-stinkpad-install"
                #~(apply execl
                         #$(file-append bash "/bin/bash") "bash"
                         #$%finish-stinkpad-install-script
                         (cdr (command-line)))))

(define %install-stinkpad-package
  (package
    (name "install-stinkpad")
    (version "0")
    (source
     #f)
    (build-system trivial-build-system)
    (arguments
     (list
      #:builder
      #~(begin
          (let ((bin (string-append #$output "/bin")))
            (mkdir #$output)
            (mkdir bin)
            (copy-file #$%install-stinkpad-command
                       (string-append bin "/install-stinkpad"))
            (copy-file #$%finish-stinkpad-install-command
                       (string-append bin "/finish-stinkpad-install"))
            (chmod (string-append bin "/install-stinkpad") #o555)
            (chmod (string-append bin "/finish-stinkpad-install") #o555)))))
    (home-page #f)
    (synopsis "Install the stinkpad Guix system")
    (description "Install the bundled stinkpad Guix system configuration.")
    (license #f)))

(define-public %stinkpad-installer
  (operating-system
    (inherit installation-os-nonfree)
    (host-name "stinkpad-installer")
    (timezone "Etc/UTC")
    (kernel-arguments '("quiet"))
    (firmware (cons* i915-firmware
                     iwlwifi-firmware
                     ibt-hw-firmware
                     sof-firmware
                     linux-firmware
                     amdgpu-firmware
                     (operating-system-firmware installation-os-nonfree)))
    (services
     (append (modify-services (operating-system-user-services
                               installation-os-nonfree)
               (guix-service-type config =>
                                  (guix-configuration (inherit config)
                                                      (substitute-urls (stinkpad-substitute-urls))
                                                      (authorized-keys (cons*
                                                                        %nonguix-pubkey-file
                                                                        %default-authorized-guix-keys)))))
             (list (simple-service 'trev-guix-installer-sources
                                   etc-service-type
                                   `(("trev-guix" ,%trev-guix-checkout)
                                     ("trev-dotfiles" ,%dotfiles-checkout)
                                     ("guix/channels.scm" ,%channels-file)
                                     ("guix/substitute-urls" ,%substitute-urls-file)))
                   (extra-special-file "/home/trev/.config/tor/torrc"
                                       %host-torrc))))
    (packages (cons* %install-stinkpad-package git
                     (operating-system-packages installation-os-nonfree)))))
