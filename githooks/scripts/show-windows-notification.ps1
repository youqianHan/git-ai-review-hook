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

function Apply-FlatButtonStyle {
    param(
        [System.Windows.Forms.Button]$Button,
        [System.Drawing.Color]$BaseBack,
        [System.Drawing.Color]$HoverBack,
        [System.Drawing.Color]$Fore
    )

    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 1
    $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(209, 213, 219)
    $Button.BackColor = $BaseBack
    $Button.ForeColor = $Fore
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.Add_MouseEnter({
        param($sender, $e)
        $sender.BackColor = $HoverBack
    })
    $Button.Add_MouseLeave({
        param($sender, $e)
        $sender.BackColor = $BaseBack
    })
}

function Show-ReportWindow {
    $reportText = Get-ReportText

    $viewer = New-Object System.Windows.Forms.Form
    $viewer.Text = "$Title - Report"
    $viewer.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $viewer.MinimumSize = New-Object System.Drawing.Size(800, 560)
    $viewer.Size = New-Object System.Drawing.Size(980, 680)
    $viewer.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $viewer.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

    $shell = New-Object System.Windows.Forms.Panel
    $shell.Dock = [System.Windows.Forms.DockStyle]::Fill
    $shell.Padding = New-Object System.Windows.Forms.Padding(16)
    $shell.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $viewer.Controls.Add($shell)

    $surface = New-Object System.Windows.Forms.Panel
    $surface.Dock = [System.Windows.Forms.DockStyle]::Fill
    $surface.BackColor = [System.Drawing.Color]::White
    $surface.Padding = New-Object System.Windows.Forms.Padding(0)
    $surface.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $shell.Controls.Add($surface)

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = [System.Windows.Forms.DockStyle]::Fill
    $layout.BackColor = [System.Drawing.Color]::White
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 104)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 70)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $surface.Controls.Add($layout)

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
    $viewerTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 15, [System.Drawing.FontStyle]::Bold)
    $viewerTitle.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $viewerTitle.Location = New-Object System.Drawing.Point(20, 18)
    $viewerTitle.Size = New-Object System.Drawing.Size(660, 28)
    $header.Controls.Add($viewerTitle)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = $ReportPath
    $pathLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
    $pathLabel.ForeColor = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $pathLabel.AutoEllipsis = $true
    $pathLabel.Location = New-Object System.Drawing.Point(20, 50)
    $pathLabel.Size = New-Object System.Drawing.Size(($viewer.ClientSize.Width - 220), 20)
    $pathLabel.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $header.Controls.Add($pathLabel)

    $viewerBadge = New-Object System.Windows.Forms.Label
    $viewerBadge.Text = $statusText
    $viewerBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $viewerBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $viewerBadge.ForeColor = $badgeFore
    $viewerBadge.BackColor = $badgeBack
    $viewerBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $viewerBadge.Location = New-Object System.Drawing.Point(($viewer.ClientSize.Width - 112), 22)
    $viewerBadge.Size = New-Object System.Drawing.Size(78, 30)
    $header.Controls.Add($viewerBadge)

    $bodyPanel = New-Object System.Windows.Forms.Panel
    $bodyPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bodyPanel.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
    $bodyPanel.Padding = New-Object System.Windows.Forms.Padding(18)
    $bodyPanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($bodyPanel, 0, 1)

    $bodyFrame = New-Object System.Windows.Forms.Panel
    $bodyFrame.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bodyFrame.BackColor = [System.Drawing.Color]::White
    $bodyFrame.Padding = New-Object System.Windows.Forms.Padding(10)
    $bodyFrame.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $bodyPanel.Controls.Add($bodyFrame)

    $body = New-Object System.Windows.Forms.RichTextBox
    $body.ReadOnly = $true
    $body.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $body.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::ForcedVertical
    $body.WordWrap = $true
    $body.Font = New-Object System.Drawing.Font("Consolas", 10)
    $body.ForeColor = [System.Drawing.Color]::FromArgb(17, 24, 39)
    $body.BackColor = [System.Drawing.Color]::White
    $body.Text = $reportText
    $body.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bodyFrame.Controls.Add($body)

    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = [System.Windows.Forms.DockStyle]::Fill
    $footer.BackColor = [System.Drawing.Color]::White
    $footer.Margin = New-Object System.Windows.Forms.Padding(0)
    $layout.Controls.Add($footer, 0, 2)

    $copyButton = New-Object System.Windows.Forms.Button
    $copyButton.Text = "Copy"
    $copyButton.Size = New-Object System.Drawing.Size(100, 34)
    $copyButton.Location = New-Object System.Drawing.Point(18, 18)
    Apply-FlatButtonStyle -Button $copyButton -BaseBack ([System.Drawing.Color]::White) -HoverBack ([System.Drawing.Color]::FromArgb(243, 244, 246)) -Fore ([System.Drawing.Color]::FromArgb(17, 24, 39))
    $copyButton.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText($body.Text)
    })
    $footer.Controls.Add($copyButton)

    $openFileButton = New-Object System.Windows.Forms.Button
    $openFileButton.Text = "Open file"
    $openFileButton.Size = New-Object System.Drawing.Size(100, 34)
    $openFileButton.Location = New-Object System.Drawing.Point(128, 18)
    Apply-FlatButtonStyle -Button $openFileButton -BaseBack ([System.Drawing.Color]::White) -HoverBack ([System.Drawing.Color]::FromArgb(243, 244, 246)) -Fore ([System.Drawing.Color]::FromArgb(17, 24, 39))
    $openFileButton.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($ReportPath) -and (Test-Path -LiteralPath $ReportPath)) {
            Start-Process -FilePath $ReportPath | Out-Null
        }
    })
    $footer.Controls.Add($openFileButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = "Close"
    $closeButton.Size = New-Object System.Drawing.Size(108, 34)
    $closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $closeButton.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 128), 18)
    Apply-FlatButtonStyle -Button $closeButton -BaseBack ([System.Drawing.Color]::FromArgb(239, 68, 68)) -HoverBack ([System.Drawing.Color]::FromArgb(220, 38, 38)) -Fore ([System.Drawing.Color]::White)
    $closeButton.Add_Click({ $viewer.Close() })
    $footer.Controls.Add($closeButton)

    $header.Add_Resize({
        $viewerBadge.Location = New-Object System.Drawing.Point(($header.ClientSize.Width - 112), 22)
        $pathLabel.Size = New-Object System.Drawing.Size(($header.ClientSize.Width - 220), 20)
    })
    $footer.Add_Resize({
        $closeButton.Location = New-Object System.Drawing.Point(($footer.ClientSize.Width - 128), 18)
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
$badge.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$badge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$badge.ForeColor = $badgeFore
$badge.BackColor = $badgeBack
$badge.AutoSize = $false
$badge.Location = New-Object System.Drawing.Point(280, 14)
$badge.Size = New-Object System.Drawing.Size(70, 26)
$form.Controls.Add($badge)

$close = New-Object System.Windows.Forms.Label
$close.Text = "×"
$close.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$close.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
$close.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
$close.Padding = New-Object System.Windows.Forms.Padding(0)
$close.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$close.AutoSize = $false
$close.Location = New-Object System.Drawing.Point(358, 13)
$close.Size = New-Object System.Drawing.Size(24, 24)
$close.Cursor = [System.Windows.Forms.Cursors]::Hand
$close.Add_MouseEnter({
    param($sender, $e)
    $sender.BackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
    $sender.ForeColor = [System.Drawing.Color]::FromArgb(153, 27, 27)
})
$close.Add_MouseLeave({
    param($sender, $e)
    $sender.BackColor = [System.Drawing.Color]::FromArgb(243, 244, 246)
    $sender.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
})
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
