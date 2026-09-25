param([switch]$Force)
$ErrorActionPreference = 'Stop'

function Resolve-KiloConfigRoot {
    $text = (& kilo debug paths | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "kilo debug paths failed with exit code $LASTEXITCODE." }
    $line = @($text -split "`r?`n") | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^\s*config\s+(.+?)\s*$') { throw 'Could not resolve Kilo global config directory.' }
    return [System.IO.Path]::GetFullPath($Matches[1])
}

if (-not (Get-Command kilo -ErrorAction SilentlyContinue)) { throw 'Kilo is required to resolve its global config directory.' }
$root = Resolve-KiloConfigRoot
$receiptPath = Join-Path $root 'prime-sub-install.json'
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { throw 'No prime-sub-install.json receipt was found; refusing to guess what to restore.' }

$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$agentDir = Join-Path $root 'agents'
$prime = Join-Path $agentDir 'prime.md'
$sub = Join-Path $agentDir 'Sub.md'

if (-not $Force) {
    if (Test-Path -LiteralPath $prime -PathType Leaf) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $prime).Hash
        if ($hash -ne $receipt.prime_sha256) { throw 'prime.md changed after installation. Use uninstall.ps1 -Force only if you intentionally want to replace it.' }
    }
    if (Test-Path -LiteralPath $sub -PathType Leaf) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sub).Hash
        if ($hash -ne $receipt.sub_sha256) { throw 'Sub.md changed after installation. Use uninstall.ps1 -Force only if you intentionally want to replace it.' }
    }
}

$backupDir = $receipt.backup_dir
if ($receipt.had_prime -eq $true) {
    $source = Join-Path $backupDir 'prime.md'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Backup missing: $source" }
    Copy-Item -LiteralPath $source -Destination $prime -Force
} elseif (Test-Path -LiteralPath $prime) {
    Remove-Item -LiteralPath $prime -Force
}

if ($receipt.had_sub -eq $true) {
    $source = Join-Path $backupDir 'Sub.md'
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Backup missing: $source" }
    Copy-Item -LiteralPath $source -Destination $sub -Force
} elseif (Test-Path -LiteralPath $sub) {
    Remove-Item -LiteralPath $sub -Force
}

Remove-Item -LiteralPath $receiptPath -Force
Write-Host 'PASS: previous global Prime/Sub agent files were restored, or package-installed files were removed.' -ForegroundColor Green
Write-Host 'No Kilo JSON/JSONC configuration was changed.'
