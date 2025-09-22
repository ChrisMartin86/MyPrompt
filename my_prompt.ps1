# =================== Helpers ===================
function Set-ShorterPath {
    param([Parameter(Mandatory)][string]$Path,[int]$Max=48)
    if ($Path.Length -le $Max) { return $Path }
    $sep=[IO.Path]::DirectorySeparatorChar
    $parts=$Path -split '[\\/]+'; if ($parts.Count -le 3) { return $Path }
    "$($parts[0])$sep...$sep$($parts[-2])$sep$($parts[-1])"
}
function Test-IsAdmin {
    $id=[Security.Principal.WindowsIdentity]::GetCurrent()
    $pri=[Security.Principal.WindowsPrincipal]$id
    $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-Command { param([Parameter(Mandatory)][string]$Name)
    try { $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) } catch { $false } }

# Always use plain ASCII for prompt symbols
$script:Ellipsis = '...'
$script:BranchPrefix = '⎇'

# =================== Azure (info-only) ===================
function Format-AzCloudTag {
    param([string]$EnvName)
    switch ($EnvName) {
        'AzureCloud'         { 'Azure Commercial:' }
        'AzureUSGovernment'  { 'Azure Government:' }
        default              { if ($EnvName) { 'Azure ?' } else { $null } }
    }
}
function Get-AzCliContext {
    if (-not (Test-Command az)) { return [ordered]@{ env=$null; subId=$null; subName=$null } }
    $envName = $null
    try { $envName = (az cloud show --query name -o tsv 2>$null) } catch {}
    $subId=$null; $subName=$null
    try {
        $acc = az account show -o json 2>$null | ConvertFrom-Json
        if ($acc) { $subId = $acc.id; $subName = $acc.name }
    } catch {}
    [ordered]@{ env=$envName; subId=$subId; subName=$subName }
}

# =================== Git (branch + dirty indicator only) ===================
function Get-GitSegment {
    if (-not (Test-Command git)) { return $null }
    try {
        git rev-parse --is-inside-work-tree 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }

        $branch = git symbolic-ref --short -q HEAD 2>$null
        if (-not $branch) { $branch = git rev-parse --short HEAD 2>$null }

        git diff --quiet --ignore-submodules -- 2>$null;  $unstaged = ($LASTEXITCODE -ne 0)
        git diff --cached --quiet --ignore-submodules -- 2>$null; $staged   = ($LASTEXITCODE -ne 0)
        $mark = if ($unstaged -or $staged) { '*' } else { '' }

        # Handle https and ssh remotes
        $raw = git config --get remote.origin.url 2>$null
        if (-not $raw) { return "$branch$mark" }

        $org=''; $repo=''
        if ($raw -match '^(?<proto>https|http)://[^/]+/(?<org>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
            $org  = $Matches['org']; $repo = $Matches['repo']
        } elseif ($raw -match '^(?:git@|ssh://git@)[^/:]+[:/](?<org>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
            $org  = $Matches['org']; $repo = $Matches['repo']
        }
        if (-not $org -or -not $repo) { return "$script:BranchPrefix $branch$mark" }
        "$org/$repo - $script:BranchPrefix $branch$mark"
    } catch { $null }
}

# =================== Prompt ===================
function prompt {
    $now   = Get-Date -Format 'MM/dd/yyyy HH:mm'
    $user  = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
    $admin = Test-IsAdmin
    $path  = Set-ShorterPath -Path (Get-Location).Path

    # Azure
    $az = Get-AzCliContext
    $cloudLabel = Format-AzCloudTag -EnvName $az.env
    $azText = $null
    if ($az.subId) {
        $id = $az.subId
        $idTag = if ($id.Length -ge 8) { $id.Substring(0,4) + ($script:Ellipsis) + $id.Substring($id.Length-4) } else { $id }
        $label = if ($cloudLabel) { $cloudLabel } else { 'Azure ?' }
        $azText = "$label $($az.subName) ($idTag)"
    } elseif ($az.env) {
        $label = if ($cloudLabel) { $cloudLabel } else { 'Azure ?' }
        $azText = "$label not logged in"
    } else {
        $azText = "Azure ? cli unavailable"
    }

    # Git (branch + dirty mark)
    $gitSeg = Get-GitSegment

    # ---- Info line ----
    Write-Host "[$now] " -NoNewline -ForegroundColor DarkGray
    if ($admin) { Write-Host "[ADMIN] " -NoNewline -ForegroundColor Red }
    Write-Host $user -NoNewline -ForegroundColor Green
    if ($azText) { Write-Host "  $azText" -NoNewline -ForegroundColor Cyan }
    if ($gitSeg) { Write-Host ""; Write-Host "Current Repo:  $gitSeg" -NoNewline -ForegroundColor Yellow }

    Write-Host ""  # newline
    "PS $path> "
}
