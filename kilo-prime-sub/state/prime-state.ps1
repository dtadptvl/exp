param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('init','snapshot','reconcile','impact','invalidate','mark')]
    [string]$Command,
    [string]$Root = (Get-Location).Path,
    [string[]]$ChangedArtifact = @(),
    [string[]]$ChangedTask = @()
)
$ErrorActionPreference = 'Stop'

function State-Path([string]$Repo) { Join-Path (Join-Path $Repo '.prime') 'state.json' }

function Empty-State {
    [ordered]@{
        schema = 1
        objective = [ordered]@{ rev = 0; text = '' }
        phase = 'capture-objective'
        active_task = $null
        tasks = [ordered]@{}
        decisions = [ordered]@{}
        assumptions = [ordered]@{}
        acceptance = @()
        evidence = [ordered]@{}
        invalidated = @()
        git = $null
        next = 'capture objective'
    }
}

function Read-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-State([string]$Path, $State) {
    $dir = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $tmp = "$Path.tmp"
    $State | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Copy-Item -LiteralPath $tmp -Destination $Path -Force
    Remove-Item -LiteralPath $tmp -Force
}

function Git-Snapshot([string]$Repo) {
    $inside = (& git -C $Repo rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $inside -ne 'true') {
        return [ordered]@{ repository=$false; branch=$null; head=$null; dirty=@(); at=(Get-Date).ToUniversalTime().ToString('o') }
    }
    $branch = (& git -C $Repo branch --show-current 2>$null | Out-String).Trim()
    $head = (& git -C $Repo rev-parse HEAD 2>$null | Out-String).Trim()
    $dirty = @(
        & git -C $Repo diff --name-only 2>$null
        & git -C $Repo diff --cached --name-only 2>$null
        & git -C $Repo ls-files --others --exclude-standard 2>$null
    ) | Where-Object { $_ } | Sort-Object -Unique
    [ordered]@{ repository=$true; branch=$branch; head=$head; dirty=$dirty; at=(Get-Date).ToUniversalTime().ToString('o') }
}

function Artifact-Match([string]$Changed, [string]$Ref) {
    if ([string]::IsNullOrWhiteSpace($Changed) -or [string]::IsNullOrWhiteSpace($Ref)) { return $false }
    return ($Changed -eq $Ref) -or $Ref.StartsWith($Changed + '#') -or $Changed.StartsWith($Ref + '#')
}

function Task-Impact($State, [string[]]$Artifacts, [string[]]$Tasks) {
    $direct = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in $Tasks) { if ($State.tasks.PSObject.Properties[$id]) { [void]$direct.Add([string]$id) } }

    foreach ($p in $State.tasks.PSObject.Properties) {
        $refs = @($p.Value.produces) + @($p.Value.consumes)
        foreach ($changed in $Artifacts) {
            foreach ($ref in $refs) {
                if (Artifact-Match ([string]$changed) ([string]$ref)) { [void]$direct.Add($p.Name) }
            }
        }
    }

    $all = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in $direct) { [void]$all.Add($id) }
    $advanced = $true
    while ($advanced) {
        $advanced = $false
        foreach ($p in $State.tasks.PSObject.Properties) {
            if ($all.Contains($p.Name)) { continue }
            foreach ($dep in @($p.Value.depends_on)) {
                if ($all.Contains([string]$dep)) { [void]$all.Add($p.Name); $advanced=$true; break }
            }
        }
    }
    [ordered]@{ direct=@($direct | Sort-Object); transitive=@($all | Sort-Object) }
}

function Git-Delta([string]$Repo, $Stored, $Current) {
    $paths = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($p in @($Current.dirty)) { [void]$paths.Add([string]$p) }
    if ($Current.repository -and $Stored -and $Stored.head -and $Stored.head -ne $Current.head) {
        $commitPaths = @(& git -C $Repo diff --name-only "$($Stored.head)..$($Current.head)" 2>$null)
        if ($LASTEXITCODE -eq 0) { foreach ($p in $commitPaths) { if ($p) { [void]$paths.Add([string]$p) } } }
    }
    @($paths | Sort-Object)
}

$repo = [IO.Path]::GetFullPath($Root)
$path = State-Path $repo

switch ($Command) {
    'init' {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-State $path (Empty-State) }
        Read-State $path | ConvertTo-Json -Depth 100
    }
    'snapshot' {
        Git-Snapshot $repo | ConvertTo-Json -Depth 20
    }
    'reconcile' {
        $state = Read-State $path
        if ($null -eq $state) { throw "Missing $path; run init first." }
        $current = Git-Snapshot $repo
        $delta = Git-Delta $repo $state.git $current
        [ordered]@{
            stored = $state.git
            current = $current
            stale = (-not $state.git) -or ($state.git.branch -ne $current.branch) -or ($state.git.head -ne $current.head) -or (@($delta).Count -gt 0)
            delta = $delta
        } | ConvertTo-Json -Depth 30
    }
    'impact' {
        $state = Read-State $path
        if ($null -eq $state) { throw "Missing $path; run init first." }
        Task-Impact $state $ChangedArtifact $ChangedTask | ConvertTo-Json -Depth 30
    }
    'invalidate' {
        $state = Read-State $path
        if ($null -eq $state) { throw "Missing $path; run init first." }
        $impact = Task-Impact $state $ChangedArtifact $ChangedTask
        $invalid = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($id in @($state.invalidated)) { [void]$invalid.Add([string]$id) }
        foreach ($id in $impact.transitive) {
            $prop = $state.tasks.PSObject.Properties[$id]
            if ($prop) { $prop.Value.status = 'invalidated'; [void]$invalid.Add([string]$id) }
        }
        $state.invalidated = @($invalid | Sort-Object)

        foreach ($e in $state.evidence.PSObject.Properties) {
            if (@($e.Value.tasks | Where-Object { $impact.transitive -contains [string]$_ }).Count -gt 0) { $e.Value.valid = $false }
        }
        foreach ($a in $state.assumptions.PSObject.Properties) {
            if ($a.Value -is [string]) { continue }
            $taskHit = @($a.Value.tasks | Where-Object { $impact.transitive -contains [string]$_ }).Count -gt 0
            $artifactHit = $false
            foreach ($changed in $ChangedArtifact) {
                foreach ($ref in @($a.Value.artifacts)) {
                    if (Artifact-Match ([string]$changed) ([string]$ref)) { $artifactHit=$true }
                }
            }
            if ($taskHit -or $artifactHit) { $a.Value.valid = $false }
        }
        Write-State $path $state
        [ordered]@{ affected=$impact; invalidated=$state.invalidated } | ConvertTo-Json -Depth 30
    }
    'mark' {
        $state = Read-State $path
        if ($null -eq $state) { throw "Missing $path; run init first." }
        $state.git = Git-Snapshot $repo
        Write-State $path $state
        $state.git | ConvertTo-Json -Depth 20
    }
}
