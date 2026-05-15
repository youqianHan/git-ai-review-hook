param(
    [string]$Scope = ""
)

$ErrorActionPreference = "Stop"

$repoSlug = if ($env:AI_REVIEW_HOOK_REPO) { $env:AI_REVIEW_HOOK_REPO } else { "youqianHan/git-ai-review-hook" }
$hostName = if ($env:AI_REVIEW_HOOK_HOST) { $env:AI_REVIEW_HOOK_HOST } else { "github" }
$version = if ($env:AI_REVIEW_HOOK_VERSION) { $env:AI_REVIEW_HOOK_VERSION } else { "latest" }
$localZip = $env:AI_REVIEW_HOOK_ZIP
$installScope = if ($Scope) { $Scope } elseif ($env:AI_REVIEW_HOOK_SCOPE) { $env:AI_REVIEW_HOOK_SCOPE } else { "" }
$latestGiteeVersion = "v0.1.6"

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Allowed,
        [string]$Default
    )

    while ($true) {
        $value = Read-Host "$Prompt ($($Allowed -join '/')) [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
        $value = $value.Trim()
        if ($Allowed -contains $value) { return $value }
        Write-Host "Invalid value: $value"
    }
}

$repoRoot = git rev-parse --show-toplevel 2>$null
if ([string]::IsNullOrWhiteSpace($installScope)) {
    $defaultScope = if ($repoRoot) { "local" } else { "global" }
    $installScope = Read-Choice "Install scope" @("local", "global") $defaultScope
}
if ($installScope -notin @("local", "global")) {
    throw "Invalid AI_REVIEW_HOOK_SCOPE: $installScope. Use local or global."
}
$hostName = $hostName.Trim().ToLowerInvariant()
if ($hostName -notin @("github", "gitee")) {
    throw "Invalid AI_REVIEW_HOOK_HOST: $hostName. Use github or gitee."
}
if (-not $repoRoot -and $installScope -ne "global") {
    throw "Run this installer inside a Git repository, or set AI_REVIEW_HOOK_SCOPE=global."
}
if ($repoRoot) {
    Set-Location $repoRoot
}

$tmpDir = Join-Path $env:TEMP ("ai-review-hook-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$zipFile = Join-Path $tmpDir "git-ai-review-hook.zip"

try {
    if ($localZip) {
        if (-not (Test-Path $localZip)) { throw "Local zip not found: $localZip" }
        Copy-Item $localZip $zipFile
    } else {
        if ($hostName -eq "gitee") {
            $archiveVersion = if ($version -eq "latest") { $latestGiteeVersion } else { $version }
            $url = "https://gitee.com/$repoSlug/repository/archive/$archiveVersion.zip"
        } else {
            if ($version -eq "latest") {
                $url = "https://github.com/$repoSlug/releases/latest/download/git-ai-review-hook.zip"
            } else {
                $url = "https://github.com/$repoSlug/releases/download/$version/git-ai-review-hook.zip"
            }
        }
        Invoke-WebRequest -Uri $url -OutFile $zipFile
    }

    $packageDir = Join-Path $tmpDir "package"
    Expand-Archive -Path $zipFile -DestinationPath $packageDir -Force

    $githooksDir = Get-ChildItem -Path $packageDir -Directory -Recurse |
        Where-Object { $_.Name -eq "githooks" } |
        Select-Object -First 1

    if (-not $githooksDir) {
        throw "Package does not contain githooks/."
    }

    if ($installScope -eq "global") {
        $target = Join-Path $HOME ".git-ai-review-hook\githooks"
    } else {
        $target = Join-Path $repoRoot "githooks"
    }
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -Path $githooksDir.FullName -Destination $target -Recurse

    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $target "install.ps1") -Scope $installScope
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
