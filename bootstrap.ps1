$ErrorActionPreference = "Stop"

$repoSlug = if ($env:AI_REVIEW_HOOK_REPO) { $env:AI_REVIEW_HOOK_REPO } else { "OWNER/git-ai-review-hook" }
$version = if ($env:AI_REVIEW_HOOK_VERSION) { $env:AI_REVIEW_HOOK_VERSION } else { "latest" }
$localZip = $env:AI_REVIEW_HOOK_ZIP

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    throw "Run this installer inside a Git repository."
}
Set-Location $repoRoot

$tmpDir = Join-Path $env:TEMP ("ai-review-hook-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpDir | Out-Null
$zipFile = Join-Path $tmpDir "git-ai-review-hook.zip"

try {
    if ($localZip) {
        if (-not (Test-Path $localZip)) { throw "Local zip not found: $localZip" }
        Copy-Item $localZip $zipFile
    } else {
        if ($version -eq "latest") {
            $url = "https://github.com/$repoSlug/releases/latest/download/git-ai-review-hook.zip"
        } else {
            $url = "https://github.com/$repoSlug/releases/download/$version/git-ai-review-hook.zip"
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

    $target = Join-Path $repoRoot "githooks"
    if (Test-Path $target) {
        Remove-Item -Recurse -Force $target
    }
    Copy-Item -Path $githooksDir.FullName -Destination $target -Recurse

    powershell -NoProfile -ExecutionPolicy Bypass -File ".\githooks\install.ps1"
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
