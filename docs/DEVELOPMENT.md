# Continuing development

This repository is the public MIT-licensed workstation template. Start with
`README.md`, `docs/SECURITY.md` and `docs/OPERATIONS.md`, then inspect `git status`
and the latest commits before editing.

## Scope and constraints

- Keep paths relative to the repository root. Launchers use `%~dp0`; PowerShell
  scripts use `$PSScriptRoot`.
- Keep tools and runtime state in `Apps` and `Data`. Never commit installed
  binaries, credentials, browser profiles or personal workstation configuration.
- Do not require elevation, persistent environment changes, registry edits,
  Windows services or a machine-wide execution-policy change.
- Support Windows PowerShell 5.1 and PowerShell 7 on Windows x64.
- Preserve hash verification before setup executes downloaded extraction tools.
- Preserve encrypted backup headers, verification before publication and source
  path validation. Use synthetic data for backup tests.

The private workstation and its Obsidian documentation can supply design ideas,
but they describe additional features outside this template. Browser/OAuth
routing, live process monitoring and authenticated cloud backup are not
implemented here. Review their scope before introducing them. Environment
redirection cannot guarantee that Windows or third-party apps leave no host
traces.

## Validation

Run from the portable workstation terminal:

```powershell
.\Tools\Test-Template.ps1 -RequireBackupTests
.\Tools\Test-Repository.ps1 -IncludeHistory
.\Tools\Test-RepositoryChecks.ps1
node --test .\Tools\tests\ai-commit.test.cjs
```

The test discovers `Apps\7Zip\7za.exe` or `Apps\7Zip\7z.exe` first; alternatively,
provide `-SevenZipPath` explicitly. Run this command under both `powershell.exe`
and `pwsh.exe`. Test fixtures live under `Data\Cache\Tests` and are removed on
completion. Setup failure tests use synthetic HTTP responses; ordinary tests do
not download or install tools. The publication check requires Git.

Run `.\Tools\Test-OnlineSetup.ps1` separately in both shells to exercise real
downloads and fresh tool installations in a disposable workstation. It tests
Git initialization, commit/clone, Node/npm, repeat setup and the backup suite.
Use `-KeepFailedFixture` only when you need to inspect a failure locally. CI's
manual workflow exposes the same opt-in online tests.

The backup regression checks include similarly named source folders such as
`Data\Backups-notes`, rejection of the actual backup tree and its ancestors,
restore content, encrypted headers and SHA-256 equality of the sync copy.
CI uses `-RequireBackupTests` so missing 7-Zip cannot turn these checks into a
successful run with skipped backup coverage. Additional checks cover invalid
passwords, archive failure cleanup, missing/mismatched hashes, junctions, common
inherited host tokens/overrides and the actual terminal launcher. Publication
regressions use only synthetic data in small isolated Git repositories without
remotes under `Data\Cache\RepositoryTests`. They intentionally retain these
small ignored fixtures for inspection. `Portable-Env.cmd` resets the inherited module search
path so Windows PowerShell reached through `cmd.exe` does not load PowerShell 7
core modules. PowerShell itself can still add host module paths during startup.

Before publication, review the full diff and tracked files as described in
`docs/SECURITY.md`. Follow `docs/OPERATIONS.md` for GitHub publication. A local
test run is not evidence that a GitHub workflow has run or that a repository
has been published.

The optional OpenCode commit-message tests use mocked CLI responses and real
synthetic local Git remotes under ignored `Data\Temp`. They require Node and Git,
make no external model or GitHub request, and retain fixtures for local inspection.
See `AI-COMMITS.md` for provider-access and privacy limits.
