param(
    [string]$Title = "AI Commit Review",
    [string]$TitleBase64 = "",
    [string]$Message = "Review finished.",
    [string]$MessageBase64 = "",
    [string]$Status = "PASS",
    [string]$ReportPath = "",
    [string]$ReportPathBase64 = "",
    [string]$OpenMode = "native",
    [int]$Seconds = 8
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Decode-Utf8Base64 {
    param(
        [string]$Value,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }

    try {
        $bytes = [Convert]::FromBase64String($Value)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return $Fallback
    }
}

$Title = Decode-Utf8Base64 -Value $TitleBase64 -Fallback $Title
$Message = Decode-Utf8Base64 -Value $MessageBase64 -Fallback $Message
$ReportPath = Decode-Utf8Base64 -Value $ReportPathBase64 -Fallback $ReportPath
$OpenMode = "$OpenMode".Trim().ToLowerInvariant()
if ($OpenMode -ne "file") {
    $OpenMode = "native"
}

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

function Get-ReportText {
    if ([string]::IsNullOrWhiteSpace($ReportPath) -or -not (Test-Path -LiteralPath $ReportPath)) {
        return "Review report file was not found.`r`n`r`nPath: $ReportPath"
    }

    try {
        return [System.IO.File]::ReadAllText($ReportPath, [System.Text.Encoding]::UTF8)
    } catch {
        return "Failed to read review report.`r`n`r`nPath: $ReportPath`r`nError: $($_.Exception.Message)"
    }
}

function Show-ReportWindow {
    $reportText = Get-ReportText

    $viewer = New-Object System.Windows.Forms.Form
    $viewer.Text = "$Title - Report"
    $viewer.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $viewer.MinimumSize = New-Object System.Drawing.Size(720, 520)
    $viewer.Size = New-Object System.Drawing.Size(880, 640)
    $viewer.BackColor = [System.Drawing.Color]::White
    $viewer.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.BackColor = [System.Drawing.Color]::White
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 78)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 58)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $viewer.Controls.Add($layout)

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = [System.Windows.Forms.DockStyle]::Fill
    $header.BackColor = [System.Drawing.Color]::White
    $header.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($header, 0, 0)

    $headerAccent = New-Object System.Windows.Forms.Panel
    $headerAccent.Dock = [System.Windows.Forms.DockStyle]::Left
    $headerAccent.Width = 6
    $headerAccent.BackColor = $accent
    $header.Controls.Add($headerAccent)

    $viewerTitle = New-Object System.Windows.Forms.Label
    $viewerTitle.Text = $Title
    $viewerTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
    $viewerTitle.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $viewerTitle.Location = New-Object System.Drawing.Point(22, 14)
    $viewerTitle.Size = New-Object System.Drawing.Size(560, 24)
    $header.Controls.Add($viewerTitle)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = $ReportPath
    $pathLabel.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 8.5)
    $pathLabel.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $pathLabel.AutoEllipsis = $true
    $pathLabel.Location = New-Object System.Drawing.Point(22, 40)
    $pathLabel.Size = New-Object System.Drawing.Size(($viewer.ClientSize.Width - 170), 20)
    $pathLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $header.Controls.Add($pathLabel)

    $viewerBadge = New-Object System.Windows.Forms.Label
    $viewerBadge.Text = $statusText
    $viewerBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $viewerBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $viewerBadge.ForeColor = $badgeFore
    $viewerBadge.BackColor = $badgeBack
    $viewerBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $viewerBadge.Location = New-Object System.Drawing.Point(($viewer.ClientSize.Width - 102), 18)
    $viewerBadge.Size = New-Object System.Drawing.Size(72, 28)
    $header.Controls.Add($viewerBadge)

    $bodyPanel = New-Object System.Windows.Forms.Panel
    $bodyPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bodyPanel.BackColor = [System.Drawing.Color]::White
    $bodyPanel.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
    $bodyPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($bodyPanel, 0, 1)

    $body = New-Object System.Windows.Forms.TextBox
    $body.Multiline = $true
    $body.ReadOnly = $true
    $body.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $body.WordWrap = $false
    $body.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $body.Font = New-Object System.Drawing.Font("Consolas", 10)
    $body.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $body.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
    $body.Text = $reportText
    $body.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bodyPanel.Controls.Add($body)

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = [System.Windows.Forms.DockStyle]::Fill
    $footer.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
    $footer.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($footer, 0, 2)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = "Copy"
    $copyButton.Size = New-Object System.Drawing.Size(92, 30)
    $copyButton.Location = New-Object System.Drawing.Point(16, 13)
    $copyButton.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($body.Text)
    })
    $footer.Controls.Add($copyButton)

    $openFileButton = New-Object System.Windows.Forms.Button
    $openFileButton.Text = "Open file"
    $openFileButton.Size = New-Object System.Drawing.Size(92, 30)
    $openFileButton.Location = New-Object System.Drawing.Point(116, 13)
    $openFileButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and (Test-Path -LiteralPath $ReportPath)) {
            Start-Process -FilePath $ReportPath | Out-Null
        }
    })
    $footer.Controls.Add($openFileButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Size = New-Object System.Drawing.Size(92, 30)
    $closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $closeButton.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 112), 13)
    $closeButton.Add_Click({ $viewer.Close() })
    $footer.Controls.Add($closeButton)

    $header.Add_Resize({
        $viewerBadge.Location = New-Object System.Drawing.Point(($header.ClientSize.Width - 102), 18)
        $pathLabel.Size = New-Object System.Drawing.Size(($header.ClientSize.Width - 170), 20)
    })
    $footer.Add_Resize({
        $closeButton.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 112), 13)
    })

    [void]$viewer.ShowDialog()
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

$hoverHint = New-Object System.Windows.Forms.Label
$hoverHint.Text = "Hover to keep open"
$hoverHint.Font = New-Object System.Drawing.Font("Segoe UI", 8.25)
$hoverHint.ForeColor = [System.Drawing.Color]::FromArgb(156, 163, 175)
$hoverHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$hoverHint.AutoSize = $false
$hoverHint.Location = New-Object System.Drawing.Point(202, 108)
$hoverHint.Size = New-Object System.Drawing.Size(162, 20)
$form.Controls.Add($hoverHint)

$openReport = {
    if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and (Test-Path -LiteralPath $ReportPath)) {
        $form.Close()
        if ($OpenMode -eq "file") {
            Start-Process -FilePath $ReportPath | Out-Null
        } else {
            Show-ReportWindow
        }
    } elseif ($OpenMode -eq "native") {
        $form.Close()
        Show-ReportWindow
    }
}

foreach ($control in @($form, $titleLabel, $messageLabel, $hint, $hoverHint, $badge)) {
    $control.Cursor = [System.Windows.Forms.Cursors]::Hand
    $control.Add_Click($openReport)
}

$isMouseInside = {
    $point = $form.PointToClient([System.Windows.Forms.Cursor]::Position)
    return ($point.X -ge 0 -and $point.Y -ge 0 -and $point.X -lt $form.Width -and $point.Y -lt $form.Height)
}

$remainingMs = $Seconds * 1000
$lastTick = [Environment]::TickCount
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    $now = [Environment]::TickCount
    $elapsed = $now - $script:lastTick
    $script:lastTick = $now

    if (& $script:isMouseInside) {
        return
    }

    $script:remainingMs -= $elapsed
    if ($script:remainingMs -le 0) {
        $timer.Stop()
        $form.Close()
    }
})

$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosed({
    $timer.Stop()
    $timer.Dispose()
    $form.Dispose()
})

[void]$form.ShowDialog()
