# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# CORE_HELPERS.PS1 - SHARED UI & UTILITIES
# Core_Helpers: Global UI functions, registry engine, and shared modal interfaces.
# ==========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ------------------------------------------
# GLOBAL UI HELPERS
# ------------------------------------------
function Write-GUI { 
    param([string]$Message)
    if ($null -ne $global:infoBox) {
        if ($Message -eq "") { $global:LastLog += "`r`n" } 
        else { $global:LastLog += "`r`n[$(Get-Date -Format 'HH:mm:ss')] $Message" }
        $global:infoBox.Text = $global:LastLog
        $global:infoBox.SelectionStart = $global:infoBox.Text.Length
        $global:infoBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Show-Description { 
    param([string]$Desc)
    if ($null -ne $global:descBox) {
        $global:descBox.Text = $Desc -replace "`n", "`r`n" 
    }
}

function Restore-Log { 
    if ($null -ne $global:descBox) {
        $global:descBox.Text = "Hover over any button to see operation details." 
    }
}

function Update-Progress { 
    param([int]$Percent)
    if ($null -ne $global:progBar) {
        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }
        $global:progBar.Value = $Percent
        [System.Windows.Forms.Application]::DoEvents() 
    }
}

function Update-DNSLabel {
    if ($null -eq $global:lblCurrentDNS) { return }
    $activeAdapter = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true -and $null -ne $_.DefaultIPGateway } | Select-Object -First 1
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
            if ($knownDNS[$dns]) { $global:lblCurrentDNS.Text = "Current DNS: $($knownDNS[$dns]) ($dns)" } 
            else { $global:lblCurrentDNS.Text = "Current DNS: $dns (Custom)" }
        } else { $global:lblCurrentDNS.Text = "Current DNS: Default provider (DHCP)" }
    } else { $global:lblCurrentDNS.Text = "Current DNS: No network connection" }
}

function Set-RegKey { 
    param($Path, $Name, $Value, $Type="DWord")
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null }
    if ($null -eq $Value -and $Type -eq "String") { 
        Set-ItemProperty -Path $Path -Name $Name -Value "" -Type String -Force -ErrorAction SilentlyContinue | Out-Null 
    } else { 
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue | Out-Null 
    } 
}

# ------------------------------------------
# INTERACTIVE MODALS (GLOBAL)
# ------------------------------------------
function Show-ActionModal {
    param (
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][array]$AuditResults,
        [switch]$EnableRevert
    )
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title
    $modal.Size = New-Object System.Drawing.Size(750, 650)
    $modal.MinimumSize = New-Object System.Drawing.Size(750, 650)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.MaximizeBox = $true
    $modal.MinimizeBox = $false
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $modal.ForeColor = [System.Drawing.Color]::White

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = $Description
    $lblDesc.Location = New-Object System.Drawing.Point(15, 15)
    $lblDesc.Size = New-Object System.Drawing.Size(700, 40)
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblDesc.Anchor = 'Top, Left, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox
    $chkList.Location = New-Object System.Drawing.Point(15, 60)
    $chkList.Size = New-Object System.Drawing.Size(700, 480)
    $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $chkList.Font = New-Object System.Drawing.Font("Consolas", 10)
    $chkList.CheckOnClick = $false
    $chkList.Anchor = 'Top, Bottom, Left, Right' 
    
    if ($null -ne $AuditResults -and $AuditResults.Count -gt 0) {
        foreach ($item in $AuditResults) {
            if ($item.IsDetected) { [void]$chkList.Items.Add("[ DETECTED ]  " + $item.UIDisplayName, $true) } 
            else { [void]$chkList.Items.Add("[ OPTIMIZED ] " + $item.UIDisplayName, $false) }
        }
    } else { [void]$chkList.Items.Add("No data returned from audit scanner.", $false) }

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Execute Selected"
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnApply.FlatStyle = "Flat"
    $btnApply.DialogResult = "OK"
    $btnApply.Anchor = 'Bottom, Left'

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.DialogResult = "Cancel"
    $btnCancel.Anchor = 'Bottom, Right'

    if ($EnableRevert) {
        $btnApply.Location = New-Object System.Drawing.Point(15, 555)
        $btnApply.Size = New-Object System.Drawing.Size(225, 35)

        $btnRevert = New-Object System.Windows.Forms.Button
        $btnRevert.Text = "Revert Selected"
        $btnRevert.Location = New-Object System.Drawing.Point(250, 555)
        $btnRevert.Size = New-Object System.Drawing.Size(225, 35)
        $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
        $btnRevert.FlatStyle = "Flat"
        $btnRevert.DialogResult = "Yes" # Hijacking 'Yes' to represent Revert action
        $btnRevert.Anchor = 'Bottom, Left'
        
        $btnCancel.Location = New-Object System.Drawing.Point(490, 555)
        $btnCancel.Size = New-Object System.Drawing.Size(225, 35)

        $modal.Controls.AddRange(@($lblDesc, $chkList, $btnApply, $btnRevert, $btnCancel))
    } else {
        $btnApply.Location = New-Object System.Drawing.Point(15, 555)
        $btnApply.Size = New-Object System.Drawing.Size(340, 35)
        $btnCancel.Location = New-Object System.Drawing.Point(375, 555)
        $btnCancel.Size = New-Object System.Drawing.Size(340, 35)
        $modal.Controls.AddRange(@($lblDesc, $chkList, $btnApply, $btnCancel))
    }

    $modal.AcceptButton = $btnApply
    $modal.CancelButton = $btnCancel

    $result = $modal.ShowDialog()
    if ($result -eq "OK" -or $result -eq "Yes") {
        $selectedItems = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $selectedItems += $AuditResults[$i] }
        }
        $actionData = if ($result -eq "OK") { "Apply" } else { "Revert" }
        return [PSCustomObject]@{ Action = $actionData; Items = $selectedItems }
    } else { return $null }
}