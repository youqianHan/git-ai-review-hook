$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

[scriptblock]::Create((Get-Content -Raw ".\githooks\install.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\uninstall.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\scripts\run-ai-review-background.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\scripts\show-windows-notification.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\scripts\test-ai-review-env.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\bootstrap.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\scripts\package-release.ps1")) | Out-Null

$sh = "C:\Program Files\Git\bin\sh.exe"
if (Test-Path $sh) {
    & $sh -n bootstrap.sh
    & $sh -n githooks/install.sh
    & $sh -n githooks/uninstall.sh
    & $sh -n githooks/pre-commit
    & $sh -n githooks/scripts/ai-review.sh
}

$tmp = Join-Path $env:TEMP ("ai-review-hook-ci-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp | Out-Null
git init $tmp | Out-Null
Copy-Item -Path ".\githooks" -Destination $tmp -Recurse
Set-Location $tmp

$inputText = @(
    "local",
    "https://example.com/v1",
    "gpt-test",
    "test-key",
    "true",
    "80000",
    "20000",
    "never",
    "false",
    "native",
    "false",
    "none"
) -join [Environment]::NewLine

$inputText + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\install.ps1
if ($LASTEXITCODE -ne 0) {
    throw "install.ps1 failed with exit code $LASTEXITCODE"
}

if ((git config core.hooksPath) -ne "githooks") {
    throw "core.hooksPath was not set"
}

if (-not (Select-String -Path ".gitignore" -Pattern "^\.ai-review\.env$" -Quiet)) {
    throw ".gitignore does not ignore .ai-review.env"
}

if (-not (Select-String -Path ".gitignore" -Pattern "^/githooks/$" -Quiet)) {
    throw ".gitignore does not ignore /githooks/"
}

if (-not (Test-Path ".ai-review.env")) {
    throw ".ai-review.env was not created"
}

Set-Location $root
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\package-release.ps1
$zip = Join-Path $root "dist\git-ai-review-hook.zip"
if (-not (Test-Path $zip)) {
    throw "release zip was not created"
}

$bootstrapTmp = Join-Path $env:TEMP ("ai-review-hook-bootstrap-ci-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $bootstrapTmp | Out-Null
git init $bootstrapTmp | Out-Null
Set-Location $bootstrapTmp
$env:AI_REVIEW_HOOK_ZIP = $zip
$env:AI_REVIEW_HOOK_SCOPE = "local"
$bootstrapInput = @(
    "https://example.com/v1",
    "gpt-test",
    "test-key",
    "true",
    "80000",
    "20000",
    "never",
    "false",
    "native",
    "false",
    "none"
) -join [Environment]::NewLine
$bootstrapInput + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bootstrap.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "bootstrap.ps1 failed with exit code $LASTEXITCODE"
}
if (-not (Test-Path "githooks\install.ps1")) {
    throw "bootstrap did not install githooks"
}
if ((git config core.hooksPath) -ne "githooks") {
    throw "bootstrap did not set core.hooksPath"
}
Remove-Item Env:\AI_REVIEW_HOOK_ZIP,Env:\AI_REVIEW_HOOK_SCOPE -ErrorAction SilentlyContinue

$nonGitTmp = Join-Path $env:TEMP ("ai-review-hook-nongit-ci-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $nonGitTmp | Out-Null
Set-Location $nonGitTmp
$oldHomeForNonGit = $env:HOME
$oldUserProfileForNonGit = $env:USERPROFILE
$nonGitHome = Join-Path $nonGitTmp "home"
New-Item -ItemType Directory -Path $nonGitHome | Out-Null
try {
    $env:HOME = $nonGitHome
    $env:USERPROFILE = $nonGitHome
    $env:AI_REVIEW_HOOK_ZIP = $zip

    $nonGitGlobalInput = @(
        "global",
        "https://example.com/v1",
        "gpt-test",
        "test-key",
        "true",
        "80000",
        "20000",
        "never",
        "false",
        "native",
        "false",
        "none"
    ) -join [Environment]::NewLine
    $nonGitGlobalInput + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bootstrap.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "non-git global bootstrap.ps1 failed with exit code $LASTEXITCODE"
    }
    $nonGitHooks = git config --global core.hooksPath
    if (-not $nonGitHooks -or -not (Test-Path (Join-Path $nonGitHooks "pre-commit"))) {
        throw "non-git global bootstrap did not install hook"
    }

    $nonGitLocalInput = "local" + [Environment]::NewLine
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $nonGitLocalOutput = $nonGitLocalInput | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bootstrap.ps1") 2>&1
        $nonGitLocalExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }
    if ($nonGitLocalExitCode -eq 0) {
        throw "non-git local bootstrap.ps1 unexpectedly succeeded"
    }
    $nonGitLocalText = $nonGitLocalOutput -join "`n"
    if ($nonGitLocalText -match "fatal: not a git repository" -or $nonGitLocalText -notmatch "Local install requires running inside a Git repository") {
        throw "non-git local bootstrap.ps1 did not show clean local-only error: $nonGitLocalText"
    }
} finally {
    Remove-Item Env:\AI_REVIEW_HOOK_ZIP -ErrorAction SilentlyContinue
    $env:HOME = $oldHomeForNonGit
    $env:USERPROFILE = $oldUserProfileForNonGit
    Set-Location $root
    Remove-Item -LiteralPath $nonGitTmp -Recurse -Force -ErrorAction SilentlyContinue
}

$globalTmp = Join-Path $env:TEMP ("ai-review-hook-global-ci-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $globalTmp | Out-Null
$globalHome = Join-Path $globalTmp "home"
New-Item -ItemType Directory -Path $globalHome | Out-Null
$oldHome = $env:HOME
$oldUserProfile = $env:USERPROFILE
$oldGlobalHooksPath = git config --global core.hooksPath 2>$null
try {
    $env:HOME = $globalHome
    $env:USERPROFILE = $globalHome
    $globalRepo = Join-Path $globalTmp "repo"
    New-Item -ItemType Directory -Path $globalRepo | Out-Null
    git init $globalRepo | Out-Null
    Set-Location $globalRepo
    $env:AI_REVIEW_HOOK_ZIP = $zip
    $env:AI_REVIEW_HOOK_SCOPE = "global"
    $globalInput = @(
        "https://example.com/v1",
        "gpt-test",
        "test-key",
        "true",
        "80000",
        "20000",
        "never",
        "false",
        "native",
        "false",
        "none"
    ) -join [Environment]::NewLine
    $globalInput + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bootstrap.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "global bootstrap.ps1 failed with exit code $LASTEXITCODE"
    }
    $globalHooks = git config --global core.hooksPath
    if (-not $globalHooks -or -not (Test-Path (Join-Path $globalHooks "pre-commit"))) {
        throw "global core.hooksPath was not set to an installed hook directory"
    }
    if (-not (Test-Path (Join-Path $globalHome ".ai-review.env"))) {
        throw "global .ai-review.env was not created"
    }

    $hookRepo = Join-Path $globalTmp "hook-repo"
    New-Item -ItemType Directory -Path $hookRepo | Out-Null
    git init $hookRepo | Out-Null
    Set-Location $hookRepo
    [System.IO.File]::WriteAllText(
        (Join-Path $globalHome ".ai-review.env"),
        "AI_REVIEW_ASYNC=false`nAI_REVIEW_ENABLED=false`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
    Set-Content -Path "test.txt" -Value "test"
    git add test.txt
    $git = (Get-Command git.exe).Source
    $gitRoot = Split-Path -Parent (Split-Path -Parent $git)
    $sh = Join-Path $gitRoot "bin\sh.exe"
    $hookOutput = & $sh (Join-Path $globalHooks "pre-commit") 2>&1
    $hookText = $hookOutput -join "`n"
    if ($LASTEXITCODE -ne 0 -or $hookText -notmatch "AI_REVIEW_ENABLED=false") {
        throw "global pre-commit did not execute correctly: $hookText"
    }
} finally {
    Remove-Item Env:\AI_REVIEW_HOOK_ZIP,Env:\AI_REVIEW_HOOK_SCOPE -ErrorAction SilentlyContinue
    if ($oldGlobalHooksPath) {
        git config --global core.hooksPath $oldGlobalHooksPath
    } else {
        git config --global --unset core.hooksPath 2>$null
    }
    $env:HOME = $oldHome
    $env:USERPROFILE = $oldUserProfile
    Set-Location $root
    Remove-Item -LiteralPath $globalTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "All tests passed."
