#requires -Version 5.1
[CmdletBinding()]
param([string]$ShellPath = (Get-Process -Id $PID).Path, [switch]$KeepFailedFixture)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$testBase = Join-Path $root 'Data\Cache\OnlineTests'
$testRoot = Join-Path $testBase ([guid]::NewGuid().ToString('N'))
$fixture = Join-Path $testRoot 'portable & bang!'
. (Join-Path $PSScriptRoot 'Workstation-Paths.ps1')
Assert-WorkstationDirectory $root $testRoot
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$succeeded = $false
try {
    Copy-Item -LiteralPath (Join-Path $root 'Start'),$PSScriptRoot -Destination $fixture -Recurse
    @'
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Check-Exit([string]$Step) { if ($LASTEXITCODE -ne 0) { throw "$Step failed: $LASTEXITCODE" } }
& (Join-Path $PSScriptRoot 'Tools\Setup-Workstation.ps1')
$git = Join-Path $PSScriptRoot 'Apps\Git\cmd\git.exe'
$node = Join-Path $PSScriptRoot 'Apps\Node\node.exe'
$sevenZip = Join-Path $PSScriptRoot 'Apps\7Zip\7za.exe'
$before = @($git,$node,$sevenZip | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
# A second invocation must preserve existing installations.
& (Join-Path $PSScriptRoot 'Tools\Setup-Workstation.ps1')
$after = @($git,$node,$sevenZip | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
if (($before -join ',') -ne ($after -join ',')) { throw 'Setup overwrote existing tools.' }
& $git --version; Check-Exit 'Git version'
& $node --version; Check-Exit 'Node version'
& (Join-Path $PSScriptRoot 'Apps\Node\npm.cmd') --version; Check-Exit 'npm version'
$source = Join-Path $PSScriptRoot 'GitRepos\synthetic-source'
$clone = Join-Path $PSScriptRoot 'GitRepos\synthetic-clone'
& $git init -b main $source; Check-Exit 'Git init'
'synthetic repository content' | Set-Content -LiteralPath (Join-Path $source 'marker.txt') -Encoding ASCII
& $git -C $source add marker.txt; Check-Exit 'Git add'
& $git -C $source -c user.name=TemplateTest -c user.email=template-test@example.invalid -c commit.gpgsign=false commit -m 'Synthetic setup validation'; Check-Exit 'Git commit'
& $git clone --no-local $source $clone; Check-Exit 'Git clone and helpers'
if ((Get-Content -LiteralPath (Join-Path $clone 'marker.txt')) -ne 'synthetic repository content') { throw 'Git clone content differs.' }
& (Join-Path $PSScriptRoot 'Apps\Git\usr\bin\bash.exe') --noprofile --norc -c 'test -x /usr/bin/bash && test ! -d /etc/post-install'
Check-Exit 'Git Bash initialization'
& $node -e "const fs = require('node:fs'); fs.writeFileSync(process.env.HOME + '/node-marker.txt', 'synthetic');"
Check-Exit 'Node file write'
& (Join-Path $PSScriptRoot 'Tools\Test-Template.ps1') -SevenZipPath $sevenZip -RequireBackupTests
Write-Host 'PASS: real verified downloads, initialized Git, commit/clone, Node/npm, repeat setup and backup suite.'
'@ | Set-Content -LiteralPath (Join-Path $fixture 'online-probe.ps1') -Encoding ASCII
    @'
@echo off
setlocal DisableDelayedExpansion
call "%~dp0Start\Portable-Env.cmd"
if errorlevel 1 exit /b 1
"%TEMPLATE_TEST_SHELL%" -NoProfile -File "%~dp0online-probe.ps1"
exit /b %errorlevel%
'@ | Set-Content -LiteralPath (Join-Path $fixture 'online-probe.cmd') -Encoding ASCII
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $env:ComSpec
    $info.Arguments = '/d /v:off /c ""' + (Join-Path $fixture 'online-probe.cmd') + '""'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables.Remove('PORTABLE_ENV_ROOT')
    $info.EnvironmentVariables['TEMPLATE_TEST_SHELL'] = (Resolve-Path -LiteralPath $ShellPath).ProviderPath
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-Host $stdout.GetAwaiter().GetResult()
        Write-Host $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Online setup validation failed: $($process.ExitCode)" }
        $succeeded = $true
    } finally { $process.Dispose() }
} finally {
    $allowed = [IO.Path]::GetFullPath($testBase).TrimEnd('\') + '\'
    if (-not ([IO.Path]::GetFullPath($testRoot)).StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe online test cleanup path.' }
    if ($KeepFailedFixture -and -not $succeeded) { Write-Warning "Failed fixture retained for local inspection: $fixture" }
    elseif (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
