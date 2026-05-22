param(
    [string]$Scope = ""
)

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
        $choice = Read-Host "$Prompt is already set. Press Enter to keep it, or type a new value / 已配置。直接回车保留，或输入新值"
        if ([string]::IsNullOrWhiteSpace($choice)) {
            return $Existing
        }
        return $choice.Trim()
    }

    $value = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }
    return $value.Trim()
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
        "# AI review git hook config. Do not commit this file. / AI review Git Hook 配置文件，请勿提交。",
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
        "AI_REVIEW_CONTEXT_ENABLED=$($Config.AI_REVIEW_CONTEXT_ENABLED)",
        "AI_REVIEW_CONTEXT_MAX_BYTES=$($Config.AI_REVIEW_CONTEXT_MAX_BYTES)",
        "AI_REVIEW_CONTEXT_MAX_FILE_BYTES=$($Config.AI_REVIEW_CONTEXT_MAX_FILE_BYTES)",
        "AI_REVIEW_TIMEOUT_SECONDS=90",
        "",
        "AI_REVIEW_NOTIFY_ON=$($Config.AI_REVIEW_NOTIFY_ON)",
        "AI_REVIEW_DESKTOP_NOTIFY=$($Config.AI_REVIEW_DESKTOP_NOTIFY)",
        "AI_REVIEW_DESKTOP_NOTIFY_SECONDS=$($Config.AI_REVIEW_DESKTOP_NOTIFY_SECONDS)",
        "AI_REVIEW_DESKTOP_OPEN_MODE=$($Config.AI_REVIEW_DESKTOP_OPEN_MODE)",
        "AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT=$($Config.AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT)"
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

    $targetPath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path (Get-Location) $Path }
    $parent = Split-Path -Parent $targetPath
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($targetPath, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), $utf8NoBom)
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
        Write-Host "Updated .gitignore with .ai-review.env and /githooks/ / 已更新 .gitignore，忽略 .ai-review.env 和 /githooks/"
    } else {
        Write-Host ".gitignore already ignores .ai-review.env and /githooks/ / .gitignore 已包含 .ai-review.env 和 /githooks/"
    }
}

function Ensure-LocalGitIgnore {
    param([string]$Scope)

    if ($Scope -eq "global") {
        return
    }
    Ensure-GitIgnore
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

function Get-AiProviderPreset {
    param([string]$Provider)

    switch ($Provider) {
        "openai" {
            return @{
                BaseUrl = "https://api.openai.com/v1"
                Model = "gpt-4o-mini"
            }
        }
        "deepseek" {
            return @{
                BaseUrl = "https://api.deepseek.com/chat/completions"
                Model = "deepseek-chat"
            }
        }
        "kimi" {
            return @{
                BaseUrl = "https://api.moonshot.ai/v1/chat/completions"
                Model = "kimi-k2-0711-preview"
            }
        }
        "glm" {
            return @{
                BaseUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
                Model = "glm-4-flash"
            }
        }
        "qwen" {
            return @{
                BaseUrl = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
                Model = "qwen-plus"
            }
        }
        "siliconflow" {
            return @{
                BaseUrl = "https://api.siliconflow.cn/v1/chat/completions"
                Model = "deepseek-ai/DeepSeek-V3"
            }
        }
        "doubao" {
            return @{
                BaseUrl = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
                Model = "doubao-seed-1-6-250615"
            }
        }
        default {
            return @{
                BaseUrl = "https://api.openai.com/v1"
                Model = "gpt-4o-mini"
            }
        }
    }
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

function Get-DownloadRegion {
    $override = $env:AI_REVIEW_DOWNLOAD_REGION
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $normalized = $override.Trim().ToLowerInvariant()
        if ($normalized -in @("cn", "china", "domestic", "mainland")) {
            return "cn"
        }
        if ($normalized -in @("global", "intl", "international", "official")) {
            return "global"
        }
    }

    try {
        if ([System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName -eq "CN") {
            return "cn"
        }
    } catch {}

    try {
        if ([System.Globalization.CultureInfo]::CurrentUICulture.Name -match "zh-CN") {
            return "cn"
        }
    } catch {}

    try {
        if ([System.TimeZoneInfo]::Local.Id -match "China|Shanghai|Beijing|Chongqing|Urumqi") {
            return "cn"
        }
    } catch {}

    return "global"
}

function Find-PythonCommand {
    foreach ($candidate in @("python", "python3", "py -3")) {
        if (Test-PythonCommand $candidate) {
            return $candidate
        }
    }
    return $null
}

function Get-PythonInstallerUrls {
    param(
        [string]$Version,
        [string]$FileName
    )

    $official = "https://www.python.org/ftp/python/$Version/$FileName"
    $domestic = @(
        "https://mirrors.tuna.tsinghua.edu.cn/python/$Version/$FileName",
        "https://mirrors.huaweicloud.com/python/$Version/$FileName"
    )

    if ((Get-DownloadRegion) -eq "cn") {
        Write-Host "[install] Download region: China. Domestic mirrors will be tried first. / 下载区域：中国，优先使用国内镜像。"
        return @($domestic + $official)
    }

    Write-Host "[install] Download region: global. Official source will be tried first. / 下载区域：国际，优先使用官方源。"
    return @(($official) + $domestic)
}

function Refresh-CurrentProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($machinePath)) { $paths += $machinePath }
    if (-not [string]::IsNullOrWhiteSpace($userPath)) { $paths += $userPath }
    $commonPaths = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin",
        "${env:ProgramFiles(x86)}\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\bin",
        "$env:LOCALAPPDATA\Programs\Python\Python313",
        "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\Python312",
        "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\Python311",
        "$env:LOCALAPPDATA\Programs\Python\Python311\Scripts"
    )
    foreach ($path in $commonPaths) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            $paths += $path
        }
    }
    if ($paths.Count -gt 0) {
        $env:Path = (($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ";")
    }
}

function Add-UserPathEntries {
    param([string[]]$Entries)

    $existing = [Environment]::GetEnvironmentVariable("Path", "User")
    $items = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        foreach ($item in ($existing -split ";")) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $items.Add($item.Trim())
            }
        }
    }

    $changed = $false
    foreach ($entry in $Entries) {
        if ([string]::IsNullOrWhiteSpace($entry) -or -not (Test-Path $entry)) {
            continue
        }
        $normalized = (Resolve-Path -LiteralPath $entry).Path.TrimEnd("\")
        $exists = $false
        foreach ($item in $items) {
            if ($item.TrimEnd("\").Equals($normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
                $exists = $true
                break
            }
        }
        if (-not $exists) {
            $items.Add($normalized)
            $changed = $true
            Write-Host "[install] Added to user PATH / 已添加到用户 PATH: $normalized"
        }
    }

    if ($changed) {
        [Environment]::SetEnvironmentVariable("Path", ($items -join ";"), "User")
        Refresh-CurrentProcessPath
    }
}

function Get-KnownDependencyPathEntries {
    $entries = New-Object System.Collections.Generic.List[string]

    $common = @(
        "$env:ProgramFiles\Git\cmd",
        "$env:ProgramFiles\Git\bin",
        "${env:ProgramFiles(x86)}\Git\cmd",
        "${env:ProgramFiles(x86)}\Git\bin",
        "$env:LOCALAPPDATA\Programs\Python\Python313",
        "$env:LOCALAPPDATA\Programs\Python\Python313\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\Python312",
        "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\Python311",
        "$env:LOCALAPPDATA\Programs\Python\Python311\Scripts"
    )
    foreach ($path in $common) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path $path)) {
            $entries.Add($path)
        }
    }

    try {
        $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
        if ($gitCommand -and $gitCommand.Source) {
            $gitCmdDir = Split-Path -Parent $gitCommand.Source
            $gitRoot = Split-Path -Parent $gitCmdDir
            $entries.Add($gitCmdDir)
            $entries.Add((Join-Path $gitRoot "bin"))
        }
    } catch {}

    try {
        $pythonCommand = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($pythonCommand -and $pythonCommand.Source -and $pythonCommand.Source -notmatch "\\WindowsApps\\") {
            $pythonDir = Split-Path -Parent $pythonCommand.Source
            $entries.Add($pythonDir)
            $entries.Add((Join-Path $pythonDir "Scripts"))
        }
    } catch {}

    try {
        $python3Command = Get-Command python3.exe -ErrorAction SilentlyContinue
        if ($python3Command -and $python3Command.Source -and $python3Command.Source -notmatch "\\WindowsApps\\") {
            $python3Dir = Split-Path -Parent $python3Command.Source
            $entries.Add($python3Dir)
            $entries.Add((Join-Path $python3Dir "Scripts"))
        }
    } catch {}

    try {
        $curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curlCommand -and $curlCommand.Source -and $curlCommand.Source -notmatch "\\Windows\\System32\\") {
            $entries.Add((Split-Path -Parent $curlCommand.Source))
        }
    } catch {}

    return $entries.ToArray()
}

function Sync-DependencyPathsToUserPath {
    Add-UserPathEntries -Entries (Get-KnownDependencyPathEntries)
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

function Install-PythonFromInstallerUrl {
    $version = "3.13.0"
    $fileName = if ([Environment]::Is64BitOperatingSystem) {
        "python-$version-amd64.exe"
    } else {
        "python-$version.exe"
    }

    $urls = Get-PythonInstallerUrls -Version $version -FileName $fileName

    $installer = Join-Path $env:TEMP $fileName
    foreach ($url in $urls) {
        try {
            Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Status "Downloading Python installer... / 正在下载 Python 安装包..." -PercentComplete 20
            Write-Host "[install] Downloading Python installer / 正在下载 Python 安装包:"
            Write-Host "          $url"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

            if (-not (Test-Path $installer) -or ((Get-Item $installer).Length -lt 1048576)) {
                Write-Host "[install] Downloaded file is invalid, trying next source. / 下载文件无效，尝试下一个下载源。"
                continue
            }

            Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Status "Installing Python from downloaded installer... / 正在安装下载的 Python..." -PercentComplete 70
            Write-Host "[install] Installing Python from downloaded installer... / 正在安装下载的 Python..."
            $arguments = @(
                "/quiet",
                "InstallAllUsers=0",
                "PrependPath=1",
                "Include_launcher=1",
                "Include_pip=1"
            )
            $process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Refresh-CurrentProcessPath
                Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Status "Python installed / Python 安装完成" -PercentComplete 100
                Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Completed
                Write-Host "[install] Python installed. / Python 安装完成。"
                return $true
            }

            Write-Host "[install] Python installer exited with code $($process.ExitCode), trying next source. / Python 安装程序退出码 $($process.ExitCode)，尝试下一个下载源。"
        } catch {
            Write-Host "[install] Failed to use this source, trying next one. / 当前下载源失败，尝试下一个。"
            Write-Host "          $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Completed
    return $false
}

function Write-DependencyStep {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Message
    )

    $percent = [int](($Current / $Total) * 100)
    Write-Progress -Activity "Checking dependencies / 正在检查依赖" -Status $Message -PercentComplete $percent
    Write-Host ""
    Write-Host "[$Current/$Total] $Message"
}

function Complete-DependencyProgress {
    Write-Progress -Activity "Checking dependencies / 正在检查依赖" -Completed
}

function Install-WithWinget {
    param(
        [string]$PackageId,
        [string]$Name
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Host "winget not found. Please install $Name manually. / 未找到 winget，请手动安装 $Name。"
        return $false
    }

    $answer = Read-Choice "Install missing dependency $Name with winget now / 是否现在用 winget 安装缺失依赖 $Name" @("yes", "no") "yes"
    if ($answer -ne "yes") { return $false }

    Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Status "Installing $Name with winget... / 正在使用 winget 安装 $Name..." -PercentComplete 50
    Write-Host "[install] Installing $Name with winget... / 正在使用 winget 安装 $Name..."
    winget install --id $PackageId --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Refresh-CurrentProcessPath
        Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Status "$Name installed / $Name 安装完成" -PercentComplete 100
        Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Completed
        Write-Host "[install] $Name installed. / $Name 安装完成。"
        return $true
    }

    Write-Progress -Activity "Installing dependencies / 正在安装依赖" -Completed
    Write-Host "[install] $Name installation failed with exit code $LASTEXITCODE. / $Name 安装失败，退出码 $LASTEXITCODE。"
    return $false
}

function Ensure-PythonUsableFromGitBash {
    param(
        [string]$GitShell,
        [string]$PythonCommand
    )

    if ([string]::IsNullOrWhiteSpace($GitShell)) {
        return @{
            Python = $PythonCommand
            Works = $false
        }
    }

    foreach ($candidate in @($PythonCommand, "python", "python3", "py -3")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-PythonInGitShell -GitShell $GitShell -PythonCommand $candidate)) {
            return @{
                Python = $candidate
                Works = $true
            }
        }
    }

    Write-Host "Python is not usable from Git Bash. Trying to repair Python installation... / Git Bash 内 Python 不可用，正在尝试自动修复 Python 安装..."
    if (-not (Install-WithWinget "Python.Python.3.13" "Python 3")) {
        Write-Host "[install] Trying Python installer download sources... / 正在尝试 Python 安装包下载源..."
        Install-PythonFromInstallerUrl | Out-Null
    }

    Refresh-CurrentProcessPath
    Sync-DependencyPathsToUserPath
    $python = Find-PythonCommand
    foreach ($candidate in @($python, "python", "python3", "py -3")) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-PythonInGitShell -GitShell $GitShell -PythonCommand $candidate)) {
            return @{
                Python = $candidate
                Works = $true
            }
        }
    }

    return @{
        Python = $python
        Works = $false
    }
}

function Ensure-Dependencies {
    Write-Host "Checking dependencies... / 正在检查依赖..."
    Sync-DependencyPathsToUserPath

    Write-DependencyStep 1 5 "Checking Git... / 检查 Git..."
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git) {
        Install-WithWinget "Git.Git" "Git for Windows" | Out-Null
        Refresh-CurrentProcessPath
        Sync-DependencyPathsToUserPath
        $git = Get-Command git.exe -ErrorAction SilentlyContinue
    }
    if ($git) {
        Write-Host "[ok] Git found / 已找到 Git: $($git.Source)"
    }

    Write-DependencyStep 2 5 "Checking Git Bash shell... / 检查 Git Bash shell..."
    $gitShell = Find-GitShell
    if (-not $gitShell) {
        Write-Host "Git Bash shell was not found. / 未找到 Git Bash shell。"
        Install-WithWinget "Git.Git" "Git for Windows" | Out-Null
        Refresh-CurrentProcessPath
        Sync-DependencyPathsToUserPath
        $gitShell = Find-GitShell
    }
    if ($gitShell) {
        Write-Host "[ok] Git Bash shell found / 已找到 Git Bash shell: $gitShell"
    }

    Write-DependencyStep 3 5 "Checking Python... / 检查 Python..."
    $python = Find-PythonCommand
    if (-not $python) {
        if (-not (Install-WithWinget "Python.Python.3.13" "Python 3")) {
            Write-Host "[install] winget Python install failed or was skipped. Trying installer download sources... / winget 安装 Python 失败或已跳过，尝试安装包下载源..."
            Install-PythonFromInstallerUrl | Out-Null
        }
        Refresh-CurrentProcessPath
        Sync-DependencyPathsToUserPath
        $python = Find-PythonCommand
    }
    if ($python) {
        Write-Host "[ok] Python found / 已找到 Python: $python"
    }

    Write-DependencyStep 4 5 "Checking Python inside Git Bash... / 检查 Git Bash 内 Python..."
    $pythonInGitShell = $false
    if ($python -and $gitShell) {
        $pythonCheck = Ensure-PythonUsableFromGitBash -GitShell $gitShell -PythonCommand $python
        $python = $pythonCheck.Python
        $pythonInGitShell = [bool]$pythonCheck.Works
    }
    if ($pythonInGitShell) {
        Write-Host "[ok] Python works in Git Bash / Git Bash 内 Python 可用: $python"
    }

    Write-DependencyStep 5 5 "Checking curl... / 检查 curl..."
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        Write-Host "curl.exe was not found. / 未找到 curl.exe。"
        Install-WithWinget "cURL.cURL" "curl" | Out-Null
        Refresh-CurrentProcessPath
        Sync-DependencyPathsToUserPath
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    }
    if ($curl) {
        Write-Host "[ok] curl found / 已找到 curl: $($curl.Source)"
    }

    Write-Host ""
    Write-Host "Dependency summary / 依赖检查结果:"
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
        Complete-DependencyProgress
        Write-Host ""
        Write-Host "Missing dependencies / 缺失依赖: $($missing -join ', ')"
        Write-Host "Manual downloads / 手动下载地址:"
        Write-Host "  Git:    https://git-scm.com/download/win"
        Write-Host "  Python: https://www.python.org/downloads/windows/"
        Write-Host "  Python mirror / Python 国内镜像: https://mirrors.tuna.tsinghua.edu.cn/python/"
        Write-Host "  curl:   https://curl.se/windows/"
        Write-Host ""
        Write-Host "Tip / 提示: If dependencies were just installed, close this PowerShell window and run the installer again. / 如果依赖刚安装完成，请关闭当前 PowerShell 窗口后重新运行安装。"
        throw "Install dependencies and re-run install.ps1 / 请安装依赖后重新运行 install.ps1"
    }

    Complete-DependencyProgress
    Write-Host "Dependencies OK. / 依赖检查通过。"
    Write-Host ""
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Get-GitRepoRoot
if ([string]::IsNullOrWhiteSpace($Scope)) {
    $defaultScope = if ($repoRoot) { "local" } else { "global" }
    $Scope = Read-Choice "Install scope / 安装范围" @("local", "global") $defaultScope
}
if ($Scope -notin @("local", "global")) {
    throw "Invalid scope / 无效安装范围: $Scope. Use local or global / 请使用 local 或 global。"
}
if ($Scope -eq "local" -and -not $repoRoot) {
    throw "Local install requires running inside a Git repository. / 当前项目安装需要在 Git 仓库内运行。"
}

if ($Scope -eq "local") {
    Set-Location $repoRoot
}
Ensure-Dependencies

if ($Scope -eq "global") {
    $hookPath = $scriptRoot
    git config --global core.hooksPath $hookPath
    $envPath = Join-Path $HOME ".ai-review.env"
    $displayRoot = "global"
} else {
    git config core.hooksPath githooks
    Ensure-LocalGitIgnore -Scope $Scope
    $envPath = ".ai-review.env"
    $displayRoot = $repoRoot
}

$existing = Read-EnvFile -Path $envPath

Write-Host ""
Write-Host "Configure AI review hook for / 配置 AI review hook: $displayRoot"
Write-Host "Press Enter to keep the value shown in brackets. / 直接回车保留方括号中的默认值。"
Write-Host ""

$config = [ordered]@{}
$provider = Read-Choice "AI provider preset / AI 厂商预设" @("openai", "deepseek", "kimi", "glm", "qwen", "siliconflow", "doubao", "custom") "openai"
$preset = Get-AiProviderPreset -Provider $provider
$baseUrlDefault = Get-ExistingOrDefault $existing "AI_REVIEW_BASE_URL" $preset.BaseUrl
$modelDefault = Get-ExistingOrDefault $existing "AI_REVIEW_MODEL" $preset.Model
if ($provider -eq "custom") {
    $baseUrlDefault = Get-ExistingOrDefault $existing "AI_REVIEW_BASE_URL" "https://api.openai.com/v1"
    $modelDefault = Get-ExistingOrDefault $existing "AI_REVIEW_MODEL" "gpt-4o-mini"
}
$config.AI_REVIEW_BASE_URL = Read-Default "AI base URL / AI 接口地址" $baseUrlDefault
$config.AI_REVIEW_MODEL = Read-Default "AI model / AI 模型" $modelDefault
$config.AI_REVIEW_API_KEY = Read-SecretText "AI API key / AI API 密钥" (Get-ExistingOrDefault $existing "AI_REVIEW_API_KEY" "")
$config.AI_REVIEW_CONTEXT_ENABLED = Read-Choice "Send related project context / 发送相关项目上下文" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_CONTEXT_ENABLED" "true")
$config.AI_REVIEW_CONTEXT_MAX_BYTES = Read-Default "Max context bytes / 最大上下文字节数" (Get-ExistingOrDefault $existing "AI_REVIEW_CONTEXT_MAX_BYTES" "80000")
$config.AI_REVIEW_CONTEXT_MAX_FILE_BYTES = Read-Default "Max bytes per context file / 单个上下文文件最大字节数" (Get-ExistingOrDefault $existing "AI_REVIEW_CONTEXT_MAX_FILE_BYTES" "20000")
$config.AI_REVIEW_NOTIFY_ON = Read-Choice "Notify when / 何时通知" @("always", "fail", "error", "never") (Get-ExistingOrDefault $existing "AI_REVIEW_NOTIFY_ON" "always")
$config.AI_REVIEW_DESKTOP_NOTIFY = Read-Choice "Enable desktop notification / 启用桌面通知" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_NOTIFY" "true")
$config.AI_REVIEW_DESKTOP_NOTIFY_SECONDS = Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_NOTIFY_SECONDS" "8"
$config.AI_REVIEW_DESKTOP_OPEN_MODE = Read-Choice "Desktop report open mode / 桌面报告打开方式" @("native", "file") (Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_OPEN_MODE" "native")
$config.AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT = Read-Choice "Auto open report dialog on macOS / macOS 自动弹出报告窗口" @("false", "true") (Get-ExistingOrDefault $existing "AI_REVIEW_DESKTOP_AUTO_OPEN_REPORT" "false")

$notifyType = Read-Choice "Notification channel / 通知渠道" @("none", "feishu", "wechat", "dingtalk", "email") "none"

if ($notifyType -eq "feishu") {
    $config.AI_REVIEW_FEISHU_WEBHOOK = Read-Default "Feishu robot webhook / 飞书机器人 webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_FEISHU_WEBHOOK" "")
} elseif ($notifyType -eq "wechat") {
    $config.AI_REVIEW_WECHAT_WEBHOOK = Read-Default "WeCom robot webhook / 企业微信机器人 webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_WECHAT_WEBHOOK" "")
} elseif ($notifyType -eq "dingtalk") {
    $config.AI_REVIEW_DINGTALK_WEBHOOK = Read-Default "DingTalk robot webhook / 钉钉机器人 webhook" (Get-ExistingOrDefault $existing "AI_REVIEW_DINGTALK_WEBHOOK" "")
} elseif ($notifyType -eq "email") {
    $config.AI_REVIEW_EMAIL_TO = Read-Default "Email recipient / 收件邮箱" (Get-ExistingOrDefault $existing "AI_REVIEW_EMAIL_TO" "")
    $config.AI_REVIEW_EMAIL_FROM = Read-Default "Email sender / 发件邮箱" (Get-ExistingOrDefault $existing "AI_REVIEW_EMAIL_FROM" $config.AI_REVIEW_EMAIL_TO)
    $config.AI_REVIEW_SMTP_HOST = Read-Default "SMTP host / SMTP 服务器" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_HOST" "smtp.163.com")
    $config.AI_REVIEW_SMTP_PORT = Read-Default "SMTP port / SMTP 端口" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_PORT" "465")
    $config.AI_REVIEW_SMTP_USERNAME = Read-Default "SMTP username / SMTP 用户名" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_USERNAME" $config.AI_REVIEW_EMAIL_FROM)
    $config.AI_REVIEW_SMTP_PASSWORD = Read-SecretText "SMTP password/auth code / SMTP 密码或授权码" (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_PASSWORD" "")
    $config.AI_REVIEW_SMTP_SSL = Read-Choice "SMTP SSL" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_SSL" "true")
    $config.AI_REVIEW_SMTP_STARTTLS = Read-Choice "SMTP STARTTLS" @("true", "false") (Get-ExistingOrDefault $existing "AI_REVIEW_SMTP_STARTTLS" "false")
}

Write-EnvFile -Path $envPath -Config $config

Write-Host ""
Write-Host "Git hooks installed for / Git hooks 已安装到: $displayRoot"
if ($Scope -eq "global") {
    Write-Host "global core.hooksPath=$(git config --global core.hooksPath)"
} else {
    Write-Host "core.hooksPath=$(git config core.hooksPath)"
}
Write-Host "Config written to / 配置已写入: $envPath"
if ($Scope -eq "local") {
    Write-Host "Keep .ai-review.env ignored because it contains secrets. / .ai-review.env 包含密钥，请保持忽略，不要提交。"
} else {
    Write-Host "Global config is stored in your user home and is not part of project commits. / 全局配置保存在用户目录，不属于项目提交内容。"
}
