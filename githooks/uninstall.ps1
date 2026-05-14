$ErrorActionPreference = "Stop"

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = (Get-Location).Path
}

Set-Location $repoRoot

$currentHooksPath = git config core.hooksPath
if ($currentHooksPath -eq "githooks") {
    git config --unset core.hooksPath
    Write-Host "Removed core.hooksPath=githooks"
} else {
    Write-Host "core.hooksPath is not githooks; current value: $currentHooksPath"
}

Write-Host "Local files were kept:"
Write-Host "  githooks/"
Write-Host "  .ai-review.env"
Write-Host "Remove them manually if you no longer need this tool."
