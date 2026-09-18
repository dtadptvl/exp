param(
    [string]$Server = "home@minipc",
    [string]$Config = (Join-Path $PSScriptRoot "rclone.conf")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install/enable Windows OpenSSH Client."
    }
}

function Check-ExitCode {
    param([string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed (exit code $LASTEXITCODE)."
    }
}

try {
    Require-Command "ssh"
    Require-Command "scp"

    $Config = [System.IO.Path]::GetFullPath($Config)
    $RemoteScriptLocal = Join-Path $PSScriptRoot "home-server-migrate.sh"

    if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) {
        throw "Missing rclone.conf: $Config"
    }
    if (-not (Test-Path -LiteralPath $RemoteScriptLocal -PathType Leaf)) {
        throw "Missing companion script: $RemoteScriptLocal"
    }

    Write-Host "Connecting to $Server..." -ForegroundColor Cyan
    $RemoteOs = (& ssh $Server "uname -s").Trim()
    Check-ExitCode "SSH connectivity check"
    if ($RemoteOs -ne "Linux") {
        throw "Remote host is '$RemoteOs'. This launcher currently supports Linux home servers only."
    }

    $RemoteHome = (& ssh $Server 'printf %s "$HOME"').Trim()
    Check-ExitCode "Remote HOME lookup"
    if ($RemoteHome -notmatch '^/[A-Za-z0-9._@+/-]+$') {
        throw "Unexpected remote HOME path: $RemoteHome"
    }

    $RemoteDir = "$RemoteHome/.local/share/onedrive-gdrive-migration"
    $RemoteScript = "$RemoteDir/home-server-migrate.sh"
    $RemoteConfig = "$RemoteDir/rclone.conf"

    & ssh $Server "mkdir -p '$RemoteDir' && chmod 700 '$RemoteDir'"
    Check-ExitCode "Remote directory setup"

    Write-Host "Uploading migration script and rclone.conf..." -ForegroundColor Cyan
    & scp -q $RemoteScriptLocal "${Server}:$RemoteScript"
    Check-ExitCode "Script upload"
    & scp -q $Config "${Server}:$RemoteConfig"
    Check-ExitCode "rclone.conf upload"

    & ssh $Server "chmod 700 '$RemoteScript' && chmod 600 '$RemoteConfig'"
    Check-ExitCode "Remote permission setup"

    Write-Host ""
    Write-Host "Running check/resume on $Server..." -ForegroundColor Cyan
    Write-Host "Source:      onedrive-src:" -ForegroundColor DarkGray
    Write-Host "Destination: gdrive-dst:OneDrive Migration" -ForegroundColor DarkGray
    Write-Host ""

    & ssh $Server "'$RemoteScript'"
    Check-ExitCode "Remote migration"

    Write-Host ""
    Write-Host "SUCCESS" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
