(notmuch-mbsync-register-plugin '((backend . gmail) (default-move-rules
                                                                        ("tag:deleted" . "[Gmail]/Trash")
                                                                        ("tag:spam" . "[Gmail]/Spam"))))
