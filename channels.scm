(use-modules (guix channels))

(cons (channel
       (name 'trev-guix)
       (url "https://codeberg.org/trevarj/trev-guix.git")
       (branch "master")
       (introduction
        (make-channel-introduction
         "439e18c6c251eaaab26d74eabb8f32150d3dca2a"
         (openpgp-fingerprint
          "A6C2 0D0C 2AD8 38F9 4907  0EA3 A52D 6879 4EBE D758"))))
      %default-channels)
