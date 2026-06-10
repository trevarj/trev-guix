(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 regex)
             (ice-9 match)
             (srfi srfi-1)
             (srfi srfi-13))

(define (die fmt . args)
  (apply format
         (current-error-port) fmt args)
  (newline (current-error-port))
  (exit 1))

;; Decrypt ~/.authinfo.gpg and return its plaintext as a list of lines.
(define (authinfo-lines)
  (let* ((home (or (getenv "HOME")
                   (die "mail-authinfo-password: HOME is unset")))
         (path (string-append home "/.authinfo.gpg"))
         (port (open-pipe* OPEN_READ
                           "gpg"
                           "--quiet"
                           "--batch"
                           "--decrypt"
                           path)))
    (let loop
      ((lines '())
       (line (read-line port)))
      (if (eof-object? line)
          (if (zero? (status:exit-val (close-pipe port)))
              (reverse lines)
              (die "mail-authinfo-password: failed to decrypt ~a" path))
          (loop (cons line lines)
                (read-line port))))))

;; True when KEY VALUE appear as an adjacent token pair anywhere in TOKENS.
(define (tokens-have? tokens key value)
  (match tokens
    ((a b . rest) (or (and (string=? a key)
                           (string=? b value))
                      (tokens-have? (cons b rest) key value)))
    (_ #f)))

(define (line-matches? line machine login)
  (let ((tokens (string-tokenize line)))
    (and (tokens-have? tokens "machine" machine)
         (tokens-have? tokens "login" login))))

;; Extract the password field, handling both `password "with spaces"' and a
;; bare `password token'.
(define (extract-password line)
  (cond
    ((string-match "password \"([^\"]*)\"" line)
     =>
     (lambda (m)
       (match:substring m 1)))
    ((string-match "password ([^ \t]+)" line)
     =>
     (lambda (m)
       (match:substring m 1)))
    (else #f)))

(define (main args)
  (match (cdr args)
    ((machine login)
     (let* ((line (find (lambda (l)
                          (line-matches? l machine login))
                        (authinfo-lines)))
            (password (and line
                           (extract-password line))))
       (if (and password
                (not (string-null? password)))
           (begin
             (display password)
             (newline))
           (die "mail-authinfo-password: no password found for ~a ~a" machine
                login))))
    (_ (die "usage: mail-authinfo-password MACHINE LOGIN"))))
