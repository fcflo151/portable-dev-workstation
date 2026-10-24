#requires -Version 5.1
[CmdletBinding()]
param([string]$SevenZipPath, [switch]$RequireBackupTests)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Rejected([scriptblock]$Action, [string]$MessagePattern) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    Assert ($null -ne $failure) "Expected rejection: $MessagePattern"
    Assert ($failure.Exception.Message -match $MessagePattern) "Unexpected failure: $failure"
}
function Invoke-TestCmd([string]$Path, [string]$InputText) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /v:off /c ""' + $Path + '""'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.RedirectStandardInput = $true
    # Never send a UTF-8 BOM before the synthetic cmd.exe "exit" command.
    $info.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    # Fixtures must also work when tests start inside the real portable terminal.
    $info.EnvironmentVariables.Remove('PORTABLE_ENV_ROOT')
    $info.EnvironmentVariables['GH_TOKEN'] = 'synthetic-host-token'
    $info.EnvironmentVariables['BASH_ENV'] = 'synthetic-host-script'
    $info.EnvironmentVariables['GIT_CONFIG_COUNT'] = '1'
    $info.EnvironmentVariables['GIT_CONFIG_KEY_0'] = 'credential.helper'
    $info.EnvironmentVariables['GIT_CONFIG_VALUE_0'] = 'synthetic-host-helper'
    $info.EnvironmentVariables['TEMPLATE_TEST_SHELL'] = (Get-Process -Id $PID).Path
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($InputText) { $process.StandardInput.WriteLine($InputText) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Test terminal timed out.' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        Assert ($process.ExitCode -eq 0) "Terminal failed: $errorOutput"
        Assert ([string]::IsNullOrWhiteSpace($errorOutput)) "Terminal wrote errors: $errorOutput"
        return $output
    } finally { $process.Dispose() }
}
foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    Assert ($errors.Count -eq 0) "PowerShell syntax error in $($script.Name): $errors"
}
$testBase = Join-Path $root 'Data\Cache\Tests'
$testRoot = Join-Path $testBase ([guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testRoot 'drive with spaces & bang!'
$originalHome = $env:HOME
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $root 'Start') -Destination $fixture -Recurse
    Copy-Item -LiteralPath $PSScriptRoot -Destination $fixture -Recurse
    @'
$ErrorActionPreference = 'Stop'
$hash = Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256
if ($hash.Hash.Length -ne 64) { throw 'Hash command failed inside portable terminal.' }
Get-Command Invoke-WebRequest -ErrorAction Stop | Out-Null
'@ | Set-Content -LiteralPath (Join-Path $fixture 'check-shell.ps1') -Encoding ASCII
    $probe = Join-Path $fixture 'probe.cmd'
    @'
@echo off
setlocal DisableDelayedExpansion
call "%~dp0Start\Portable-Env.cmd"
if errorlevel 1 exit /b 1
if defined GH_TOKEN exit /b 2
if defined BASH_ENV exit /b 3
if defined GIT_CONFIG_COUNT exit /b 4
call "%~dp0Start\Portable-Env.cmd"
if errorlevel 1 exit /b 1
"%TEMPLATE_TEST_SHELL%" -NoProfile -File "%~dp0check-shell.ps1"
if errorlevel 1 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File "%~dp0check-shell.ps1"
if errorlevel 1 exit /b 1
set HOME
set TEMP
set PATH
'@ | Set-Content -LiteralPath $probe -Encoding ASCII
    $output = Invoke-TestCmd $probe
    Assert ($output.Contains("HOME=$fixture\Data\PortableHome")) 'HOME is not relative to the fixture.'
    Assert ($output.Contains("TEMP=$fixture\Data\PortableHome\Temp")) 'TEMP is not portable.'
    Assert (([regex]::Matches($output, [regex]::Escape("$fixture\Apps\Git\cmd"))).Count -eq 1) 'Repeated setup duplicated PATH.'
    Assert ($env:HOME -eq $originalHome) 'Parent environment was modified.'
    $launcherOutput = Invoke-TestCmd (Join-Path $fixture 'Start\Start-Workstation.bat') 'exit'
    Assert ($launcherOutput.Contains('Portable Workstation: "' + $fixture + '"')) 'Launcher did not print the workstation path safely.'
    & (Join-Path $fixture 'Tools\Setup-Workstation.ps1') -WhatIf
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'Apps\Git'))) 'WhatIf installed tools.'
    @'
param([string]$Mode)
$ErrorActionPreference = 'Stop'
function Invoke-RestMethod {
    $digest = if ($Mode -eq 'missing') { $null } else { 'sha256:' + ('0' * 64) }
    [pscustomobject]@{ assets = @(
        [pscustomobject]@{ name = '7zr.exe'; digest = $digest; browser_download_url = 'https://invalid.example/7zr.exe' },
        [pscustomobject]@{ name = '7z9999-extra.7z'; digest = $digest; browser_download_url = 'https://invalid.example/extra.7z' }
    ) }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec, [switch]$UseBasicParsing)
    if ($Mode -eq 'missing') { throw 'An unverified download was attempted.' }
    [IO.File]::WriteAllText($OutFile, 'synthetic invalid download')
}
& (Join-Path $PSScriptRoot 'Tools\Setup-Workstation.ps1') -Tools SevenZip
'@ | Set-Content -LiteralPath (Join-Path $fixture 'mock-setup.ps1') -Encoding ASCII
    Assert-Rejected { & (Join-Path $fixture 'mock-setup.ps1') -Mode missing } 'no SHA-256 digest'
    Assert-Rejected { & (Join-Path $fixture 'mock-setup.ps1') -Mode mismatch } 'SHA-256 mismatch'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'Apps\7Zip'))) 'Setup published an unverified tool.'
    Assert (-not (Get-ChildItem -LiteralPath (Join-Path $fixture 'Data\Cache\Setup') -Force)) 'Failed setup left staging files.'

    if (-not $SevenZipPath) {
        foreach ($relative in @('Apps\7Zip\7za.exe', 'Apps\7Zip\7z.exe')) {
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $SevenZipPath = $candidate; break }
        }
        if (-not $SevenZipPath) {
            $command = Get-Command 7z.exe -ErrorAction SilentlyContinue
            if ($command) { $SevenZipPath = $command.Source }
            elseif (Test-Path -LiteralPath 'C:\Program Files\7-Zip\7z.exe') { $SevenZipPath = 'C:\Program Files\7-Zip\7z.exe' }
        }
    }
    if ($RequireBackupTests -and -not $SevenZipPath) { throw 'Backup integration checks are required. Supply -SevenZipPath or install 7-Zip.' }
    if ($SevenZipPath) {
        $SevenZipPath = (Resolve-Path -LiteralPath $SevenZipPath).ProviderPath
        $source = Join-Path $fixture 'Data\PortableHome'
        'synthetic backup fixture' | Set-Content -LiteralPath (Join-Path $source 'restore-marker.txt') -Encoding ASCII
        'must be excluded' | Set-Content -LiteralPath (Join-Path $source 'Temp\excluded.txt')
        foreach ($excluded in @('Cache','node_modules')) {
            New-Item -ItemType Directory -Path (Join-Path $source $excluded) | Out-Null
            'must be excluded' | Set-Content -LiteralPath (Join-Path $source "$excluded\excluded.txt")
        }
        'folder marker' | Set-Content -LiteralPath (Join-Path $source '.gitkeep')
        $password = ConvertTo-SecureString ('fixture ' + [guid]::NewGuid().ToString('N') + ' & !\') -AsPlainText -Force
        $backupScript = Join-Path $fixture 'Tools\Backup-Workstation.ps1'
        $emptyPassword = New-Object Security.SecureString
        Assert-Rejected { & $backupScript -SevenZipPath $SevenZipPath -Password $emptyPassword } 'Empty passwords'
        foreach ($invalidPassword in @('synthetic"quote', "synthetic`nline", "synthetic`0nul")) {
            $invalidSecret = ConvertTo-SecureString $invalidPassword -AsPlainText -Force
            Assert-Rejected { & $backupScript -SevenZipPath $SevenZipPath -Password $invalidSecret } 'contain no quotes or line breaks'
        }
        # Similar names are legitimate sources; only the actual backup tree is forbidden.
        New-Item -ItemType Directory -Path (Join-Path $fixture 'Data\Backups-notes') | Out-Null
        & $backupScript -IncludePaths 'Data\Backups-notes' -SevenZipPath $SevenZipPath -WhatIf
        Assert (-not (Get-ChildItem -LiteralPath (Join-Path $fixture 'Data\Backups') -Force)) 'Backup WhatIf wrote an archive.'
        $sync = Join-Path $testRoot 'sync'
        New-Item -ItemType Directory -Path $sync | Out-Null
        $archive = & $backupScript -SevenZipPath $SevenZipPath -Password $password -SyncDirectory $sync
        Assert (Test-Path -LiteralPath $archive) 'Verified archive was not published.'
        $syncCopy = Join-Path $sync (Split-Path $archive -Leaf)
        Assert (Test-Path -LiteralPath $syncCopy -PathType Leaf) 'Sync copy is missing.'
        Assert ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $syncCopy -Algorithm SHA256).Hash) 'Sync copy differs from the verified archive.'
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        try {
            $argument = '-p' + [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
            $restore = Join-Path $testRoot 'restore'
            & $SevenZipPath x $archive $argument "-o$restore" -y | Out-Null
            Assert ($LASTEXITCODE -eq 0) 'Restore failed.'
            Assert ((Get-Content -LiteralPath (Join-Path $restore 'Data\PortableHome\restore-marker.txt')) -eq 'synthetic backup fixture') 'Restored content differs.'
            Assert (-not (Test-Path -LiteralPath (Join-Path $restore 'Data\PortableHome\Temp\excluded.txt'))) 'Backup includes temporary data.'
            foreach ($excluded in @('Cache','node_modules','.gitkeep')) {
                Assert (-not (Test-Path -LiteralPath (Join-Path $restore "Data\PortableHome\$excluded"))) "Backup includes excluded content: $excluded"
            }
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { & $SevenZipPath l $archive '-pdeliberately-wrong-password' 2>$null | Out-Null }
            finally { $ErrorActionPreference = $savedPreference }
            Assert ($LASTEXITCODE -ne 0) 'Encrypted headers accepted an incorrect password.'
        } finally {
            $argument = $null
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
        foreach ($invalidSource in @('..', 'Data', 'Data\Backups', 'Data\Backups\nested')) {
            $rejected = $false
            try { & $backupScript -IncludePaths $invalidSource -SevenZipPath $SevenZipPath -WhatIf } catch { $rejected = $true }
            Assert $rejected "Backup accepted an unsafe source: $invalidSource"
        }
        # Simulate an archiver that leaves an incomplete output and exits with an error.
        @'
@echo off
for /l %%I in (1,1,9) do shift
> "%~1" echo synthetic-incomplete-archive
exit /b 2
'@ | Set-Content -LiteralPath (Join-Path $fixture 'fail-archiver.cmd') -Encoding ASCII
        $archiveCount = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'Data\Backups') -Filter '*.7z').Count
        $failurePassword = ConvertTo-SecureString 'synthetic-failure-test' -AsPlainText -Force
        Assert-Rejected { & $backupScript -SevenZipPath (Join-Path $fixture 'fail-archiver.cmd') -Password $failurePassword } 'Archive creation failed'
        Assert (-not (Get-ChildItem -LiteralPath (Join-Path $fixture 'Data\Backups') -Filter '*.partial')) 'Failed backup left an incomplete archive.'
        Assert (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'Data\Backups') -Filter '*.7z').Count -eq $archiveCount) 'Failed backup published an archive.'
        # Junctions require no elevation on NTFS. Never recurse through them in cleanup.
        $outside = Join-Path $testRoot 'outside-workstation'
        New-Item -ItemType Directory -Path $outside | Out-Null
        $junction = Join-Path $fixture 'Data\linked-source'
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            Assert-Rejected { & $backupScript -IncludePaths 'Data\linked-source' -SevenZipPath $SevenZipPath -WhatIf } 'Linked source'
        } finally { [IO.Directory]::Delete($junction) }
        $junction = Join-Path $source 'linked-child'
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            Assert-Rejected { & $backupScript -SevenZipPath $SevenZipPath -WhatIf } 'Remove linked files/directories'
        } finally { [IO.Directory]::Delete($junction) }
        $junction = Join-Path $fixture 'Apps'
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            Assert-Rejected { & (Join-Path $fixture 'Tools\Setup-Workstation.ps1') -Tools SevenZip -WhatIf } 'Linked workstation directory'
        } finally { [IO.Directory]::Delete($junction) }
        # The destination guard must reject a link even when all sources are safe.
        $backupDirectory = Join-Path $fixture 'Data\Backups'
        $savedBackups = Join-Path $fixture 'Data\saved-backups'
        Move-Item -LiteralPath $backupDirectory -Destination $savedBackups
        New-Item -ItemType Junction -Path $backupDirectory -Target $outside | Out-Null
        try {
            Assert-Rejected { & $backupScript -SevenZipPath $SevenZipPath -Password $password -WhatIf } 'Linked workstation directory'
            Assert (-not (Get-ChildItem -LiteralPath $outside -Force)) 'A guarded operation wrote outside the workstation.'
        } finally {
            [IO.Directory]::Delete($backupDirectory)
            Move-Item -LiteralPath $savedBackups -Destination $backupDirectory
        }
        Write-Host 'PASS: missing/mismatched download hashes, cleanup, invalid passwords and junction rejection.'
        Write-Host 'PASS: AES-encrypted backup, header protection, restore, exclusions, sync and traversal rejection.'
    } else { Write-Warning '7-Zip unavailable: backup integration checks skipped. Supply -SevenZipPath to run them.' }
    Write-Host 'PASS: syntax, special-character paths, session isolation, idempotent environment and setup WhatIf.'
} finally {
    $allowed = [IO.Path]::GetFullPath($testBase).TrimEnd('\') + '\'
    Assert (([IO.Path]::GetFullPath($testRoot)).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) 'Unsafe test cleanup path.'
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
