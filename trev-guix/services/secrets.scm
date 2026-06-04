(define-module (trev-guix services secrets)
  #:use-module (gnu packages bash)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (guix gexp)
  #:use-module (guix records)
  #:export (trev-secrets-configuration
            trev-secrets-configuration?
            trev-secrets-service-type))

(define-record-type* <trev-secrets-configuration>
  trev-secrets-configuration make-trev-secrets-configuration
  trev-secrets-configuration?
  (env-file trev-secrets-configuration-env-file
            (default "/etc/trev-local/env")))

(define (trev-secrets-shepherd-service config)
  (match-record config <trev-secrets-configuration> (env-file)
    (list
     (shepherd-service
      (documentation "Apply local private settings decrypted by trev-secrets.")
      (provision '(trev-secrets-local-settings))
      (requirement '(user-processes))
      (one-shot? #t)
      (auto-start? #t)
      (start
       #~(make-forkexec-constructor
          (list #$(file-append bash "/bin/bash")
                "-c"
                #$(string-append
                   "set -eu\n"
                   "env_file=" env-file "\n"
                   "timezone=Etc/UTC\n"
                   "if [ -f \"$env_file\" ]; then\n"
                   "  set -a\n"
                   "  . \"$env_file\"\n"
                   "  set +a\n"
                   "  timezone=\"${TREV_TIMEZONE:-Etc/UTC}\"\n"
                   "else\n"
                   "  echo 'trev-secrets: missing /etc/trev-local/env; using Etc/UTC' >&2\n"
                   "fi\n"
                   "zoneinfo=\"/run/current-system/profile/share/zoneinfo/$timezone\"\n"
                   "if [ ! -f \"$zoneinfo\" ]; then\n"
                   "  echo \"trev-secrets: invalid timezone $timezone; using Etc/UTC\" >&2\n"
                   "  timezone=Etc/UTC\n"
                   "  zoneinfo=/run/current-system/profile/share/zoneinfo/Etc/UTC\n"
                   "fi\n"
                   "ln -sfn \"$zoneinfo\" /etc/localtime\n"))
          #:log-file "/var/log/trev-secrets-local-settings.log"))
      (stop #~(const #f))))))

(define-public trev-secrets-service-type
  (service-type
   (name 'trev-secrets)
   (extensions
    (list (service-extension shepherd-root-service-type
                             trev-secrets-shepherd-service)))
   (default-value (trev-secrets-configuration))
   (description "Apply private local settings from /etc/trev-local/env.")))
