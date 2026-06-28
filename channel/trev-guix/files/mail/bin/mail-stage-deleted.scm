(define-module (trev-guix files mail bin mail-stage-deleted)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-13)
  #:export (main))

(define %notmuch
  (or (getenv "NOTMUCH") "/home/trev/.guix-home/profile/bin/notmuch"))

(define %query
  "tag:deleted and not (path:main/[Gmail]/Trash/** or path:lists/[Gmail]/Trash/**)")

;; Non-empty output lines of `%notmuch ARGS...', or exit 1 with MSG on failure.
(define (notmuch-lines msg . args)
  (let ((port (apply open-pipe* OPEN_READ %notmuch args)))
    (let loop
      ((lines '())
       (line (read-line port)))
      (if (eof-object? line)
          (begin
            (unless (zero? (status:exit-val (close-pipe port)))
              (format (current-error-port) "mail-stage-deleted: ~a~%" msg)
              (exit 1))
            (reverse lines))
          (loop (if (string-null? line) lines
                    (cons line lines))
                (read-line port))))))

;; Absolute Maildir prefixes whose copies must never be flagged for deletion,
;; from the generated ~/.notmuch-config ([mailsync] read_only_paths).  Empty
;; when unset -> every deleted copy is staged (the original behaviour).  Read
;; from notmuch config so the daemon and the manual `mail-sync' share one source.
(define (read-only-paths)
  (notmuch-lines "could not read notmuch config"
                 "config" "get" "mailsync.read_only_paths"))

(define (read-only? read-only-paths file)
  (any (lambda (prefix)
         (string-prefix? prefix file))
       read-only-paths))

;; Maildir info part (after ":2,"), or #f when the name has no info section.
(define (maildir-flags file)
  (let ((m (string-contains file ":2,")))
    (and m
         (substring file
                    (+ m 3)))))

(define (stage-file file dry-run? read-only-paths)
  (let ((flags (maildir-flags file)))
    (unless (or (read-only? read-only-paths file)
                (string-contains file "/[Gmail]/Trash/")
                (not flags)
                (string-index flags #\T))
      (let ((target (string-append file "T")))
        (if dry-run?
            (format #t "~a -> ~a~%" file target)
            (rename-file file target))))))

;; Files matching %query, from `notmuch search --output=files'.  NOTE: a
;; `path:' predicate selects MESSAGES, not files, so a deduplicated message
;; returns ALL its files here -- account scoping must be done per file (see
;; `read-only?'), not in the query.
(define (deleted-files)
  (notmuch-lines "notmuch search failed"
                 "search" "--format=text" "--output=files" "--" %query))

(define (main args)
  (let ((dry-run? (match (cdr args)
                    (() #f)
                    (("--dry-run")
                     #t)
                    (_ (format (current-error-port)
                               "usage: mail-stage-deleted [--dry-run]~%")
                       (exit 2))))
        (read-only-paths (read-only-paths)))
    (for-each (lambda (file)
                (when (file-exists? file)
                  (stage-file file dry-run? read-only-paths)))
              (deleted-files))))
