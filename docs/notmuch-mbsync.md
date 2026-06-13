# notmuch-mbsync

`notmuch-mbsync` is a Guix Home service that keeps a local Maildir + notmuch
database in sync with Gmail over IMAP.  It runs as a long-lived user daemon that,
on a fixed interval, pulls mail with `mbsync` (isync), indexes it with `notmuch`,
stages deletions, applies tag rules, and pushes local changes back.

It is built for two Gmail accounts:

| Account id    | Address               | Channel | Maildir         |
|---------------|-----------------------|---------|-----------------|
| `main-gmail`  | `tmarjeski@gmail.com` | `main`  | `~/Mail/main/`  |
| `lists-gmail` | `tarjeski@gmail.com`  | `lists` | `~/Mail/lists/` |

The notmuch database lives at `~/Mail`; both accounts' Maildirs sit underneath it,
alongside an `~/Mail/archive/` tree for imported mailing-list archives.

---

## Components

| Path | Role |
|------|------|
| `channel/trev-guix/services/notmuch-mbsync.scm` | Service type, configuration record, and the daemon runner (a `program-file` gexp). |
| `channel/trev-guix/files/scripts/notmuch-mbsync.scm` | The sync **orchestration** logic, written in Guile and `load`ed by the runner at runtime. |
| `channel/trev-guix/files/notmuch-config.scm` | The concrete `%notmuch-mbsync-configuration` and `%notmuch-tag-rules` consumed by the home config. |
| `channel/trev-guix/packages/mail.scm` | The `mail-scripts` package — installs the helper scripts onto `PATH`. |
| `channel/trev-guix/files/mail/bin/` | The helper script sources (two Guile `.scm`, two POSIX shell). |

`~/.mbsyncrc` and `~/.notmuch-config` are **not** hand-maintained dotfiles — they
are generated from `%notmuch-mbsync-configuration` (see [Generated config
files](#generated-config-files) below) and symlinked into `$HOME` from the store.

The service is instantiated in `host/trev-guix/home/base.scm`:

```scheme
(service notmuch-mbsync-service-type %notmuch-mbsync-configuration)
```

---

## How it runs

The service extends `home-shepherd-service-type` with a **long-running daemon**
(`make-forkexec-constructor`), not a timer.  This matters for credential
handling (below).  It logs to:

```
$XDG_STATE_HOME/shepherd/notmuch-mbsync.log   (i.e. ~/.local/state/shepherd/notmuch-mbsync.log)
```

The runner loop is, in pseudocode:

```
ensure-credentials!        ; decrypt secrets ONCE, cache them in the environment
loop:
  run one full sync over all accounts   ; wrapped in a catch — a failed pass never kills the daemon
  sleep interval-seconds                ; default 600 (10 minutes)
```

A second Shepherd extension (`home-activation-service-type`) symlinks the config
files into `$HOME` on every `guix home reconfigure`:

```
~/.mbsyncrc        -> /gnu/store/…-mbsyncrc          (generated)
~/.notmuch-config  -> /gnu/store/…-notmuch-config    (generated)
```

See [Generated config files](#generated-config-files) for how those store items
are produced from the configuration record.

### Per-account sync pass

For each enabled account, `notmuch-mbsync-run-account-sync`
(`files/scripts/notmuch-mbsync.scm`) does:

1. **ensure maildir** — `mkdir -p` the account's `cur`/`new`/`tmp`.
2. **`mbsync <channel>`** — pull from Gmail.
3. **`notmuch new`** — index newly arrived files.
4. **tag-command** — runs `mail-stage-deleted.scm`, which adds the Maildir `T`
   flag to anything tagged `deleted` (see *Deletion* below).
5. **`notmuch new`** — re-index, because step 4 *renames* files (the `T` flag is
   part of the Maildir filename).
6. **apply tag rules** — runs the `%notmuch-tag-rules` queries.
7. **`mbsync <channel>`** — push: the `T` flags become IMAP `\Deleted`, and the
   expunge triggers Gmail's trash move.

There is no folder-move / "plugin" machinery — earlier versions moved files into
`[Gmail]/Trash` locally, which duplicated messages on Gmail.  Deletion is now
entirely flag-based (see below).

---

## Credentials (decrypt-once, in-memory)

Authentication uses a **Gmail app password** stored in `~/.authinfo.gpg`, not
OAuth.  The design goal: unlock once, then never re-prompt at random when the
gpg-agent cache expires.

- The configuration carries a `credentials` field: a list of
  `(ENV-VAR COMMAND ARG …)` entries.  For this setup:

  ```
  ("MBSYNC_PASS_MAIN"  ".../mail-authinfo-password.scm" "imap.gmail.com" "tmarjeski@gmail.com")
  ("MBSYNC_PASS_LISTS" ".../mail-authinfo-password.scm" "imap.gmail.com" "tarjeski@gmail.com")
  ```

- `ensure-credentials!` runs each `COMMAND` **once per daemon lifetime**,
  captures its stdout (the password), and `setenv`s it into the daemon's
  environment.  The decrypted secret is held in the daemon's memory; it is not
  re-decrypted on later passes, so it **survives gpg-agent TTL expiry**.  A
  failed/cancelled decrypt is *not* cached, so the next pass retries.

- `mbsync` child processes inherit that environment.  In `.mbsyncrc`, each
  `PassCmd` prefers the env var and falls back to the script for manual runs:

  ```
  PassCmd "sh -c 'if [ -n \"$MBSYNC_PASS_MAIN\" ]; then printf %s \"$MBSYNC_PASS_MAIN\";
                  else .../mail-authinfo-password.scm imap.gmail.com tmarjeski@gmail.com; fi'"
  ```

  So the daemon uses the in-memory secret; a manual `mbsync`/`mail-sync` falls
  back to `gpg` (which uses the gpg-agent cache, prompting via pinentry only if
  needed).

**The only time you are prompted** for the gpg passphrase is the first sync
after the daemon (re)starts — i.e. on reboot, `guix home reconfigure`, or
`herd restart`.  The graphical `pinentry-fuzzguy` handles the prompt.

---

## Deletion (Gmail-native, no duplicates)

Gmail is label-based; the only reliable way to *trash* a message over IMAP is to
mark it `\Deleted` and expunge it so Gmail moves it to Trash server-side.

1. Tag a message `+deleted` in notmuch (e.g. from `notmuch.el`).
2. `mail-stage-deleted.scm` adds the Maildir `T` flag to its file(s) — isync maps
   `T` ↔ IMAP `\Deleted`.  Files already in a Trash folder, already flagged `T`,
   or **under a read-only path** (see below) are skipped.
3. On the next push, `mbsync` (with `Expunge Both` in `.mbsyncrc`) sets
   `\Deleted` and expunges.
4. Gmail moves the message to Trash and it re-syncs into the local
   `[Gmail]/Trash` folder.

### Required Gmail setting (one-time, per account)

This flow depends on a server-side setting in the Gmail web UI for **both**
`tmarjeski@gmail.com` and `tarjeski@gmail.com` — Settings → Forwarding and
POP/IMAP:

- **Auto-Expunge: OFF** ("Wait for the client to update the server").
- **When a message is marked deleted and expunged from the last visible IMAP
  folder → Move the message to the Trash.**

Without this, expunging just *archives* (removes the INBOX label, leaving the
message in All Mail) instead of trashing it.

### Read-only paths (per-account deletion)

notmuch tags are per *logical message* (by Message-ID), but a deduplicated
message can have physical files in **both** accounts — e.g. a list reply sent
from `main` comes back through the list into `lists/INBOX`, so the one notmuch
message has a `main/…` file and a `lists/INBOX/…` file.  Because
`notmuch search --output=files` returns *all* files of a matching message (a
`path:` predicate selects messages, not files), naively flagging every file
would delete the lists copy too.

The `read-only-paths` configuration field lists absolute Maildir prefixes whose
physical copies must **never** be flagged for deletion.  It is serialized into
the generated `~/.notmuch-config` as

```ini
[mailsync]
read_only_paths=/home/trev/Mail/lists/
```

and `mail-stage-deleted.scm` reads it via `notmuch config get` — so the daemon
*and* the manual `mail-sync` share one source of truth.  With `lists/` read-only,
deleting a deduplicated message removes only the `main/` copy (and the message
stays visible in the lists "forum" via the surviving `lists/INBOX` file); a
message that exists *only* under a read-only path is never deleted from notmuch
(handle those rare cases in Gmail's web UI).

This is why `deleted` is **not** in `exclude_tags`: exclusion is per logical
message, so excluding `deleted` would also hide the surviving lists copy.
Instead, the `main` saved searches carry `not tag:deleted` to hide it per view.

---

## Tag rules

`%notmuch-tag-rules` (in `files/notmuch-config.scm`) is a list of
`((query . "<notmuch query>") (tags +x -y …))` entries applied on every pass.
They are path- and header-derived, so they are idempotent and self-correcting:

- **Account tags** — `+account-main` for `path:main/**`, `+account-lists +lists`
  for `path:lists/**`, with `-account-main` / `-account-lists` cleanup when a
  file no longer matches its path.
- **Archive tags** — `+archive` for `path:archive/**` (+ cleanup).
- **List tags** — `+guix-devel`, `+guix-help`, `+emacs-devel`, `+emacs-bugs`
  (each `+lists`), matched both by `To`/`Cc` and by the `archive/gnu/<list>/`
  import path.
- **Forge tags** — `+github` (GitHub notification senders), `+codeberg`.
- **Cleanup** — `-new` removes the transient `new` tag after each pass.

These rules are the single source of truth for tagging; the daemon applies them
automatically, so neither `mail-sync` nor `mail-fetch-gnu-archive` re-tags.

---

## Helper scripts (`mail-scripts` package)

Installed to the home profile's `bin/` (on `PATH`).  The two Guile scripts are
"pure Guile" — their `exec guile` trampoline is rewritten by the package to the
**store guile**, so they have no PATH/profile dependency for the daemon.

| Command | Language | Purpose |
|---------|----------|---------|
| `mail-authinfo-password.scm MACHINE LOGIN` | Guile | Decrypt `~/.authinfo.gpg` and print the password for a `machine`/`login` pair. Handles both quoted and bare password fields. Used by the daemon's credential cache and by `.mbsyncrc`'s PassCmd fallback. |
| `mail-stage-deleted.scm [--dry-run]` | Guile | Add the Maildir `T` flag to `tag:deleted` files, skipping copies already in Trash, already flagged, or under a `read_only_paths` prefix (read from `notmuch config`). `--dry-run` prints intended renames without touching files. Run by the daemon as `tag-command`. |
| `mail-sync` | POSIX sh | One-shot manual sync: `notmuch new` → `mail-stage-deleted.scm` → `mbsync mail` → `notmuch new`, plus pruning of cached archive mboxes older than 90 days. Tagging is left to the daemon. |
| `mail-fetch-gnu-archive LIST YYYY-MM` | POSIX sh | Download a GNU mailing-list mbox (e.g. `guix-devel`, `emacs-devel`, `bug-gnu-emacs`, `help-guix`), split it, de-duplicate against the notmuch DB by `Message-ID`, and import new messages into `~/Mail/archive/gnu/<list>/`. |

---

## Configuration reference

`notmuch-mbsync-configuration` fields (`services/notmuch-mbsync.scm`):

| Field | Default | Meaning |
|-------|---------|---------|
| `enabled` | `#t` | Whether the Shepherd service is created. |
| `dry-run` | `#f` | Log commands without executing them. |
| `verbose` | `#f` | Extra logging. |
| `accounts` | `'()` | List of account alists. The orchestrator reads `id`, `channel`, `maildir` (plus optional per-account command/`tag-rules` overrides); the `.mbsyncrc` generator additionally reads `host`, `user`, `pass-env`, `patterns`. |
| `tag-rules` | `'()` | The tag-rule list described above. |
| `mbsync-command` | `"mbsync"` | mbsync binary. |
| `notmuch-command` | `"notmuch"` | notmuch binary. |
| `tag-command` | `#f` | Command run after `notmuch new`, before the push — here, `mail-stage-deleted.scm`. |
| `mbsyncrc-file` | `#f` | Override for `~/.mbsyncrc`. When `#f`, the file is **generated** from `accounts`/`credentials`. |
| `notmuch-config-file` | `#f` | Override for `~/.notmuch-config`. When `#f`, the file is **generated** from `notmuch-settings`. |
| `notmuch-settings` | `'()` | Alist serialized into the generated `~/.notmuch-config` (see below). |
| `read-only-paths` | `'()` | Absolute Maildir prefixes whose copies are never staged for deletion (serialized to `[mailsync] read_only_paths`; see *Read-only paths*). |
| `interval-seconds` | `600` | Daemon sleep between sync passes. |
| `credentials` | `'()` | `(ENV-VAR COMMAND ARG …)` entries decrypted once and cached. |

### Generated config files

`~/.mbsyncrc` and `~/.notmuch-config` are **generated from the configuration
record** by the service's activation extension (serializers
`notmuch-mbsync-mbsyncrc` / `notmuch-mbsync-notmuch-config` in
`services/notmuch-mbsync.scm`), turned into `plain-file` store items, and
symlinked into `$HOME`.  This keeps the structured account/credential/notmuch
data as the single source of truth — there are no hand-maintained mail dotfiles.
Set `mbsyncrc-file` / `notmuch-config-file` to a file-like or path to override a
generated file with a hand-written one.

**`.mbsyncrc`** — one `IMAPAccount`/`IMAPStore`/`MaildirStore`/`Channel` block
per account, then a `Group mail` joining the channels.  Per account it reads
`id` (account/store names), `channel`, `host`, `user`, `maildir`
(`Path`/`Inbox`), and `patterns`.  The `PassCmd` prefers the daemon-exported
`pass-env` var and falls back to the matching `credentials` command (so the
fallback can't drift from the cached secret).  Global settings are constant:
`TLSType IMAPS`, the system `CertificateFile`, `Create Both`, `Expunge Both`
(what makes the `\Deleted`/trash flow work), and `SyncState *`.

**`.notmuch-config`** — built from the `notmuch-settings` alist.  Recognized
keys (list-valued ones are joined with `;`):

| Key | Example | Section |
|-----|---------|---------|
| `database-path` | `"/home/trev/Mail"` | `[database] path` |
| `user-name` | `"Trevor Arjeski"` | `[user] name` |
| `primary-email` | `"tmarjeski@gmail.com"` | `[user] primary_email` |
| `other-email` | `()` | `[user] other_email` |
| `new-tags` | `("new" "unread")` | `[new] tags` |
| `new-ignore` | `(".uidvalidity" ".mbsyncstate")` | `[new] ignore` |
| `exclude-tags` | `("spam")` | `[search] exclude_tags` |
| `synchronize-flags` | `#t` | `[maildir] synchronize_flags` |

`synchronize_flags=true` keeps the standard Maildir flags (`F`/`R`/`S`/…) in sync
with notmuch tags.  `exclude_tags` hides those tags from normal searches *except*
queries that mention the tag explicitly.  `deleted` is intentionally **not**
excluded (see *Read-only paths*) — it is hidden per view via `not tag:deleted` in
the `main` saved searches, so a dup deleted from `main` stays visible in lists.

---

## Usage

### Background

The daemon runs automatically every `interval-seconds`.  Nothing to do.

### Manual sync now

```sh
mail-sync
```

### Delete mail

Tag it `+deleted` in `notmuch.el` (or `notmuch tag +deleted -- <query>`).  It is
trashed on the next sync pass (≤ 10 min), or immediately with `mail-sync`.

### Import a GNU list archive

```sh
mail-fetch-gnu-archive emacs-devel 2026-05
```

### Service control

```sh
herd status  notmuch-mbsync     # state, last runs, log path
herd restart notmuch-mbsync     # reload after reconfigure (re-prompts pinentry once)
herd stop    notmuch-mbsync
tail -f ~/.local/state/shepherd/notmuch-mbsync.log
```

### Deploy changes

```sh
guixboy reconfigure apply home niri      # or: guix home reconfigure -L channel -L host -e '...'
herd restart notmuch-mbsync              # pick up the new runner; unlock once at the first sync
```

---

## Troubleshooting

- **`Maildir error: duplicate UID N`** — a local Maildir has two files claiming
  the same isync UID (a relic of older move-based flows).  `mbsync` refuses to
  sync until it is resolved.  Find collisions with:

  ```sh
  find "~/Mail/main/[Gmail]/Trash"/{cur,new} -type f \
    | sed -n 's/.*,U=\([0-9]*\):.*/\1/p' | sort -n | uniq -d
  ```

  Then either remove the redundant copy of each colliding UID (keeping one file
  per UID avoids any Gmail expunge), or move the whole folder aside — together
  with its `.uidvalidity` / `.mbsyncstate` — and let `mbsync` re-pull it fresh.

- **A deleted message reappears briefly in a search** — it is staged but not yet
  synced.  `deleted` is hidden per view rather than via `exclude_tags`, so add
  `not tag:deleted` to volatile searches (the `main` inbox/unread views already
  have it).

- **Deleting a message removed the wrong account's copy** — check
  `notmuch config get mailsync.read_only_paths`; the account you want to protect
  must be listed (set via `read-only-paths`, see *Read-only paths*).

- **Sync fails with an auth error after a long uptime** — should not happen (the
  daemon holds the password in memory).  If it does, `herd restart
  notmuch-mbsync` re-decrypts (one pinentry prompt).

- **Deletions archive instead of trashing** — the Gmail IMAP setting is wrong;
  set Auto-Expunge OFF and the expunge action to "Move to Trash" for the account.

- **Nothing is being tagged** — tagging is the daemon's job; a bare `mbsync` or
  `mail-sync` will not apply `%notmuch-tag-rules`.  Wait for a daemon pass or
  check the log for `tag-rule-apply` lines.

---

## Design notes / history

- **Engine:** mbsync/IMAP with an app password, *not* lieer/Gmail-API.  Lieer was
  evaluated and rejected because it uses OAuth and cannot read the
  `.authinfo.gpg` app password.
- **Deletion** was migrated from a fragile local folder-move (which duplicated
  messages and left copies in All Mail) to the Gmail-native `\Deleted`-flag flow.
- **Per-account deletion (`read-only-paths`)** was added because notmuch tags are
  per logical message: a list reply sent from `main` is deduplicated with its
  `lists/INBOX` copy, and flagging "the message" would delete both.  Marking the
  lists maildir read-only scopes deletion to the `main` copy.
- **The service** was converted from a Shepherd *timer* to a *daemon* specifically
  so the decrypted password can be held in memory across passes.
- **The plugin / move-rule subsystem** was removed once deletion no longer needed
  it; tagging is the only remaining post-sync transform.
- **Helper scripts** were moved out of the dotfiles tree into this channel as the
  `mail-scripts` package, and the credential/deletion-staging scripts were
  rewritten from POSIX shell to Guile.
- **`~/.mbsyncrc` and `~/.notmuch-config`** were the last hand-maintained mail
  dotfiles; they are now *generated* from `%notmuch-mbsync-configuration` so the
  account/credential/notmuch data has a single source of truth.
