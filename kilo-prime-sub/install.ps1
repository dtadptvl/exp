$ErrorActionPreference = 'Stop'

function Resolve-KiloConfigRoot {
    $text = (& kilo debug paths | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "kilo debug paths failed with exit code $LASTEXITCODE." }
    $line = @($text -split "`r?`n") | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^\s*config\s+(.+?)\s*$') { throw 'Could not resolve Kilo global config directory.' }
    return [System.IO.Path]::GetFullPath($Matches[1])
}

function Invoke-KiloJson([string[]]$Arguments, [string]$Label) {
    $text = (& kilo @Arguments | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
    try { return $text | ConvertFrom-Json } catch { throw "$Label did not return valid JSON." }
}

function Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Permission-Action($Rules, [string]$Permission, [string]$Pattern) {
    $action = 'ask'
    foreach ($rule in @($Rules)) {
        $permissionMatch = ($rule.permission -eq '*') -or ($rule.permission -eq $Permission)
        $patternMatch = $Pattern -like $rule.pattern
        if ($permissionMatch -and $patternMatch) { $action = $rule.action }
    }
    return $action
}

$kilo = Get-Command kilo -ErrorAction SilentlyContinue
if (-not $kilo) { throw 'Native Kilo is required in PATH. Install/configure Kilo, then rerun install.bat.' }

$root = Resolve-KiloConfigRoot
$agentDir = Join-Path $root 'agents'
$pluginDir = Join-Path $root 'plugin'
$ownedDir = Join-Path $root 'prime-sub'
$backupRoot = Join-Path $root 'prime-sub-backups'
$manifestPath = Join-Path $root 'prime-sub-install.json'

$files = @(
    @{ Source = Join-Path $PSScriptRoot 'agents\prime.md'; Target = Join-Path $agentDir 'prime.md'; Key = 'prime' },
    @{ Source = Join-Path $PSScriptRoot 'agents\sub.md'; Target = Join-Path $agentDir 'sub.md'; Key = 'sub' },
    @{ Source = Join-Path $PSScriptRoot 'plugin\prime-sub-watchdog.js'; Target = Join-Path $pluginDir 'prime-sub-watchdog.js'; Key = 'watchdog' },
    @{ Source = Join-Path $PSScriptRoot 'state\prime-state.ps1'; Target = Join-Path $ownedDir 'prime-state.ps1'; Key = 'state-helper' },
    @{ Source = Join-Path $PSScriptRoot 'state\state-template.json'; Target = Join-Path $ownedDir 'state-template.json'; Key = 'state-template' }
)
foreach ($f in $files) { if (-not (Test-Path -LiteralPath $f.Source -PathType Leaf)) { throw "Package incomplete: $($f.Source)" } }
New-Item -ItemType Directory -Path $agentDir -Force | Out-Null
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
New-Item -ItemType Directory -Path $ownedDir -Force | Out-Null

$previousManifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try { $previousManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json } catch { throw 'Existing Prime/Sub install manifest is invalid.' }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $backupRoot ("$stamp-" + (Get-Random -Minimum 1000 -Maximum 9999))
$records = New-Object System.Collections.ArrayList

foreach ($f in $files) {
    $sourceHash = Sha256 $f.Source
    $currentHash = Sha256 $f.Target
    $prior = $null
    if ($previousManifest) { $prior = @($previousManifest.files) | Where-Object { $_.path -eq $f.Target } | Select-Object -First 1 }

    $previousHash = $currentHash
    $backup = $null
    if ($prior -and $currentHash -eq $prior.sha256) {
        $previousHash = $prior.previous_sha256
        $backup = $prior.backup
    } elseif ($currentHash -and $currentHash -ne $sourceHash) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backup = Join-Path $backupDir ($f.Key + '-' + [IO.Path]::GetFileName($f.Target))
        Copy-Item -LiteralPath $f.Target -Destination $backup -Force
    }

    if ($currentHash -ne $sourceHash) { Copy-Item -LiteralPath $f.Source -Destination $f.Target -Force }
    [void]$records.Add([ordered]@{
        key = $f.Key
        path = $f.Target
        sha256 = $sourceHash
        previous_sha256 = $previousHash
        backup = $backup
    })
}

$manifest = [ordered]@{
    schema = 2
    installed_at = (Get-Date).ToUniversalTime().ToString('o')
    files = @($records)
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$config = Invoke-KiloJson -Arguments @('debug','config') -Label 'kilo debug config'
$prime = Invoke-KiloJson -Arguments @('debug','agent','prime') -Label 'kilo debug agent prime'
$sub = Invoke-KiloJson -Arguments @('debug','agent','sub') -Label 'kilo debug agent sub'
$errors = New-Object System.Collections.Generic.List[string]

if ($config.default_agent -ne 'prime') { $errors.Add("default_agent resolves to '$($config.default_agent)', expected 'prime'.") }
if ([int]$config.subagent_depth -ne 1) { $errors.Add("subagent_depth resolves to '$($config.subagent_depth)', expected 1.") }
if ($prime.mode -ne 'primary') { $errors.Add("Prime mode resolves to '$($prime.mode)', expected primary.") }
if ((Permission-Action $prime.permission 'task' 'sub') -ne 'allow') { $errors.Add('Prime cannot delegate to custom sub.') }
foreach ($other in @('general','explore')) { if ((Permission-Action $prime.permission 'task' $other) -ne 'deny') { $errors.Add("Prime can delegate to built-in '$other'; expected deny.") } }
if ($sub.mode -ne 'subagent') { $errors.Add("Sub mode resolves to '$($sub.mode)', expected subagent.") }
if ($sub.model.providerID -ne '9router' -or $sub.model.modelID -ne 'sub') { $errors.Add("Sub model resolves to '$($sub.model.providerID)/$($sub.model.modelID)', expected 9router/sub.") }
if ((Permission-Action $sub.permission 'task' '*') -ne 'deny') { $errors.Add('Sub Task permission is not denied.') }
if ((Permission-Action $sub.permission 'doom_loop' '*') -ne 'deny') { $errors.Add('Sub doom_loop permission is not denied.') }
if ($null -ne $sub.steps -or $null -ne $sub.maxSteps) { $errors.Add('Sub has a steps/maxSteps limit; remove it. Anti-stall must be lifecycle based.') }
if ((Permission-Action $sub.permission 'bash' 'git commit -m x') -ne 'deny') { $errors.Add('Sub can mutate Git with git commit.') }
if ((Permission-Action $sub.permission 'bash' 'git status --short') -ne 'allow') { $errors.Add('Sub cannot inspect git status.') }
if ($env:KILO_PURE -eq '1') { $errors.Add('KILO_PURE=1 disables external plugins, including the Prime/Sub watchdog.') }

foreach ($r in $records) { Write-Host "Installed: $($r.path)" }
if (Test-Path -LiteralPath $backupDir -PathType Container) { Write-Host "Backup:    $backupDir" }

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Files installed, but effective Kilo configuration FAILED validation:' -ForegroundColor Red
    foreach ($e in $errors) { Write-Host " - $e" -ForegroundColor Red }
    Write-Host "Apply only the minimal merge in: $(Join-Path $PSScriptRoot 'AI-CONFIG-MERGE-GUIDE.md')"
    exit 1
}

Write-Host ''
Write-Host 'PASS: Prime/Sub topology, state helper, and lifecycle guard installation validate.' -ForegroundColor Green
Write-Host 'Installer did not edit Kilo configuration, providers, credentials, MCP, plugin config, or built-ins.'
