param(
    [string]$Title = "AI Commit Review",
    [string]$Message = "Review finished.",
    [string]$Status = "PASS",
    [string]$ReportPath = "",
    [int]$Seconds = 8
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($Seconds -lt 2) {
    $Seconds = 2
}

$statusText = ($Status | ForEach-Object { "$_".Trim().ToUpperInvariant() })
if ([string]::IsNullOrWhiteSpace($statusText)) {
    $statusText = "PASS"
}

switch ($statusText) {
    "FAIL" {
        $accent = [System.Drawing.Color]::FromArgb(220, 38, 38)
        $badgeBack = [System.Drawing.Color]::FromArgb(254, 242, 242)
        $badgeFore = [System.Drawing.Color]::FromArgb(185, 28, 28)
    }
    "ERROR" {
        $accent = [System.Drawing.Color]::FromArgb(234, 88, 12)
        $badgeBack = [System.Drawing.Color]::FromArgb(255, 247, 237)
        $badgeFore = [System.Drawing.Color]::FromArgb(194, 65, 12)
    }
    default {
        $accent = [System.Drawing.Color]::FromArgb(22, 163, 74)
        $badgeBack = [System.Drawing.Color]::FromArgb(240, 253, 244)
        $badgeFore = [System.Drawing.Color]::FromArgb(21, 128, 61)
        $statusText = "PASS"
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $Title
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.Width = 390
$form.Height = 146
$form.BackColor = [System.Drawing.Color]::White
$form.Padding = New-Object System.Windows.Forms.Padding(0)

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location = New-Object System.Drawing.Point(
    ($screen.Right - $form.Width - 18),
    ($screen.Bottom - $form.Height - 18)
)

$accentBar = New-Object System.Windows.Forms.Panel
$accentBar.BackColor = $accent
$accentBar.Dock = [System.Windows.Forms.DockStyle]::Left
$accentBar.Width = 6
$form.Controls.Add($accentBar)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = $Title
$titleLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10.5, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
$titleLabel.AutoSize = $false
$titleLabel.Location = New-Object System.Drawing.Point(22, 16)
$titleLabel.Size = New-Object System.Drawing.Size(260, 24)
$form.Controls.Add($titleLabel)

$badge = New-Object System.Windows.Forms.Label
$badge.Text = $statusText
$badge.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$badge.ForeColor = $badgeFore
$badge.BackColor = $badgeBack
$badge.AutoSize = $false
$badge.Location = New-Object System.Drawing.Point(288, 16)
$badge.Size = New-Object System.Drawing.Size(58, 24)
$form.Controls.Add($badge)

$close = New-Object System.Windows.Forms.Label
$close.Text = "x"
$close.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
$close.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
$close.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$close.AutoSize = $false
$close.Location = New-Object System.Drawing.Point(356, 14)
$close.Size = New-Object System.Drawing.Size(22, 24)
$close.Cursor = [System.Windows.Forms.Cursors]::Hand
$close.Add_Click({ $form.Close() })
$form.Controls.Add($close)

$messageLabel = New-Object System.Windows.Forms.Label
$messageLabel.Text = $Message
$messageLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$messageLabel.ForeColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
$messageLabel.AutoEllipsis = $true
$messageLabel.AutoSize = $false
$messageLabel.Location = New-Object System.Drawing.Point(22, 52)
$messageLabel.Size = New-Object System.Drawing.Size(342, 48)
$form.Controls.Add($messageLabel)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "Click to open report"
$hint.Font = New-Object System.Drawing.Font("Segoe UI", 8.25)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
$hint.AutoSize = $false
$hint.Location = New-Object System.Drawing.Point(22, 108)
$hint.Size = New-Object System.Drawing.Size(180, 20)
$form.Controls.Add($hint)

$openReport = {
    if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and (Test-Path -LiteralPath $ReportPath)) {
        Start-Process -FilePath $ReportPath | Out-Null
        $form.Close()
    }
}

foreach ($control in @($form, $titleLabel, $messageLabel, $hint, $badge)) {
    $control.Cursor = [System.Windows.Forms.Cursors]::Hand
    $control.Add_Click($openReport)
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $Seconds * 1000
$timer.Add_Tick({
    $timer.Stop()
    $form.Close()
})

$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosed({
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()
})

[void]$form.ShowDialog()
