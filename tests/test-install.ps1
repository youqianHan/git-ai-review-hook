$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

[scriptblock]::Create((Get-Content -Raw ".\githooks\install.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\uninstall.ps1")) | Out-Null
[scriptblock]::Create((Get-Content -Raw ".\githooks\scripts\run-ai-review-background.ps1")) | Out-Null
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
    "https://example.com/v1",
    "gpt-test",
    "test-key",
    "never",
    "false",
    "none"
) -join [Environment]::NewLine

$inputText + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File .\githooks\install.ps1

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
$bootstrapInput = @(
    "https://example.com/v1",
    "gpt-test",
    "test-key",
    "never",
    "false",
    "none"
) -join [Environment]::NewLine
$bootstrapInput + [Environment]::NewLine | powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "bootstrap.ps1")
if (-not (Test-Path "githooks\install.ps1")) {
    throw "bootstrap did not install githooks"
}
if ((git config core.hooksPath) -ne "githooks") {
    throw "bootstrap did not set core.hooksPath"
}
Remove-Item Env:\AI_REVIEW_HOOK_ZIP -ErrorAction SilentlyContinue

Write-Host "All tests passed."
