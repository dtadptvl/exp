param([switch]$Uninstall, [switch]$UpgradeOwned)
$ErrorActionPreference = 'Stop'
function Hash($path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) }
    finally { $sha.Dispose() }
}
$paths = (& kilo debug paths | Out-String)
if ($LASTEXITCODE -ne 0 -or $paths -notmatch '(?m)^config\s+(.+?)\s*$') { throw 'Install Kilo CLI first; kilo debug paths must report config.' }
$dir = Join-Path ([IO.Path]::GetFullPath($Matches[1])) 'agents'
$backup = Join-Path $dir '.prime-sub-original'
$names = @('prime.md', 'sub.md')
if ($Uninstall) {
    foreach ($name in $names) {
        $target = Join-Path $dir $name
        $source = Join-Path $PSScriptRoot "agents\$name"
        $original = Join-Path $backup $name
        if (Test-Path $target) {
            if ((Hash $target) -ne (Hash $source)) { throw "Refusing to overwrite edited $target; restore manually." }
            Remove-Item $target
        }
        if (Test-Path $original) { Move-Item $original $target }
        $previous = Join-Path $backup "previous-$name"
        if (Test-Path $previous) { Remove-Item $previous }
    }
    Write-Host 'Owned agents removed; original agents restored. No config/project files touched.'
    exit 0
}
New-Item -ItemType Directory -Path $dir -Force | Out-Null
foreach ($name in $names) {
    $source = Join-Path $PSScriptRoot "agents\$name"
    $target = Join-Path $dir $name
    if (-not (Test-Path $source)) { throw "Missing $source" }
    if (Test-Path $target) {
        if ((Hash $source) -eq (Hash $target)) { continue }
        $original = Join-Path $backup $name
        if (Test-Path $original) {
            if (-not $UpgradeOwned) { throw "Refusing overwrite of modified $target. If this is your previously installed agent, rerun with -UpgradeOwned." }
            $previous = Join-Path $backup "previous-$name"
            if (Test-Path $previous) { throw "Refusing to overwrite rollback snapshot $previous; reconcile manually." }
            Copy-Item $target $previous
            Remove-Item $target
        } else {
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Move-Item $target $original
        }
    }
    Copy-Item $source $target
}
$prime = & kilo debug agent prime | ConvertFrom-Json
$sub = & kilo debug agent sub | ConvertFrom-Json
$config = & kilo debug config | ConvertFrom-Json
if ($prime.mode -ne 'primary' -or $sub.mode -ne 'subagent' -or
    $sub.model.providerID -ne '9router' -or $sub.model.modelID -ne 'sub') {
    throw 'Effective agents do not match. Check project overrides; see AI_CONFIG_MERGE_GUIDE.md.'
}
if ($config.default_agent -ne 'prime' -or $config.subagent_depth -ne 1) {
    Write-Warning 'Human config action needed: default_agent=prime; subagent_depth=1. See AI_CONFIG_MERGE_GUIDE.md.'
}
Write-Host "Installed agent Markdown in $dir. No kilo.json/jsonc or built-ins changed."
