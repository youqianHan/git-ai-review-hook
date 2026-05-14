param(
    [string]$SendMail = "true",
    [string]$TestAi = "true"
)

$ErrorActionPreference = "Continue"

function Mask-Value {
    param([string]$Key, [string]$Value)
    if ($Key -match "KEY|PASSWORD|TOKEN|WEBHOOK|SECRET") {
        if ([string]::IsNullOrWhiteSpace($Value)) { return "<empty>" }
        if ($Value.Length -le 8) { return "***" }
        return "$($Value.Substring(0, 4))***$($Value.Substring($Value.Length - 4))"
    }
    return $Value
}

function Read-EnvFile {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) { return $map }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq "" -or $line.StartsWith("#") -or $line -notmatch "=") { return }
        $parts = $line -split "=", 2
        $map[$parts[0].Trim()] = $parts[1].Trim()
    }
    return $map
}

function Get-Cfg {
    param([hashtable]$Config, [string]$Key, [string]$Default = "")
    if ($Config.Contains($Key) -and -not [string]::IsNullOrWhiteSpace($Config[$Key])) {
        return $Config[$Key]
    }
    return $Default
}

function To-Bool {
    param([string]$Value, [bool]$Default = $true)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    $normalized = $Value.Trim().TrimStart(":").ToLowerInvariant()
    if ($normalized -in @("1", "true", "yes", "y", "on")) { return $true }
    if ($normalized -in @("0", "false", "no", "n", "off")) { return $false }
    return $Default
}

$sendMailEnabled = To-Bool $SendMail $true
$testAiEnabled = To-Bool $TestAi $true

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) { $repoRoot = (Get-Location).Path }
Set-Location $repoRoot

$diagDir = Join-Path $repoRoot ".git\ai-review\diagnostics"
New-Item -ItemType Directory -Force -Path $diagDir | Out-Null
$logFile = Join-Path $diagDir ("diagnostic-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Start-Transcript -Path $logFile -Force | Out-Null

try {
    Write-Host "== AI Review Hook Diagnostics =="
    Write-Host "Repo: $repoRoot"
    Write-Host "Log:  $logFile"
    Write-Host ""

    Write-Host "== Git Hook =="
    $hooksPath = git config core.hooksPath
    Write-Host "core.hooksPath=$hooksPath"
    Write-Host "pre-commit exists=$(Test-Path .\githooks\pre-commit)"
    Write-Host "ai-review.sh exists=$(Test-Path .\githooks\scripts\ai-review.sh)"
    Write-Host "background ps1 exists=$(Test-Path .\githooks\scripts\run-ai-review-background.ps1)"
    Write-Host ""

    Write-Host "== Runtime =="
    Write-Host "PowerShell=$($PSVersionTable.PSVersion)"
    try { Write-Host "git=$(git --version)" } catch { Write-Host "git error=$($_.Exception.Message)" }
    try { Write-Host "python=$(python --version 2>&1)" } catch { Write-Host "python error=$($_.Exception.Message)" }
    $defaultSh = "C:\Program Files\Git\bin\sh.exe"
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    $derivedSh = ""
    if ($gitCommand -and $gitCommand.Source) {
        $gitCmdDir = Split-Path -Parent $gitCommand.Source
        $gitRoot = Split-Path -Parent $gitCmdDir
        $candidate = Join-Path $gitRoot "bin\sh.exe"
        if (Test-Path $candidate) { $derivedSh = $candidate }
    }
    $pathSh = Get-Command sh.exe -ErrorAction SilentlyContinue
    Write-Host "default sh exists=$(Test-Path $defaultSh) path=$defaultSh"
    Write-Host "PATH sh=$($pathSh.Source)"
    Write-Host "derived sh from git=$derivedSh"
    $testSh = if ($pathSh -and $pathSh.Source) { $pathSh.Source } elseif ($derivedSh) { $derivedSh } else { $defaultSh }
    try {
        $shOk = & $testSh -lc "echo ok" 2>&1
        Write-Host "selected sh test=$shOk path=$testSh"
    } catch {
        Write-Host "selected sh test error=$($_.Exception.Message)"
    }
    Write-Host ""

    Write-Host "== Config =="
    $homeConfig = Join-Path $HOME ".ai-review.env"
    $repoConfig = Join-Path $repoRoot ".ai-review.env"
    $config = [ordered]@{}
    foreach ($item in (Read-EnvFile $homeConfig).GetEnumerator()) { $config[$item.Key] = $item.Value }
    foreach ($item in (Read-EnvFile $repoConfig).GetEnumerator()) { $config[$item.Key] = $item.Value }
    Write-Host "home config exists=$(Test-Path $homeConfig) path=$homeConfig"
    Write-Host "repo config exists=$(Test-Path $repoConfig) path=$repoConfig"
    foreach ($key in $config.Keys) {
        Write-Host "$key=$(Mask-Value $key $config[$key])"
    }
    Write-Host ""

    Write-Host "== Network =="
    try {
        $smtpHost = Get-Cfg $config "AI_REVIEW_SMTP_HOST"
        $smtpPort = [int](Get-Cfg $config "AI_REVIEW_SMTP_PORT" "465")
        if ($smtpHost) {
            $net = Test-NetConnection $smtpHost -Port $smtpPort -WarningAction SilentlyContinue
            Write-Host "SMTP TcpTestSucceeded=$($net.TcpTestSucceeded) host=$smtpHost port=$smtpPort"
        } else {
            Write-Host "SMTP config missing, skip Test-NetConnection"
        }
    } catch {
        Write-Host "SMTP network test error=$($_.Exception.Message)"
    }
    Write-Host ""

    if ($testAiEnabled) {
        Write-Host "== AI API Test =="
        $baseUrl = (Get-Cfg $config "AI_REVIEW_BASE_URL" "https://api.openai.com/v1").TrimEnd("/")
        if ($baseUrl -notmatch "/chat/completions$") {
            if ($baseUrl -match "/v1$") { $chatUrl = "$baseUrl/chat/completions" } else { $chatUrl = $baseUrl }
        } else {
            $chatUrl = $baseUrl
        }
        $apiKey = Get-Cfg $config "AI_REVIEW_API_KEY"
        $model = Get-Cfg $config "AI_REVIEW_MODEL" "gpt-4o-mini"
        if (-not $apiKey) {
            Write-Host "AI API key missing, skip AI test"
        } else {
            try {
                $headers = @{ Authorization = "Bearer $apiKey"; "Content-Type" = "application/json" }
                $body = @{ model = $model; messages = @(@{ role = "user"; content = "只回复 OK" }); temperature = 0 } | ConvertTo-Json -Depth 6
                $res = Invoke-WebRequest -Uri $chatUrl -Headers $headers -Method Post -Body $body -TimeoutSec 60
                Write-Host "AI status=$($res.StatusCode)"
                Write-Host "AI content-type=$($res.Headers['Content-Type'])"
                $head = $res.Content
                if ($head.Length -gt 500) { $head = $head.Substring(0, 500) + "...<truncated>" }
                Write-Host "AI response head=$head"
            } catch {
                Write-Host "AI test error=$($_.Exception.Message)"
                if ($_.Exception.Response) { Write-Host "AI http status=$([int]$_.Exception.Response.StatusCode)" }
            }
        }
        Write-Host ""
    }

    if ($sendMailEnabled) {
        Write-Host "== SMTP Mail Test =="
        foreach ($item in $config.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($item.Key, $item.Value, "Process")
        }
        @'
import os
import smtplib
from datetime import datetime
from email.message import EmailMessage

host = os.environ.get("AI_REVIEW_SMTP_HOST")
port = int(os.environ.get("AI_REVIEW_SMTP_PORT", "465"))
username = os.environ.get("AI_REVIEW_SMTP_USERNAME")
password = os.environ.get("AI_REVIEW_SMTP_PASSWORD")
sender = os.environ.get("AI_REVIEW_EMAIL_FROM") or username
recipient = os.environ.get("AI_REVIEW_EMAIL_TO")
use_ssl = os.environ.get("AI_REVIEW_SMTP_SSL", "true").lower() == "true"
starttls = os.environ.get("AI_REVIEW_SMTP_STARTTLS", "false").lower() == "true"

print(f"SMTP host={host}")
print(f"SMTP port={port}")
print(f"SMTP from={sender}")
print(f"SMTP to={recipient}")
print(f"SMTP ssl={use_ssl}")
print(f"SMTP starttls={starttls}")

if not host or not sender or not recipient or not username or not password:
    raise SystemExit("missing SMTP config")

msg = EmailMessage()
msg["Subject"] = "AI Review Hook Diagnostic Test"
msg["From"] = sender
msg["To"] = recipient
body = "\n".join([
    "AI Review Hook diagnostic test email.",
    f"Time: {datetime.now().isoformat()}",
    "If you received this email, SMTP config is working.",
])
msg.set_content(body, charset="utf-8", cte="base64")

if use_ssl:
    server = smtplib.SMTP_SSL(host, port, timeout=30)
else:
    server = smtplib.SMTP(host, port, timeout=30)
try:
    if starttls and not use_ssl:
        server.starttls()
    server.login(username, password)
    server.send_message(msg)
    print("SMTP_SEND_OK")
finally:
    try:
        server.quit()
    except Exception:
        pass
'@ | python -
        Write-Host ""
    }

    Write-Host "== Latest Background Job =="
    if (Test-Path .git\ai-review\jobs) {
        $job = Get-ChildItem .git\ai-review\jobs -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($job) {
            Write-Host "job=$($job.FullName)"
            Get-ChildItem $job.FullName | Select-Object Name,Length,LastWriteTime | Format-Table | Out-String | Write-Host
            $bg = Join-Path $job.FullName "background.log"
            if (Test-Path $bg) {
                Write-Host "-- background.log --"
                Get-Content $bg -TotalCount 200
            } else {
                Write-Host "background.log not found"
            }
        } else {
            Write-Host "No job directory found"
        }
    } else {
        Write-Host "No .git\ai-review\jobs directory found"
    }
} finally {
    Stop-Transcript | Out-Null
    Write-Host ""
    Write-Host "Diagnostic log saved to: $logFile"
}
