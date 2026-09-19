param(
    [string]$Config = (Join-Path $PSScriptRoot "rclone.conf"),
    [string]$GoogleClientId = "",
    [string]$GoogleClientSecret = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$DownloadUrl = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$WorkDir = Join-Path $env:TEMP "onedrive-gdrive-google-oauth-update"
$ZipPath = Join-Path $WorkDir "rclone.zip"
$ExtractPath = Join-Path $WorkDir "rclone"

function Invoke-Rclone {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $script:RcloneExe --config $Config @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "rclone failed (exit code $LASTEXITCODE)."
    }
}

try {
    $Config = [System.IO.Path]::GetFullPath($Config)
    if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Missing rclone.conf: $Config"
    }

    if ([string]::IsNullOrWhiteSpace($GoogleClientId)) {
        $GoogleClientId = Read-Host "Paste your Google OAuth Desktop client ID"
    }
    if ([string]::IsNullOrWhiteSpace($GoogleClientSecret)) {
        $GoogleClientSecret = Read-Host "Paste your Google OAuth Desktop client secret"
    }
    if ([string]::IsNullOrWhiteSpace($GoogleClientId) -or [string]::IsNullOrWhiteSpace($GoogleClientSecret)) {
        throw "Google client ID and client secret are required."
    }

    Write-Host "Preparing rclone..." -ForegroundColor Cyan
    if (Test-Path $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkDir | Out-Null

    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractPath -Force

    $script:RcloneExe = Get-ChildItem -Path $ExtractPath -Filter "rclone.exe" -Recurse -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $script:RcloneExe) {
        throw "Downloaded archive did not contain rclone.exe."
    }

    $remotes = & $script:RcloneExe --config $Config listremotes
    if ($LASTEXITCODE -ne 0 -or $remotes -notcontains "gdrive-dst:") {
        throw "rclone.conf does not contain gdrive-dst:."
    }

    Write-Host "Updating gdrive-dst to your private Google OAuth client..." -ForegroundColor Cyan
    Invoke-Rclone config update gdrive-dst `
        client_id=$GoogleClientId `
        client_secret=$GoogleClientSecret

    Write-Host "Re-authenticate Google Drive in the browser window." -ForegroundColor Cyan
    Invoke-Rclone config reconnect "gdrive-dst:"

    Write-Host "Validating Google Drive..." -ForegroundColor Cyan
    Invoke-Rclone lsf "gdrive-dst:" --max-depth 1 --tpslimit 8 --tpslimit-burst 1 | Out-Null

    Write-Host "`nSUCCESS" -ForegroundColor Green
    Write-Host "gdrive-dst now uses your own Google OAuth client."
    Write-Host "You can rerun home-server-migrate.ps1 and continue OneDrive Migration 2."
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if (Test-Path $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
