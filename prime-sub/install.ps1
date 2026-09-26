param([switch]$Uninstall, [switch]$UpgradeOwned)
$ErrorActionPreference = 'Stop'
$paths = (& kilo debug paths | Out-String)
if ($LASTEXITCODE -ne 0 -or $paths -notmatch '(?m)^config\s+(.+?)\s*$') { throw 'Install Kilo CLI first; kilo debug paths must report config.' }
$dir = Join-Path ([IO.Path]::GetFullPath($Matches[1])) 'agents'
$backup = Join-Path $dir '.prime-sub-original'
$names = @('prime.md', 'sub.md', 'state.py')
function Source($name) {
    if ($name -eq 'state.py') { return Join-Path $PSScriptRoot 'state.py' }
    return Join-Path $PSScriptRoot "agents\$name"
}
function InstalledText($name) {
    $text = [IO.File]::ReadAllText((Source $name), [Text.Encoding]::UTF8)
    if ($name -eq 'prime.md') {
        # JSON-style escaping is unnecessary inside Markdown code; Python receives a quoted path.
        $path = (Join-Path $dir 'state.py').Replace('\', '/')
        $text = $text.Replace('__PRIME_SUB_STATE_PATH__', $path)
    }
    return $text
}
function MatchesSource($name, $path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    return [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Replace("`r`n", "`n") -eq (InstalledText $name).Replace("`r`n", "`n")
}
if ($Uninstall) {
    foreach ($name in $names) {
        $target = Join-Path $dir $name
        $original = Join-Path $backup $name
        if (Test-Path $target) {
            if (-not (MatchesSource $name $target)) { throw "Refusing to overwrite edited $target; restore manually." }
            Remove-Item $target
        }
        if (Test-Path $original) { Move-Item $original $target }
        # Keep upgrade snapshots for manual rollback; never erase prior revisions.
    }
    Write-Host 'Owned agents removed; original agents restored. No config/project files touched.'
    exit 0
}
New-Item -ItemType Directory -Path $dir -Force | Out-Null
foreach ($name in $names) {
    $source = Source $name
    $target = Join-Path $dir $name
    if (-not (Test-Path $source)) { throw "Missing $source" }
    if (Test-Path $target) {
        if (MatchesSource $name $target) { continue }
        $original = Join-Path $backup $name
        if (Test-Path $original) {
            if (-not $UpgradeOwned) { throw "Refusing overwrite of modified $target. If this is your previously installed agent, rerun with -UpgradeOwned." }
            $previous = Join-Path $backup ("previous-" + [guid]::NewGuid().ToString('N') + "-$name")
            Copy-Item $target $previous
            Remove-Item $target
        } else {
            New-Item -ItemType Directory -Path $backup -Force | Out-Null
            Move-Item $target $original
        }
    }
    [IO.File]::WriteAllText($target, (InstalledText $name), (New-Object Text.UTF8Encoding($false)))
}
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { throw 'Python is required to run the installed state.py; install it and rerun setup.' }
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
Write-Host "Installed global agents and state.py in $dir. No kilo.json/jsonc or built-ins changed."
