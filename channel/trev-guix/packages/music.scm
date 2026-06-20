(define-module (trev-guix packages music)
  #:use-module (guix packages)
  #:use-module (guix download)
  #:use-module (guix git-download)
  #:use-module (guix build-system python)
  #:use-module (guix build-system pyproject)
  #:use-module (guix gexp)
  #:use-module ((guix licenses)
                #:prefix license:)
  #:use-module (gnu packages music)
  #:use-module (gnu packages python-build)
  #:use-module (gnu packages python-web)
  #:use-module (gnu packages python-xyz)
  #:use-module (gnu packages video))

(define-public python-ytmusicapi
  (package
    (name "python-ytmusicapi")
    (version "1.12.1")
    (source
     (origin
       (method url-fetch)
       (uri (pypi-uri "ytmusicapi" version))
       (sha256
        (base32 "0m97fwcp5gdw8254ya1gdrznkc26vqdaaaazkqdww7iivcjg8csf"))))
    (build-system pyproject-build-system)
    (arguments
     (list
      #:tests? #f ; test suite hits the live YouTube Music API
      #:phases
      #~(modify-phases %standard-phases
          ;; setuptools_scm derives the version from git, which the sdist lacks.
          (add-before 'build 'set-scm-version
            (lambda _
              (setenv "SETUPTOOLS_SCM_PRETEND_VERSION" #$version))))))
    (native-inputs (list python-setuptools python-setuptools-scm python-wheel))
    (propagated-inputs (list python-requests))
    (home-page "https://github.com/sigma67/ytmusicapi")
    (synopsis "Unofficial API for YouTube Music")
    (description
     "ytmusicapi is a Python library providing programmatic access to the
YouTube Music web client, including search and album/playlist queries.  It works
unauthenticated for browsing and is used to resolve tracks to downloadable
sources.")
    (license license:expat)))

(define-public yoink
  (package
    (name "yoink")
    (version "0.2.0")
    (source
     (origin
       (method git-fetch)
       (uri (git-reference
             (url "https://github.com/trevarj/yoink")
             (commit (string-append "v" version))))
       (file-name (git-file-name name version))
       (sha256
        (base32 "1wbd2vhhwbgjimf5wqa923difnbp017jbb8lhlqxkbcc35agbx4z"))))
    (build-system pyproject-build-system)
    ;; Only the pure unit tests run offline; the smoke tests need network, so
    ;; skip the suite at build time.
    (arguments (list #:tests? #f))
    (native-inputs (list python-hatchling))
    (propagated-inputs
     (list python-textual
           python-musicbrainzngs
           python-mutagen
           python-rapidfuzz
           python-ytmusicapi
           python-platformdirs
           python-httpx
           python-requests
           yt-dlp
           beets
           ffmpeg))
    (home-page "https://github.com/trevarj/yoink")
    (synopsis "TUI music browser that downloads full albums from YouTube Music")
    (description
     "yoink is a terminal music browser: browse MusicBrainz, queue full albums,
and a background worker crawls YouTube Music and downloads each track with
yt-dlp, tags it, and writes a clean @code{Artist/Album/NN Title.opus} library
tree.  Output is plain files; syncing elsewhere is left to the user.")
    (license license:expat)))
