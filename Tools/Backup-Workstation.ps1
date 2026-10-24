#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$IncludePaths = @('Data\Config','Data\PortableHome','GitRepos'),
    [string]$SevenZipPath,
    [Security.SecureString]$Password,
    [string]$SyncDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Workstation-Paths.ps1')
$prefix = $root.TrimEnd('\') + '\'
$sources = @()
foreach ($relative in $IncludePaths) {
    if ([IO.Path]::IsPathRooted($relative)) { throw 'Backup sources must be relative to the workstation.' }
    $full = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup source escapes workstation.' }
    $backupRoot = Join-Path $root 'Data\Backups'
    if ($full.Equals($backupRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($backupRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $backupRoot.StartsWith($full.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Backup sources must not include or be inside Data\Backups.'
    }
    if (Test-Path -LiteralPath $full) {
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { throw 'Backup sources must be directories.' }
        # Reject links, including any parent junction, to avoid archiving external data.
        $parent = Get-Item -LiteralPath $full -Force
        while ($parent -and $parent.FullName.Length -ge $root.Length) {
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked source is not supported: $($parent.FullName)" }
            $parent = $parent.Parent
        }
        $links = @(Get-ChildItem -LiteralPath $full -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($links.Count) { throw "Remove linked files/directories from source: $relative" }
        $sources += $full
    }
}
if (-not $sources.Count) { throw 'No backup sources exist.' }
if (-not $SevenZipPath) {
    $candidate = @('Apps\7Zip\7za.exe','Apps\7Zip\7z.exe' | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
    if (-not $candidate.Count) { throw 'Run Setup-Workstation.ps1 -Tools SevenZip first.' }
    $SevenZipPath = $candidate[0]
}
if (-not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) { throw '7-Zip executable not found.' }
$SevenZipPath = (Resolve-Path -LiteralPath $SevenZipPath).ProviderPath
$destination = Join-Path $root ('Data\Backups\workstation-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.7z')
Assert-WorkstationDirectory $root (Split-Path -Parent $destination)
if (-not $PSCmdlet.ShouldProcess($destination, 'Create and verify encrypted 7z backup; optionally copy to sync directory')) { return }
New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
$partial = $destination + '.partial'
$passwordArgument = $null
$pointer = [IntPtr]::Zero
try {
    if (-not $Password) { $Password = Read-Host 'Backup password (nonempty)' -AsSecureString }
    if ($Password.Length -eq 0) { throw 'Empty passwords are not allowed.' }
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrEmpty($plain) -or $plain -match '[\x00\r\n"]') { throw 'Password must be nonempty and contain no quotes or line breaks.' }
    $passwordArgument = '-p' + $plain
    $plain = $null
    Push-Location -LiteralPath $root
    try {
        $relativeSources = @($sources | ForEach-Object { $_.Substring($prefix.Length) })
        & $SevenZipPath a -t7z -mhe=on -m0=lzma2 $passwordArgument '-xr!Temp' '-xr!Cache' '-xr!node_modules' '-xr!.gitkeep' $partial -- @relativeSources | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Archive creation failed (exit $LASTEXITCODE). Close applications and retry." }
        & $SevenZipPath t $passwordArgument $partial | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Archive verification failed (exit $LASTEXITCODE)." }
        Move-Item -LiteralPath $partial -Destination $destination
    } finally { Pop-Location }
    if ($SyncDirectory) {
        if (-not (Test-Path -LiteralPath $SyncDirectory -PathType Container)) { throw 'Sync directory must already exist. Verified local backup is retained.' }
        $copy = Join-Path $SyncDirectory (Split-Path $destination -Leaf)
        if (Test-Path -LiteralPath $copy) { throw 'Sync target already exists; refusing overwrite.' }
        Copy-Item -LiteralPath $destination -Destination $copy
        if ((Get-FileHash -LiteralPath $copy).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw 'Sync copy hash mismatch. Local backup is retained.' }
    }
    Write-Output $destination
} finally {
    $plain = $null
    $passwordArgument = $null
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
}
