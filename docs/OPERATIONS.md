# Operations

## A session-based automatic backup loop

Scheduling is opt-in. This template does not register a Windows task or service. In a PowerShell process launched from the portable terminal, you can run:

```powershell
$password = Read-Host 'Backup password' -AsSecureString
while ($true) {
    & "$env:WORKSTATION_ROOT\Tools\Backup-Workstation.ps1" -Password $password -ErrorAction Stop
    Start-Sleep -Seconds 3600
}
```

The first backup runs immediately; failures stop the loop. Close applications before each backup or adapt this example to your own consistency requirements. Stop with Ctrl+C. The loop ends when its terminal closes. Do not paste passwords into source code. The native process-argument exposure described in SECURITY.md also applies here. There is no retention or automatic deletion. A sync client and its authentication remain your responsibility.

## Provisioning and maintenance

Run scripts from the portable terminal so temporary paths are on the SSD. An interrupted download can leave a GUID directory under `Data\Cache\Setup`; inspect and remove only stale staging directories when no setup is running. Existing folders in `Apps` are skipped even if incomplete. Review a failed installation before moving its folder aside and retrying.

Keep tool licenses next to the binaries. The 7-Zip Extra archive is kept intact, with its x64 console copied to `Apps\7Zip\7za.exe`. No tool binaries are committed. Windows x64 is the automatic setup target; do not run this setup under an ARM64 host's x64 emulation and assume native compatibility.

For reproducible provisioning, replace dynamic release selection with reviewed, pinned URLs and hashes in your own fork. GitHub API rate limiting or a release without hashes will fail closed. Downloaded files require network access only during setup; the workstation's command-line tools and dashboard can then work offline according to each tool's own requirements.

## Repository publication

The upstream repository is `fcflo151/portable-dev-workstation`. For your own template repository, first review every tracked file, then:

```powershell
git init -b main
git add .
git diff --cached
git commit -m "Create portable workstation template"
gh repo create YOUR_ACCOUNT/YOUR_TEMPLATE --public --source . --remote origin --push
gh repo edit YOUR_ACCOUNT/YOUR_TEMPLATE --template
gh api repos/YOUR_ACCOUNT/YOUR_TEMPLATE --jq '.is_template'
```

`gh repo create --template OWNER/REPO` means **generate from an existing template**. `gh repo edit --template` marks an existing repository as a template. Files under `.github` cannot set this repository property by themselves. See the official [create](https://cli.github.com/manual/gh_repo_create) and [edit](https://cli.github.com/manual/gh_repo_edit) documentation.

Use a repository-local Git identity for publication when needed. Do not distribute the maintainer's personal Git configuration through the template. Update README badge links after generating a repository under a different account or name.
