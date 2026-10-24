#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Git','Node','SevenZip')][string[]]$Tools = @('Git','Node','SevenZip'))

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Workstation-Paths.ps1')
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    throw 'This bootstrap supports Windows x64 only. Install other architectures manually.'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ 'User-Agent' = 'portable-dev-workstation'; Accept = 'application/vnd.github+json' }

function Get-Release([string]$Repository) {
    Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest" -Headers $headers -TimeoutSec 120
}
function Save-Verified([string]$Uri, [string]$Hash, [string]$Destination) {
    if ($Uri -notmatch '^https://' -or $Hash -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'Missing HTTPS URL or upstream SHA-256 digest; refusing download.'
    }
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination -TimeoutSec 900
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $Hash) {
        throw "SHA-256 mismatch: $Destination"
    }
}
function Save-Asset($Asset, [string]$Destination) {
    if (-not $Asset -or -not $Asset.PSObject.Properties['digest'] -or $Asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'Release asset has no SHA-256 digest. No executable will run.'
    }
    Save-Verified $Asset.browser_download_url $Matches[1] $Destination
}
function Get-PortableExtractor([string]$Stage, [switch]$Zip) {
    $release = Get-Release 'ip7z/7zip'
    $asset = @($release.assets | Where-Object { $_.name -eq '7zr.exe' })
    if ($asset.Count -ne 1) { throw '7zr asset missing or ambiguous.' }
    $exe = Join-Path $Stage '7zr.exe'
    Save-Asset $asset[0] $exe
    if (-not $Zip) { return $exe }
    $extra = @($release.assets | Where-Object { $_.name -match '^7z\d+-extra\.7z$' })
    if ($extra.Count -ne 1) { throw '7-Zip Extra asset missing or ambiguous.' }
    $archive = Join-Path $Stage 'extractor.7z'
    $folder = Join-Path $Stage 'extractor'
    Save-Asset $extra[0] $archive
    & $exe x $archive "-o$folder" -y | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not unpack ZIP extractor.' }
    return (Join-Path $folder 'x64\7za.exe')
}

foreach ($tool in $Tools | Select-Object -Unique) {
    $folder = @{ Git = 'Git'; Node = 'Node'; SevenZip = '7Zip' }[$tool]
    $target = Join-Path $root "Apps\$folder"
    Assert-WorkstationDirectory $root $target
    if (Test-Path -LiteralPath $target) { Write-Host "$tool already has a folder; leaving it untouched: $target"; continue }
    if (-not $PSCmdlet.ShouldProcess($target, "Download, verify and unpack $tool (latest upstream release; Node uses LTS)")) { continue }
    $stage = Join-Path $root ('Data\Cache\Setup\' + [guid]::NewGuid().ToString('N'))
    $payload = Join-Path $stage 'payload'
    Assert-WorkstationDirectory $root $stage
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    try {
        switch ($tool) {
            'Node' {
                $index = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -TimeoutSec 120
                $release = @($index | Where-Object { $_.lts -is [string] })[0]
                $version = $release.version
                if ($version -notmatch '^v\d+\.\d+\.\d+$') { throw 'Unexpected Node version.' }
                $name = "node-$version-win-x64.zip"
                $base = "https://nodejs.org/dist/$version"
                $sums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/SHASUMS256.txt" -TimeoutSec 120).Content
                $line = @($sums -split "`n" | Where-Object { $_ -match ('^[a-fA-F0-9]{64}\s+' + [regex]::Escape($name) + '\s*$') })
                if ($line.Count -ne 1) { throw 'Node checksum entry missing or ambiguous.' }
                $archive = Join-Path $stage 'node.zip'
                Save-Verified "$base/$name" ($line[0].Substring(0,64)) $archive
                # Avoid Windows PowerShell 5.1 ZIP/path-length limitations.
                $exe = Get-PortableExtractor $stage -Zip
                & $exe x $archive "-o$payload" -y | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Node extraction failed: $LASTEXITCODE" }
                $install = Join-Path $payload "node-$version-win-x64"
            }
            'Git' {
                $release = Get-Release 'git-for-windows/git'
                $asset = @($release.assets | Where-Object { $_.name -match '^PortableGit-.*-64-bit\.7z\.exe$' })
                if ($asset.Count -ne 1) { throw 'PortableGit x64 asset missing or ambiguous.' }
                $archive = Join-Path $stage 'PortableGit.7z.exe'
                Save-Asset $asset[0] $archive
                # Read the SFX as an archive; do not execute its installer hooks.
                $exe = Get-PortableExtractor $stage
                & $exe x $archive "-o$payload" -y | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "PortableGit extraction failed: $LASTEXITCODE" }
                # README.portable requires post-install initialization after manual extraction.
                # This is the x64 shell portion of upstream post-install.bat; avoid its
                # unquoted batch CD, which breaks workstation paths containing '&'.
                $bash = Join-Path $payload 'usr\bin\bash.exe'
                & $bash --noprofile --norc -c 'unset GIT_EXEC_PATH; export PATH=/ucrt64/bin:/mingw64/bin:/usr/bin:$PATH; export SYSCONFDIR=/etc; for p in $(export LC_COLLATE=C; echo /etc/post-install/*.post); do test -e "$p" && . "$p"; done' | Out-Host
                # MSYS may append .exe when hard-linking the git executable as a marker.
                $initialized = @( @('ucrt64','mingw64') | Where-Object {
                    (Test-Path -LiteralPath (Join-Path $payload "$_\libexec\git-core\dlls-copied")) -or
                    (Test-Path -LiteralPath (Join-Path $payload "$_\libexec\git-core\dlls-copied.exe"))
                } )
                if ($LASTEXITCODE -ne 0 -or
                    (Test-Path -LiteralPath (Join-Path $payload 'etc\post-install')) -or
                    $initialized.Count -ne 1) {
                    throw 'PortableGit post-install initialization failed.'
                }
                Remove-Item -LiteralPath (Join-Path $payload 'post-install.bat') -Force
                $install = $payload
            }
            'SevenZip' {
                $release = Get-Release 'ip7z/7zip'
                $extractor = @($release.assets | Where-Object { $_.name -eq '7zr.exe' })
                $extra = @($release.assets | Where-Object { $_.name -match '^7z\d+-extra\.7z$' })
                if ($extractor.Count -ne 1 -or $extra.Count -ne 1) { throw '7-Zip portable assets missing or ambiguous.' }
                $exe = Join-Path $stage '7zr.exe'
                $archive = Join-Path $stage 'extra.7z'
                Save-Asset $extractor[0] $exe
                Save-Asset $extra[0] $archive
                & $exe x $archive "-o$payload" -y | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed: $LASTEXITCODE" }
                $install = $payload
                Copy-Item -LiteralPath (Join-Path $payload 'x64\7za.exe') -Destination (Join-Path $payload '7za.exe')
            }
        }
        $expected = @{ Git = 'cmd\git.exe'; Node = 'node.exe'; SevenZip = '7za.exe' }[$tool]
        if (-not (Test-Path -LiteralPath (Join-Path $install $expected) -PathType Leaf)) { throw "$tool payload is incomplete." }
        New-Item -ItemType Directory -Path (Join-Path $root 'Apps') -Force | Out-Null
        # Directory.Move fails if target already exists; never merge into an installation.
        [IO.Directory]::Move($install, $target)
        Write-Host "$tool ready at $target"
    } finally {
        # stage is a GUID directory below this workstation, never an arbitrary input path.
        $stagePrefix = [IO.Path]::GetFullPath((Join-Path $root 'Data\Cache\Setup')).TrimEnd('\') + '\'
        if (-not ([IO.Path]::GetFullPath($stage)).StartsWith($stagePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path.' }
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
}
