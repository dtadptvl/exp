$ErrorActionPreference = 'Stop'

function Resolve-KiloConfigRoot {
    $text = (& kilo debug paths | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'kilo debug paths failed.' }
    $line = @($text -split "`r?`n") | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^\s*config\s+(.+?)\s*$') { throw 'Could not resolve Kilo config root.' }
    [System.IO.Path]::GetFullPath($Matches[1])
}
function Sha256([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() } }

$root = Resolve-KiloConfigRoot
$manifestPath = Join-Path $root 'prime-sub-install.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Write-Host 'No Prime/Sub install manifest found; nothing removed.'; exit 0 }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

foreach ($f in @($manifest.files)) {
    if (-not (Test-Path -LiteralPath $f.path -PathType Leaf)) { continue }
    $current = Sha256 $f.path
    if ($current -eq $f.sha256) { Remove-Item -LiteralPath $f.path -Force }
    else { Write-Warning "Preserved modified owned file: $($f.path)" }
}

if ($manifest.backup_dir -and (Test-Path -LiteralPath $manifest.backup_dir -PathType Container)) {
    $map = @{
        'prime.md' = Join-Path $root 'agents\prime.md'
        'sub.md' = Join-Path $root 'agents\sub.md'
        'prime-sub-watchdog.js' = Join-Path $root 'plugin\prime-sub-watchdog.js'
    }
    foreach ($name in $map.Keys) {
        $source = Join-Path $manifest.backup_dir $name
        $target = $map[$name]
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and -not (Test-Path -LiteralPath $target -PathType Leaf)) {
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
}
Remove-Item -LiteralPath $manifestPath -Force
Write-Host 'Prime/Sub owned installation removed. User-modified files were preserved. Configuration files were untouched.'
