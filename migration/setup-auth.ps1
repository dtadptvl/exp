param(
    [string]$OutputConfig = (Join-Path $PSScriptRoot "rclone.conf")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceRemote = "onedrive-src"
$DestinationRemote = "gdrive-dst"
$DownloadUrl = "https://downloads.rclone.org/rclone-current-windows-amd64.zip"
$WorkDir = Join-Path $env:TEMP "onedrive-gdrive-rclone-setup"
$ZipPath = Join-Path $WorkDir "rclone.zip"
$ExtractPath = Join-Path $WorkDir "rclone"

function Invoke-Rclone {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $script:RcloneExe --config $OutputConfig @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "rclone failed (exit code $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

try {
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

    $OutputConfig = [System.IO.Path]::GetFullPath($OutputConfig)
    $OutputDir = Split-Path -Parent $OutputConfig
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    if (Test-Path $OutputConfig) {
        Remove-Item -LiteralPath $OutputConfig -Force
    }

    Write-Host "`n1/2 Sign in to Microsoft OneDrive in the browser window." -ForegroundColor Cyan
    Write-Host "Only read permissions are requested for the source." -ForegroundColor DarkGray
    Invoke-Rclone config create $SourceRemote onedrive `
        access_scopes="Files.Read Files.Read.All Sites.Read.All offline_access"

    Write-Host "`n2/2 Sign in to the personal Google Drive account in the browser window." -ForegroundColor Cyan
    Invoke-Rclone config create $DestinationRemote drive scope=drive

    Write-Host "`nValidating OneDrive..." -ForegroundColor Cyan
    Invoke-Rclone lsf "$SourceRemote`:" --max-depth 1 | Out-Null

    Write-Host "Validating Google Drive..." -ForegroundColor Cyan
    Invoke-Rclone lsf "$DestinationRemote`:" --max-depth 1 | Out-Null

    if (-not (Test-Path $OutputConfig)) {
        throw "rclone.conf was not created."
    }

    Write-Host "`nSUCCESS" -ForegroundColor Green
    Write-Host "Config created at: $OutputConfig"
    Write-Host "Keep this file private. Upload it only to the Colab notebook when asked."
}
catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "No migration was started and no source data was modified." -ForegroundColor Yellow
    exit 1
}
finally {
    if (Test-Path $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
