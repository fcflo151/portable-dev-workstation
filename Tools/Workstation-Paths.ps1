#requires -Version 5.1
# Shared guard for script-managed directories. Explicit external sync targets are separate.
function Assert-WorkstationDirectory([string]$Root, [string]$Path) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $current = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $current.Equals($base, [StringComparison]::OrdinalIgnoreCase) -and
        -not $current.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Managed directory escapes the workstation.'
    }
    while ($current.Length -ge $base.Length) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked workstation directory is not supported: $current"
            }
            if (-not $item.PSIsContainer) { throw "Expected a directory: $current" }
        }
        if ($current.Equals($base, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = Split-Path -Parent $current
    }
}
