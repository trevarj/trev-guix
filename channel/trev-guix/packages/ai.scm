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
  #:use-module (guix git-download)
  #:use-module (guix gexp)
  #:use-module (guix packages)
  #:use-module ((guix licenses)
                #:prefix license:)
  #:use-module (nonguix licenses)
  #:use-module (nonguix build-system binary))

(define-public ollama
  (package
    (name "ollama")
    (version "0.30.10")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/ollama/ollama/releases/download/v" version
             "/ollama-linux-amd64.tar.zst"))
       (sha256
        (base32 "1pbqs489r4gz295w94vz525wm09frcdqv3am95x4fn4dwll8yv84"))))
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
    (native-inputs (list zstd))
    (propagated-inputs (list glibc
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
    (version "1.17.8")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/anomalyco/opencode/releases/download/v"
             version "/opencode-linux-x64.tar.gz"))
       (sha256
        (base32 "0pqy5f33v4xz3c89r08j4r6dkkq4p2k7wxqlglmld4vh48lzrzqk"))))
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
              (invoke "tar" "xzf"
                      (assoc-ref inputs "source"))
              (chmod "opencode" #o755)))
          (add-after 'install 'wrap-binary
            (lambda* (#:key inputs #:allow-other-keys)
              (let* ((fzf (assoc-ref inputs "fzf"))
                     (ripgrep (assoc-ref inputs "ripgrep"))
                     (path (string-append fzf "/bin:" ripgrep "/bin")))
                (wrap-program (string-append #$output "/bin/opencode")
                  `("PATH" ":" prefix
                    (,path))
                  `("OPENCODE_DISABLE_UPDATE" ":" =
                    ("1")))))))))
    (inputs (list bash-minimal fzf ripgrep))
    (native-inputs (list gzip))
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
    (version "0.141.0")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://github.com/openai/codex/releases/download/rust-v"
             version "/codex-x86_64-unknown-linux-musl.tar.gz"))
       (sha256
        (base32 "0zcmb0iha9x065xqdhkdq0rxv3n33fvvc8fn34hvhvmsl2gvzqpi"))))
    (build-system binary-build-system)
    (propagated-inputs (list bubblewrap))
    (arguments
     (list
      #:validate-runpath? #f
      #:install-plan
      #~'(("codex-x86_64-unknown-linux-musl" "bin/codex"))))
    (home-page "https://github.com/openai/codex")
    (synopsis "AI coding agent from OpenAI")
    (description
     "Codex CLI is an AI-powered coding agent from OpenAI that runs locally
on your computer.  It assists with software development tasks directly within
a terminal environment, providing code suggestions, explanations, and
automated coding assistance.")
    (license license:asl2.0)))

(define-public claude-code
  (package
    (name "claude-code")
    (version "2.1.183")
    (source
     (origin
       (method url-fetch)
       (uri (string-append "https://storage.googleapis.com/claude-code-dist-"
             "86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/"
             version "/linux-x64/claude"))
       (hash (content-hash
              "1kndm3q2dhrkyzkyzgn130pcpg8xh5j1zs2y5ksrsa95bff40fyz"))))
    (build-system binary-build-system)
    (arguments
     (list
      #:strip-binaries? #f
      #:validate-runpath? #f
      #:patchelf-plan
      #~'(("claude" ()))
      #:install-plan
      #~'(("claude" "bin/claude-unwrapped"))
      #:phases
      #~(modify-phases %standard-phases
          (replace 'unpack
            (lambda* (#:key inputs #:allow-other-keys)
              (copy-file (assoc-ref inputs "source") "claude")
              (chmod "claude" #o755)))
          (add-after 'install 'create-wrapper
            (lambda* (#:key inputs outputs #:allow-other-keys)
              (let* ((out (assoc-ref outputs "out"))
                     (bin (string-append out "/bin"))
                     (unwrapped (string-append bin "/claude-unwrapped"))
                     (wrapper (string-append bin "/claude")))
                (call-with-output-file wrapper
                  (lambda (port)
                    (format port "#!~a
export DISABLE_AUTOUPDATER=1
export DISABLE_INSTALLATION_CHECKS=1
exec ~a \"$@\"
"
                            (search-input-file inputs "bin/bash") unwrapped)))
                (chmod wrapper #o755)))))))
    (inputs (list bash-minimal))
    (supported-systems '("x86_64-linux"))
    (home-page "https://github.com/anthropics/claude-code")
    (synopsis "Claude AI assistant for the terminal")
    (description
     "Claude Code is an agentic coding tool that lives in your terminal.
It can understand your codebase, edit files, run terminal commands, and
handle entire workflows.  This package disables auto-updates.")
    (license (nonfree "https://code.claude.com/docs/en/legal-and-compliance"))))

(define-public gac
  (package
    (name "gac")
    (version "0.1.7")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/guix-agent-container")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       ;; Hash of the v<version> git checkout (from the build's hash mismatch).
       (sha256
        (base32 "0sb6bb60dy37j7y9kg663qz95hrmnl65rs65h2nypa0mr9pk5713"))))
    (build-system copy-build-system)
    (arguments
     (list
      #:install-plan
      #~'(("gac" "bin/gac")
          ("bin/" "share/gac/bin/")
          ("manifest.scm" "share/gac/manifest.scm")
          ("README.md" "share/doc/gac/README.md")
          ("PLAN.md" "share/doc/gac/PLAN.md"))
      #:phases
      #~(modify-phases %standard-phases
          (add-after 'install 'patch-gac-shebang
            (lambda* (#:key inputs outputs #:allow-other-keys)
              ;; gac uses bash arrays + `local`, so pin its shebang to the
              ;; store bash (no /usr/bin/env in a pure Guix profile).
              (let* ((bash (search-input-file inputs "bin/bash"))
                     (gac (string-append (assoc-ref outputs "out")
                                         "/bin/gac")))
                (substitute* gac
                  (("^#!.*") (string-append "#!" bash "\n")))
                (chmod gac #o755)))))))
    (inputs (list bash-minimal))
    (home-page "https://github.com/trevarj/guix-agent-container")
    (synopsis "Run claude/codex in an isolated Guix container")
    (description
     "gac launches the Claude Code and Codex agents inside an isolated Guix
container with a read-only home, masked secret directories, a read-only agent
config with read-write state, and a host-side commit-only GPG signing oracle
so the container never sees the gpg-agent socket or private keys.  The in-container
@command{guix} surface is filtered to safe subcommands and @code{--nesting} lets
per-project manifests work natively.  Run @command{gac claude}, @command{gac
codex}, or @command{gac bash}.")
    (license license:gpl3+)))
