$ErrorActionPreference = "Stop"

function Read-Default {
    param(
        [string]$Prompt,
        [string]$Default = ""
    )

    if ([string]::IsNullOrWhiteSpace($Default)) {
        $value = Read-Host $Prompt
    } else {
        $value = Read-Host "$Prompt [$Default]"
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value.Trim()
}

function Read-SecretText {
    param(
        [string]$Prompt,
        [string]$Existing = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Existing)) {
        $choice = Read-Host "$Prompt is already set. Press Enter to keep it, or type a new value"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $Existing
        }
        return $choice.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Allowed,
        [string]$Default
    )

    while ($true) {
        $value = Read-Default -Prompt "$Prompt ($($Allowed -join '/'))" -Default $Default
        if ($Allowed -contains $value) {
            return $value
        }
        Write-Host "Invalid value: $value"
    }
}

function Read-EnvFile {
    param([string]$Path)

    $map = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $map
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#") -or $line -notmatch "=") {
            return
        }
        $parts = $line -split "=", 2
        $map[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $map
}

function Write-EnvFile {
    param(
        [string]$Path,
        $Config
    )

    $lines = @(
        "# AI review git hook config. Do not commit this file.",
        "AI_REVIEW_ENABLED=true",
        "AI_REVIEW_API_KEY=$($Config.AI_REVIEW_API_KEY)",
        "AI_REVIEW_MODEL=$($Config.AI_REVIEW_MODEL)",
        "AI_REVIEW_BASE_URL=$($Config.AI_REVIEW_BASE_URL)",
        "",
        "AI_REVIEW_COMPILE=false",
        "AI_REVIEW_RUN_TESTS=false",
        "AI_REVIEW_REQUIRE_API=false",
        "AI_REVIEW_FAIL_ON_AI_ERROR=false",
        "AI_REVIEW_FAIL_ON_FINDINGS=false",
        "AI_REVIEW_MAX_DIFF_BYTES=120000",
        "AI_REVIEW_TIMEOUT_SECONDS=90",
        "",
        "AI_REVIEW_NOTIFY_ON=$($Config.AI_REVIEW_NOTIFY_ON)",
        "AI_REVIEW_DESKTOP_NOTIFY=$($Config.AI_REVIEW_DESKTOP_NOTIFY)",
        "AI_REVIEW_DESKTOP_NOTIFY_SECONDS=$($Config.AI_REVIEW_DESKTOP_NOTIFY_SECONDS)"
    )

    if ($Config.AI_REVIEW_FEISHU_WEBHOOK) {
        $lines += "AI_REVIEW_FEISHU_WEBHOOK=$($Config.AI_REVIEW_FEISHU_WEBHOOK)"
    }
    if ($Config.AI_REVIEW_WECHAT_WEBHOOK) {
        $lines += "AI_REVIEW_WECHAT_WEBHOOK=$($Config.AI_REVIEW_WECHAT_WEBHOOK)"
    }
    if ($Config.AI_REVIEW_DINGTALK_WEBHOOK) {
        $lines += "AI_REVIEW_DINGTALK_WEBHOOK=$($Config.AI_REVIEW_DINGTALK_WEBHOOK)"
    }
    if ($Config.AI_REVIEW_EMAIL_TO) {
        $lines += @(
            "AI_REVIEW_EMAIL_TO=$($Config.AI_REVIEW_EMAIL_TO)",
            "AI_REVIEW_EMAIL_FROM=$($Config.AI_REVIEW_EMAIL_FROM)",
            "AI_REVIEW_SMTP_HOST=$($Config.AI_REVIEW_SMTP_HOST)",
            "AI_REVIEW_SMTP_PORT=$($Config.AI_REVIEW_SMTP_PORT)",
            "AI_REVIEW_SMTP_USERNAME=$($Config.AI_REVIEW_SMTP_USERNAME)",
            "AI_REVIEW_SMTP_PASSWORD=$($Config.AI_REVIEW_SMTP_PASSWORD)",
            "AI_REVIEW_SMTP_STARTTLS=$($Config.AI_REVIEW_SMTP_STARTTLS)",
            "AI_REVIEW_SMTP_SSL=$($Config.AI_REVIEW_SMTP_SSL)"
        )
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Path), (($lines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
}

function Ensure-GitIgnore {
    param([string]$Path = ".gitignore")

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path | Out-Null
    }

    $lines = @(Get-Content $Path)
    $changed = $false

    if (-not ($lines -contains ".ai-review.env")) {
        Add-Content -Path $Path -Value ".ai-review.env"
        $changed = $true
    }

    if (-not ($lines -contains "/githooks/")) {
        Add-Content -Path $Path -Value "/githooks/"
        $changed = $true
    }

    if ($changed) {
        Write-Host "Updated .gitignore with .ai-review.env and /githooks/"
    } else {
        Write-Host ".gitignore already ignores .ai-review.env and /githooks/"
    }
}

function Get-ExistingOrDefault {
    param(
        $Map,
        [string]$Key,
        [string]$Default = ""
    )

    if ($Map.Contains($Key) -and -not [string]::IsNullOrWhiteSpace($Map[$Key])) {
        return $Map[$Key]
    }
    return $Default
}

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
            $gitCmdDir = Split-Path -Parent $gitCommand.Source
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
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

function Test-PythonCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    try {
        if ($Command -eq "py -3") {
            $output = & py -3 -c "import sys; print(sys.version_info[0])" 2>$null
        } else {
            $output = & $Command -c "import sys; print(sys.version_info[0])" 2>$null
        }
        return ($LASTEXITCODE -eq 0 -and (($output -join "").Trim() -eq "3"))
    } catch {
        return $false
    }
}

function Find-PythonCommand {
    foreach ($candidate in @("python", "python3", "py -3")) {
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
    }
    return $null
}

function Test-PythonInGitShell {
    param(
        [string]$GitShell,
        [string]$PythonCommand
    )

    if ([string]::IsNullOrWhiteSpace($GitShell) -or [string]::IsNullOrWhiteSpace($PythonCommand)) {
        return $false
    }
    try {
        $result = & $GitShell -lc "$PythonCommand -c 'import sys; print(sys.version_info[0])'" 2>$null
        return ($LASTEXITCODE -eq 0 -and (($result -join "").Trim() -eq "3"))
    } catch {
        return $false
    }
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$Name
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host "winget not found. Please install $Name manually."
        return $false
    }

    $answer = Read-Choice "Install missing dependency $Name with winget now" @("yes", "no") "yes"
    if ($answer -ne "yes") { return $false }

    Write-Host "Installing $Name with winget..."
    winget install --id $PackageId --exact --source winget --accept-package-agreements --accept-source-agreements
    return ($LASTEXITCODE -eq 0)
}

function Ensure-Dependencies {
    Write-Host "Checking dependencies..."

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) {
        Install-WithWinget "Git.Git" "Git for Windows" | Out-Null
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
    }

    $gitShell = Find-GitShell
    if (-not $gitShell) {
        Write-Host "Git Bash shell was not found."
        Install-WithWinget "Git.Git" "Git for Windows" | Out-Null
        $gitShell = Find-GitShell
    }

    $python = Find-PythonCommand
    if (-not $python) {
        Install-WithWinget "Python.Python.3.13" "Python 3" | Out-Null
        $python = Find-PythonCommand
    }

    $pythonInGitShell = $false
    if ($python -and $gitShell) {
        $pythonInGitShell = Test-PythonInGitShell -GitShell $gitShell -PythonCommand $python
        if (-not $pythonInGitShell) {
            foreach ($candidate in @("python", "python3", "py -3")) {
                if (Test-PythonInGitShell -GitShell $gitShell -PythonCommand $candidate) {
                    $python = $candidate
                    $pythonInGitShell = $true
                    break
                }
            }
        }
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        Write-Host "curl.exe was not found. Windows 10+ usually includes curl. Please install curl or upgrade Windows."
    }

    Write-Host "Dependency summary:"
    Write-Host "  git:    $($git.Source)"
    Write-Host "  sh:     $gitShell"
    Write-Host "  python: $python"
    Write-Host "  python in Git Bash: $pythonInGitShell"
    Write-Host "  curl:   $($curl.Source)"

    $missing = @()
    if (-not $git) { $missing += "git" }
    if (-not $gitShell) { $missing += "Git Bash sh.exe/bash.exe" }
    if (-not $python -or -not $pythonInGitShell) { $missing += "python usable from Git Bash" }
    if (-not $curl) { $missing += "curl" }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "Missing dependencies: $($missing -join ', ')"
        Write-Host "Manual downloads:"
        Write-Host "  Git:    https://git-scm.com/download/win"
        Write-Host "  Python: https://www.python.org/downloads/windows/"
        throw "Install dependencies and re-run install.ps1"
    }

    Write-Host "Dependencies OK."
    Write-Host ""
}

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = (Get-Location).Path
}

Set-Location $repoRoot
Ensure-Dependencies
git config core.hooksPath githooks
Ensure-GitIgnore

$envPath = ".ai-review.env"
$existing = Read-EnvFile -Path $envPath

Write-Host ""
Write-Host "Configure AI review hook for: $repoRoot"
Write-Host "Press Enter to keep the value shown in brackets."
Write-Host ""

$config = [ordered]@{}
$config.AI_REVIEW_BASE_URL = Read-Default "AI base URL" (Get-ExistingOrDefault $existing "AI_REVIEW_BASE_URL" "https://api.openai.com/v1")
$config.AI_REVIEW_MODEL = Read-Default "AI model" (Get-ExistingOrDefault $existing "AI_REVIEW_MODEL" "gpt-4o-mini")
$config.AI_REVIEW_API_KEY = Read-SecretText "AI API key" (Get-ExistingOrDefault $existing "AI_REVIEW_API_KEY" "")
$config.AI_REVIEW_NOTIFY_ON = Read-Choice "Notify when" @("always", "fail", "error", "never") (Get-ExistingOrDefault $existing "AI_REVIEW_NOTIFY_ON" "always")
$config.AI_REVIEW_DESKTOP_NOTIFY = Read-Choice "Enable desktop notification" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_NOTIFY" "true")
$config.AI_REVIEW_DESKTOP_NOTIFY_SECONDS = Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_NOTIFY_SECONDS" "8"

$notifyType = Read-Choice "Notification channel" @("none", "feishu", "wechat", "dingtalk", "email") "none"

if ($notifyType -eq "feishu") {
    $config.AI_REVIEW_FEISHU_WEBHOOK = Read-Default "Feishu robot webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_FEISHU_WEBHOOK" "")
} elseif ($notifyType -eq "wechat") {
    $config.AI_REVIEW_WECHAT_WEBHOOK = Read-Default "WeCom robot webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_WECHAT_WEBHOOK" "")
} elseif ($notifyType -eq "dingtalk") {
    $config.AI_REVIEW_DINGTALK_WEBHOOK = Read-Default "DingTalk robot webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_DINGTALK_WEBHOOK" "")
} elseif ($notifyType -eq "email") {
    $config.AI_REVIEW_EMAIL_TO = Read-Default "Email recipient" (Get-ExistingOrDefault $existing "AI_REVIEW_EMAIL_TO" "")
    $config.AI_REVIEW_EMAIL_FROM = Read-Default "Email sender" (Get-ExistingOrDefault $existing "AI_REVIEW_EMAIL_FROM" $config.AI_REVIEW_EMAIL_TO)
    $config.AI_REVIEW_SMTP_HOST = Read-Default "SMTP host" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_HOST" "smtp.163.com")
    $config.AI_REVIEW_SMTP_PORT = Read-Default "SMTP port" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_PORT" "465")
    $config.AI_REVIEW_SMTP_USERNAME = Read-Default "SMTP username" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_USERNAME" $config.AI_REVIEW_EMAIL_FROM)
    $config.AI_REVIEW_SMTP_PASSWORD = Read-SecretText "SMTP password/auth code" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_PASSWORD" "")
    $config.AI_REVIEW_SMTP_SSL = Read-Choice "SMTP SSL" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_SSL" "true")
    $config.AI_REVIEW_SMTP_STARTTLS = Read-Choice "SMTP STARTTLS" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_STARTTLS" "false")
}

Write-EnvFile -Path $envPath -Config $config

Write-Host ""
Write-Host "Git hooks installed for: $repoRoot"
Write-Host "core.hooksPath=$(git config core.hooksPath)"
Write-Host "Config written to: $envPath"
Write-Host "Keep .ai-review.env ignored because it contains secrets."
