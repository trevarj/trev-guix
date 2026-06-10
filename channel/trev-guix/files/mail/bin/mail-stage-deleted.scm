(use-modules (ice-9 popen)
             (ice-9 rdelim)
             (ice-9 match)
             (srfi srfi-13))

(define %notmuch
  (or (getenv "NOTMUCH") "/home/trev/.guix-home/profile/bin/notmuch"))

(define %query
  "tag:deleted and not (path:main/[Gmail]/Trash/** or path:lists/[Gmail]/Trash/**)")

;; Maildir info part (after ":2,"), or #f when the name has no info section.
(define (maildir-flags file)
  (let ((m (string-contains file ":2,")))
    (and m
         (substring file
                    (+ m 3)))))

(define (stage-file file dry-run?)
  (let ((flags (maildir-flags file)))
    (unless (or (string-contains file "/[Gmail]/Trash/")
                (not flags)
                (string-index flags #\T))
      (let ((target (string-append file "T")))
        (if dry-run?
            (format #t "~a -> ~a~%" file target)
            (rename-file file target))))))

;; Files matching %query, from `notmuch search --output=files'.
(define (deleted-files)
  (let ((port (open-pipe* OPEN_READ
                          %notmuch
                          "search"
                          "--format=text"
                          "--output=files"
                          "--"
                          %query)))
    (let loop
      ((files '())
       (line (read-line port)))
      (if (eof-object? line)
          (begin
            (unless (zero? (status:exit-val (close-pipe port)))
              (format (current-error-port)
                      "mail-stage-deleted: notmuch search failed~%")
              (exit 1))
            (reverse files))
          (loop (if (string-null? line) files
                    (cons line files))
                (read-line port))))))

(define (main args)
  (let ((dry-run? (match (cdr args)
                    (() #f)
                    (("--dry-run")
                     #t)
                    (_ (format (current-error-port)
                               "usage: mail-stage-deleted [--dry-run]~%")
                       (exit 2)))))
    (for-each (lambda (file)
                (when (file-exists? file)
                  (stage-file file dry-run?)))
              (deleted-files))))
