(define-module (trev-guix systems local)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:use-module (system base compile)
  #:export (%stinkpad-local-timezone))

(define %local-module-file
  (canonicalize-path (search-path %load-path "trev-guix/systems/local.scm")))

(define %host-root
  (dirname (dirname (dirname %local-module-file))))

(define %local-config-file
  (or (getenv "TREV_GUIX_LOCAL_CONFIG")
      (string-append %host-root "/trev-guix/private/local.scm")))

(define (fail format-string . args)
  (error (string-append "local system config: "
                        (apply format #f format-string args))))

(define (read-local-config file)
  (call-with-input-file file
    read))

(define (local-config-ref config key)
  (match (assoc key config)
    ((_ . value) value)
    (#f (fail "missing required key ~s in ~a" key %local-config-file))))

(define (valid-timezone? value)
  (and (string? value)
       (regexp-exec (make-regexp "^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$")
                    value)
       (not (string-contains value ".."))))

(define (local-timezone config)
  (let ((timezone (local-config-ref config
                                    'timezone)))
    (unless (valid-timezone? timezone)
      (fail "invalid timezone ~s in ~a" timezone %local-config-file)) timezone))

(define %local-config
  (read-local-config %local-config-file))

(define-public %stinkpad-local-timezone
  (local-timezone %local-config))
