$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

$dist = Join-Path $root "dist"
if (Test-Path $dist) {
    Remove-Item -Recurse -Force $dist
}
New-Item -ItemType Directory -Path $dist | Out-Null

$zip = Join-Path $dist "git-ai-review-hook.zip"
$staging = Join-Path $env:TEMP ("git-ai-review-hook-package-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $staging | Out-Null

try {
    Copy-Item -Path "githooks" -Destination $staging -Recurse
    Copy-Item -Path "README.md", "SECURITY.md", "LICENSE", "CHANGELOG.md" -Destination $staging

    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $zip -Force

    Write-Host "Created $zip"
} finally {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}
