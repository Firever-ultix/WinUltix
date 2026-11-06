# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# MODULAR MAIN LAUNCHER
# ==========================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path -LiteralPath $PSCommandPath)) {
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        Write-Warning "WinUltix requires Administrator privileges. Please launch PowerShell / Terminal as Administrator."
    }
    return
}

$Global:AppVersion = "v3.14"

# ------------------------------------------
# 1. MODULE LOADING (ARCHITECTURE MANIFESTS)
# ------------------------------------------
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$ModulesDir = Join-Path $ScriptDir "Modules"

# Snapshot built-in PowerShell session functions before loading WinUltix modules
$baselineFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($fn in (Get-ChildItem -Path Function:\)) {
    [void]$baselineFunctions.Add($fn.Name)
}

# Core_Helpers: Unified C# P/Invoke runtime (DWM, DPI, Shell, Token Privileges, COM AppActivator, CPU Topology, NtDll Timer/DPC, CfgMgr32 PnpTree), async Runspace engine ($UltixSync), 4-color UI factories, and JSON profile snapshotter.
. (Join-Path $ModulesDir "Core_Helpers.ps1")

# Z1_Cleanup: Deep disk & orphan hygiene (WU/CBS cache, Temp/Dumps, 3rd-party/GPU shader caches, Event Logs, DriverStore OEM INF Sweeper, Windows Installer MSI/MSP Sweeper, Surgical Registry Orphan Sweeper, Ghost Services, and NTFS Recycle Bin).
. (Join-Path $ModulesDir "Z1_Cleanup.ps1")

# Z2_Bloatware: Multi-profile OneDrive amputation, 64-target UWP Bloatware & Windows Recall/Copilot AI removal, FOD Preset, Appx Framework Garbage Collector, CBS Stubs, and 4 manual package/feature inspector grids.
. (Join-Path $ModulesDir "Z2_Bloatware.ps1")

# Z3_Registry: OS Tweaks, Taskbar (with UCPD.sys bypass), native 3-icon Start Menu compiler (with 26H2 Classic List view), File Explorer, Modern Standby S0, 7-Point Power & Display Optimizer, 1:1 Raw Mouse Input, and Extreme Gaming Registry.
. (Join-Path $ModulesDir "Z3_Registry.ps1")

# Z4_Services: Symmetrically revertible Office (Light) and Gaming (Heavy) service profiles, Telemetry Scheduled Tasks lockdown, and 3 interactive managers (System Services, Scheduled Tasks, and Deep Startup Manager).
. (Join-Path $ModulesDir "Z4_Services.ps1")

# Z5_Utilities: Security & Control module. Privacy & UWP AppPrivacy, Boot & UEFI WPBT block, 4-Layer USB Storage & BadUSB/DMA Perimeter Guard, Dual-Layer SRP+IFEO Execution Locks, Hardened DNS + Native DoH Enforcer, and classic Win32 applets.
. (Join-Path $ModulesDir "Z5_Utilities.ps1")

# Z6_Integrity: System First-Aid & OS repair (ChkDisk + DISM + SFC with fast health audit, WinSxS ResetBase compression, WMI repository salvage, Windows Update & CryptSvc reset, Network Stack refresh, Print Spooler First-Aid, and Icon Cache rebuild).
. (Join-Path $ModulesDir "Z6_Integrity.ps1")

# Z7_Hardware: Low-level hardware & latency cockpit (Topology-Aware Affinity Lasso, CPPC Unhider + Dead Man's Switch, Pre-Flight Shortcut, Quantum Scheduler Matrix, MSI & Core 0 IRQ Offload, 0.5ms TSC Timer, USB XHCI Topology Mapper, NVMe/PCIe locks, NDIS/TCP Tuner, WHEA Decoder, and 1Hz DPC Monitor).
. (Join-Path $ModulesDir "Z7_Hardware.ps1")

# Promote only WinUltix toolkit functions to Global scope and register them for Runspace hydration
$Global:UltixToolkitFunctions = [System.Collections.Generic.List[string]]::new()
foreach ($fn in (Get-ChildItem -Path Function:\)) {
    if (-not $baselineFunctions.Contains($fn.Name)) {
        $Global:UltixToolkitFunctions.Add($fn.Name)
        Set-Item -Path "Function:\global:$($fn.Name)" -Value $fn.ScriptBlock -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------
# 2. GLOBAL UI COMPONENTS
# ------------------------------------------
[WinUltix.NativeMethods]::EnableGdiDpiScaling()
[System.Windows.Forms.Application]::EnableVisualStyles()

$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "WinUltix - Ultimate System Toolkit $AppVersion"
$global:form.Size = New-Object System.Drawing.Size(1280, 800)
$global:form.MinimumSize = New-Object System.Drawing.Size(1260, 750)
$global:form.StartPosition = "CenterScreen"
$global:form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$global:form.FormBorderStyle = "Sizable"
$global:form.MaximizeBox = $true
$global:form.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

$global:descBox = New-Object System.Windows.Forms.TextBox
$global:descBox.Multiline = $true; $global:descBox.Location = New-Object System.Drawing.Point(440, 20)
$global:descBox.Size = New-Object System.Drawing.Size(800, 80)
$global:descBox.BackColor = [System.Drawing.Color]::FromArgb(255, 25, 25, 25); $global:descBox.ForeColor = [System.Drawing.Color]::LightSkyBlue; $global:descBox.ReadOnly = $true; $global:descBox.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$global:descBox.Text = "Hover over any button to see operation details."
$global:descBox.Anchor = 'Top, Left, Right'

$global:infoBox = New-Object System.Windows.Forms.RichTextBox
$global:infoBox.Multiline = $true
$global:infoBox.Location = New-Object System.Drawing.Point(440, 110)
$global:infoBox.Size = New-Object System.Drawing.Size(800, 610)
$global:infoBox.BackColor = [System.Drawing.Color]::FromArgb(255, 15, 15, 15)
$global:infoBox.ForeColor = [System.Drawing.Color]::LightGray
$global:infoBox.BorderStyle = "FixedSingle"
$global:infoBox.ReadOnly = $true
$global:infoBox.DetectUrls = $false
$global:infoBox.ScrollBars = "Vertical"
$global:infoBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$global:infoBox.Anchor = 'Top, Bottom, Left, Right'
Write-UltixSystemBanner -StatusMessage "Ready for deployment. Modular architecture loaded successfully."

$global:tabControl = New-Object WinUltix.DarkTabControl
$global:tabControl.Location = New-Object System.Drawing.Point(10, 20)
$global:tabControl.Size = New-Object System.Drawing.Size(410, 700)
$global:tabControl.Anchor = 'Top, Bottom, Left'

$global:progBar = New-Object WinUltix.DarkProgressBar
$global:progBar.Location = New-Object System.Drawing.Point(440, 725)
$global:progBar.Size = New-Object System.Drawing.Size(510, 25)
$global:progBar.Minimum = 0
$global:progBar.Maximum = 100
$global:progBar.Anchor = 'Bottom, Left, Right'

# ------------------------------------------
# 3. MODULE INJECTION (TAB ORDER DEFINED HERE)
# ------------------------------------------
Initialize-Z1UI -TabControl $global:tabControl
Initialize-Z2UI -TabControl $global:tabControl
Initialize-Z3UI -TabControl $global:tabControl
Initialize-Z4UI -TabControl $global:tabControl
Initialize-Z5UI -TabControl $global:tabControl
Initialize-Z6UI -TabControl $global:tabControl
Initialize-Z7UI -TabControl $global:tabControl

# ------------------------------------------
# 4. GLOBAL FOOTER BUTTONS
# ------------------------------------------
$btnExportLog = New-Object System.Windows.Forms.Button
$btnExportLog.Text = "Export Log to Desktop"
$btnExportLog.Location = New-Object System.Drawing.Point(970, 725)
$btnExportLog.Size = New-Object System.Drawing.Size(150, 25)
$btnExportLog.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
$btnExportLog.ForeColor = [System.Drawing.Color]::White
$btnExportLog.FlatStyle = "Flat"
$btnExportLog.Anchor = 'Bottom, Right'
$btnExportLog.Add_Click({ 
    if ($global:infoBox.Text.Length -gt 0) { 
        $desktop = [Environment]::GetFolderPath("Desktop")
        $logPath = "$desktop\WinUltix_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $global:infoBox.Text | Out-File -FilePath $logPath -Encoding UTF8
        Write-GUI "-> Log successfully exported to: $logPath" 
    } else { 
        [System.Windows.Forms.MessageBox]::Show("Log is empty.", "Export Failed") 
    } 
})

$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "[ Clear Log ]"
$btnClearLog.Location = New-Object System.Drawing.Point(1130, 725)
$btnClearLog.Size = New-Object System.Drawing.Size(110, 25)
$btnClearLog.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
$btnClearLog.ForeColor = [System.Drawing.Color]::LightGray
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Anchor = 'Bottom, Right'
$btnClearLog.Add_Click({ 
    $global:infoBox.Clear()
    Write-UltixSystemBanner -StatusMessage "Ready for deployment."
})

$btnCredits = New-Object System.Windows.Forms.Button
$btnCredits.Text = "[ About / GitHub ]"
$btnCredits.Location = New-Object System.Drawing.Point(10, 725)
$btnCredits.Size = New-Object System.Drawing.Size(130, 25)
$btnCredits.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 48)
$btnCredits.ForeColor = [System.Drawing.Color]::LightGray
$btnCredits.FlatStyle = "Flat"
$btnCredits.Anchor = 'Bottom, Left'

$btnCredits.Add_Click({ 
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About WinUltix"
    $aboutForm.Size = New-Object System.Drawing.Size(420, 270)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $aboutForm.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $picLogo = New-Object System.Windows.Forms.PictureBox
    $picLogo.Location = New-Object System.Drawing.Point(20, 22)
    $picLogo.Size = New-Object System.Drawing.Size(64, 64)
    $picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

    $srcLogo = if ($null -ne $global:UltixHighResLogo) {
        $global:UltixHighResLogo
    } elseif ($null -ne $global:UltixAppIcon) {
        $global:UltixAppIcon.ToBitmap()
    } else { $null }

    if ($null -ne $srcLogo) {
        $bmpLogo = New-Object System.Drawing.Bitmap(64, 64, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gLogo   = [System.Drawing.Graphics]::FromImage($bmpLogo)
        $gLogo.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gLogo.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $gLogo.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gLogo.DrawImage($srcLogo, 0, 0, 64, 64)
        $gLogo.Dispose()
        $picLogo.Image = $bmpLogo
    }

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(98, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(295, 24)
    $lblTitle.ForeColor = [System.Drawing.Color]::Cyan
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Text = "WinUltix $AppVersion"

    $lblAbout = New-Object System.Windows.Forms.Label
    $lblAbout.Location = New-Object System.Drawing.Point(98, 46)
    $lblAbout.Size = New-Object System.Drawing.Size(295, 65)
    $lblAbout.ForeColor = [System.Drawing.Color]::LightGray
    $lblAbout.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblAbout.Text = "Ultimate Windows System and Hardware Toolkit`nConcept, architecture and combat tests: Firever`nCoding assistance: Gemini AI"
    
    $linkGit = New-Object System.Windows.Forms.LinkLabel
    $linkGit.Location = New-Object System.Drawing.Point(20, 120)
    $linkGit.Size = New-Object System.Drawing.Size(370, 20)
    $linkGit.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkGit.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkGit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkGit.Text = "https://github.com/Firever-ultix/WinUltix"
    $linkGit.Add_LinkClicked({ Start-Process "https://github.com/Firever-ultix/WinUltix" -ErrorAction SilentlyContinue })
    
    $linkcoffee = New-Object System.Windows.Forms.LinkLabel
    $linkcoffee.Location = New-Object System.Drawing.Point(20, 145)
    $linkcoffee.Size = New-Object System.Drawing.Size(370, 20)
    $linkcoffee.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkcoffee.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkcoffee.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkcoffee.Text = "https://buymeacoffee.com/firever"
    $linkcoffee.Add_LinkClicked({ Start-Process "https://buymeacoffee.com/firever" -ErrorAction SilentlyContinue })
    
    $btnAboutOK = New-Object System.Windows.Forms.Button
    $btnAboutOK.Text = "Close"
    $btnAboutOK.Location = New-Object System.Drawing.Point(160, 185)
    $btnAboutOK.Size = New-Object System.Drawing.Size(90, 28)
    $btnAboutOK.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnAboutOK.ForeColor = [System.Drawing.Color]::White
    $btnAboutOK.FlatStyle = "Flat"
    $btnAboutOK.Add_Click({ $aboutForm.Close() })
    
    $aboutForm.Controls.AddRange(@($picLogo, $lblTitle, $lblAbout, $linkGit, $linkcoffee, $btnAboutOK))
    try {
        [void]$aboutForm.ShowDialog($global:form)
    } finally {
        if ($null -ne $picLogo.Image) { $picLogo.Image.Dispose() }
        $aboutForm.Dispose()
    }
})

$btnExportProfile = New-Object System.Windows.Forms.Button
$btnExportProfile.Text = "[ Export Profile ]"
$btnExportProfile.Location = New-Object System.Drawing.Point(150, 725)
$btnExportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnExportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
$btnExportProfile.ForeColor = [System.Drawing.Color]::White
$btnExportProfile.FlatStyle = "Flat"
$btnExportProfile.Anchor = 'Bottom, Left'
$btnExportProfile.Add_MouseEnter({ Show-Description "Exports your active Registry tweaks, SRP locks, Services state, and Affinity Lasso roster into a portable JSON snapshot." })
$btnExportProfile.Add_MouseLeave({ Restore-Log })
$btnExportProfile.Add_Click({ Export-WinUltixProfile -ControlsToDisable @($btnExportProfile, $btnImportProfile) })

$btnImportProfile = New-Object System.Windows.Forms.Button
$btnImportProfile.Text = "[ Import Profile ]"
$btnImportProfile.Location = New-Object System.Drawing.Point(290, 725)
$btnImportProfile.Size = New-Object System.Drawing.Size(130, 25)
$btnImportProfile.BackColor = [System.Drawing.Color]::FromArgb(255, 135, 50, 50)
$btnImportProfile.ForeColor = [System.Drawing.Color]::White
$btnImportProfile.FlatStyle = "Flat"
$btnImportProfile.Anchor = 'Bottom, Left'
$btnImportProfile.Add_MouseEnter({ Show-Description "Imports and enforces a previously saved WinUltix JSON configuration snapshot on this machine." })
$btnImportProfile.Add_MouseLeave({ Restore-Log })
$btnImportProfile.Add_Click({ Import-WinUltixProfile -ControlsToDisable @($btnExportProfile, $btnImportProfile) })

$global:form.Controls.AddRange(@(
    $btnClearLog, $btnExportLog, $global:progBar, 
    $btnCredits, $btnExportProfile, $btnImportProfile, 
    $global:descBox, $global:tabControl, $global:infoBox
))

# ------------------------------------------
# 5. INITIALIZE AND LAUNCH
# ------------------------------------------
foreach ($tab in $global:tabControl.TabPages) { 
    foreach ($ctrl in $tab.Controls) { 
        if ($ctrl -is [System.Windows.Forms.Button]) {
            $ctrl.Add_MouseLeave({ Restore-Log }) 
        }
    } 
}

$global:form.Add_Shown({
    try {
        $ev = [System.Threading.EventWaitHandle]::OpenExisting("Local\WinUltix_Splash_Close")
        [void]$ev.Set()
        $ev.Dispose()
    } catch { }
    $this.Activate()
})

Update-DNSLabel
try {
    [void]$global:form.ShowDialog()
} finally {
    $global:form.Dispose()
    if ($null -ne $global:UltixHighResLogo) {
        $global:UltixHighResLogo.Dispose()
        $global:UltixHighResLogo = $null
    }
    if ($null -ne $global:UltixAppIcon) {
        $global:UltixAppIcon.Dispose()
        $global:UltixAppIcon = $null
    }
}