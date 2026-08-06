# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT (EN)
# ==========================================
$Global:AppVersion = "v1.1.0"

# Loading the main engine, audit, and rescue modules
. "$PSScriptRoot\Optimizer_Core_EN.ps1"
. "$PSScriptRoot\Optimizer_Audit_EN.ps1"
. "$PSScriptRoot\Optimizer_Restore_EN.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==========================================
# MAIN APPLICATION WINDOW
# ==========================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "WinUltix Pro - Ultimate System Toolkit $AppVersion"
$form.Size = New-Object System.Drawing.Size(1200, 800)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

$descBox = New-Object System.Windows.Forms.TextBox
$descBox.Multiline = $true; $descBox.Location = New-Object System.Drawing.Point(440, 20); 
$descBox.Size = New-Object System.Drawing.Size(720, 80); 
$descBox.BackColor = [System.Drawing.Color]::FromArgb(255, 25, 25, 25); $descBox.ForeColor = [System.Drawing.Color]::LightSkyBlue; $descBox.ReadOnly = $true; $descBox.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Italic)
$descBox.Text = "Hover over any button to see operation details."

$infoBox = New-Object System.Windows.Forms.TextBox
$infoBox.Multiline = $true; $infoBox.Location = New-Object System.Drawing.Point(440, 110); 
$infoBox.Size = New-Object System.Drawing.Size(720, 610); 
$infoBox.BackColor = [System.Drawing.Color]::FromArgb(255, 15, 15, 15); $infoBox.ForeColor = [System.Drawing.Color]::LightGreen; $infoBox.ReadOnly = $true; $infoBox.ScrollBars = "Vertical"; $infoBox.Font = New-Object System.Drawing.Font("Consolas", 10)

$global:LastLog = "--- WINULTIX PRO ---`r`n`r`nReady for deployment. Architecture loaded successfully.`r`n"
$infoBox.Text = $global:LastLog

function Write-GUI { param([string]$Message); if ($Message -eq "") { $global:LastLog += "`r`n" } else { $global:LastLog += "`r`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }; $infoBox.Text = $global:LastLog; $infoBox.SelectionStart = $infoBox.Text.Length; $infoBox.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents() }
function Show-Description { param([string]$Desc); $descBox.Text = $Desc -replace "`n", "`r`n" }
function Restore-Log { $descBox.Text = "Hover over any button to see operation details." }

$tabControl = New-Object System.Windows.Forms.TabControl; $tabControl.Location = New-Object System.Drawing.Point(10, 20); $tabControl.Size = New-Object System.Drawing.Size(410, 560)

$tabClean = New-Object System.Windows.Forms.TabPage; $tabClean.Text = "Cleanup"; $tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$tabApps = New-Object System.Windows.Forms.TabPage; $tabApps.Text = "Bloatware"; $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$tabReg = New-Object System.Windows.Forms.TabPage; $tabReg.Text = "Registry"; $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$tabServices = New-Object System.Windows.Forms.TabPage; $tabServices.Text = "Services"; $tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$tabUtil = New-Object System.Windows.Forms.TabPage; $tabUtil.Text = "Utilities"; $tabUtil.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
$tabWinSXS = New-Object System.Windows.Forms.TabPage; $tabWinSXS.Text = "Integrity"; $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

# Z1: Cleanup
$btnWU = New-Object System.Windows.Forms.Button; $btnWU.Text = "Clean Windows Update Cache"; $btnWU.Location = New-Object System.Drawing.Point(15, 20); $btnWU.Size = New-Object System.Drawing.Size(320, 40); $btnWU.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnWU.ForeColor = [System.Drawing.Color]::White; $btnWU.FlatStyle = "Flat"
$btnAudWU = New-Object System.Windows.Forms.Button; $btnAudWU.Text = "?"; $btnAudWU.Location = New-Object System.Drawing.Point(345, 20); $btnAudWU.Size = New-Object System.Drawing.Size(40, 40); $btnAudWU.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudWU.ForeColor = [System.Drawing.Color]::White; $btnAudWU.FlatStyle = "Flat"
$btnTemp = New-Object System.Windows.Forms.Button; $btnTemp.Text = "Clean Temp & Prefetch Buffers"; $btnTemp.Location = New-Object System.Drawing.Point(15, 70); $btnTemp.Size = New-Object System.Drawing.Size(320, 40); $btnTemp.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnTemp.ForeColor = [System.Drawing.Color]::White; $btnTemp.FlatStyle = "Flat"
$btnAudTemp = New-Object System.Windows.Forms.Button; $btnAudTemp.Text = "?"; $btnAudTemp.Location = New-Object System.Drawing.Point(345, 70); $btnAudTemp.Size = New-Object System.Drawing.Size(40, 40); $btnAudTemp.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudTemp.ForeColor = [System.Drawing.Color]::White; $btnAudTemp.FlatStyle = "Flat"
$btnLogs = New-Object System.Windows.Forms.Button; $btnLogs.Text = "Clear Event Viewer Logs"; $btnLogs.Location = New-Object System.Drawing.Point(15, 120); $btnLogs.Size = New-Object System.Drawing.Size(320, 40); $btnLogs.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnLogs.ForeColor = [System.Drawing.Color]::White; $btnLogs.FlatStyle = "Flat"
$btnAudLogs = New-Object System.Windows.Forms.Button; $btnAudLogs.Text = "?"; $btnAudLogs.Location = New-Object System.Drawing.Point(345, 120); $btnAudLogs.Size = New-Object System.Drawing.Size(40, 40); $btnAudLogs.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudLogs.ForeColor = [System.Drawing.Color]::White; $btnAudLogs.FlatStyle = "Flat"
$btnThirdParty = New-Object System.Windows.Forms.Button; $btnThirdParty.Text = "Clean Third-Party App Cache"; $btnThirdParty.Location = New-Object System.Drawing.Point(15, 170); $btnThirdParty.Size = New-Object System.Drawing.Size(320, 40); $btnThirdParty.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnThirdParty.ForeColor = [System.Drawing.Color]::White; $btnThirdParty.FlatStyle = "Flat"
$btnAudThirdParty = New-Object System.Windows.Forms.Button; $btnAudThirdParty.Text = "?"; $btnAudThirdParty.Location = New-Object System.Drawing.Point(345, 170); $btnAudThirdParty.Size = New-Object System.Drawing.Size(40, 40); $btnAudThirdParty.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudThirdParty.ForeColor = [System.Drawing.Color]::White; $btnAudThirdParty.FlatStyle = "Flat"
$btnRecycle = New-Object System.Windows.Forms.Button; $btnRecycle.Text = "Hard Empty Recycle Bin (NTFS)"; $btnRecycle.Location = New-Object System.Drawing.Point(15, 220); $btnRecycle.Size = New-Object System.Drawing.Size(320, 40); $btnRecycle.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40); $btnRecycle.ForeColor = [System.Drawing.Color]::White; $btnRecycle.FlatStyle = "Flat"
$btnAudRecycle = New-Object System.Windows.Forms.Button; $btnAudRecycle.Text = "?"; $btnAudRecycle.Location = New-Object System.Drawing.Point(345, 220); $btnAudRecycle.Size = New-Object System.Drawing.Size(40, 40); $btnAudRecycle.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40); $btnAudRecycle.ForeColor = [System.Drawing.Color]::White; $btnAudRecycle.FlatStyle = "Flat"
$tabClean.Controls.AddRange(@($btnWU, $btnAudWU, $btnTemp, $btnAudTemp, $btnLogs, $btnAudLogs, $btnThirdParty, $btnAudThirdParty, $btnRecycle, $btnAudRecycle))

# Z2: Bloatware
$btnOneDrive = New-Object System.Windows.Forms.Button; $btnOneDrive.Text = "Uninstall & Deprovision OneDrive"; $btnOneDrive.Location = New-Object System.Drawing.Point(15, 20); $btnOneDrive.Size = New-Object System.Drawing.Size(320, 40); $btnOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 100); $btnOneDrive.ForeColor = [System.Drawing.Color]::White; $btnOneDrive.FlatStyle = "Flat"
$btnAudOneDrive = New-Object System.Windows.Forms.Button; $btnAudOneDrive.Text = "?"; $btnAudOneDrive.Location = New-Object System.Drawing.Point(345, 20); $btnAudOneDrive.Size = New-Object System.Drawing.Size(40, 40); $btnAudOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudOneDrive.ForeColor = [System.Drawing.Color]::White; $btnAudOneDrive.FlatStyle = "Flat"
$btnCaps = New-Object System.Windows.Forms.Button; $btnCaps.Text = "Remove System Features (FOD)"; $btnCaps.Location = New-Object System.Drawing.Point(15, 70); $btnCaps.Size = New-Object System.Drawing.Size(320, 40); $btnCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnCaps.ForeColor = [System.Drawing.Color]::White; $btnCaps.FlatStyle = "Flat"
$btnAudCaps = New-Object System.Windows.Forms.Button; $btnAudCaps.Text = "?"; $btnAudCaps.Location = New-Object System.Drawing.Point(345, 70); $btnAudCaps.Size = New-Object System.Drawing.Size(40, 40); $btnAudCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudCaps.ForeColor = [System.Drawing.Color]::White; $btnAudCaps.FlatStyle = "Flat"
$btnBloat = New-Object System.Windows.Forms.Button; $btnBloat.Text = "Aggressive Bloatware Removal (Appx)"; $btnBloat.Location = New-Object System.Drawing.Point(15, 120); $btnBloat.Size = New-Object System.Drawing.Size(320, 40); $btnBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnBloat.ForeColor = [System.Drawing.Color]::White; $btnBloat.FlatStyle = "Flat"
$btnAudBloat = New-Object System.Windows.Forms.Button; $btnAudBloat.Text = "?"; $btnAudBloat.Location = New-Object System.Drawing.Point(345, 120); $btnAudBloat.Size = New-Object System.Drawing.Size(40, 40); $btnAudBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudBloat.ForeColor = [System.Drawing.Color]::White; $btnAudBloat.FlatStyle = "Flat"
$btnGC = New-Object System.Windows.Forms.Button; $btnGC.Text = "Run Appx Garbage Collector"; $btnGC.Location = New-Object System.Drawing.Point(15, 170); $btnGC.Size = New-Object System.Drawing.Size(320, 40); $btnGC.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 80, 40); $btnGC.ForeColor = [System.Drawing.Color]::White; $btnGC.FlatStyle = "Flat"
$btnAudGC = New-Object System.Windows.Forms.Button; $btnAudGC.Text = "?"; $btnAudGC.Location = New-Object System.Drawing.Point(345, 170); $btnAudGC.Size = New-Object System.Drawing.Size(40, 40); $btnAudGC.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudGC.ForeColor = [System.Drawing.Color]::White; $btnAudGC.FlatStyle = "Flat"
$tabApps.Controls.AddRange(@($btnOneDrive, $btnAudOneDrive, $btnCaps, $btnAudCaps, $btnBloat, $btnAudBloat, $btnGC, $btnAudGC))


# Z3: Registry
$btnRegTaskbar = New-Object System.Windows.Forms.Button; $btnRegTaskbar.Text = "Taskbar & Start Menu"; $btnRegTaskbar.Location = New-Object System.Drawing.Point(15, 20); $btnRegTaskbar.Size = New-Object System.Drawing.Size(320, 40); $btnRegTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnRegTaskbar.ForeColor = [System.Drawing.Color]::White; $btnRegTaskbar.FlatStyle = "Flat"
$btnAudTaskbar = New-Object System.Windows.Forms.Button; $btnAudTaskbar.Text = "?"; $btnAudTaskbar.Location = New-Object System.Drawing.Point(345, 20); $btnAudTaskbar.Size = New-Object System.Drawing.Size(40, 40); $btnAudTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudTaskbar.ForeColor = [System.Drawing.Color]::White; $btnAudTaskbar.FlatStyle = "Flat"
$btnRegExplorer = New-Object System.Windows.Forms.Button; $btnRegExplorer.Text = "File Explorer & Context Menu"; $btnRegExplorer.Location = New-Object System.Drawing.Point(15, 70); $btnRegExplorer.Size = New-Object System.Drawing.Size(320, 40); $btnRegExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnRegExplorer.ForeColor = [System.Drawing.Color]::White; $btnRegExplorer.FlatStyle = "Flat"
$btnAudExplorer = New-Object System.Windows.Forms.Button; $btnAudExplorer.Text = "?"; $btnAudExplorer.Location = New-Object System.Drawing.Point(345, 70); $btnAudExplorer.Size = New-Object System.Drawing.Size(40, 40); $btnAudExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudExplorer.ForeColor = [System.Drawing.Color]::White; $btnAudExplorer.FlatStyle = "Flat"
$btnRegAnnoyances = New-Object System.Windows.Forms.Button; $btnRegAnnoyances.Text = "OS Annoyances (AutoRun / Sticky Keys)"; $btnRegAnnoyances.Location = New-Object System.Drawing.Point(15, 120); $btnRegAnnoyances.Size = New-Object System.Drawing.Size(320, 40); $btnRegAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnRegAnnoyances.ForeColor = [System.Drawing.Color]::White; $btnRegAnnoyances.FlatStyle = "Flat"
$btnAudAnnoyances = New-Object System.Windows.Forms.Button; $btnAudAnnoyances.Text = "?"; $btnAudAnnoyances.Location = New-Object System.Drawing.Point(345, 120); $btnAudAnnoyances.Size = New-Object System.Drawing.Size(40, 40); $btnAudAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudAnnoyances.ForeColor = [System.Drawing.Color]::White; $btnAudAnnoyances.FlatStyle = "Flat"
$btnRegPrivacy = New-Object System.Windows.Forms.Button; $btnRegPrivacy.Text = "Privacy & Background Apps (AppPrivacy)"; $btnRegPrivacy.Location = New-Object System.Drawing.Point(15, 170); $btnRegPrivacy.Size = New-Object System.Drawing.Size(320, 40); $btnRegPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnRegPrivacy.ForeColor = [System.Drawing.Color]::White; $btnRegPrivacy.FlatStyle = "Flat"
$btnAudPrivacy = New-Object System.Windows.Forms.Button; $btnAudPrivacy.Text = "?"; $btnAudPrivacy.Location = New-Object System.Drawing.Point(345, 170); $btnAudPrivacy.Size = New-Object System.Drawing.Size(40, 40); $btnAudPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudPrivacy.ForeColor = [System.Drawing.Color]::White; $btnAudPrivacy.FlatStyle = "Flat"
$btnRegSystemBoot = New-Object System.Windows.Forms.Button; $btnRegSystemBoot.Text = "Boot & WPBT (BIOS/UEFI Block)"; $btnRegSystemBoot.Location = New-Object System.Drawing.Point(15, 220); $btnRegSystemBoot.Size = New-Object System.Drawing.Size(320, 40); $btnRegSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnRegSystemBoot.ForeColor = [System.Drawing.Color]::White; $btnRegSystemBoot.FlatStyle = "Flat"
$btnAudSystemBoot = New-Object System.Windows.Forms.Button; $btnAudSystemBoot.Text = "?"; $btnAudSystemBoot.Location = New-Object System.Drawing.Point(345, 220); $btnAudSystemBoot.Size = New-Object System.Drawing.Size(40, 40); $btnAudSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudSystemBoot.ForeColor = [System.Drawing.Color]::White; $btnAudSystemBoot.FlatStyle = "Flat"
$btnRegMouse = New-Object System.Windows.Forms.Button; $btnRegMouse.Text = "Hard Mouse Acceleration Disable (Raw Input)"; $btnRegMouse.Location = New-Object System.Drawing.Point(15, 280); $btnRegMouse.Size = New-Object System.Drawing.Size(320, 40); $btnRegMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRegMouse.ForeColor = [System.Drawing.Color]::White; $btnRegMouse.FlatStyle = "Flat"
$btnAudMouse = New-Object System.Windows.Forms.Button; $btnAudMouse.Text = "?"; $btnAudMouse.Location = New-Object System.Drawing.Point(345, 280); $btnAudMouse.Size = New-Object System.Drawing.Size(40, 40); $btnAudMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnAudMouse.ForeColor = [System.Drawing.Color]::White; $btnAudMouse.FlatStyle = "Flat"
$btnRegGaming = New-Object System.Windows.Forms.Button; $btnRegGaming.Text = "Hardware & Gaming (Extreme)"; $btnRegGaming.Location = New-Object System.Drawing.Point(15, 330); $btnRegGaming.Size = New-Object System.Drawing.Size(320, 40); $btnRegGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnRegGaming.ForeColor = [System.Drawing.Color]::White; $btnRegGaming.FlatStyle = "Flat"
$btnAudGaming = New-Object System.Windows.Forms.Button; $btnAudGaming.Text = "?"; $btnAudGaming.Location = New-Object System.Drawing.Point(345, 330); $btnAudGaming.Size = New-Object System.Drawing.Size(40, 40); $btnAudGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnAudGaming.ForeColor = [System.Drawing.Color]::White; $btnAudGaming.FlatStyle = "Flat"
$lblRescueReg = New-Object System.Windows.Forms.Label; $lblRescueReg.Text = "--- RESCUE OPTIONS ---"; $lblRescueReg.Location = New-Object System.Drawing.Point(15, 420); $lblRescueReg.Size = New-Object System.Drawing.Size(370, 20); $lblRescueReg.ForeColor = [System.Drawing.Color]::DarkOrange
$btnRestoreReg = New-Object System.Windows.Forms.Button; $btnRestoreReg.Text = "Revert Changes & Restore Default Registry"; $btnRestoreReg.Location = New-Object System.Drawing.Point(15, 445); $btnRestoreReg.Size = New-Object System.Drawing.Size(370, 40); $btnRestoreReg.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 20); $btnRestoreReg.ForeColor = [System.Drawing.Color]::White; $btnRestoreReg.FlatStyle = "Flat"
$tabReg.Controls.AddRange(@($btnRegTaskbar, $btnAudTaskbar, $btnRegExplorer, $btnAudExplorer, $btnRegAnnoyances, $btnAudAnnoyances, $btnRegPrivacy, $btnAudPrivacy, $btnRegSystemBoot, $btnAudSystemBoot, $btnRegMouse, $btnAudMouse, $btnRegGaming, $btnAudGaming, $lblRescueReg, $btnRestoreReg))

# Z4: Services
$btnTelemetry = New-Object System.Windows.Forms.Button; $btnTelemetry.Text = "Disable Telemetry Tasks (Scheduler)"; $btnTelemetry.Location = New-Object System.Drawing.Point(15, 20); $btnTelemetry.Size = New-Object System.Drawing.Size(320, 40); $btnTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnTelemetry.ForeColor = [System.Drawing.Color]::White; $btnTelemetry.FlatStyle = "Flat"
$btnAudTelemetry = New-Object System.Windows.Forms.Button; $btnAudTelemetry.Text = "?"; $btnAudTelemetry.Location = New-Object System.Drawing.Point(345, 20); $btnAudTelemetry.Size = New-Object System.Drawing.Size(40, 40); $btnAudTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudTelemetry.ForeColor = [System.Drawing.Color]::White; $btnAudTelemetry.FlatStyle = "Flat"
$btnStartMenu = New-Object System.Windows.Forms.Button; $btnStartMenu.Text = "Reset Start Menu Layout (Unpin All)"; $btnStartMenu.Location = New-Object System.Drawing.Point(15, 70); $btnStartMenu.Size = New-Object System.Drawing.Size(320, 40); $btnStartMenu.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnStartMenu.ForeColor = [System.Drawing.Color]::White; $btnStartMenu.FlatStyle = "Flat"
$btnAudStartMenu = New-Object System.Windows.Forms.Button; $btnAudStartMenu.Text = "?"; $btnAudStartMenu.Location = New-Object System.Drawing.Point(345, 70); $btnAudStartMenu.Size = New-Object System.Drawing.Size(40, 40); $btnAudStartMenu.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudStartMenu.ForeColor = [System.Drawing.Color]::White; $btnAudStartMenu.FlatStyle = "Flat"
$btnPower = New-Object System.Windows.Forms.Button; $btnPower.Text = "Optimize Power & Display"; $btnPower.Location = New-Object System.Drawing.Point(15, 120); $btnPower.Size = New-Object System.Drawing.Size(320, 40); $btnPower.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnPower.ForeColor = [System.Drawing.Color]::White; $btnPower.FlatStyle = "Flat"
$btnAudPower = New-Object System.Windows.Forms.Button; $btnAudPower.Text = "?"; $btnAudPower.Location = New-Object System.Drawing.Point(345, 120); $btnAudPower.Size = New-Object System.Drawing.Size(40, 40); $btnAudPower.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudPower.ForeColor = [System.Drawing.Color]::White; $btnAudPower.FlatStyle = "Flat"
$btnNetwork = New-Object System.Windows.Forms.Button; $btnNetwork.Text = "Reduce Network Latency (TCP NoDelay)"; $btnNetwork.Location = New-Object System.Drawing.Point(15, 170); $btnNetwork.Size = New-Object System.Drawing.Size(320, 40); $btnNetwork.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnNetwork.ForeColor = [System.Drawing.Color]::White; $btnNetwork.FlatStyle = "Flat"
$btnAudNetwork = New-Object System.Windows.Forms.Button; $btnAudNetwork.Text = "?"; $btnAudNetwork.Location = New-Object System.Drawing.Point(345, 170); $btnAudNetwork.Size = New-Object System.Drawing.Size(40, 40); $btnAudNetwork.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudNetwork.ForeColor = [System.Drawing.Color]::White; $btnAudNetwork.FlatStyle = "Flat"
$btnSvcLight = New-Object System.Windows.Forms.Button; $btnSvcLight.Text = "Background Services: OFFICE PROFILE"; $btnSvcLight.Location = New-Object System.Drawing.Point(15, 230); $btnSvcLight.Size = New-Object System.Drawing.Size(320, 40); $btnSvcLight.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnSvcLight.ForeColor = [System.Drawing.Color]::White; $btnSvcLight.FlatStyle = "Flat"
$btnAudSvcLight = New-Object System.Windows.Forms.Button; $btnAudSvcLight.Text = "?"; $btnAudSvcLight.Location = New-Object System.Drawing.Point(345, 230); $btnAudSvcLight.Size = New-Object System.Drawing.Size(40, 40); $btnAudSvcLight.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudSvcLight.ForeColor = [System.Drawing.Color]::White; $btnAudSvcLight.FlatStyle = "Flat"
$btnSvcHeavy = New-Object System.Windows.Forms.Button; $btnSvcHeavy.Text = "Background Services: GAMING PROFILE"; $btnSvcHeavy.Location = New-Object System.Drawing.Point(15, 280); $btnSvcHeavy.Size = New-Object System.Drawing.Size(320, 40); $btnSvcHeavy.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnSvcHeavy.ForeColor = [System.Drawing.Color]::White; $btnSvcHeavy.FlatStyle = "Flat"
$btnAudSvcHeavy = New-Object System.Windows.Forms.Button; $btnAudSvcHeavy.Text = "?"; $btnAudSvcHeavy.Location = New-Object System.Drawing.Point(345, 280); $btnAudSvcHeavy.Size = New-Object System.Drawing.Size(40, 40); $btnAudSvcHeavy.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80); $btnAudSvcHeavy.ForeColor = [System.Drawing.Color]::White; $btnAudSvcHeavy.FlatStyle = "Flat"
$lblRescueSvc = New-Object System.Windows.Forms.Label; $lblRescueSvc.Text = "--- RESCUE OPTIONS ---"; $lblRescueSvc.Location = New-Object System.Drawing.Point(15, 420); $lblRescueSvc.Size = New-Object System.Drawing.Size(370, 20); $lblRescueSvc.ForeColor = [System.Drawing.Color]::DarkOrange
$btnRestoreSvc = New-Object System.Windows.Forms.Button; $btnRestoreSvc.Text = "Revert Restrictions & Restore Default Services"; $btnRestoreSvc.Location = New-Object System.Drawing.Point(15, 445); $btnRestoreSvc.Size = New-Object System.Drawing.Size(370, 40); $btnRestoreSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 20); $btnRestoreSvc.ForeColor = [System.Drawing.Color]::White; $btnRestoreSvc.FlatStyle = "Flat"
$tabServices.Controls.AddRange(@($btnTelemetry, $btnAudTelemetry, $btnStartMenu, $btnAudStartMenu, $btnPower, $btnAudPower, $btnNetwork, $btnAudNetwork, $btnSvcLight, $btnAudSvcLight, $btnSvcHeavy, $btnAudSvcHeavy, $lblRescueSvc, $btnRestoreSvc))

# Z5: Utilities
$lblInspect = New-Object System.Windows.Forms.Label; $lblInspect.Text = "Interactive Inspection Tables (Ctrl+Click to remove)"; $lblInspect.Location = New-Object System.Drawing.Point(15, 15); $lblInspect.Size = New-Object System.Drawing.Size(370, 20); $lblInspect.ForeColor = [System.Drawing.Color]::DarkGray
$btnUtilAppx = New-Object System.Windows.Forms.Button; $btnUtilAppx.Text = "Appx (Accounts)"; $btnUtilAppx.Location = New-Object System.Drawing.Point(15, 40); $btnUtilAppx.Size = New-Object System.Drawing.Size(180, 40); $btnUtilAppx.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilAppx.ForeColor = [System.Drawing.Color]::White; $btnUtilAppx.FlatStyle = "Flat"
$btnUtilAppxProv = New-Object System.Windows.Forms.Button; $btnUtilAppxProv.Text = "Appx (Image)"; $btnUtilAppxProv.Location = New-Object System.Drawing.Point(205, 40); $btnUtilAppxProv.Size = New-Object System.Drawing.Size(180, 40); $btnUtilAppxProv.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilAppxProv.ForeColor = [System.Drawing.Color]::White; $btnUtilAppxProv.FlatStyle = "Flat"
$btnUtilCaps = New-Object System.Windows.Forms.Button; $btnUtilCaps.Text = "Capabilities (FOD)"; $btnUtilCaps.Location = New-Object System.Drawing.Point(15, 90); $btnUtilCaps.Size = New-Object System.Drawing.Size(180, 40); $btnUtilCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilCaps.ForeColor = [System.Drawing.Color]::White; $btnUtilCaps.FlatStyle = "Flat"
$btnUtilOpt = New-Object System.Windows.Forms.Button; $btnUtilOpt.Text = "Optional Features"; $btnUtilOpt.Location = New-Object System.Drawing.Point(205, 90); $btnUtilOpt.Size = New-Object System.Drawing.Size(180, 40); $btnUtilOpt.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilOpt.ForeColor = [System.Drawing.Color]::White; $btnUtilOpt.FlatStyle = "Flat"
$btnUtilSvc = New-Object System.Windows.Forms.Button; $btnUtilSvc.Text = "Running Services Management"; $btnUtilSvc.Location = New-Object System.Drawing.Point(15, 140); $btnUtilSvc.Size = New-Object System.Drawing.Size(370, 40); $btnUtilSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilSvc.ForeColor = [System.Drawing.Color]::White; $btnUtilSvc.FlatStyle = "Flat"
$btnUtilStartup = New-Object System.Windows.Forms.Button; $btnUtilStartup.Text = "Startup Management (Registry & Folders)"; $btnUtilStartup.Location = New-Object System.Drawing.Point(15, 190); $btnUtilStartup.Size = New-Object System.Drawing.Size(370, 40); $btnUtilStartup.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnUtilStartup.ForeColor = [System.Drawing.Color]::White; $btnUtilStartup.FlatStyle = "Flat"

$lblClassic = New-Object System.Windows.Forms.Label; $lblClassic.Text = "Classic Windows Applets"; $lblClassic.Location = New-Object System.Drawing.Point(15, 245); $lblClassic.Size = New-Object System.Drawing.Size(370, 20); $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray
$btnUtilNet = New-Object System.Windows.Forms.Button; $btnUtilNet.Text = "Network Adapters (ncpa)"; $btnUtilNet.Location = New-Object System.Drawing.Point(15, 270); $btnUtilNet.Size = New-Object System.Drawing.Size(180, 40); $btnUtilNet.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilNet.ForeColor = [System.Drawing.Color]::White; $btnUtilNet.FlatStyle = "Flat"
$btnUtilSound = New-Object System.Windows.Forms.Button; $btnUtilSound.Text = "Sound Settings"; $btnUtilSound.Location = New-Object System.Drawing.Point(205, 270); $btnUtilSound.Size = New-Object System.Drawing.Size(180, 40); $btnUtilSound.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilSound.ForeColor = [System.Drawing.Color]::White; $btnUtilSound.FlatStyle = "Flat"
$btnUtilApps = New-Object System.Windows.Forms.Button; $btnUtilApps.Text = "Programs and Features"; $btnUtilApps.Location = New-Object System.Drawing.Point(15, 320); $btnUtilApps.Size = New-Object System.Drawing.Size(180, 40); $btnUtilApps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilApps.ForeColor = [System.Drawing.Color]::White; $btnUtilApps.FlatStyle = "Flat"
$btnUtilPrint = New-Object System.Windows.Forms.Button; $btnUtilPrint.Text = "Devices and Printers"; $btnUtilPrint.Location = New-Object System.Drawing.Point(205, 320); $btnUtilPrint.Size = New-Object System.Drawing.Size(180, 40); $btnUtilPrint.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnUtilPrint.ForeColor = [System.Drawing.Color]::White; $btnUtilPrint.FlatStyle = "Flat"

$lblDNS = New-Object System.Windows.Forms.Label; $lblDNS.Text = "Fast DNS Server Switch"; $lblDNS.Location = New-Object System.Drawing.Point(15, 385); $lblDNS.Size = New-Object System.Drawing.Size(370, 20); $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray
$comboDNS = New-Object System.Windows.Forms.ComboBox; $comboDNS.Location = New-Object System.Drawing.Point(15, 410); $comboDNS.Size = New-Object System.Drawing.Size(240, 25); $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $comboDNS.ForeColor = [System.Drawing.Color]::White; $comboDNS.DropDownStyle = "DropDownList"; $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)")); $comboDNS.SelectedIndex = 0
$btnApplyDNS = New-Object System.Windows.Forms.Button; $btnApplyDNS.Text = "Apply DNS"; $btnApplyDNS.Location = New-Object System.Drawing.Point(265, 409); $btnApplyDNS.Size = New-Object System.Drawing.Size(120, 27); $btnApplyDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40); $btnApplyDNS.ForeColor = [System.Drawing.Color]::White; $btnApplyDNS.FlatStyle = "Flat"

function Update-DNSLabel {
    $activeAdapter = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true -and $_.DefaultIPGateway -ne $null } | Select-Object -First 1
    if ($activeAdapter) {
        if ($activeAdapter.DNSServerSearchOrder) {
            $dns = $activeAdapter.DNSServerSearchOrder -join ", "
            $knownDNS = @{
                "9.9.9.9, 149.112.112.112" = "Quad9"
                "1.1.1.1, 1.0.0.1" = "Cloudflare"
                "94.140.14.14, 94.140.15.15" = "AdGuard"
                "8.8.8.8, 8.8.4.4" = "Google"
                "208.67.222.222, 208.67.220.220" = "OpenDNS"
            }
            $dnsName = $knownDNS[$dns]
            if ($dnsName) { $lblCurrentDNS.Text = "Current DNS: $dnsName ($dns)" }
            else { $lblCurrentDNS.Text = "Current DNS: $dns (Custom)" }
        } else {
            $lblCurrentDNS.Text = "Current DNS: Default provider (DHCP)"
        }
    } else {
        $lblCurrentDNS.Text = "Current DNS: No network connection"
    }
}

$lblCurrentDNS = New-Object System.Windows.Forms.Label
$lblCurrentDNS.Text = "Current DNS: Reading from the main adapter..."
$lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 442)
$lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 20)
$lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue

$tabUtil.Controls.AddRange(@($lblInspect, $btnUtilAppx, $btnUtilAppxProv, $btnUtilCaps, $btnUtilOpt, $btnUtilSvc, $btnUtilStartup, $lblClassic, $btnUtilNet, $btnUtilApps, $btnUtilSound, $btnUtilPrint, $lblDNS, $comboDNS, $btnApplyDNS, $lblCurrentDNS))

# Z6: Integrity
$btnCheckSystem = New-Object System.Windows.Forms.Button; $btnCheckSystem.Text = "Scan System (SFC + RestoreHealth)"; $btnCheckSystem.Location = New-Object System.Drawing.Point(15, 20); $btnCheckSystem.Size = New-Object System.Drawing.Size(370, 40); $btnCheckSystem.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnCheckSystem.ForeColor = [System.Drawing.Color]::White; $btnCheckSystem.FlatStyle = "Flat"
$btnResetBase = New-Object System.Windows.Forms.Button; $btnResetBase.Text = "Aggressive Cleanup (ResetBase)"; $btnResetBase.Location = New-Object System.Drawing.Point(15, 70); $btnResetBase.Size = New-Object System.Drawing.Size(370, 40); $btnResetBase.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40); $btnResetBase.ForeColor = [System.Drawing.Color]::White; $btnResetBase.FlatStyle = "Flat"
$tabWinSXS.Controls.AddRange(@($btnCheckSystem, $btnResetBase))

# Logical UI order
$tabControl.TabPages.AddRange(@($tabClean, $tabApps, $tabReg, $tabServices, $tabUtil, $tabWinSXS))

# MAIN CONTROLS
$btnClearLog = New-Object System.Windows.Forms.Button; $btnClearLog.Text = "[ Clear Log ]"; $btnClearLog.Location = New-Object System.Drawing.Point(1050, 725); $btnClearLog.Size = New-Object System.Drawing.Size(110, 25); $btnClearLog.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $btnClearLog.ForeColor = [System.Drawing.Color]::LightGray; $btnClearLog.FlatStyle = "Flat"; $btnClearLog.Add_Click({ $global:LastLog = "--- WINULTIX PRO ---`r`n`r`nReady for deployment."; $infoBox.Text = $global:LastLog })
$form.Controls.Add($btnClearLog)

$global:progBar = New-Object System.Windows.Forms.ProgressBar
$global:progBar.Location = New-Object System.Drawing.Point(440, 725)
$global:progBar.Size = New-Object System.Drawing.Size(600, 25)
$global:progBar.Style = "Continuous"
$global:progBar.Minimum = 0
$global:progBar.Maximum = 100
$form.Controls.Add($global:progBar)

function Update-Progress { 
    param([int]$Percent)
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $global:progBar.Value = $Percent
    [System.Windows.Forms.Application]::DoEvents() 
}

$btnCredits = New-Object System.Windows.Forms.Button
$btnCredits.Text = "[ About / GitHub ]"
$btnCredits.Location = New-Object System.Drawing.Point(10, 720)
$btnCredits.Size = New-Object System.Drawing.Size(140, 25)
$btnCredits.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 40)
$btnCredits.ForeColor = [System.Drawing.Color]::LightGray
$btnCredits.FlatStyle = "Flat"
$btnCredits.Add_Click({ 
    # Tworzymy dedykowane okienko About
    $aboutForm = New-Object System.Windows.Forms.Form
    $aboutForm.Text = "About WinUltix Pro"
    $aboutForm.Size = New-Object System.Drawing.Size(380, 240)
    $aboutForm.StartPosition = "CenterParent"
    $aboutForm.FormBorderStyle = "FixedDialog"
    $aboutForm.MaximizeBox = $false
    $aboutForm.MinimizeBox = $false
    $aboutForm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

    # Etykieta z tekstem informacyjnym
    $lblAbout = New-Object System.Windows.Forms.Label
    $lblAbout.Location = New-Object System.Drawing.Point(20, 20)
    $lblAbout.Size = New-Object System.Drawing.Size(340, 80)
    $lblAbout.ForeColor = [System.Drawing.Color]::LightGray
    $lblAbout.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblAbout.Text = "WinUltix Pro - Ultimate System Toolkit $AppVersion`n`nConcept, architecture and combat tests: Firever`nCoding assistance: Gemini AI`n`nLet your hardware breathe!"
    
    # Klikalny link
    $linkGit = New-Object System.Windows.Forms.LinkLabel
    $linkGit.Location = New-Object System.Drawing.Point(20, 115)
    $linkGit.Size = New-Object System.Drawing.Size(340, 20)
    $linkGit.LinkColor = [System.Drawing.Color]::LightSkyBlue
    $linkGit.ActiveLinkColor = [System.Drawing.Color]::Cyan
    $linkGit.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $linkGit.Text = "https://github.com/Firever-ultix/WinUltix"
    $linkGit.Add_LinkClicked({ 
        Start-Process "https://github.com/Firever-ultix/WinUltix" -ErrorAction SilentlyContinue 
    })

    # Przycisk zamykający
    $btnAboutOK = New-Object System.Windows.Forms.Button
    $btnAboutOK.Text = "Close"
    $btnAboutOK.Location = New-Object System.Drawing.Point(140, 155)
    $btnAboutOK.Size = New-Object System.Drawing.Size(80, 25)
    $btnAboutOK.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnAboutOK.ForeColor = [System.Drawing.Color]::White
    $btnAboutOK.FlatStyle = "Flat"
    $btnAboutOK.Add_Click({ $aboutForm.Close() })

    $aboutForm.Controls.AddRange(@($lblAbout, $linkGit, $btnAboutOK))
    [void]$aboutForm.ShowDialog()
})
$form.Controls.Add($btnCredits)

# ACTIONS
foreach ($tab in $tabControl.TabPages) { foreach ($btn in $tab.Controls) { $btn.Add_MouseLeave({ Restore-Log }) } }
$btnWU.Add_MouseEnter({ Show-Description "Stops download services and safely removes all buffered Windows Update files." }); $btnWU.Add_Click({ Clean-WindowsUpdateCache; Write-GUI "Completed."; Write-GUI "" })
$btnAudWU.Add_MouseEnter({ Show-Description "AUDIT: Scans the Download folder of Windows Update to calculate space wasted by old updates." }); $btnAudWU.Add_Click({ Audit-WindowsUpdate; Write-GUI "" })
$btnTemp.Add_MouseEnter({ Show-Description "Clears global temporary buffers (Temp/Prefetch) and Temp folders across all user profiles." }); $btnTemp.Add_Click({ Clean-TempFiles; Write-GUI "Completed."; Write-GUI "" })
$btnAudTemp.Add_MouseEnter({ Show-Description "AUDIT: Verifies the amount of lingering temporary files." }); $btnAudTemp.Add_Click({ Audit-TempFiles; Write-GUI "" })
$btnLogs.Add_MouseEnter({ Show-Description "Clears all system event logs in the Event Viewer." }); $btnLogs.Add_Click({ Clean-EventLogs; Write-GUI "Completed."; Write-GUI "" })
$btnAudLogs.Add_MouseEnter({ Show-Description "AUDIT: Counts the number of active event logging channels." }); $btnAudLogs.Add_Click({ Audit-EventLogs; Write-GUI "" })
$btnThirdParty.Add_MouseEnter({ Show-Description "Cleans multi-gigabyte buffers from browsers, messengers, and GPU shaders." }); $btnThirdParty.Add_Click({ Clean-ThirdPartyCache; Write-GUI "Completed."; Write-GUI "" })
$btnAudThirdParty.Add_MouseEnter({ Show-Description "AUDIT: Scans browser cache, Discord, and GPU shaders (AMD/NVIDIA) to calculate wasted space." }); $btnAudThirdParty.Add_Click({ Audit-ThirdPartyCache; Write-GUI "" })
$btnRecycle.Add_MouseEnter({ Show-Description "Hard reset of the Recycle Bin. Takes ownership and forcefully deletes corrupted bins across all partitions." }); $btnRecycle.Add_Click({ Clean-RecycleBinHard; Write-GUI "Completed."; Write-GUI "" })
$btnAudRecycle.Add_MouseEnter({ Show-Description "AUDIT: Scans corrupted and standard Recycle Bins across all physical drives." }); $btnAudRecycle.Add_Click({ Audit-RecycleBin; Write-GUI "" })
$btnOneDrive.Add_MouseEnter({ Show-Description "Completely uninstalls OneDrive, burns it from the Registry, and physically deletes folders across all profiles." }); $btnOneDrive.Add_Click({ Remove-OneDrive; Write-GUI "Completed."; Write-GUI "" })
$btnAudOneDrive.Add_MouseEnter({ Show-Description "AUDIT: Scans for active OneDrive installers and startup keys." }); $btnAudOneDrive.Add_Click({ Audit-OneDrive; Write-GUI "" })
$btnCaps.Add_MouseEnter({ Show-Description "Removes optional built-in Features on Demand (FOD)." }); $btnCaps.Add_Click({ Remove-WindowsCapabilities; Write-GUI "Completed."; Write-GUI "" })
$btnAudCaps.Add_MouseEnter({ Show-Description "AUDIT: Verifies installed unnecessary Capabilities (FOD)." }); $btnAudCaps.Add_Click({ Audit-Capabilities; Write-GUI "" })
$btnBloat.Add_MouseEnter({ Show-Description "Massive, aggressive removal of junk Appx applications from the system." }); $btnBloat.Add_Click({ Remove-Bloatware; Write-GUI "Completed."; Write-GUI "" })
$btnAudBloat.Add_MouseEnter({ Show-Description "AUDIT: Scans the system for the full list of target Bloatware." }); $btnAudBloat.Add_Click({ Audit-Bloatware; Write-GUI "" })
$btnGC.Add_MouseEnter({ Show-Description "Intelligent detective. Scans application dependencies and removes orphaned frameworks." }); $btnGC.Add_Click({ Run-AppxGarbageCollector; Write-GUI "Completed."; Write-GUI "" })
$btnAudGC.Add_MouseEnter({ Show-Description "AUDIT: Scans and lists all orphaned frameworks that will be removed." }); $btnAudGC.Add_Click({ Audit-GarbageCollector; Write-GUI "" })
$btnTelemetry.Add_MouseEnter({ Show-Description "Paralyzes the Task Scheduler. Disables analytics, error reporting, Windows AI, and feedback. Severs telemetry from the OS core." }); $btnTelemetry.Add_Click({ Disable-TelemetryTasks; Write-GUI "Completed."; Write-GUI "" })
$btnAudTelemetry.Add_MouseEnter({ Show-Description "AUDIT: Verifies if telemetry tasks are active in the scheduler." }); $btnAudTelemetry.Add_Click({ Audit-TelemetryTasks; Write-GUI "" })
$btnStartMenu.Add_MouseEnter({ Show-Description "Wipes the internal Start Menu database (start2.bin) and removes MDM locks. This safely unpins all bloated tiles and gives you a fresh, fully customizable layout." }); $btnStartMenu.Add_Click({ Force-CleanStartMenu; Write-GUI "Completed."; Write-GUI "" })
$btnAudStartMenu.Add_MouseEnter({ Show-Description "AUDIT: Scans the size of the current Start Menu layout database." }); $btnAudStartMenu.Add_Click({ Audit-StartMenu; Write-GUI "" })
$btnPower.Add_MouseEnter({ Show-Description "Disables the hibernation file, system sleep, and sets display turn-off to 60 minutes." }); $btnPower.Add_Click({ Optimize-PowerSettings; Write-GUI "Completed."; Write-GUI "" })
$btnAudPower.Add_MouseEnter({ Show-Description "AUDIT: Verifies power profile (hibernation, sleep state, and display)." }); $btnAudPower.Add_Click({ Audit-Power; Write-GUI "" })
$btnNetwork.Add_MouseEnter({ Show-Description "Disables Nagle's algorithm on all network adapters, drastically reducing latency in games." }); $btnNetwork.Add_Click({ Optimize-Network; Write-GUI "Completed."; Write-GUI "" })
$btnAudNetwork.Add_MouseEnter({ Show-Description "AUDIT: Verifies TCPNoDelay status on network adapters." }); $btnAudNetwork.Add_Click({ Audit-Network; Write-GUI "" })
$btnSvcLight.Add_MouseEnter({ Show-Description "OFFICE PROFILE: Kills telemetry, leaving print services and indexing intact." }); $btnSvcLight.Add_Click({ Disable-ServicesLight; Write-GUI "Completed."; Write-GUI "" })
$btnAudSvcLight.Add_MouseEnter({ Show-Description "AUDIT: Thoroughly verifies Office Profile services shutdown." }); $btnAudSvcLight.Add_Click({ Audit-ServicesLight; Write-GUI "" })
$btnSvcHeavy.Add_MouseEnter({ Show-Description "GAMING PROFILE: Disables almost everything in the background, including print and cloud services." }); $btnSvcHeavy.Add_Click({ Disable-ServicesHeavy; Write-GUI "Completed."; Write-GUI "" })
$btnAudSvcHeavy.Add_MouseEnter({ Show-Description "AUDIT: Thoroughly verifies Gaming Profile services shutdown." }); $btnAudSvcHeavy.Add_Click({ Audit-ServicesHeavy; Write-GUI "" })
$btnRestoreSvc.Add_MouseEnter({ Show-Description "RESCUE: Lifts locks from system services and restores them to factory settings (Manual/Automatic). Use in case of system issues." }); $btnRestoreSvc.Add_Click({ Restore-ServicesLight; Write-GUI "Completed."; Write-GUI "" })
$btnCheckSystem.Add_MouseEnter({ Show-Description "System First Aid: Scans the core Windows OS files for corruption and replaces damaged components with fresh copies downloaded directly from Microsoft servers (SFC & DISM)." }); $btnCheckSystem.Add_Click({ Check-SystemIntegrity; Write-GUI "Completed."; Write-GUI "" })
$btnResetBase.Add_MouseEnter({ Show-Description "WinSXS Deep Clean: Permanently deletes superseded Windows Update backup files. Reclaims gigabytes of C: drive space, but you will NOT be able to uninstall previously applied Windows Updates." }); $btnResetBase.Add_Click({ Optimize-WinSXS; Write-GUI "Completed."; Write-GUI "" })
$btnRegTaskbar.Add_MouseEnter({ Show-Description "Aligns the taskbar to the left, kills Bing assistants, and hides widgets." }); $btnRegTaskbar.Add_Click({ Apply-RegTaskbar; Write-GUI "Completed."; Write-GUI "" })
$btnAudTaskbar.Add_MouseEnter({ Show-Description "AUDIT: Verifies taskbar alignment policy and Bing locks." }); $btnAudTaskbar.Add_Click({ Audit-RegTaskbar; Write-GUI "" })
$btnRegExplorer.Add_MouseEnter({ Show-Description "Restores the full context menu, launches folder processes in isolation." }); $btnRegExplorer.Add_Click({ Apply-RegExplorer; Write-GUI "Completed."; Write-GUI "" })
$btnAudExplorer.Add_MouseEnter({ Show-Description "AUDIT: Verifies the presence of the key enforcing the classic context menu." }); $btnAudExplorer.Add_Click({ Audit-RegExplorer; Write-GUI "" })
$btnRegAnnoyances.Add_MouseEnter({ Show-Description "Deactivates AutoPlay and Sticky Keys shortcuts." }); $btnRegAnnoyances.Add_Click({ Apply-RegAnnoyances; Write-GUI "Completed."; Write-GUI "" })
$btnAudAnnoyances.Add_MouseEnter({ Show-Description "AUDIT: Verifies AutoPlay and Sticky Keys blockade." }); $btnAudAnnoyances.Add_Click({ Audit-RegAnnoyances; Write-GUI "" })
$btnRegPrivacy.Add_MouseEnter({ Show-Description "Blocks app access to history and enables GPO cutting off full telemetry. Blocks MS Store background execution." }); $btnRegPrivacy.Add_Click({ Apply-RegPrivacy; Write-GUI "Completed."; Write-GUI "" })
$btnAudPrivacy.Add_MouseEnter({ Show-Description "AUDIT: Checks the registry for telemetry, Edge, and background execution blocks." }); $btnAudPrivacy.Add_Click({ Audit-RegPrivacy; Write-GUI "" })
$btnRegSystemBoot.Add_MouseEnter({ Show-Description "Disables Fast Boot, OneDrive, RDP, and blocks software injections from BIOS/UEFI (WPBT)." }); $btnRegSystemBoot.Add_Click({ Apply-RegSystemBoot; Write-GUI "Completed."; Write-GUI "" })
$btnAudSystemBoot.Add_MouseEnter({ Show-Description "AUDIT: Verifies kernel hibernation logic (Fast Boot), WPBT, and RDP." }); $btnAudSystemBoot.Add_Click({ Audit-RegSystemBoot; Write-GUI "" })
$btnRegMouse.Add_MouseEnter({ Show-Description "Pure 1:1 input. Hard-disables 'Enhance pointer precision'." }); $btnRegMouse.Add_Click({ Apply-RegMouse; Write-GUI "Completed."; Write-GUI "" })
$btnAudMouse.Add_MouseEnter({ Show-Description "AUDIT: Scans registry keys for system pointer acceleration." }); $btnAudMouse.Add_Click({ Audit-RegMouse; Write-GUI "" })
$btnRegGaming.Add_MouseEnter({ Show-Description "Enforces MMCSS priorities, disables core isolation, enables HAGS." }); $btnRegGaming.Add_Click({ Apply-RegGaming; Write-GUI "Completed."; Write-GUI "" })
$btnAudGaming.Add_MouseEnter({ Show-Description "AUDIT: Verifies MMCSS limits and HAGS acceleration." }); $btnAudGaming.Add_Click({ Audit-RegGaming; Write-GUI "" })
$btnRestoreReg.Add_MouseEnter({ Show-Description "RESCUE: Reverts Registry modifications, including the removal of BIOS locks, Bing assistants, and the standard Win11 menu." }); $btnRestoreReg.Add_Click({ Restore-Registry; Write-GUI "Completed."; Write-GUI "" })

$btnUtilAppx.Add_MouseEnter({ Show-Description "Interactive Appx table. Use Ctrl+Click to remove selected apps." }); $btnUtilAppx.Add_Click({ Show-AppxGrid; Write-GUI "" })
$btnUtilAppxProv.Add_MouseEnter({ Show-Description "Interactive Provisioned table. Use Ctrl+Click to deprovision installers." }); $btnUtilAppxProv.Add_Click({ Show-AppxProvGrid; Write-GUI "" })
$btnUtilCaps.Add_MouseEnter({ Show-Description "Interactive Capabilities (FOD) table. Select unnecessary packages to remove." }); $btnUtilCaps.Add_Click({ Show-CapsGrid; Write-GUI "" })
$btnUtilOpt.Add_MouseEnter({ Show-Description "Interactive Optional Features table. Allows disabling unnecessary modules." }); $btnUtilOpt.Add_Click({ Show-OptFeaturesGrid; Write-GUI "" })
$btnUtilSvc.Add_MouseEnter({ Show-Description "Interactive services table. Selected items will be forcefully stopped and disabled." }); $btnUtilSvc.Add_Click({ Show-ServicesGrid; Write-GUI "" })
$btnUtilStartup.Add_MouseEnter({ Show-Description "Interactive table. Aggregates hidden shortcuts and registry keys starting with the system." }); $btnUtilStartup.Add_Click({ Show-StartupGrid; Write-GUI "" })
$btnUtilNet.Add_MouseEnter({ Show-Description "Quick access to the Network Adapters applet." }); $btnUtilNet.Add_Click({ Open-ClassicNet; Write-GUI "" })
$btnUtilApps.Add_MouseEnter({ Show-Description "Quick access to the classic Win32 installed software list." }); $btnUtilApps.Add_Click({ Open-ClassicApps; Write-GUI "" })
$btnUtilSound.Add_MouseEnter({ Show-Description "Quick access to playback and recording devices." }); $btnUtilSound.Add_Click({ Open-ClassicSound; Write-GUI "" })
$btnUtilPrint.Add_MouseEnter({ Show-Description "Trick opening a clean folder of the legacy printers applet." }); $btnUtilPrint.Add_Click({ Open-ClassicPrinters; Write-GUI "" })

$btnApplyDNS.Add_MouseEnter({ Show-Description "Applies the selected secure DNS server for all active network adapters and flushes the DNS resolver cache." })
$btnApplyDNS.Add_Click({ 
    Set-CustomDNS $comboDNS.SelectedItem; 
    if ($comboDNS.SelectedItem -eq "Default (DHCP)") {
        $lblCurrentDNS.Text = "Current DNS: Default provider (DHCP)"
    } else {
        $lblCurrentDNS.Text = "Current DNS: $($comboDNS.SelectedItem)"
    }
    Write-GUI "Completed."; Write-GUI "" 
})

Update-DNSLabel # Load DNS on app startup
$form.Controls.Add($descBox)
$form.Controls.Add($tabControl)
$form.Controls.Add($infoBox)
[void]$form.ShowDialog() # Fixes the "Cancel" popup issue