#requires -Version 5.1
[CmdletBinding()]
param([string]$RepositoryRoot, [switch]$IncludeHistory, [string]$Revision = 'HEAD')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $PSScriptRoot }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).ProviderPath
$git = (Get-Command git.exe -ErrorAction Stop).Source
function Invoke-RepositoryGit([string[]]$GitArguments) {
    # Trust only the explicitly selected checkout, without changing global Git config.
    $result = & $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot @GitArguments
    if ($LASTEXITCODE -ne 0) { throw 'Repository inspection failed.' }
    return $result
}
$files = (Invoke-RepositoryGit @('ls-files','-z','--cached','--others','--exclude-standard')) -join "`n"
$markers = @('Apps/.gitkeep','Data/Config/.gitkeep','Data/PortableHome/.gitkeep')
$patterns = @(
    '-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----',
    '\bgh[pousr]_[A-Za-z0-9]{36,}\b',
    '\bgithub_pat_[A-Za-z0-9_]{50,}\b',
    '\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}\b'
)
function Assert-PublicPath([string]$File) {
    if (($File -match '^(Apps|Data|GitRepos|Downloads)/' -and $File -notin $markers) -or
        $File -match '\.(exe|dll|msi|7z|zip|sqlite3?|db|pem|key|pfx|p12|kdbx?)$' -or
        ($File -match '(^|/)\.env(?:\..+)?$' -and $File -notmatch '(^|/)\.env\.example$') -or
        $File -match '(^|/)(\.ssh|\.gnupg|\.aws|\.azure|\.mcp-auth)(/|$)' -or
        $File -match '(^|/)(Local State|History|Cookies|Login Data|Web Data|Preferences|Secure Preferences|Bookmarks|credentials[^/]*\.json|tokens?\.json|auth\.json|hosts\.yml|\.git-credentials|\.npmrc|id_(rsa|ed25519|ecdsa)[^/]*)$') {
        throw "Private/runtime file is tracked or publishable: $File"
    }
}
function Assert-PublicContent([string]$File, [string]$Content) {
    if ($File -in $markers -and $Content.Length) { throw "Folder marker is not empty: $File" }
    foreach ($pattern in $patterns) {
        if ($Content -match $pattern) { throw "Possible credential in $File. Inspect locally; never paste its value into public logs." }
    }
}
foreach ($file in $files.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Unique) {
    Assert-PublicPath $file
    $full = Join-Path $RepositoryRoot $file
    if (Test-Path -LiteralPath $full -PathType Leaf) {
        if ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked publishable file is not supported: $file" }
        Assert-PublicContent $file ([IO.File]::ReadAllText($full))
    }
}
# Inspect the actual index too: a clean working file must not hide a staged secret.
$seenBlobs = New-Object 'Collections.Generic.HashSet[string]'
function Test-GitEntries([string]$Entries) {
    foreach ($entry in $Entries.Split([char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries)) {
        if ($entry -notmatch '^(\d+) (?:blob )?([a-f0-9]+)(?: [0-3])?\t(.+)$') { throw 'Unrecognized Git tree/index entry.' }
        $mode = $Matches[1]; $objectId = $Matches[2]; $name = $Matches[3]
        Assert-PublicPath $name
        if ($mode -notin @('100644','100755')) { throw "Non-regular file in publication: $name" }
        if ($seenBlobs.Add($objectId)) {
            $content = (Invoke-RepositoryGit @('cat-file','blob',$objectId)) -join "`n"
            Assert-PublicContent $name $content
        }
    }
}
Test-GitEntries ((Invoke-RepositoryGit @('ls-files','--stage','-z')) -join "`n")
if ($IncludeHistory) {
    foreach ($commit in @(Invoke-RepositoryGit @('rev-list',$Revision))) {
        $metadata = (Invoke-RepositoryGit @('cat-file','commit',$commit)) -join "`n"
        Assert-PublicContent 'commit metadata' $metadata
        Test-GitEntries ((Invoke-RepositoryGit @('ls-tree','-r','-z',$commit)) -join "`n")
    }
    Write-Host 'PASS: reachable history and commit metadata checked for the selected revision.'
}
$privateSamples = @('Apps/tool/config.json','Data/Config/credentials.json','Data/PortableHome/note.txt','GitRepos/private/README.md','Downloads/private.txt','.env','nested/.env.production','nested/private.sqlite','nested/id_ed25519','nested/Local State','nested/Cookies','nested/Login Data')
$ignored = @(& $git -c "safe.directory=$RepositoryRoot" -C $RepositoryRoot check-ignore --no-index -- @privateSamples)
if ($LASTEXITCODE -ne 0 -or @($privateSamples | Where-Object { $_ -notin $ignored }).Count) { throw 'Git ignore rules do not protect expected private paths.' }
Write-Host 'PASS: publication file boundaries, private-path ignore rules and recognizable credential patterns.'
Write-Host 'PASS: staged file contents inspected. This remains a limited guard; manually review publication.'
