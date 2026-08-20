# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# MODULAR MAIN LAUNCHER
# ==========================================
$Global:AppVersion = "v2.5.0"

# ------------------------------------------
# 1. MODULE LOADING (ARCHITECTURE MANIFESTS)
# ------------------------------------------
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
$ModulesDir = Join-Path $ScriptDir "Modules"

# Core_Helpers: Global UI functions, registry engine, and shared modal interfaces.
. (Join-Path $ModulesDir "Core_Helpers.ps1")

# Z1_Cleanup: Deep system cleaning. Removes Windows Update cache, Temp files, Event Viewer logs (wevtutil), and 3rd-party app caches. Enhanced button interactivity and optimized execution flows.
. (Join-Path $ModulesDir "Z1_Cleanup.ps1")

# Z2_Bloatware: Aggressive debloatifier. Incorporates CBS and Appx state verification. Enhanced OneDrive removal across profiles, FOD package management, and intelligent orphaned framework collection (Garbage Collector).
. (Join-Path $ModulesDir "Z2_Bloatware.ps1")

# Z3_Registry: Main registry engine (Invoke-ApplyRegistry) featuring dedicated revert modals. Manages UI tweaks, telemetry blocks, gaming optimizations (VBS/HVCI, GameDVR), and implements Software Restriction Policies (SRP).
. (Join-Path $ModulesDir "Z3_Registry.ps1")

# Z4_Services: Service state management and Task Scheduler control via centralized revert modals. Disables telemetry tasks, configures TCPNoDelay, and enforces strict service operational profiles with improved UI interactivity.
. (Join-Path $ModulesDir "Z4_Services.ps1")

# Z5_Utilities: Interactive tools and applets via Out-GridView for selective package and service management. Includes DNS Enforcer and classic Windows applet launchers.
. (Join-Path $ModulesDir "Z5_Utilities.ps1")

# Z6_Integrity: Advanced repair and reset module. Features WinSXS compression (DISM /ResetBase) with deployment auditing, full network stack refresh, Print Spooler subsystem reset, and core file repairs.
. (Join-Path $ModulesDir "Z6_Integrity.ps1")

# Z7_Hardware: Low-level hardware diagnostics and tuning with interactive modals. Includes Affinity Lasso, CPPC P-State control, MSI Interrupt Enforcer, WHEA APIC decoder, Network NDIS offload tuning, System Timer (TSC) configuration, and NVMe APST/ASPM power management.
. (Join-Path $ModulesDir "Z7_Hardware.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------
# 2. GLOBAL UI COMPONENTS
# ------------------------------------------
$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "WinUltix Pro - Ultimate System Toolkit $AppVersion"
$global:form.Size = New-Object System.Drawing.Size(1200, 800)
$global:form.StartPosition = "CenterScreen"
$global:form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
$global:form.FormBorderStyle = "FixedDialog"
$global:form.MaximizeBox = $false

$global:descBox = New-Object System.Windows.Forms.TextBox
$global:descBox.Multiline = $true; $global:descBox.Location = New-Object System.Drawing.Point(440, 20)
$global:descBox.Size = New-Object System.Drawing.Size(720, 80)
$global:descBox.BackColor = [System.Drawing.Color]::FromArgb(255, 25, 25, 25); $global:descBox.ForeColor = [System.Drawing.Color]::LightSkyBlue; $global:descBox.ReadOnly = $true; $global:descBox.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$global:descBox.Text = "Hover over any button to see operation details."

$global:infoBox = New-Object System.Windows.Forms.TextBox
$global:infoBox.Multiline = $true; $global:infoBox.Location = New-Object System.Drawing.Point(440, 110)
$global:infoBox.Size = New-Object System.Drawing.Size(720, 610)
$global:infoBox.BackColor = [System.Drawing.Color]::FromArgb(255, 15, 15, 15); $global:infoBox.ForeColor = [System.Drawing.Color]::LightGreen; $global:infoBox.ReadOnly = $true; $global:infoBox.ScrollBars = "Vertical"; $global:infoBox.Font = New-Object System.Drawing.Font("Consolas", 10)

$global:LastLog = "--- WINULTIX PRO ---`r`n`r`nReady for deployment. Modular architecture loaded successfully.`r`n"
$global:infoBox.Text = $global:LastLog

$global:tabControl = New-Object System.Windows.Forms.TabControl
$global:tabControl.Location = New-Object System.Drawing.Point(10, 20)
$global:tabControl.Size = New-Object System.Drawing.Size(410, 700)

$global:progBar = New-Object System.Windows.Forms.ProgressBar
$global:progBar.Location = New-Object System.Drawing.Point(440, 725)
$global:progBar.Size = New-Object System.Drawing.Size(400, 25)
$global:progBar.Style = "Continuous"
$global:progBar.Minimum = 0
$global:progBar.Maximum = 100

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
$btnExportLog.Location = New-Object System.Drawing.Point(890, 725)
$btnExportLog.Size = New-Object System.Drawing.Size(150, 25)
$btnExportLog.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
$btnExportLog.ForeColor = [System.Drawing.Color]::White
$btnExportLog.FlatStyle = "Flat"
$btnExportLog.Add_Click({ 
    if ($global:infoBox.Text -ne "") { 
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
$btnClearLog.Location = New-Object System.Drawing.Point(1050, 725)
$btnClearLog.Size = New-Object System.Drawing.Size(110, 25)
$btnClearLog.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$btnClearLog.ForeColor = [System.Drawing.Color]::LightGray
$btnClearLog.FlatStyle = "Flat"
$btnClearLog.Add_Click({ 
    $global:LastLog = "--- WINULTIX PRO ---`r`n`r`nReady for deployment."
    $global:infoBox.Text = $global:LastLog 
})

$btnCredits = New-Object System.Windows.Forms.Button
$btnCredits.Text = "[ About / GitHub ]"
$btnCredits.Location = New-Object System.Drawing.Point(10, 730)
$btnCredits.Size = New-Object System.Drawing.Size(140, 25)
$btnCredits.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 40)
$btnCredits.ForeColor = [System.Drawing.Color]::LightGray
$btnCredits.FlatStyle = "Flat"
$btnCredits.Add_Click({ 
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About WinUltix Pro"
    $aboutForm.Size = New-Object System.Drawing.Size(380, 265)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    
    $lblAbout = New-Object System.Windows.Forms.Label
    $lblAbout.Location = New-Object System.Drawing.Point(20, 20)
    $lblAbout.Size = New-Object System.Drawing.Size(340, 80)
    $lblAbout.ForeColor = [System.Drawing.Color]::LightGray
    $lblAbout.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblAbout.Text = "WinUltix Pro - Ultimate System Toolkit $AppVersion`n`nConcept, architecture and combat tests: Firever`nCoding assistance: Gemini AI`n`nLet your hardware breathe!"
    
    $linkGit = New-Object System.Windows.Forms.LinkLabel
    $linkGit.Location = New-Object System.Drawing.Point(20, 115)
    $linkGit.Size = New-Object System.Drawing.Size(340, 20)
    $linkGit.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkGit.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkGit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkGit.Text = "https://github.com/Firever-ultix/WinUltix"
    $linkGit.Add_LinkClicked({ Start-Process "https://github.com/Firever-ultix/WinUltix" -ErrorAction SilentlyContinue })
    
    $linkcoffee = New-Object System.Windows.Forms.LinkLabel
    $linkcoffee.Location = New-Object System.Drawing.Point(20, 140)
    $linkcoffee.Size = New-Object System.Drawing.Size(340, 20)
    $linkcoffee.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkcoffee.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkcoffee.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkcoffee.Text = "https://buymeacoffee.com/firever"
    $linkcoffee.Add_LinkClicked({ Start-Process "https://buymeacoffee.com/firever" -ErrorAction SilentlyContinue })
    
    $btnAboutOK = New-Object System.Windows.Forms.Button
    $btnAboutOK.Text = "Close"
    $btnAboutOK.Location = New-Object System.Drawing.Point(140, 185)
    $btnAboutOK.Size = New-Object System.Drawing.Size(80, 25)
    $btnAboutOK.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnAboutOK.ForeColor = [System.Drawing.Color]::White
    $btnAboutOK.FlatStyle = "Flat"
    $btnAboutOK.Add_Click({ $aboutForm.Close() })
    
    $aboutForm.Controls.AddRange(@($lblAbout, $linkGit, $linkcoffee, $btnAboutOK))
    [void]$aboutForm.ShowDialog()
})

$global:form.Controls.AddRange(@($btnClearLog, $btnExportLog, $global:progBar, $btnCredits, $global:descBox, $global:tabControl, $global:infoBox))

# ------------------------------------------
# 5. INITIALIZE AND LAUNCH
# ------------------------------------------
foreach ($tab in $global:tabControl.TabPages) { 
    foreach ($btn in $tab.Controls) { 
        $btn.Add_MouseLeave({ Restore-Log }) 
    } 
}

Update-DNSLabel
[void]$global:form.ShowDialog()