$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$node = Join-Path $root 'Apps\Node\node.exe'
if (-not (Test-Path -LiteralPath $node)) { throw 'Node auf der SSD fehlt.' }
& $node (Join-Path $PSScriptRoot 'Repo-Actions.cjs') push
exit $LASTEXITCODE
