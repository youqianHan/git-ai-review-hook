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
        Write-Host "Invalid value / 无效输入: $value"
    }
}

function Get-GitRepoRoot {
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $root = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root)) {
            return ($root -join "").Trim()
        }
        return ""
    } catch {
        return ""
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

if ([string]::IsNullOrWhiteSpace($installScope)) {
    $defaultScope = "global"
    $installScope = Read-Choice "Install scope / 安装范围" @("local", "global") $defaultScope
}
if ($installScope -notin @("local", "global")) {
    throw "Invalid AI_REVIEW_HOOK_SCOPE / 无效安装范围: $installScope. Use local or global / 请使用 local 或 global."
}
$hostName = $hostName.Trim().ToLowerInvariant()
if ($hostName -notin @("github", "gitee")) {
    throw "Invalid AI_REVIEW_HOOK_HOST / 无效下载源: $hostName. Use github or gitee / 请使用 github 或 gitee."
}

$repoRoot = ""
if ($installScope -eq "local") {
    $repoRoot = Get-GitRepoRoot
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        throw "Local install requires running inside a Git repository. / 当前项目安装需要在 Git 仓库内运行。"
    }
}
if ($repoRoot) {
    Set-Location $repoRoot
}

$tmpDir = Join-Path $env:TEMP ("ai-review-hook-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$zipFile = Join-Path $tmpDir "git-ai-review-hook.zip"

try {
    if ($localZip) {
        if (-not (Test-Path $localZip)) { throw "Local zip not found / 本地 zip 不存在: $localZip" }
        Copy-Item $localZip $zipFile
    } elseif ($hostName -eq "gitee") {
        $cloneVersion = if ($version -eq "latest") { "main" } else { $version }
        $cloneUrl = "https://gitee.com/$repoSlug.git"
        $cloneDir = Join-Path $tmpDir "repo"
        git clone --depth 1 --branch $cloneVersion $cloneUrl $cloneDir
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone from Gitee / 从 Gitee 克隆失败: $cloneUrl ($cloneVersion)"
        }
    } else {
        if ($version -eq "latest") {
            $url = "https://github.com/$repoSlug/releases/latest/download/git-ai-review-hook.zip"
        } else {
            $url = "https://github.com/$repoSlug/releases/download/$version/git-ai-review-hook.zip"
        }
        Invoke-WebRequest -Uri $url -OutFile $zipFile
    }

    if ($hostName -eq "gitee" -and -not $localZip) {
        $packageDir = Join-Path $tmpDir "repo"
    } else {
        $packageDir = Join-Path $tmpDir "package"
        Expand-Archive -Path $zipFile -DestinationPath $packageDir -Force
    }

    $githooksDir = Get-ChildItem -Path $packageDir -Directory -Recurse |
        Where-Object { $_.Name -eq "githooks" } |
        Select-Object -First 1

    if (-not $githooksDir) {
        throw "Package does not contain githooks/. / 安装包中未找到 githooks/ 目录。"
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
