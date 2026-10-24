# Security and isolation

## Trust boundary

The SSD contains private keys, sessions, code and backups. Treat it like a laptop: protect physical access, encrypt the drive with a solution appropriate for your host permissions, and keep a separate backup. Never use sensitive credentials on an untrusted host. A portable home cannot protect against host malware, keyloggers or administrators.

No provided script installs a service, requests elevation, writes persistent environment variables or deliberately modifies the Windows Registry. Environment redirection is a convention respected by many command-line tools; it is not containment.

Windows may record process execution, recent files, DNS activity, event logs, Defender scans, crash dumps, paging data or USB device history. Applications may use Windows known-folder APIs or the Registry instead of environment variables. Browser history, credential managers, OAuth callbacks, SSH agents and system Git configuration need separate review. Host environment variables and PATH entries are inherited, so host tools and tokens can still be accessible. `GIT_CONFIG_NOSYSTEM` does not block credential helpers configured elsewhere.

The dashboard opens in the default browser only when requested. A browser's explicit profile flag is required for portable profile storage. This template does not change default browser associations or intercept OAuth. Launch only tools whose own portable behavior you have verified.

## Keeping secrets out of Git

`Apps` and `Data` are denied by default except their `.gitkeep` markers. Common key, database, token and environment filenames are ignored globally. These rules are an accident-prevention layer, not a secret detector. A credential pasted into a README or arbitrary JSON file can still be committed. Forced adds and already tracked files bypass ignore protection.

Before every publication, inspect `git ls-files`, `git status --short`, and `git diff --cached`. Enable GitHub secret scanning and push protection where available. If a secret was committed, revoke it first, then remove it from history using an appropriate history-rewriting procedure. Deleting the latest file alone is insufficient.

`Tools\Test-Repository.ps1` adds a limited check of tracked and unignored files,
runtime boundaries, expected ignore rules and recognizable credential patterns.
It reports filenames without printing matched values. Staged Git objects are
checked independently of working files. `-IncludeHistory` checks files and
metadata reachable from `-Revision` (default `HEAD`); other refs are not covered.
It does not detect arbitrary credentials and does not replace manual review.

Browser profile filenames are ignored and rejected even if previously tracked.
Before publication, also review commit author/committer identities: token scans
do not identify every personal email address. Prefer GitHub's noreply address.

The terminal clears common inherited Git overrides, SSH agent references,
GitHub token variables and runtime injection variables such as `BASH_ENV` and
`NODE_OPTIONS`. This reduces accidental host configuration and credential use;
it is not a complete filter of environment variables or an OS security boundary.
Configure credentials deliberately after starting the portable terminal.

See `BROWSER-PRIVACY.md` for the pre-publication inspection of the separate SSD
Chrome installation. Its profile is persistent; neither it nor the host profile
is automatically wiped by this template. Re-login must be expected on PC changes.

## Downloads and backups

Setup verifies upstream SHA-256 hashes before extraction or execution. Missing digests are a hard failure. This does not protect against a compromised publisher or independently authenticate Node's checksum file. Review releases and licenses before provisioning. Setup never overwrites existing app folders.

After extracting the verified PortableGit archive, setup runs its x64 post-install shell scripts. These initialize the private Git installation, including DLL hard links and local copies of Windows network configuration files. Treat these scripts as publisher code, just like the downloaded binaries. Managed setup and backup destination directories reject existing links and junctions within the workstation; this remains a best-effort check on a trusted filesystem, not a defense against concurrent path replacement.

Backups use the 7z format with AES-256 and encrypted headers (`-mhe=on`). Passwords reach 7-Zip through native process arguments and can be inspected by sufficiently privileged local processes. A SecureString is not an OS isolation boundary. Temporary incomplete archives are removed on handled failures; abrupt power loss can leave `.partial` files. Keep the passphrase separate from the SSD.

Backup sources must be directories below the workstation root and must not contain links or junctions. Backup archives cannot include themselves. This is best-effort validation on a trusted filesystem, not protection against malicious concurrent filesystem changes. Close apps before archiving, protect private data with suitable filesystem permissions, and test a restore regularly.

## Reporting a vulnerability

Do not post credentials or private logs in public issues. Use GitHub's private vulnerability reporting on the upstream repository when enabled. Otherwise contact the maintainer through a private contact route listed on their GitHub profile before sharing sensitive details. Sanitized non-sensitive bug reports can use the issue forms.
