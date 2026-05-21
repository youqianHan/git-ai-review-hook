param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [Parameter(Mandatory = $true)]
    [string]$HookDir,

    [Parameter(Mandatory = $true)]
    [string]$JobId,

    [Parameter(Mandatory = $true)]
    [string]$DiffFile
)

$ErrorActionPreference = "SilentlyContinue"

$jobDir = Join-Path $RepoRoot ".git\ai-review\jobs\$JobId"
$logFile = Join-Path $jobDir "background.log"
$script = Join-Path $HookDir "scripts\ai-review.sh"

function Find-GitShell {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $shCommand = Get-Command sh.exe -ErrorAction SilentlyContinue
        if ($shCommand -and $shCommand.Source) { $candidates.Add($shCommand.Source) }
    } catch {}

    try {
        $bashCommand = Get-Command bash.exe -ErrorAction SilentlyContinue
        if ($bashCommand -and $bashCommand.Source) { $candidates.Add($bashCommand.Source) }
    } catch {}

    try {
        $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($gitCommand -and $gitCommand.Source) {
            $gitExe = $gitCommand.Source
            $gitCmdDir = Split-Path -Parent $gitExe
            $gitRoot = Split-Path -Parent $gitCmdDir
            $candidates.Add((Join-Path $gitRoot "bin\sh.exe"))
            $candidates.Add((Join-Path $gitRoot "usr\bin\bash.exe"))
            $candidates.Add((Join-Path $gitRoot "bin\bash.exe"))
            $candidates.Add((Join-Path $gitCmdDir "sh.exe"))
            $candidates.Add((Join-Path $gitCmdDir "bash.exe"))
        }
    } catch {}

    $candidates.Add("C:\Program Files\Git\bin\sh.exe")
    $candidates.Add("C:\Program Files (x86)\Git\bin\sh.exe")

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

$sh = Find-GitShell
if (-not $sh) {
    "Cannot find Git Bash shell. Install Git for Windows with Git Bash, or ensure sh.exe/bash.exe is in PATH." | Out-File -FilePath $logFile -Encoding UTF8
    exit 0
}

$env:AI_REVIEW_JOB_ID = $JobId
$env:AI_REVIEW_DIFF_FILE = $DiffFile

Set-Location $RepoRoot
$repoRootSh = $RepoRoot -replace "\\", "/"
$scriptSh = $script -replace "\\", "/"
$diffFileSh = $DiffFile -replace "\\", "/"
$jobIdEscaped = $JobId.Replace("'", "'\''")
$command = "cd '$repoRootSh' && AI_REVIEW_JOB_ID='$jobIdEscaped' AI_REVIEW_DIFF_FILE='$diffFileSh' '$scriptSh'"

& $sh -lc $command *> $logFile
