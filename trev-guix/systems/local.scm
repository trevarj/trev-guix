(define-module (trev-guix systems local)
  #:use-module (ice-9 format)
  #:use-module (ice-9 match)
  #:use-module (ice-9 regex)
  #:export (%stinkpad-local-timezone))

(define %local-config-file
  (or (getenv "TREV_GUIX_LOCAL_CONFIG")
      "/home/trev/Workspace/trev-guix/trev-guix/private/local.scm"))

(define (fail format-string . args)
  (error (string-append "local system config: "
                        (apply format #f format-string args))))

(define (read-local-config file)
  (unless (file-exists? file)
    (fail "missing ~a; create it from trev-guix/private/local.scm.example"
          file))
  (call-with-input-file file read))

(define (local-config-ref config key)
  (match (assoc key config)
    ((_ . value) value)
    (#f (fail "missing required key ~s in ~a" key %local-config-file))))

(define (valid-timezone? value)
  (and (string? value)
       (regexp-exec
        (make-regexp "^[A-Za-z0-9_+.-]+(/[A-Za-z0-9_+.-]+)*$")
        value)
       (not (string-contains value ".."))))

(define (local-timezone config)
  (let ((timezone (local-config-ref config 'timezone)))
    (unless (valid-timezone? timezone)
      (fail "invalid timezone ~s in ~a" timezone %local-config-file))
    timezone))

(define %local-config
  (read-local-config %local-config-file))

(define-public %stinkpad-local-timezone
  (local-timezone %local-config))
