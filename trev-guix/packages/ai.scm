(define-module (trev-guix packages ai)
  #:use-module (gnu packages bash)
  #:use-module (gnu packages base)
  #:use-module (gnu packages compression)
  #:use-module (gnu packages gcc)
  #:use-module (gnu packages glib)
  #:use-module (gnu packages rust-apps)
  #:use-module (gnu packages terminals)
  #:use-module (gnu packages virtualization)
  #:use-module (guix build-system copy)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (nonguix build-system binary))

(define-public ollama
  (package
    (name "ollama")
    (version "0.24.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/ollama/ollama/releases/download/v"
             version "/ollama-linux-amd64.tar.zst"))
       (sha256
        (base32 "1nywgijy2limpclhjxl29vhndg9dc5l8ipqr8wxhsvm0dgbgii8m"))))
    (build-system binary-build-system)
    (arguments
     (list
      #:strip-binaries? #f
      #:validate-runpath? #f
      #:patchelf-plan
      #~'(("bin/ollama" ("glibc" "gcc")))
      #:install-plan
      #~'(("bin/ollama" "bin/"))
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack
            (lambda* (#:key inputs #:allow-other-keys)
              (invoke "tar" "--use-compress-program=zstd" "-xf"
                      (assoc-ref inputs "source")))))))
    (native-inputs
     (list zstd))
    (propagated-inputs
     (list glibc
           `(,gcc "lib")))
    (supported-systems '("x86_64-linux"))
    (home-page "https://ollama.com")
    (synopsis "Run large language models locally")
    (description
     "Ollama allows you to run large language models locally.
It provides a simple API for creating, running and managing models,
as well as a library of pre-built models that can be easily used.")
    (license license:expat)))

(define-public opencode
  (package
    (name "opencode")
    (version "1.14.19")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/anomalyco/opencode/releases/download/v"
             version "/opencode-linux-x64.tar.gz"))
       (sha256
        (base32 "0h0ljmkz26ab02is0yq8balw9x6229mkb8prdwmjxj0frqiigccc"))))
    (build-system binary-build-system)
    (arguments
     (list
      #:strip-binaries? #f
      #:validate-runpath? #f
      #:patchelf-plan
      #~'(("opencode" ()))
      #:install-plan
      #~'(("opencode" "bin/opencode"))
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack
            (lambda* (#:key inputs #:allow-other-keys)
              (invoke "tar" "xzf" (assoc-ref inputs "source"))
              (chmod "opencode" #o755)))
          (add-after 'install 'wrap-binary
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((fzf (assoc-ref inputs "fzf"))
                     (ripgrep (assoc-ref inputs "ripgrep"))
                     (path (string-append
                            fzf "/bin:"
                            ripgrep "/bin")))
                (wrap-program (string-append #$output "/bin/opencode")
                  `("PATH" ":" prefix (,path))
                  `("OPENCODE_DISABLE_UPDATE" ":" = ("1")))))))))
    (inputs
     (list bash-minimal fzf ripgrep))
    (native-inputs
     (list gzip))
    (supported-systems '("x86_64-linux"))
    (home-page "https://github.com/anomalyco/opencode")
    (synopsis "Open source AI coding agent for the terminal")
    (description
     "OpenCode is an open source AI coding agent that lives in your terminal.
It can understand your codebase, edit files, run terminal commands, and
handle entire workflows.  It supports multiple AI providers including
Claude, OpenAI, Google, and local models.  This package disables
auto-updates for reproducibility and bundles fzf and ripgrep in PATH.")
    (license license:expat)))

(define-public codex
  (package
    (name "codex")
    (version "0.134.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/openai/codex/releases/download/rust-v"
             version "/codex-x86_64-unknown-linux-musl.tar.gz"))
       (sha256 (base32 "0w8w5rwrwp8nibqkkyn4f8d7cid556xq7ppdm0nrkjmm78y9hjz5"))))
    (build-system binary-build-system)
    (propagated-inputs (list bubblewrap))
    (arguments
     (list
      #:validate-runpath? #f
      #:install-plan #~'(("codex-x86_64-unknown-linux-musl" "bin/codex"))))
    (home-page "https://github.com/openai/codex")
    (synopsis "AI coding agent from OpenAI")
    (description
     "Codex CLI is an AI-powered coding agent from OpenAI that runs locally
on your computer.  It assists with software development tasks directly within
a terminal environment, providing code suggestions, explanations, and
automated coding assistance.")
    (license license:asl2.0)))
