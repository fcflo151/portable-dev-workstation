# Validation record: 2026-10-24

These results describe local tests on one Windows x64 host and an NTFS drive,
using Windows PowerShell `5.1.26100.9278` and PowerShell `7.6.5`.
They are not a security certification or evidence of a GitHub Actions run.

| Check | Result |
| --- | --- |
| Offline template suite, Windows PowerShell 5.1 | Passed |
| Offline template suite, PowerShell 7 | Passed |
| Fresh online setup, Windows PowerShell 5.1 | Passed |
| Fresh online setup, PowerShell 7 | Passed |
| Public repository boundaries and recognizable credential scan, both shells | Passed; no pattern detections |
| Staged and reachable-history publication checks | Passed |
| Publication guard regressions | Staged/historical synthetic tokens and staged browser export rejected |
| Git whitespace check | Passed |

Online runs downloaded Git `2.56.0.windows.3`, Node `v24.22.1`, npm `11.19.1`
and 7-Zip `26.05`. Setup verified the upstream SHA-256 values before running
extraction helpers and the Git initialization scripts. Both runs used a fresh
workstation path containing spaces, `&` and `!`. They verified repeat setup
preserved executable hashes, created a synthetic commit, cloned it using Git's
transport helpers, exercised Node/npm and ran backup tests with the newly
installed standalone 7-Zip.

Offline checks cover the actual batch launcher, child shell module loading,
parent environment preservation, repeat environment setup, synthetic missing
and mismatched download hashes, setup staging cleanup, backup dry-runs,
password rejection, encrypted headers, restoration, exclusions, sync-copy
hash equality, archive-failure cleanup and source/destination junction guards.

## Repairs

- Reset inherited PowerShell module paths in the batch environment. A real
  setup run reached through `cmd.exe` previously failed to find `Get-FileHash`
  because it inherited PowerShell 7 core module paths in Windows PowerShell.
  Microsoft documents this [indirect child-process behavior](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath?view=powershell-7.6#starting-windows-powershell-from-powershell-7).
- Initialize manually extracted PortableGit as required by its packaged
  `README.portable`. Run the verified archive's x64 shell initialization before
  moving the payload into `Apps\Git`; support both UCRT64 and MINGW64 layouts.
- Quote the displayed workstation path in the batch launcher so `&` does not
  turn part of the path into a command.
- Use BOM-free ASCII input for terminal tests and clear expected native failure
  statuses before returning test success to a CI caller.
- Reject existing links and junctions in managed setup/backup write paths.
- Distinguish `Data\Backups` from similarly named directories such as
  `Data\Backups-notes`.
- Require backup coverage in CI, add opt-in real setup jobs for both shells,
  and add a limited publication guard. Downloads and database files are also
  ignored by default.

## Remaining limits

- No test on a second physical PC, Windows 10, ARM64 or a different drive
  letter. No complete measurement of host writes or administrative isolation.
- These local results do not establish a GitHub Actions result. Consult the
  repository's Actions page for results after publication.
- The publication guard checks working files, staged objects and (with
  `-IncludeHistory`) the selected reachable history, using a limited set of
  recognizable credential patterns. It does not prove the absence of arbitrary
  secrets. Earlier negative-test commands were blocked by automatic action
  review. A later non-destructive synthetic fixture suite completed successfully;
  no force-add, remote or deletion is used by that suite.
- Successful online fixtures were removed by the test runner. Automatic action
  review also blocked cleanup of the earlier diagnostic fixture under
  `Data\Cache\Review`; it remains ignored
  and can be removed manually when no test process is using it.
- Download selection remains dynamic and trusts upstream publishers.
  [GitHub asset digests](https://github.blog/changelog/2025-06-03-releases-now-expose-digests-for-release-assets/)
  provide integrity checks, not independent publisher verification.
- Backup passwords still reach 7-Zip through native process arguments, as
  described in `SECURITY.md`. Filesystem checks do not prevent concurrent
  malicious changes. The static dashboard and private production workstation
  features were not expanded or certified by these tests.

Re-run the commands in `DEVELOPMENT.md` after relevant code or upstream changes.

The pre-publication Chrome review is recorded separately in
`BROWSER-PRIVACY.md`. It checked storage paths and file metadata without
reading browser content, deleting host profiles or weakening encryption.

## Optional AI commits, 2026-10-24

Seven Node tests passed for saved-login/free-model requirements, isolated config,
denied tools/integrations, prompt attachment cleanup, provider rejection without
paid fallback, private/oversized inputs, generated commit subjects with real local
Git push, cancellation and changed-file rejection. The provider rejection path
also completed a local push using the manually supplied fallback subject.
The template/backup suite and publication guard passed again after this addition.
The tests do not establish successful authenticated live model access; see
`AI-COMMITS.md`. The workstation's private browser patches are outside this public
template and are not distributed with its application data or binaries.
