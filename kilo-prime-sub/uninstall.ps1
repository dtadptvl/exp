$ErrorActionPreference = 'Stop'

function Resolve-KiloConfigRoot {
    $text = (& kilo debug paths | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'kilo debug paths failed.' }
    $line = @($text -split "`r?`n") | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^\s*config\s+(.+?)\s*$') { throw 'Could not resolve Kilo config root.' }
    [System.IO.Path]::GetFullPath($Matches[1])
}

function Sha256([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $null
}

$root = Resolve-KiloConfigRoot
$manifestPath = Join-Path $root 'prime-sub-install.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host 'No Prime/Sub install manifest found; nothing removed.'
    exit 0
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

if ($manifest.schema -eq 1 -and $manifest.backup_dir) {
    foreach ($f in @($manifest.files)) {
        $current = Sha256 $f.path
        if ($current -and $current -eq $f.sha256) { Remove-Item -LiteralPath $f.path -Force }
        elseif ($current) { Write-Warning "Preserved modified owned file: $($f.path)" }
    }
    foreach ($f in @($manifest.files)) {
        $legacy = Join-Path $manifest.backup_dir ([IO.Path]::GetFileName($f.path))
        if ((Test-Path -LiteralPath $legacy -PathType Leaf) -and -not (Test-Path -LiteralPath $f.path -PathType Leaf)) {
            New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($f.path)) -Force | Out-Null
            Copy-Item -LiteralPath $legacy -Destination $f.path -Force
            Write-Host "Restored:  $($f.path)"
        }
    }
    Remove-Item -LiteralPath $manifestPath -Force
    Write-Host 'Legacy Prime/Sub installation removed/rolled back. Configuration files were untouched.'
    exit 0
}

foreach ($f in @($manifest.files)) {
    $current = Sha256 $f.path
    if (-not $current) { continue }

    if ($current -ne $f.sha256) {
        Write-Warning "Preserved modified owned file: $($f.path)"
        continue
    }

    if ($f.backup -and (Test-Path -LiteralPath $f.backup -PathType Leaf)) {
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($f.path)) -Force | Out-Null
        Copy-Item -LiteralPath $f.backup -Destination $f.path -Force
        Write-Host "Restored:  $($f.path)"
    } elseif ($f.previous_sha256) {
        Write-Host "Preserved pre-existing identical file: $($f.path)"
    } else {
        Remove-Item -LiteralPath $f.path -Force
        Write-Host "Removed:   $($f.path)"
    }
}

Remove-Item -LiteralPath $manifestPath -Force
Write-Host 'Prime/Sub owned installation removed/rolled back. User-modified files were preserved. Configuration files were untouched.'
