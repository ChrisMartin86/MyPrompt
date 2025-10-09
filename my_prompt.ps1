# =================== Utility: Command Existence ===================
function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    Get-Command $Name -ErrorAction Ignore | ForEach-Object { return $true }
    return $false
}

# =================== Utility: Short Path ===================
function Set-ShorterPath {
    param([Parameter(Mandatory)][string]$Path, [int]$Max = 48)
    if ($Path.Length -le $Max) { return $Path }
    $sep = [IO.Path]::DirectorySeparatorChar
    $parts = $Path.Split($sep, [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -le 3) { return $Path }
    return "$($parts[0])$sep...$sep$($parts[-2])$sep$($parts[-1])"
}

# =================== Utility: Admin Check ===================
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pri = [Security.Principal.WindowsPrincipal]$id
    $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =================== Simple Cache Framework (for cloud only) ===================
$script:Cache = @{}
function Get-Cached {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ScriptBlock]$Block,
        [int]$TTLSeconds = 20
    )
    $now = Get-Date
    if ($script:Cache[$Name] -and ($now -lt $script:Cache[$Name].Expiry)) {
        return $script:Cache[$Name].Value
    }
    $val = & $Block
    $script:Cache[$Name] = @{ Value = $val; Expiry = $now.AddSeconds($TTLSeconds) }
    return $val
}

# =================== AWS Account ===================
function Get-AwsAccountNumber {
    if (-not (Test-Command aws)) { return $null }
    try {
        $id = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
        return $id.Account
    }
    catch { return $null }
}

# =================== Azure Context ===================
function Format-AzCloudTag {
    param([string]$EnvName)
    switch ($EnvName) {
        'AzureCloud' { 'Azure Commercial:' }
        'AzureUSGovernment' { 'Azure Government:' }
        default { if ($EnvName) { 'Azure ?' } else { $null } }
    }
}
function Get-AzCliContext {
    if (-not (Test-Command az)) { return [ordered]@{ env = $null; subId = $null; subName = $null } }
    try {
        $envName = az cloud show --query name -o tsv 2>$null
        $acc = az account show -o json 2>$null | ConvertFrom-Json
        [ordered]@{
            env     = $envName
            subId   = $acc.id
            subName = $acc.name
        }
    }
    catch {
        [ordered]@{ env = $null; subId = $null; subName = $null }
    }
}

# =================== Git Segment (single call, no cache) ===================
$script:GitSymbol = '⎇'
function Get-GitSegment {
    if (-not (Test-Command git)) { return $null }
    try {
        $output = git status --porcelain=2 --branch 2>$null        
        if ($LASTEXITCODE -ne 0) { return $null }

        $branch = ($output | Where-Object { $_ -match '^# branch.head ' } | ForEach-Object { $_.Split(' ')[2] })
        if (-not $branch) { $branch = git rev-parse --short HEAD 2>$null }
        $dirty = if ($output | Where-Object { $_ -notmatch '^#' }) { '*' } else { '' }
        $remote = git config --get remote.origin.url 2>$null
        if ($remote -match '[:/](?<org>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$') {
            return "$($Matches['org'])/$($Matches['repo']) - $script:GitSymbol $branch$dirty"
        }
        "$script:GitSymbol $branch$dirty"
    }
    catch { $null }
}

# =================== Script-Scoped Globals ===================
$script:Ellipsis = '...'

# ANSI color escapes (PowerShell 7+)
$esc = [char]27
$script:ColorGray = "${esc}[90m"
$script:ColorGreen = "${esc}[32m"
$script:ColorCyan = "${esc}[36m"
$script:ColorMagenta = "${esc}[35m"
$script:ColorYellow = "${esc}[33m"
$script:ColorRed = "${esc}[31m"
$script:ColorReset = "${esc}[0m"
$script:ColorBlue = "${esc}[34m"
$script:ColorWhite = "${esc}[97m"


# =================== Prompt ===================
function prompt {
    $now = Get-Date -Format 'MM/dd/yyyy HH:mm'
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name.Split('\')[-1]
    $admin = Test-IsAdmin
    $path = Set-ShorterPath -Path (Get-Location).Path

    # Use cache for expensive cloud lookups
    $az = Get-Cached -Name 'AzContext' -Block { Get-AzCliContext } -TTLSeconds 30
    $awsAccount = Get-Cached -Name 'AwsAccount' -Block { Get-AwsAccountNumber } -TTLSeconds 30
    $gitSeg = Get-GitSegment

    # Azure label
    $cloudLabel = Format-AzCloudTag -EnvName $az.env
    if ($az.subId) {
        $idTag = if ($az.subId.Length -ge 8) { $az.subId.Substring(0, 4) + $script:Ellipsis + $az.subId.Substring($az.subId.Length - 4) } else { $az.subId }
        $azText = "$cloudLabel $($az.subName) ($idTag)"
    }
    elseif ($az.env) {
        $azText = "$cloudLabel not logged in"
    }
    else {
        $azText = "Azure ? cli unavailable"
    }

    # Compose and print the info line
    $infoLine = "$($script:ColorGray)[$now]$($script:ColorReset) "
    if ($admin) { $infoLine += "$($script:ColorRed)[ADMIN]$($script:ColorReset) " }
    $infoLine += "$($script:ColorGreen)$user$($script:ColorReset)"
    if ($azText) { $infoLine += "  $($script:ColorCyan)$azText$($script:ColorReset)" }
    if ($awsAccount) { $infoLine += "  $($script:ColorMagenta)AWS: $awsAccount$($script:ColorReset)" }

    Write-Host $infoLine
    if ($gitSeg) {
        $authAccount = (gh auth status -a | Select-String keyring).ToString().Split(" ")[-2]
        $committingAs = git config user.email
        Write-Host "$($script:ColorBlue)github:[$authAccount] $($script:ColorWhite)git:[$committingAs] $($script:ColorYellow)$gitSeg$($script:ColorReset)"
    }

    "PS $path> "
}
