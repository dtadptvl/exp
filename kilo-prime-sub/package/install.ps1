$ErrorActionPreference = 'Stop'

function Resolve-KiloConfigRoot {
    $text = (& kilo debug paths | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "kilo debug paths failed with exit code $LASTEXITCODE." }
    $line = @($text -split "`r?`n") | Where-Object { $_ -match '^\s*config\s+' } | Select-Object -First 1
    if (-not $line -or $line -notmatch '^\s*config\s+(.+?)\s*$') {
        throw 'Could not resolve Kilo global config directory from kilo debug paths.'
    }
    return [System.IO.Path]::GetFullPath($Matches[1])
}

function Invoke-KiloJson {
    param([string[]]$Arguments, [string]$Label)
    $text = (& kilo @Arguments | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
    try { return $text | ConvertFrom-Json } catch { throw "$Label did not return valid JSON." }
}

function Permission-Action {
    param($Rules, [string]$Permission, [string]$Pattern)
    $action = 'ask'
    foreach ($rule in @($Rules)) {
        $permissionMatch = ($rule.permission -eq '*') -or ($rule.permission -eq $Permission)
        $patternMatch = $Pattern -like $rule.pattern
        if ($permissionMatch -and $patternMatch) { $action = $rule.action }
    }
    return $action
}

function Positive-FiniteNumber {
    param($Value)
    if ($null -eq $Value) { return $false }
    $number = 0.0
    if (-not [double]::TryParse([string]$Value, [ref]$number)) { return $false }
    return ($number -gt 0 -and -not [double]::IsInfinity($number) -and -not [double]::IsNaN($number))
}

function Parse-SemVer {
    param([string]$Text)
    if ($Text -match '(\d+)\.(\d+)\.(\d+)') {
        return [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    }
    return $null
}

function Same-File {
    param([string]$A, [string]$B)
    if (-not (Test-Path -LiteralPath $A -PathType Leaf) -or -not (Test-Path -LiteralPath $B -PathType Leaf)) { return $false }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $A).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $B).Hash
}

$kilo = Get-Command kilo -ErrorAction SilentlyContinue
if (-not $kilo) {
    throw 'Native Kilo is required but was not found in PATH. Install/configure Kilo first.'
}

$versionText = (& kilo --version | Out-String).Trim()
$kiloVersion = Parse-SemVer $versionText
$kiloRoot = Resolve-KiloConfigRoot
$agentDir = Join-Path $kiloRoot 'agents'
$backupRoot = Join-Path $kiloRoot 'prime-sub-backups'
$receiptPath = Join-Path $kiloRoot 'prime-sub-install.json'
$sourcePrime = Join-Path $PSScriptRoot 'agents\prime.md'
$sourceSub = Join-Path $PSScriptRoot 'agents\Sub.md'
$targetPrime = Join-Path $agentDir 'prime.md'
$targetSub = Join-Path $agentDir 'Sub.md'

foreach ($required in @($sourcePrime, $sourceSub)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Package is incomplete: missing $required" }
}

New-Item -ItemType Directory -Path $agentDir -Force | Out-Null

$needsInstall = -not (Same-File $sourcePrime $targetPrime) -or -not (Same-File $sourceSub $targetSub)
$backupDir = $null
$hadPrime = Test-Path -LiteralPath $targetPrime -PathType Leaf
$hadSub = Test-Path -LiteralPath $targetSub -PathType Leaf

if ($needsInstall) {
    if ($hadPrime -or $hadSub) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupDir = Join-Path $backupRoot ("$stamp-" + (Get-Random -Minimum 1000 -Maximum 9999))
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        if ($hadPrime) { Copy-Item -LiteralPath $targetPrime -Destination (Join-Path $backupDir 'prime.md') -Force }
        if ($hadSub) { Copy-Item -LiteralPath $targetSub -Destination (Join-Path $backupDir 'Sub.md') -Force }
    }

    Copy-Item -LiteralPath $sourcePrime -Destination $targetPrime -Force
    Copy-Item -LiteralPath $sourceSub -Destination $targetSub -Force

    $receipt = [ordered]@{
        version = 1
        installed_at = (Get-Date).ToString('o')
        backup_dir = $backupDir
        had_prime = $hadPrime
        had_sub = $hadSub
        prime_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetPrime).Hash
        sub_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $targetSub).Hash
    }
    $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
}

$config = Invoke-KiloJson -Arguments @('debug', 'config') -Label 'kilo debug config'
$prime = Invoke-KiloJson -Arguments @('debug', 'agent', 'prime') -Label 'kilo debug agent prime'
$sub = Invoke-KiloJson -Arguments @('debug', 'agent', 'Sub') -Label 'kilo debug agent Sub'

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if ($config.default_agent -ne 'prime') { $errors.Add("default_agent must resolve to 'prime'.") }
if ([int]$config.subagent_depth -ne 1) { $errors.Add('subagent_depth must resolve to 1.') }

if ($null -eq $kiloVersion) {
    $warnings.Add("Could not parse Kilo version from '$versionText'. Verify per-task model selection manually.")
} elseif ($kiloVersion -lt [version]'7.7.12') {
    if ($config.experimental.task_model_selection -ne $true) {
        $errors.Add('This Kilo version still gates per-task model selection; experimental.task_model_selection must resolve to true so Prime can force 9router/sub.')
    }
}

$router = $config.provider.'9router'
if ($null -eq $router) {
    $errors.Add('provider.9router is missing from effective Kilo configuration.')
} else {
    $routerOptions = $router.options
    if ($null -eq $routerOptions -or -not (Positive-FiniteNumber $routerOptions.chunkTimeout)) {
        $errors.Add('provider.9router.options.chunkTimeout must be an explicit positive finite millisecond value.')
    }
    if ($null -ne $routerOptions -and @($routerOptions.PSObject.Properties.Name) -contains 'timeout') {
        $requestTimeout = $routerOptions.timeout
        if (($requestTimeout -is [bool]) -and -not $requestTimeout) {
            $errors.Add('provider.9router.options.timeout must not be false; remove it or use a positive finite millisecond value.')
        } elseif (-not (Positive-FiniteNumber $requestTimeout)) {
            $errors.Add('provider.9router.options.timeout override must be a positive finite millisecond value when specified.')
        }
    }
}

if ($prime.mode -ne 'primary') { $errors.Add("Prime mode resolved to '$($prime.mode)', expected 'primary'.") }
if ((Permission-Action $prime.permission 'task' 'Sub') -ne 'allow') { $errors.Add('Prime is not allowed to delegate to Sub.') }
if ((Permission-Action $prime.permission 'task' 'general') -ne 'deny') { $errors.Add('Prime Task permission does not deny non-Sub agents.') }

if ($sub.mode -ne 'subagent') { $errors.Add("Sub mode resolved to '$($sub.mode)', expected 'subagent'.") }
if ($sub.model.providerID -ne '9router' -or $sub.model.modelID -ne 'sub') {
    $errors.Add("Effective Sub model resolved to '$($sub.model.providerID)/$($sub.model.modelID)', expected '9router/sub'.")
}
if (-not (Positive-FiniteNumber $sub.steps)) { $errors.Add('Sub emergency steps ceiling is not a positive finite value.') }
if ($sub.tools.task -ne $false) { $errors.Add('Sub Task tool is enabled; Sub must not spawn agents.') }
if ((Permission-Action $sub.permission 'doom_loop' '*') -ne 'deny') { $errors.Add('Sub doom_loop permission must resolve to deny.') }
if ((Permission-Action $sub.permission 'read' '.prime/state.json') -ne 'deny') { $errors.Add('Sub can read .prime/state.json; minimum-context isolation requires it to be denied.') }
if ((Permission-Action $sub.permission 'bash' 'git commit -m x') -ne 'deny') { $errors.Add('Sub can run Git mutation commands; git commit must be denied.') }
if ((Permission-Action $sub.permission 'bash' 'git status --short') -ne 'allow') { $errors.Add('Sub cannot perform read-only git status inspection.') }

Write-Host ''
Write-Host "Kilo version:     $versionText"
Write-Host "Installed Prime:  $targetPrime"
Write-Host "Installed Sub:    $targetSub"
Write-Host 'Project state:    created lazily by Prime as .prime\state.json'
if ($backupDir) { Write-Host "Previous agent files backed up to: $backupDir" }
if (-not $needsInstall) { Write-Host 'Agent files already matched this package; no new backup/receipt was created.' }

foreach ($item in $warnings) { Write-Host "WARNING: $item" -ForegroundColor Yellow }

if ($errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Agent installation completed, but effective Kilo configuration FAILED validation:' -ForegroundColor Red
    foreach ($item in $errors) { Write-Host " - $item" -ForegroundColor Red }
    Write-Host "Apply the minimal human-owned edits in: $(Join-Path $PSScriptRoot 'CONFIG-MERGE-GUIDE.md')"
    Write-Host 'Then run setup.cmd again. The installer never edits kilo.json or kilo.jsonc.'
    exit 1
}

Write-Host ''
Write-Host 'PASS: effective Prime/Sub topology and native/additive liveness guards satisfy package invariants.' -ForegroundColor Green
Write-Host 'Run Kilo in a target project with: kilo run --auto --agent prime "<objective>"'
exit 0
