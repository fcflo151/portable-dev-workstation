# Chrome privacy review

Review date: 2026-10-24. This separates the public template from the maintainer's
private SSD installation. No browser data or credentials are included here.

## What was checked before publication

- Read the private SSD browser starters, environment setup, preference preparation
  and disconnect script.
- Inspected executable locations and only the profile/cache flags of running
  Chrome processes. Did not record URLs or full browser command lines.
- Checked the presence, sizes and modification timestamps of known browser
  database files. Did not read browsing history, cookies, passwords or account
  values and did not attempt decryption.
- Located the real host profile using Windows profile/Explorer registry metadata.
  In a redirected environment, `LOCALAPPDATA` and even runtime folder lookup can
  point to the SSD and are insufficient to establish the host's storage path.
- Checked Git publication paths independently. Host and SSD browser data live
  outside this repository, and private runtime trees inside it are ignored and
  rejected by `Test-Repository.ps1`, including staged/history objects when used
  with `-IncludeHistory`.

## Findings

The running private SSD Chrome used `Data\Browser` for user data and
`Data\Cache\Browser` for the explicit disk cache. The profile contained the
expected `Local State`, history, cookie and login databases. This is persistent
SSD storage, not a temporary or automatically erased session.

A separate Chrome profile existed in the Windows user's actual local AppData.
The inspected `Default` profile files and `Local State` had modification dates
in August, before this review. No running Chrome instance inspected used that
host profile. File timestamps alone cannot attribute all earlier host writes or
prove that no other files were written during SSD use.

The private disconnect script only clears its SSD temporary directory and
selected lock files after attempting to stop SSD processes. It does not erase
the SSD Chrome profile or the host's Chrome data. It was read, not executed:
stopping the live workstation would interrupt active applications. The public
template includes neither that disconnect script nor a browser cleanup tool.

## Sign-in expectations

Plan to sign in again whenever you move the drive to a different PC or Windows
account. Sessions can remain available on the same host; a fresh login on every
launch is not enforced. Chrome uses Windows protections for sensitive data, and
App-Bound Encryption binds keys to the machine when applicable. The exact
protection depends on the Chrome installation and policies. This review did
not change policies or weaken encryption.

See [Google's security explanation](https://security.googleblog.com/2024/07/improving-security-of-chrome-cookies-on.html)
and [Chromium's user-data directory documentation](https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md).

## Practical limits

Use explicit SSD profile/cache paths and configure downloads on the SSD. Check
`chrome://version` for the effective profile. The template's optional dashboard
opens through the host default browser; that action can leave host browser
state. Never infer isolation solely from environment variables.

No general zero-trace guarantee is possible here. Windows execution records,
crash data, paging, security software and manually selected download locations
are outside profile redirection. Existing host-browser data belongs to that
host's user; it was not deleted or copied to the repository.
