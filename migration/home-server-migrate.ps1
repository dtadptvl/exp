param(
    [string]$Server = "home@minipc",
    [string]$Config = (Join-Path $PSScriptRoot "rclone.conf"),
    [string]$DestinationFolder = "OneDrive Migration 2"
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

$FailureMessage = $null
$RemoteRuntime = $null
$RemoteConfig = $null
$LocalReturnedConfig = $null

try {
    Require-Command "ssh"
    Require-Command "scp"

    if ($DestinationFolder -notmatch '^[A-Za-z0-9 ._-]+$') {
        throw "DestinationFolder may contain only letters, numbers, spaces, dot, underscore, and hyphen."
    }

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

    & ssh $Server "mkdir -p '$RemoteDir' && chmod 700 '$RemoteDir'"
    Check-ExitCode "Remote directory setup"

    $RemoteRuntime = (& ssh $Server "mktemp -d /tmp/onedrive-gdrive-migration.XXXXXX").Trim()
    Check-ExitCode "Remote temporary directory setup"
    if ($RemoteRuntime -notmatch '^/tmp/onedrive-gdrive-migration\.[A-Za-z0-9]+$') {
        throw "Unexpected remote temporary path: $RemoteRuntime"
    }

    $RemoteConfig = "$RemoteRuntime/rclone.conf"
    $LocalReturnedConfig = "$Config.remote-returned"

    Write-Host "Uploading migration script and temporary rclone.conf..." -ForegroundColor Cyan
    & scp -q $RemoteScriptLocal "${Server}:$RemoteScript"
    Check-ExitCode "Script upload"
    & scp -q $Config "${Server}:$RemoteConfig"
    Check-ExitCode "rclone.conf upload"

    & ssh $Server "chmod 700 '$RemoteScript' && chmod 600 '$RemoteConfig'"
    Check-ExitCode "Remote permission setup"

    Write-Host ""
    Write-Host "Starting fresh migration on $Server" -ForegroundColor Cyan
    Write-Host "Source:      onedrive-src:" -ForegroundColor DarkGray
    Write-Host "Destination: gdrive-dst:$DestinationFolder" -ForegroundColor DarkGray
    Write-Host "Press Ctrl+C at any time to cancel." -ForegroundColor Yellow
    Write-Host ""

    # Force a remote TTY so Ctrl+C is delivered to the foreground rclone process.
    & ssh -tt $Server "'$RemoteScript' '$RemoteConfig' '$DestinationFolder'"
    Check-ExitCode "Remote migration"
}
catch {
    $FailureMessage = $_.Exception.Message
}
finally {
    if ($RemoteConfig -and $LocalReturnedConfig) {
        try {
            & scp -q "${Server}:$RemoteConfig" $LocalReturnedConfig
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $LocalReturnedConfig -PathType Leaf)) {
                Move-Item -LiteralPath $LocalReturnedConfig -Destination $Config -Force
                Write-Host "Updated local rclone.conf with refreshed OAuth tokens." -ForegroundColor DarkGray
            }
            elseif (Test-Path -LiteralPath $LocalReturnedConfig) {
                Remove-Item -LiteralPath $LocalReturnedConfig -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Could not retrieve refreshed rclone.conf: $($_.Exception.Message)"
        }
    }

    if ($RemoteRuntime) {
        try {
            & ssh $Server "rm -rf '$RemoteRuntime'" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Could not remove temporary remote config directory: $RemoteRuntime"
            }
        }
        catch {
            Write-Warning "Could not remove temporary remote config directory: $RemoteRuntime"
        }
    }
}

if ($FailureMessage) {
    Write-Host ""
    Write-Host "STOPPED/FAILED: $FailureMessage" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "SUCCESS" -ForegroundColor Green
