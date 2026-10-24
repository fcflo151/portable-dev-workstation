#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Workstation-Paths.ps1')
$fixture = Join-Path $root ('Data\Cache\RepositoryTests\' + [guid]::NewGuid().ToString('N'))
Assert-WorkstationDirectory $root $fixture
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$hooks = Join-Path $fixture 'empty-hooks'
New-Item -ItemType Directory -Path $hooks | Out-Null
$git = (Get-Command git.exe -ErrorAction Stop).Source
function Invoke-FixtureGit([string[]]$Arguments) {
    & $git -c "safe.directory=$fixture" -c "core.hooksPath=$hooks" -c user.name=TemplateTest -c user.email=template-test@users.noreply.github.com -c commit.gpgsign=false -C $fixture @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic fixture Git operation failed.' }
}
function Expect-Rejection([scriptblock]$Action, [string]$Pattern) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    if (-not $failure -or $failure.Exception.Message -notmatch $Pattern) { throw "Expected publication rejection: $Pattern" }
}
$checker = Join-Path $PSScriptRoot 'Test-Repository.ps1'
Copy-Item -LiteralPath (Join-Path $root '.gitignore') -Destination $fixture
$readme = Join-Path $fixture 'README.md'
[IO.File]::WriteAllText($readme, 'Synthetic public fixture')
Invoke-FixtureGit @('init','-q','-b','main')
Invoke-FixtureGit @('add','.gitignore','README.md')
& $checker -RepositoryRoot $fixture
# Never use a real credential: this only resembles a token for regex testing.
$syntheticToken = 'gh' + 'p_' + ('x' * 36)
[IO.File]::WriteAllText($readme, $syntheticToken)
Invoke-FixtureGit @('add','README.md')
[IO.File]::WriteAllText($readme, 'Synthetic public fixture')
Expect-Rejection { & $checker -RepositoryRoot $fixture } 'Possible credential'
# A cleaned working file and index must not hide an older committed credential.
Invoke-FixtureGit @('commit','-q','-m','Synthetic history fixture')
Invoke-FixtureGit @('add','README.md')
Invoke-FixtureGit @('commit','-q','-m','Remove synthetic token')
& $checker -RepositoryRoot $fixture
Expect-Rejection { & $checker -RepositoryRoot $fixture -IncludeHistory } 'Possible credential'
# Simulate a browser export staged before protective ignore rules were restored.
[IO.File]::WriteAllText((Join-Path $fixture '.gitignore'), '')
$export = Join-Path $fixture 'Export'
New-Item -ItemType Directory -Path $export | Out-Null
[IO.File]::WriteAllText((Join-Path $export 'Local State'), '{"synthetic":true}')
Invoke-FixtureGit @('add','Export/Local State')
Copy-Item -LiteralPath (Join-Path $root '.gitignore') -Destination $fixture -Force
Expect-Rejection { & $checker -RepositoryRoot $fixture } 'Private/runtime file'
Write-Host 'PASS: clean publication accepted; staged synthetic token, historical synthetic token and staged browser export rejected.'
Write-Host "Small synthetic fixture retained under ignored Data\Cache\RepositoryTests: $fixture"
