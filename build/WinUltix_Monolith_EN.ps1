# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# MODULAR MAIN LAUNCHER
# ==========================================
$Global:AppVersion = "v2.7.0"

# ------------------------------------------
# 1. MODULE LOADING (ARCHITECTURE MANIFESTS)
# ------------------------------------------
# $ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
# $ModulesDir = Join-Path $ScriptDir "Modules"

# Core_Helpers: Global UI functions, registry engine, and shared modal interfaces.
# . (Join-Path $ModulesDir "Core_Helpers.ps1")
# >>> BEGIN INJECTED MODULE: Core_Helpers.ps1 <<<
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
    
    $activeAdapter = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue | 
        Where-Object { $null -ne $_.DefaultIPGateway } | 
        Select-Object -First 1

    if ($null -ne $activeAdapter) {
        if ($activeAdapter.DNSServerSearchOrder -and $activeAdapter.DNSServerSearchOrder.Count -gt 0) {
            $dns = $activeAdapter.DNSServerSearchOrder -join ", "
            $knownDNS = @{ 
                "9.9.9.9, 149.112.112.112"         = "Quad9"
                "1.1.1.1, 1.0.0.1"                 = "Cloudflare"
                "94.140.14.14, 94.140.15.15"       = "AdGuard"
                "8.8.8.8, 8.8.4.4"                 = "Google"
                "208.67.222.222, 208.67.220.220"   = "OpenDNS" 
            }
            if ($knownDNS.ContainsKey($dns)) { 
                $global:lblCurrentDNS.Text = "Current DNS: $($knownDNS[$dns]) ($dns)" 
            } else { 
                $global:lblCurrentDNS.Text = "Current DNS: $dns (Custom)" 
            }
        } else { 
            $global:lblCurrentDNS.Text = "Current DNS: Default provider (DHCP)" 
        }
    } else { 
        $global:lblCurrentDNS.Text = "Current DNS: No network connection" 
    }
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
# ASYNCHRONOUS RUNSPACE ENGINE (GLOBAL)
# ------------------------------------------
function Invoke-AsyncTask {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [array]$Arguments = @(),
        [Parameter(Mandatory=$true)][scriptblock]$OnComplete,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [int]$PollIntervalMs = 150
    )

    foreach ($ctrl in $ControlsToDisable) {
        if ($null -ne $ctrl) { $ctrl.Enabled = $false }
    }

    $ps = [powershell]::Create()
    [void]$ps.AddScript($ScriptBlock)
    foreach ($arg in $Arguments) {
        [void]$ps.AddArgument($arg)
    }

    $asyncResult = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $PollIntervalMs
    $timer.Tag = @{
        PS          = $ps
        AsyncResult = $asyncResult
        Controls    = $ControlsToDisable
        OnComplete  = $OnComplete
    }

    $timer.Add_Tick({
        $state = $this.Tag
        if (-not $state.AsyncResult.IsCompleted) { return }

        $this.Stop()
        $taskOutput = $null
        $taskError  = $null

        try {
            $taskOutput = $state.PS.EndInvoke($state.AsyncResult)
        } catch {
            $taskError = $_
        } finally {
            $state.PS.Dispose()
            $this.Dispose()
            foreach ($ctrl in $state.Controls) {
                if ($null -ne $ctrl -and -not $ctrl.IsDisposed) { $ctrl.Enabled = $true }
            }
        }

        if ($null -ne $taskError) {
            Write-GUI "  [ERROR] Background task failed: $($taskError.Exception.Message)"
            return
        }

        if ($null -ne $state.OnComplete) {
            & $state.OnComplete $taskOutput
        }
    })

    $timer.Start()
}

# ------------------------------------------
# INTERACTIVE MODALS (GLOBAL)
# ------------------------------------------
function Show-ActionModal {
    param (
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$AuditResults,
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
    
    $hasValidItems = ($null -ne $AuditResults -and $AuditResults.Count -gt 0)

    if ($hasValidItems) {
        foreach ($item in $AuditResults) {
            if ($item.IsDetected) { 
                [void]$chkList.Items.Add("[ DETECTED ]  " + $item.UIDisplayName, $true) 
            } else { 
                [void]$chkList.Items.Add("[ OPTIMIZED ] " + $item.UIDisplayName, $false) 
            }
        }
    } else { 
        [void]$chkList.Items.Add("No data returned from audit scanner.", $false)
        $chkList.Enabled = $false
    }

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = "Execute Selected"
    $btnApply.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnApply.FlatStyle = "Flat"
    $btnApply.DialogResult = "OK"
    $btnApply.Enabled = $hasValidItems
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
        $btnRevert.DialogResult = "Yes"
        $btnRevert.Enabled = $hasValidItems
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

    try {
        $result = $modal.ShowDialog($global:form)
        if ($hasValidItems -and ($result -eq "OK" -or $result -eq "Yes")) {
            $selectedItems = @()
            for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
                if ($chkList.GetItemChecked($i)) { $selectedItems += $AuditResults[$i] }
            }
            $actionData = if ($result -eq "OK") { "Apply" } else { "Revert" }
            return [PSCustomObject]@{ Action = $actionData; Items = $selectedItems }
        }
        return $null
    } finally {
        $modal.Dispose()
    }
}
# <<< END INJECTED MODULE: Core_Helpers.ps1 <<<


# Z1_Cleanup: Deep system cleaning. Removes Windows Update cache, Temp files, Event Viewer logs (wevtutil), and 3rd-party app caches. Enhanced button interactivity and optimized execution flows.
# . (Join-Path $ModulesDir "Z1_Cleanup.ps1")
# >>> BEGIN INJECTED MODULE: Z1_Cleanup.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z1_CLEANUP.PS1 - CLEANUP MODULE
# Z1_Cleanup: Manages deep system cleaning. Removes Windows Update cache, Temp files (system and user profiles), clears Event Viewer logs (wevtutil), and purges 3rd-party app caches (Browsers, Discord, Steam, GPU drivers) bypassing hidden attributes.
# ==========================================

# ------------------------------------------
# Z1: CLEANUP AUDITS (PURE RUNSPACE WORKER)
# ------------------------------------------
function Get-CleanupState {
    param([string]$Category)
    
    # Use generic lists for performance
    $rules = [System.Collections.Generic.List[hashtable]]::new()
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($Category -eq "WU") {
        $rules.Add(@{ UIDisplayName = "Windows Update Download Cache"; Path = "$env:windir\SoftwareDistribution\Download"; Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Windows Update ETW Logs"; Path = "$env:windir\Logs\WindowsUpdate"; Type = "Files" })
    }
    if ($Category -eq "Temp") {
        $rules.Add(@{ UIDisplayName = "Windows System Temp"; Path = "$env:windir\Temp"; Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Global User Temp"; Path = "$env:TEMP"; Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Type = "Files" })

        if (Test-Path "$env:windir\MEMORY.DMP" -PathType Leaf) { $rules.Add(@{ UIDisplayName = "System Memory Dump"; Path = "$env:windir\MEMORY.DMP"; Type = "Files" }) }
        if (Test-Path "$env:windir\Minidump" -PathType Container) { $rules.Add(@{ UIDisplayName = "Minidump Files"; Path = "$env:windir\Minidump"; Type = "Files" }) }

        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue
        foreach ($cimProfile in $userProfiles) {
            $userName = [System.IO.Path]::GetFileName($cimProfile.LocalPath)
            if ($userName -notmatch '^(Public|Default.*|All Users)$') {
                $rules.Add(@{ UIDisplayName = "User Temp ($userName)"; Path = "$($cimProfile.LocalPath)\AppData\Local\Temp"; Type = "Files" })
            }
        }
    }
    if ($Category -eq "EventLogs") {
        $rules.Add(@{ UIDisplayName = "Windows Event Logs"; Path = "$env:windir\System32\winevt\Logs"; Type = "EventLogs" })
    }
    if ($Category -eq "ThirdParty") {
        $userCaches = @(
            @{ Name = "Chrome"; Path = "AppData\Local\Google\Chrome\User Data\Default\Cache" }
            @{ Name = "Edge"; Path = "AppData\Local\Microsoft\Edge\User Data\Default\Cache" }
            @{ Name = "Opera"; Path = "AppData\Local\Opera Software\Opera Stable\Cache" }
            @{ Name = "Opera GX"; Path = "AppData\Local\Opera Software\Opera GX Stable\Cache" }
            @{ Name = "Discord"; Path = "AppData\Roaming\discord\Cache" }
            @{ Name = "Discord Code"; Path = "AppData\Roaming\discord\Code Cache" }
            @{ Name = "Steam"; Path = "AppData\Local\Steam\htmlcache" }
            @{ Name = "Epic Games Web"; Path = "AppData\Local\EpicGamesLauncher\Saved\webcache" }
            @{ Name = "Epic Games Http"; Path = "AppData\Local\EpicGamesLauncher\Saved\HttpCache" }
            @{ Name = "Spotify Data"; Path = "AppData\Local\Spotify\Data" }
            @{ Name = "Spotify Browser"; Path = "AppData\Local\Spotify\Browser\Cache" }
            @{ Name = "Deezer"; Path = "AppData\Roaming\deezer-desktop\Cache" }
            @{ Name = "VLC Art"; Path = "AppData\Roaming\vlc\art" }
            @{ Name = "NVIDIA DXCache"; Path = "AppData\Local\NVIDIA\DXCache" }
            @{ Name = "NVIDIA GLCache"; Path = "AppData\Local\NVIDIA\GLCache" }
            @{ Name = "AMD DxCache"; Path = "AppData\Local\AMD\DxCache" }
        )

        $globalCaches = @(
            @{ Name = "Battle.net"; Path = "$env:ProgramData\Battle.net\Cache" }
            @{ Name = "GOG Galaxy"; Path = "$env:ProgramData\GOG.com\Galaxy\webcache" }
        )

        # Dynamic profile resolution instead of hardcoded 'C:\Users'
        $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue
        foreach ($cimProfile in $userProfiles) {
            $usr = [System.IO.Path]::GetFileName($cimProfile.LocalPath)
            if ($usr -match '^(Public|Default.*|All Users)$') { continue }
            
            $base = $cimProfile.LocalPath
            
            foreach ($app in $userCaches) {
                $rules.Add(@{ UIDisplayName = "$($app.Name) Cache ($usr)"; Path = "$base\$($app.Path)"; Type = "Files" })
            }
            
            $ffProfilesPath = "$base\AppData\Local\Mozilla\Firefox\Profiles"
            if (Test-Path $ffProfilesPath -ErrorAction SilentlyContinue) {
                $ffFolders = Get-ChildItem -Path $ffProfilesPath -Directory -Force -ErrorAction SilentlyContinue
                foreach ($ff in $ffFolders) {
                    $rules.Add(@{ UIDisplayName = "Firefox Cache ($usr - $($ff.Name))"; Path = "$($ff.FullName)\cache2"; Type = "Files" })
                    $rules.Add(@{ UIDisplayName = "Firefox Startup ($usr - $($ff.Name))"; Path = "$($ff.FullName)\startupCache"; Type = "Files" })
                }
            }
        }

        foreach ($app in $globalCaches) {
            $rules.Add(@{ UIDisplayName = "$($app.Name) Cache (Global)"; Path = $app.Path; Type = "Files" })
        }
    }
    if ($Category -eq "RecycleBin") {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
            $rules.Add(@{ UIDisplayName = "Recycle Bin ($($drive.Name):)"; Path = "$($drive.Root)`$Recycle.Bin"; Type = "RecycleBin" })
        }
    }

    foreach ($rule in $rules) {
        $isDetected = $false
        $sizeMB = 0

        if (Test-Path $rule.Path -ErrorAction SilentlyContinue) {
            # Pipe directly to Measure-Object to reduce memory footprint on directories with >100k files
            $bytes = (Get-ChildItem -Path $rule.Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            
            if ($null -ne $bytes -and $bytes -gt 0) {
                $sizeMB = [math]::Round(($bytes / 1MB), 2)
            }
        }

        if ($sizeMB -ge 1) {
            $isDetected = $true
            $displayName = "$($rule.UIDisplayName) [ $sizeMB MB ]"
        } else {
            $displayName = "$($rule.UIDisplayName) [ Clean ]"
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $displayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    
    return $results
}

# ------------------------------------------
# Z1: CLEANING ENGINE
# ------------------------------------------
function Invoke-InteractiveCleanup {
    param([array]$SelectedItems)
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }

        $rule = $item.ActionData
        Write-GUI " -> Purging: $($rule.UIDisplayName)..."

        try {
            if ($rule.Type -eq "EventLogs") {
                $channels = @(wevtutil.exe el 2>$null)
                $chIdx = 0
                foreach ($ch in $channels) {
                    $chIdx++
                    if ($chIdx % 25 -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
                    & wevtutil.exe cl "$ch" 2>$null
                }
            }
            elseif ($rule.Type -eq "RecycleBin") {
                $path = $rule.Path
                & takeown.exe /F "$path\*" /R /A /D Y 2>$null | Out-Null
                # Use well-known Administrators SID (*S-1-5-32-544) for locale independence
                & icacls.exe "$path\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            elseif ($rule.Type -eq "Files") {
                # Stop update services and take ownership of restricted Windows Update folders before deletion
                if ($rule.UIDisplayName -match "Windows Update") {
                    Stop-Service -Name "wuauserv", "bits" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    $path = $rule.Path
                    & takeown.exe /F "$path\*" /R /A /D Y 2>$null | Out-Null
                    & icacls.exe "$path\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                }

                if (Test-Path -Path $rule.Path -PathType Leaf) {
                    Remove-Item -Path $rule.Path -Force -ErrorAction SilentlyContinue
                } else {
                    Remove-Item -Path "$($rule.Path)\*" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        } catch { }
    }

    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
}

# ------------------------------------------
# Z1: ASYNC EXECUTION ENGINE (VIA CORE_HELPERS)
# ------------------------------------------
function Invoke-AuditAsync {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable,
        [switch]$AuditOnly
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: $Category (Background Thread) ---"
    } else {
        Write-GUI " -> Analyzing $Category footprint (Background Thread)..."
    }
    Update-Progress 25

    $sb = (Get-Command -Name Get-CleanupState).ScriptBlock
    $isAuditOnly = $AuditOnly.IsPresent

    Invoke-AsyncTask -ScriptBlock $sb -Arguments @($Category) -ControlsToDisable $ControlsToDisable -OnComplete {
        param($output)
        Update-Progress 0
        [array]$auditData = @($output | Where-Object { $null -ne $_ })
        $detectedItems = @($auditData | Where-Object { $_.IsDetected })

        if ($isAuditOnly) {
            if ($detectedItems.Count -eq 0) {
                Write-GUI "  [OK] Clean.`n"
            } else {
                foreach ($det in $detectedItems) {
                    Write-GUI "  [ DETECTED ] $($det.UIDisplayName)"
                }
                Write-GUI "  -> Ready for purge ($($detectedItems.Count) item(s)).`n"
            }
        } else {
            if ($auditData.Count -eq 0) {
                Write-GUI "  [OK] Clean.`n"
            } else {
                $modalResult = Show-ActionModal -Title "WinUltix - $Category Purge" -Description "Select items to empty." -AuditResults $auditData
                
                if ($null -ne $modalResult -and $null -ne $modalResult.Items -and $modalResult.Items.Count -gt 0) {
                    Invoke-InteractiveCleanup -SelectedItems $modalResult.Items
                    Write-GUI " -> Operation completed.`n"
                } else {
                    Write-GUI "Operation cancelled.`n"
                }
            }
        }
    }.GetNewClosure()
}

function Initialize-Z1UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabClean = New-Object System.Windows.Forms.TabPage
    $tabClean.Text = "Cleanup"
    $tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # ------------------------------------------
    # 1. WINDOWS UPDATE CACHE
    # ------------------------------------------
    $btnWU = New-Object System.Windows.Forms.Button
    $btnWU.Text = "Clean Windows Update Cache"
    $btnWU.Location = New-Object System.Drawing.Point(15, 20)
    $btnWU.Size = New-Object System.Drawing.Size(320, 40)
    $btnWU.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnWU.ForeColor = [System.Drawing.Color]::White
    $btnWU.FlatStyle = "Flat"
    $btnWU.Add_MouseEnter({ Show-Description "Analyzes and interactively purges downloaded Windows Update caches (SoftwareDistribution) safely." })
    $btnWU.Add_MouseLeave({ Restore-Log })

    $btnAudWU = New-Object System.Windows.Forms.Button
    $btnAudWU.Text = "?"
    $btnAudWU.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudWU.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudWU.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudWU.ForeColor = [System.Drawing.Color]::White
    $btnAudWU.FlatStyle = "Flat"
    $btnAudWU.Add_MouseEnter({ Show-Description "AUDIT: Calculates the exact megabyte footprint of leftover Windows Update files." })
    $btnAudWU.Add_MouseLeave({ Restore-Log })

    $btnWU.Add_Click({ Invoke-AuditAsync -Category "WU" -ControlsToDisable @($btnWU, $btnAudWU) }.GetNewClosure())
    $btnAudWU.Add_Click({ Invoke-AuditAsync -Category "WU" -ControlsToDisable @($btnWU, $btnAudWU) -AuditOnly }.GetNewClosure())

    # ------------------------------------------
    # 2. TEMP & PREFETCH BUFFERS
    # ------------------------------------------
    $btnTemp = New-Object System.Windows.Forms.Button
    $btnTemp.Text = "Clean Temp and Prefetch Buffers"
    $btnTemp.Location = New-Object System.Drawing.Point(15, 70)
    $btnTemp.Size = New-Object System.Drawing.Size(320, 40)
    $btnTemp.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnTemp.ForeColor = [System.Drawing.Color]::White
    $btnTemp.FlatStyle = "Flat"
    $btnTemp.Add_MouseEnter({ Show-Description "Scans and weighs System Temp, Prefetch, and local Temp directories across all user profiles for interactive removal." })
    $btnTemp.Add_MouseLeave({ Restore-Log })

    $btnAudTemp = New-Object System.Windows.Forms.Button
    $btnAudTemp.Text = "?"
    $btnAudTemp.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudTemp.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudTemp.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudTemp.ForeColor = [System.Drawing.Color]::White
    $btnAudTemp.FlatStyle = "Flat"
    $btnAudTemp.Add_MouseEnter({ Show-Description "AUDIT: Weighs orphaned temporary files and prefetch data globally." })
    $btnAudTemp.Add_MouseLeave({ Restore-Log })

    $btnTemp.Add_Click({ Invoke-AuditAsync -Category "Temp" -ControlsToDisable @($btnTemp, $btnAudTemp) }.GetNewClosure())
    $btnAudTemp.Add_Click({ Invoke-AuditAsync -Category "Temp" -ControlsToDisable @($btnTemp, $btnAudTemp) -AuditOnly }.GetNewClosure())

    # ------------------------------------------
    # 3. EVENT VIEWER LOGS
    # ------------------------------------------
    $btnLogs = New-Object System.Windows.Forms.Button
    $btnLogs.Text = "Clear Event Viewer Logs"
    $btnLogs.Location = New-Object System.Drawing.Point(15, 120)
    $btnLogs.Size = New-Object System.Drawing.Size(320, 40)
    $btnLogs.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnLogs.ForeColor = [System.Drawing.Color]::White
    $btnLogs.FlatStyle = "Flat"
    $btnLogs.Add_MouseEnter({ Show-Description "Calculates the size of Event Logs (.evtx) and safely clears diagnostic history using the native wevtutil engine." })
    $btnLogs.Add_MouseLeave({ Restore-Log })

    $btnAudLogs = New-Object System.Windows.Forms.Button
    $btnAudLogs.Text = "?"
    $btnAudLogs.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudLogs.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudLogs.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudLogs.ForeColor = [System.Drawing.Color]::White
    $btnAudLogs.FlatStyle = "Flat"
    $btnAudLogs.Add_MouseEnter({ Show-Description "AUDIT: Checks the current disk space consumed by Windows Event Logs." })
    $btnAudLogs.Add_MouseLeave({ Restore-Log })

    $btnLogs.Add_Click({ Invoke-AuditAsync -Category "EventLogs" -ControlsToDisable @($btnLogs, $btnAudLogs) }.GetNewClosure())
    $btnAudLogs.Add_Click({ Invoke-AuditAsync -Category "EventLogs" -ControlsToDisable @($btnLogs, $btnAudLogs) -AuditOnly }.GetNewClosure())

    # ------------------------------------------
    # 4. THIRD-PARTY APP CACHE
    # ------------------------------------------
    $btnThirdParty = New-Object System.Windows.Forms.Button
    $btnThirdParty.Text = "Clean Third-Party App Cache"
    $btnThirdParty.Location = New-Object System.Drawing.Point(15, 170)
    $btnThirdParty.Size = New-Object System.Drawing.Size(320, 40)
    $btnThirdParty.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnThirdParty.ForeColor = [System.Drawing.Color]::White
    $btnThirdParty.FlatStyle = "Flat"
    $btnThirdParty.Add_MouseEnter({ Show-Description "Locates bloated application caches (Edge, Chrome, Discord, DxCache) across all user profiles for precise cleanup." })
    $btnThirdParty.Add_MouseLeave({ Restore-Log })

    $btnAudThirdParty = New-Object System.Windows.Forms.Button
    $btnAudThirdParty.Text = "?"
    $btnAudThirdParty.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudThirdParty.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudThirdParty.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudThirdParty.ForeColor = [System.Drawing.Color]::White
    $btnAudThirdParty.FlatStyle = "Flat"
    $btnAudThirdParty.Add_MouseEnter({ Show-Description "AUDIT: Aggregates the storage space wasted by third-party caches." })
    $btnAudThirdParty.Add_MouseLeave({ Restore-Log })

    $btnThirdParty.Add_Click({ Invoke-AuditAsync -Category "ThirdParty" -ControlsToDisable @($btnThirdParty, $btnAudThirdParty) }.GetNewClosure())
    $btnAudThirdParty.Add_Click({ Invoke-AuditAsync -Category "ThirdParty" -ControlsToDisable @($btnThirdParty, $btnAudThirdParty) -AuditOnly }.GetNewClosure())

    # ------------------------------------------
    # 5. RECYCLE BIN
    # ------------------------------------------
    $btnRecycle = New-Object System.Windows.Forms.Button
    $btnRecycle.Text = "Hard Empty Recycle Bin (NTFS)"
    $btnRecycle.Location = New-Object System.Drawing.Point(15, 220)
    $btnRecycle.Size = New-Object System.Drawing.Size(320, 40)
    $btnRecycle.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnRecycle.ForeColor = [System.Drawing.Color]::White
    $btnRecycle.FlatStyle = "Flat"
    $btnRecycle.Add_MouseEnter({ Show-Description "Scans all logical partitions for Recycle Bin contents and forcefully purges them, bypassing standard file locks." })
    $btnRecycle.Add_MouseLeave({ Restore-Log })

    $btnAudRecycle = New-Object System.Windows.Forms.Button
    $btnAudRecycle.Text = "?"
    $btnAudRecycle.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudRecycle.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudRecycle.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnAudRecycle.ForeColor = [System.Drawing.Color]::White
    $btnAudRecycle.FlatStyle = "Flat"
    $btnAudRecycle.Add_MouseEnter({ Show-Description "AUDIT: Reports the total size of deleted files waiting in the Recycle Bins across all partitions." })
    $btnAudRecycle.Add_MouseLeave({ Restore-Log })

    $btnRecycle.Add_Click({ Invoke-AuditAsync -Category "RecycleBin" -ControlsToDisable @($btnRecycle, $btnAudRecycle) }.GetNewClosure())
    $btnAudRecycle.Add_Click({ Invoke-AuditAsync -Category "RecycleBin" -ControlsToDisable @($btnRecycle, $btnAudRecycle) -AuditOnly }.GetNewClosure())

    # Add controls to tab
    $tabClean.Controls.AddRange(@(
        $btnWU, $btnAudWU, 
        $btnTemp, $btnAudTemp, 
        $btnLogs, $btnAudLogs, 
        $btnThirdParty, $btnAudThirdParty, 
        $btnRecycle, $btnAudRecycle
    ))
    
    $TabControl.Controls.Add($tabClean)
}
# <<< END INJECTED MODULE: Z1_Cleanup.ps1 <<<


# Z2_Bloatware: Aggressive debloatifier. Incorporates CBS and Appx state verification. Enhanced OneDrive removal across profiles, FOD package management, and intelligent orphaned framework collection (Garbage Collector).
# . (Join-Path $ModulesDir "Z2_Bloatware.ps1")
# >>> BEGIN INJECTED MODULE: Z2_Bloatware.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE
# Z2_Bloatware: Aggressive debloatifier. Uninstalls OneDrive (iterating through profiles), removes FOD packages (Capabilities), cleans orphaned Appx frameworks (Garbage Collector), and mass-removes preinstalled UWP bloatware.
# ==========================================

# ------------------------------------------
# Z2: BLOATWARE AUDITS (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-OneDriveState {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # 1. Core Executables & Run Keys (SystemRoot stubs are left dormant for SFC/DISM integrity, so check active user payload/startup)
    $localExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    $runKey   = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
    $liveProc = Get-Process -Name "OneDrive", "OneDriveSetup" -ErrorAction SilentlyContinue

    $isCoreDetected = ((Test-Path $localExe) -or ($null -ne $runKey) -or ($null -ne $liveProc))
    
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup and Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    })

    # 2. Zombie Registry Keys
    $zombieKeys = @("HKCU:\Software\Microsoft\OneDrive\SyncEngine", "HKCU:\Software\Microsoft\OneDrive\Client_Policy")
    foreach ($key in $zombieKeys) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Registry: $($key | Split-Path -Leaf)"
            IsDetected    = (Test-Path -Path $key)
            ActionData    = @{ Type = "Registry"; Path = $key }
        })
    }

    # 3. System Data Folders
    $staticFolders = @("$env:PROGRAMDATA\Microsoft OneDrive", "$env:SystemDrive\OneDriveTemp")
    foreach ($folder in $staticFolders) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Folder: $folder"
            IsDetected    = (Test-Path -Path $folder)
            ActionData    = @{ Type = "Folder"; Path = $folder }
        })
    }

    # 4. Dynamic User Profiles Data Folders (Zero hardcoded C:\Users)
    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue
    foreach ($cimProfile in $userProfiles) {
        $userName = [System.IO.Path]::GetFileName($cimProfile.LocalPath)
        if ($userName -notmatch '^(Public|Default.*|All Users)$') {
            $userPath = Join-Path -Path $cimProfile.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
            $results.Add([PSCustomObject]@{
                UIDisplayName = "User Data: $userName"
                IsDetected    = (Test-Path -Path $userPath)
                ActionData    = @{ Type = "Folder"; Path = $userPath }
            })
        }
    }

    return $results
}

function Get-CapabilitiesState {
    $capsWildcards = @("*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*", "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*", "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*", "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*", "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*")
    
    $installedCaps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Installed' })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($capName in $capsWildcards) {
        $found = @($installedCaps | Where-Object { $_.Name -like $capName })
        $isDetected = ($found.Count -gt 0)
        $cleanName = $capName.Replace("*", "") 

        $results.Add([PSCustomObject]@{
            UIDisplayName = "FOD: $cleanName"
            IsDetected    = $isDetected
            ActionData    = $found
        })
    }
    return $results
}

function Get-GarbageCollectorState {
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $standardApps = @($allPackages | Where-Object { $_.IsFramework -eq $false })
    
    $activeDependencies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($app in $standardApps) { 
        if ($app.Dependencies) {
            foreach ($dep in $app.Dependencies) {
                [void]$activeDependencies.Add($dep.PackageFullName)
            }
        }
    }
    
    # Complete protected framework whitelist per WinUltix architecture standards
    $critical = "Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
    $frameworks = @($allPackages | Where-Object { $_.IsFramework -eq $true -and $_.Name -notmatch $critical })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($fw in $frameworks) { 
        if (-not $activeDependencies.Contains($fw.PackageFullName)) { 
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Framework: $($fw.Name)"
                IsDetected    = $true
                ActionData    = @{ Type = "Framework"; Target = $fw.PackageFullName }
            })
        } 
    }
    
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($prov in $provisioned) { 
        if (-not ($allPackages | Where-Object { $_.Name -eq $prov.DisplayName })) { 
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Base: $($prov.DisplayName)"
                IsDetected    = $true
                ActionData    = @{ Type = "Provisioned"; Target = $prov.PackageName }
            })
        } 
    } 
    return $results
}

function Get-BloatwareState {
    # Ordered, non-overlapping definitions with clear UI labels matching Windows 11 24H2/25H2/26H2 packages
    $appCatalog = @(
        @{ Label = "Microsoft Bing Search (BingSearch)";          Pattern = "*BingSearch*" }
        @{ Label = "Microsoft News (BingNews)";                   Pattern = "*BingNews*" }
        @{ Label = "Microsoft Weather (BingWeather)";             Pattern = "*BingWeather*" }
        @{ Label = "Microsoft Finance / Sports / Food (Bing)";    Pattern = "Microsoft.BingFinance|Microsoft.BingSports|Microsoft.BingFoodAndDrink|Microsoft.BingTravel|Microsoft.BingHealthAndFitness|Microsoft.BingTranslator" }
        @{ Label = "Microsoft To Do (Todos)";                     Pattern = "*Todos*" }
        @{ Label = "Microsoft Sticky Notes (StickyNotes)";        Pattern = "*StickyNotes*" }
        @{ Label = "Microsoft Teams Personal / Work (MSTeams)";   Pattern = "*MSTeams*|*MicrosoftTeams*" }
        @{ Label = "New Outlook for Windows (OutlookForWindows)"; Pattern = "*OutlookForWindows*" }
        @{ Label = "Mail & Calendar (CommunicationsApps)";        Pattern = "*windowscommunicationsapps*" }
        @{ Label = "Microsoft 365 / Office Hub";                  Pattern = "*MicrosoftOfficeHub*" }
        @{ Label = "Microsoft OneNote (UWP)";                     Pattern = "*OneNote*" }
        @{ Label = "Microsoft Family Safety";                     Pattern = "*MicrosoftFamily*|*Family*" }
        @{ Label = "Microsoft Clipchamp Video Editor";            Pattern = "*Clipchamp*" }
        @{ Label = "Windows Dev Home (DevHome)";                  Pattern = "*DevHome*" }
        @{ Label = "Power Automate Desktop";                      Pattern = "*PowerAutomateDesktop*" }
        @{ Label = "Windows Copilot & AI Assistant";              Pattern = "*Copilot*" }
        @{ Label = "Microsoft Edge Game Assist";                  Pattern = "*Edge.GameAssist*" }
        @{ Label = "Windows Widgets (Client.WebExperience)";      Pattern = "*Client.WebExperience*" }
        @{ Label = "Widgets Platform Runtime";                    Pattern = "*WidgetsPlatformRuntime*" }
        @{ Label = "Cross Device Experience Host";                Pattern = "*CrossDevice*" }
        @{ Label = "Phone Link (YourPhone)";                      Pattern = "*YourPhone*" }
        @{ Label = "Quick Assist (Remote Help)";                  Pattern = "*QuickAssist*" }
        @{ Label = "Windows Feedback Hub";                        Pattern = "*FeedbackHub*" }
        @{ Label = "Get Help (Contact Support)";                  Pattern = "*GetHelp*" }
        @{ Label = "Windows Tips (GetStarted)";                   Pattern = "*Getstarted*" }
        @{ Label = "Windows Maps";                                Pattern = "*WindowsMaps*" }
        @{ Label = "Windows Alarms & Clock";                      Pattern = "*WindowsAlarms*" }
        @{ Label = "Windows Voice Recorder (SoundRecorder)";      Pattern = "*SoundRecorder*" }
        @{ Label = "Windows Camera";                              Pattern = "*WindowsCamera*" }
        @{ Label = "Windows Photos";                              Pattern = "*Windows.Photos*" }
        @{ Label = "Media Player / Groove Music (ZuneMusic)";     Pattern = "*ZuneMusic*" }
        @{ Label = "Movies & TV (ZuneVideo)";                     Pattern = "*ZuneVideo*" }
        @{ Label = "Microsoft Solitaire Collection";              Pattern = "*SolitaireCollection*" }
        @{ Label = "Xbox App (GamingApp)";                        Pattern = "*GamingApp*|*XboxApp*" }
        @{ Label = "Xbox Game Bar (XboxGamingOverlay)";           Pattern = "*XboxGamingOverlay*" }
        @{ Label = "Xbox Speech To Text Overlay";                 Pattern = "*XboxSpeechToTextOverlay*" }
        @{ Label = "Xbox TCUI (Live In-Game Experience)";         Pattern = "*Xbox.TCUI*" }
        @{ Label = "Microsoft People";                            Pattern = "*Microsoft.People*" }
        @{ Label = "Skype UWP";                                   Pattern = "*SkypeApp*" }
        @{ Label = "Cortana";                                     Pattern = "*Cortana*" }
        @{ Label = "Mixed Reality Portal";                        Pattern = "*MixedReality*" }
        @{ Label = "3D Builder & 3D Viewer";                      Pattern = "*3DBuilder*|*3DViewer*" }
        @{ Label = "OneDrive UWP Sync Client";                    Pattern = "*OneDriveSync*" }
        @{ Label = "Third-Party Games (CandyCrush / Disney / etc.)"; Pattern = "*CandyCrush*|*BubbleWitch*|*FarmHeroes*|*MarchofEmpires*|*Homescapes*|*Township*|*Disney*" }
        @{ Label = "Third-Party Social & Media (TikTok / Spotify / etc.)"; Pattern = "*TikTok*|*Instagram*|*Facebook*|*Twitter*|*LinkedIn*|*Netflix*|*Spotify*|*Amazon*" }
        @{ Label = "OEM & Antivirus Bloat (McAfee / Norton / OEM)"; Pattern = "*McAfee*|*Norton*|*Lenovo*|*Dell*|*HP*" }
    )

    $protectedRegex = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|WindowsStore|StorePurchaseApp|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|ApplicationCompatibilityEnhancements|MicrosoftEdge\.Stable"

    $installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
    $provAppx      = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })

    $seenInstalled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenProv      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results       = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($entry in $appCatalog) {
        $patterns = $entry.Pattern -split '\|'

        $foundInstalled = [System.Collections.Generic.List[object]]::new()
        foreach ($pkg in $installedAppx) {
            if ($seenInstalled.Contains($pkg.PackageFullName)) { continue }
            foreach ($pat in $patterns) {
                if ($pkg.Name -like $pat) {
                    $foundInstalled.Add($pkg)
                    [void]$seenInstalled.Add($pkg.PackageFullName)
                    break
                }
            }
        }

        $foundProv = [System.Collections.Generic.List[object]]::new()
        foreach ($prov in $provAppx) {
            if ($seenProv.Contains($prov.PackageName)) { continue }
            foreach ($pat in $patterns) {
                if ($prov.DisplayName -like $pat) {
                    $foundProv.Add($prov)
                    [void]$seenProv.Add($prov.PackageName)
                    break
                }
            }
        }

        $totalSizeMB = 0
        foreach ($pkg in $foundInstalled) {
            $loc = $pkg.InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path $loc)) {
                $bytes = (Get-ChildItem -Path $loc -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($null -ne $bytes) { $totalSizeMB += ($bytes / 1MB) }
            }
        }

        # Every registered package in Get-AppxPackage or Provisioned store is flagged for removal (no 10MB blind spot)
        $isDetected = ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)

        $sizeLabel = ""
        if ($isDetected) {
            if ($totalSizeMB -ge 0.5) {
                $sizeLabel = " [ $([math]::Round($totalSizeMB, 1)) MB ]"
            } elseif ($foundInstalled.Count -gt 0) {
                $sizeLabel = " [ Installed Stub ]"
            } elseif ($foundProv.Count -gt 0) {
                $sizeLabel = " [ Provisioned Image ]"
            }
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = "$($entry.Label)$sizeLabel"
            IsDetected    = $isDetected
            ActionData    = @{ Installed = @($foundInstalled); Provisioned = @($foundProv) }
        })
    }

    return $results
}

function Get-CapabilityStubState {
    # Queries CBS directly for any installed packages acting as empty shells/stubs
    $cbsStubs = @(Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match "(?i)stub" -and $_.PackageState -eq "Installed" })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($stub in $cbsStubs) {
        $cleanName = ($stub.PackageName -split '~')[0]
        $results.Add([PSCustomObject]@{
            UIDisplayName = "CBS Stub: $cleanName"
            IsDetected    = $true
            ActionData    = $stub.PackageName
        })
    }
    return $results
}

# ------------------------------------------
# Z2: BLOATWARE & APPS ENGINE
# ------------------------------------------
function Invoke-RemoveOneDrive {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No OneDrive components selected. Aborting."; return }
    $current = 0
    
    # Pre-kill all OneDrive and companion processes holding handles
    Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        $data = $item.ActionData
        try {
            if ($data.Type -eq "Core") {
                $setupX64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                $setupX86 = "$env:SystemRoot\System32\OneDriveSetup.exe"

                if (Test-Path $setupX64) { 
                    Start-Process $setupX64 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                } elseif (Test-Path $setupX86) { 
                    Start-Process $setupX86 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                }
                
                Start-Sleep -Seconds 2
                Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue

                # Neutralize execution vectors while preserving dormant SystemRoot binary for SFC/DISM integrity
                reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>$null | Out-Null
                
                Write-GUI "    [+] Core installation payloads purged. SystemRoot stubs neutralized."
            }
            elseif ($data.Type -eq "Registry") {
                if (Test-Path -Path $data.Path) { Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop }
            }
            elseif ($data.Type -eq "Folder") {
                $targetDir = $data.Path
                if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
                    & takeown.exe /F "$targetDir" /R /A /D Y 2>$null | Out-Null
                    & icacls.exe "$targetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null

                    # Evacuate memory-mapped shell extensions (e.g., FileSyncShell64.dll locked by explorer.exe)
                    # Using explicit foreach variable ($dll) so catch block does not overwrite $_ with ErrorRecord
                    $dllFiles = @(Get-ChildItem -LiteralPath $targetDir -Filter "*.dll" -Recurse -File -Force -ErrorAction SilentlyContinue)
                    foreach ($dll in $dllFiles) {
                        $dllPath = $dll.FullName
                        $dllName = $dll.Name
                        if ([string]::IsNullOrWhiteSpace($dllPath)) { continue }

                        try {
                            $dll.Attributes = 'Normal'
                            Remove-Item -LiteralPath $dllPath -Force -ErrorAction Stop
                        } catch {
                            $trashPath = Join-Path -Path $env:TEMP -ChildPath "WinUltix_Locked_${dllName}_$([guid]::NewGuid().ToString('N')).tmp"
                            Move-Item -LiteralPath $dllPath -Destination $trashPath -Force -ErrorAction SilentlyContinue
                        }
                    }

                    # Strip ReadOnly/Hidden/System attributes from remaining items and wipe directory
                    Get-ChildItem -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try { $_.Attributes = 'Normal' } catch {}
                    }
                    Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue

                    # Final fallback: if directory still exists due to an open directory handle in Explorer, cycle explorer.exe
                    if (Test-Path -LiteralPath $targetDir) {
                        Write-GUI "    [*] Releasing Shell Extension lock via Explorer refresh..."
                        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 600
                        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
                        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                            Start-Process "explorer.exe"
                        }
                    }
                    Write-GUI "    [OK] Folder eradicated: $targetDir"
                }
            }
        } catch {
            Write-GUI "    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)"
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Selected OneDrive components eliminated."
}

function Invoke-RemoveCapabilities {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Removing Capability: $($item.UIDisplayName)"
        foreach ($cap in $item.ActionData) {
            try { Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null } catch { }
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> System features removal completed."
}

function Invoke-GarbageCollector {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> System clean or operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Cleaning: $($item.UIDisplayName)"
        try {
            if ($item.ActionData.Type -eq "Framework") {
                Remove-AppxPackage -Package $item.ActionData.Target -AllUsers -ErrorAction Stop
            } elseif ($item.ActionData.Type -eq "Provisioned") {
                Remove-AppxProvisionedPackage -Online -PackageName $item.ActionData.Target -ErrorAction Stop | Out-Null
            }
        } catch { Write-GUI "    [!] Error removing $($item.UIDisplayName): $($_.Exception.Message)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Appx Garbage Collector finished its run."
}

function Invoke-RemoveBloatware {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }
    $current = 0

    Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        if ($item.UIDisplayName -match "(?i)Copilot") {
            Write-GUI "    [*] Applying local policy constraints for Copilot..."
            $policies = @(
                "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
                "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
            )
            foreach ($pol in $policies) {
                if (-not (Test-Path $pol)) { New-Item -Path $pol -Force | Out-Null }
                Set-ItemProperty -Path $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
            }
        }

        # 1. Process Installed Packages (AllUsers + CurrentUser fallback)
        foreach ($pkg in $item.ActionData.Installed) {
            $pfn = $pkg.PackageFamilyName
            
            try {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                } catch {
                    # Fallback for packages staged only in the current user context
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                }
                
                # Register in Deprovisioned store to prevent Windows Update from reinstalling it
                if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                    $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                    if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                }
                Write-GUI "    [+] Removed Appx: $($pkg.Name)"
            } catch { 
                if ($pkg.Name -match "(?i)Copilot") {
                    Write-GUI "    [!] API uninstallation blocked for $($pkg.Name). Relying on GPO lockdown."
                } else {
                    Write-GUI "    [-] Error removing $($pkg.Name): $($_.Exception.Message)"
                }
            }
        }
        
        # 2. Process Provisioned Packages (Only if still present after Remove-AppxPackage -AllUsers)
        $remainingProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        foreach ($prov in $item.ActionData.Provisioned) {
            $stillProvisioned = $remainingProv | Where-Object { $_.PackageName -eq $prov.PackageName }
            if ($null -eq $stillProvisioned) { continue }

            try { 
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                Write-GUI "    [+] Deprovisioned base image: $($prov.DisplayName)"
            } catch {
                # Ignore 0x80070002 / 0x80070003 if Remove-AppxPackage -AllUsers already wiped the staging directory
                if ($_.Exception.Message -notmatch "(?i)nie można odnaleźć|cannot find|0x80070002|0x80070003") {
                    Write-GUI "    [-] Error deprovisioning $($prov.DisplayName): $($_.Exception.Message)"
                }
            }
        }
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Aggressive Bloatware Removal completed."
}

function Invoke-RemoveCapabilityStubs {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No stubs selected. Operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging CBS Stub: $($item.UIDisplayName)"
        try {
            # Strips the underlying package, implicitly removing it from Get-WindowsCapability payload list
            Remove-WindowsPackage -Online -PackageName $item.ActionData -NoRestart -ErrorAction Stop | Out-Null
        } catch { 
            Write-GUI "    [!] Error purging stub: $($_.Exception.Message)" 
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> CBS capability stubs successfully eradicated."
}

# ------------------------------------------
# Z2: ASYNC SCANNER DISPATCHER (VIA CORE_HELPERS)
# ------------------------------------------
function Invoke-Z2ScannerAsync {
    param(
        [Parameter(Mandatory=$true)][string]$ScannerFunction,
        [Parameter(Mandatory=$true)][string]$AuditLabel,
        [string]$ModalTitle = "",
        [string]$ModalDescription = "",
        [string]$ExecutorFunction = "",
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable,
        [switch]$AuditOnly,
        [switch]$SkipModalIfClean
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: $AuditLabel (Background Thread) ---"
    } else {
        Write-GUI " -> Initializing $AuditLabel Scanner (Background Thread)..."
    }
    Update-Progress 25

    $sb = (Get-Command -Name $ScannerFunction).ScriptBlock
    $isAuditOnly = $AuditOnly.IsPresent
    $skipIfClean = $SkipModalIfClean.IsPresent

    Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $ControlsToDisable -OnComplete {
        param($output)
        Update-Progress 0
        [array]$auditData = @($output | Where-Object { $null -ne $_ })
        $detected = @($auditData | Where-Object { $_.IsDetected })

        if ($isAuditOnly) {
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] Found: $($d.UIDisplayName)" }
                Write-GUI "-> STATUS: $($detected.Count) item(s) detected.`n"
            } else {
                Write-GUI "  [OK] System clean.`n"
            }
            return
        }

        if ($skipIfClean -and $detected.Count -eq 0) {
            Write-GUI "  [OK] System is completely clean. Nothing to remove.`n"
            return
        }

        $selectedData = Show-ActionModal -Title $ModalTitle -Description $ModalDescription -AuditResults $auditData
        if ($null -ne $selectedData -and $null -ne $selectedData.Items -and $selectedData.Items.Count -gt 0) {
            & $ExecutorFunction -SelectedItems $selectedData.Items
            Write-GUI ""
        } else {
            Write-GUI "Operation cancelled.`n"
        }
    }.GetNewClosure()
}

function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloatware"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # OneDrive
    $btnOneDrive = New-Object System.Windows.Forms.Button
    $btnOneDrive.Text = "Uninstall and Deprovision OneDrive"
    $btnOneDrive.Location = New-Object System.Drawing.Point(15, 20)
    $btnOneDrive.Size = New-Object System.Drawing.Size(320, 40)
    $btnOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 100)
    $btnOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnOneDrive.FlatStyle = "Flat"
    $btnOneDrive.Add_MouseEnter({ Show-Description "Completely uninstalls OneDrive, burns it from the Registry, and physically deletes folders across all profiles." })

    $btnAudOneDrive = New-Object System.Windows.Forms.Button
    $btnAudOneDrive.Text = "?"
    $btnAudOneDrive.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudOneDrive.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnAudOneDrive.FlatStyle = "Flat"
    $btnAudOneDrive.Add_MouseEnter({ Show-Description "AUDIT: Scans for active OneDrive installers and startup keys." })

    $btnOneDrive.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable @($btnOneDrive, $btnAudOneDrive) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudOneDrive.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable @($btnOneDrive, $btnAudOneDrive) -AuditOnly
    }.GetNewClosure())

    # Capabilities (FOD)
    $btnCaps = New-Object System.Windows.Forms.Button
    $btnCaps.Text = "Remove System Features (FOD)"
    $btnCaps.Location = New-Object System.Drawing.Point(15, 70)
    $btnCaps.Size = New-Object System.Drawing.Size(320, 40)
    $btnCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCaps.ForeColor = [System.Drawing.Color]::White
    $btnCaps.FlatStyle = "Flat"
    $btnCaps.Add_MouseEnter({ Show-Description "Interactive removal of optional built-in Features on Demand (FOD)." })

    $btnAudCaps = New-Object System.Windows.Forms.Button
    $btnAudCaps.Text = "?"
    $btnAudCaps.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudCaps.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudCaps.ForeColor = [System.Drawing.Color]::White
    $btnAudCaps.FlatStyle = "Flat"
    $btnAudCaps.Add_MouseEnter({ Show-Description "AUDIT: Verifies installed unnecessary Capabilities (FOD)." })

    $btnCaps.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable @($btnCaps, $btnAudCaps)
    }.GetNewClosure())
    $btnAudCaps.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable @($btnCaps, $btnAudCaps) -AuditOnly
    }.GetNewClosure())

    # Aggressive Bloatware
    $btnBloat = New-Object System.Windows.Forms.Button
    $btnBloat.Text = "Aggressive Bloatware Removal (Appx)"
    $btnBloat.Location = New-Object System.Drawing.Point(15, 120)
    $btnBloat.Size = New-Object System.Drawing.Size(320, 40)
    $btnBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnBloat.ForeColor = [System.Drawing.Color]::White
    $btnBloat.FlatStyle = "Flat"
    $btnBloat.Add_MouseEnter({ Show-Description "Aggressive, interactive removal of junk Appx applications from the system." })

    $btnAudBloat = New-Object System.Windows.Forms.Button
    $btnAudBloat.Text = "?"
    $btnAudBloat.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudBloat.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudBloat.ForeColor = [System.Drawing.Color]::White
    $btnAudBloat.FlatStyle = "Flat"
    $btnAudBloat.Add_MouseEnter({ Show-Description "AUDIT: Scans the system for target Appx Bloatware and prints a report." })

    $btnBloat.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable @($btnBloat, $btnAudBloat)
    }.GetNewClosure())
    $btnAudBloat.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable @($btnBloat, $btnAudBloat) -AuditOnly
    }.GetNewClosure())

    # Garbage Collector
    $btnGC = New-Object System.Windows.Forms.Button
    $btnGC.Text = "Run Appx Garbage Collector"
    $btnGC.Location = New-Object System.Drawing.Point(15, 170)
    $btnGC.Size = New-Object System.Drawing.Size(320, 40)
    $btnGC.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 80, 40)
    $btnGC.ForeColor = [System.Drawing.Color]::White
    $btnGC.FlatStyle = "Flat"
    $btnGC.Add_MouseEnter({ Show-Description "Intelligently scans application dependencies and removes orphaned frameworks." })

    $btnAudGC = New-Object System.Windows.Forms.Button
    $btnAudGC.Text = "?"
    $btnAudGC.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudGC.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGC.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudGC.ForeColor = [System.Drawing.Color]::White
    $btnAudGC.FlatStyle = "Flat"
    $btnAudGC.Add_MouseEnter({ Show-Description "AUDIT: Scans and lists all orphaned frameworks that will be removed." })

    $btnGC.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable @($btnGC, $btnAudGC) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudGC.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable @($btnGC, $btnAudGC) -AuditOnly
    }.GetNewClosure())

    # CBS Capability Stubs
    $btnStubs = New-Object System.Windows.Forms.Button
    $btnStubs.Text = "Purge Capability Stubs (CBS)"
    $btnStubs.Location = New-Object System.Drawing.Point(15, 220)
    $btnStubs.Size = New-Object System.Drawing.Size(320, 40)
    $btnStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 100)
    $btnStubs.ForeColor = [System.Drawing.Color]::White
    $btnStubs.FlatStyle = "Flat"
    $btnStubs.Add_MouseEnter({ Show-Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." })

    $btnAudStubs = New-Object System.Windows.Forms.Button
    $btnAudStubs.Text = "?"
    $btnAudStubs.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudStubs.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudStubs.ForeColor = [System.Drawing.Color]::White
    $btnAudStubs.FlatStyle = "Flat"
    $btnAudStubs.Add_MouseEnter({ Show-Description "AUDIT: Queries CBS registry/payload directly for active stubs." })

    $btnStubs.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable @($btnStubs, $btnAudStubs) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudStubs.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable @($btnStubs, $btnAudStubs) -AuditOnly
    }.GetNewClosure())

    $tabApps.Controls.AddRange(@($btnOneDrive, $btnAudOneDrive, $btnCaps, $btnAudCaps, $btnBloat, $btnAudBloat, $btnGC, $btnAudGC, $btnStubs, $btnAudStubs))
    $TabControl.Controls.Add($tabApps)
}
# <<< END INJECTED MODULE: Z2_Bloatware.ps1 <<<


# Z3_Registry: Main registry engine (Invoke-ApplyRegistry) featuring dedicated revert modals. Manages UI tweaks, telemetry blocks, gaming optimizations (VBS/HVCI, GameDVR), and implements Software Restriction Policies (SRP).
# . (Join-Path $ModulesDir "Z3_Registry.ps1")
# >>> BEGIN INJECTED MODULE: Z3_Registry.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z3_REGISTRY.PS1 - REGISTRY ENGINE MODULE
# Z3_Registry: Main registry engine (Invoke-ApplyRegistry). Modulates UI (classic taskbar, Start menu), disables telemetry and data collection, optimizes background services (Edge, Defender), applies gaming tweaks (MMCSS, disabling VBS/HVCI, GameDVR), and disables mouse acceleration.
# ==========================================

# ------------------------------------------
# Z3: REGISTRY AUDIT HELPER
# ------------------------------------------
function Invoke-RegistryAudit {
    param([array]$Rules)
    
    $results = @()
    foreach ($rule in $Rules) {
        $isDetected = $true
        $keyExists  = Test-Path -Path $rule.Path
        $currentValue = $null
        $valueExists  = $false

        if ($keyExists) {
            if ($rule.Name -eq "" -or $rule.Name -eq "(Default)") {
                $regKey = Get-Item -Path $rule.Path -ErrorAction SilentlyContinue
                if ($null -ne $regKey -and $null -ne $regKey.GetValue($null, $null)) {
                    $currentValue = $regKey.GetValue("")
                    $valueExists  = $true
                }
            } else {
                $prop = Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue
                if ($null -ne $prop -and $prop.PSObject.Properties.Match($rule.Name).Count -gt 0) {
                    $currentValue = $prop.$($rule.Name)
                    $valueExists  = $true
                }
            }
        }
        
        if ($rule.ContainsKey("ValidValues")) {
            if ($valueExists -and ($rule.ValidValues -contains $currentValue)) { 
                $isDetected = $false 
            }
        } else {
            if ($valueExists -and ([string]$currentValue -eq [string]$rule.Expected)) { 
                $isDetected = $false 
            }
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

# ------------------------------------------
# Z3: REGISTRY AUDITS
# ------------------------------------------
function Get-RegState_Taskbar {
    $rules = @(
        @{ UIDisplayName = "Taskbar: Align to Left (Disables Windows 11 center alignment)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Show Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Search Box (Saves space)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Expected = 0; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Disable Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; Expected = 3; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Enable 'End Task' on right-click (Dev feature)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Enforce Classic Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Web Search (Forces local-only, faster search)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Hide Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Search Highlights (Bing bloat)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableSearchBoxSearchHighlights"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Tailored Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowTailoredSearch"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Toast Notifications"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "ToastEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Focus Assist (Global)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"; Name = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Push Notifications (Policy)"; Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoToastApplicationNotification"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Bing Web Results (Keeps local queries private)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Connected Cloud Search Services"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Location Tracking in Search"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchToUseLocation"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Force Local-Only UI (Disable Bing Search UI)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Search Highlights (Dynamic Web Content)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableDynamicContentInWSB"; Expected = 0; Default = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Explorer {
    $rules = @(
        @{ UIDisplayName = "Explorer: Open to 'This PC' instead of Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show hidden files and folders"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show known file extensions (Security)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Run folder windows in a separate process (Stability)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "SeparateProcess"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Expand navigation pane to current folder"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "NavPaneExpandToCurrentFolder"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Hide Cloud Files in Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = "ShowCloudFilesInQuickAccess"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Context Menu: Restore Classic Win10 Style"; Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ""; Expected = ""; Default = "DELETE_KEY"; Type = "String" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon on Desktop"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon (Classic Start)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (64-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (32-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Reduce Menu Show Delay from 400ms to 50ms"; Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; Expected = "50"; Default = "400"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Annoyances {
    $rules = @(
        @{ UIDisplayName = "Power: Disable Modern Standby S0 (Force Hardware S3 Sleep)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"; Name = "PlatformAoAcOverride"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable AutoPlay for all drives"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255; Default = 91; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Autoplay Handlers"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"; Name = "DisableAutoplay"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Accessibility: Disable Sticky Keys prompt (Shift x5)"; Path = "HKCU:\Control Panel\Accessibility\StickyKeys"; Name = "Flags"; Expected = "506"; Default = "510"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Filter Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"; Name = "Flags"; Expected = "122"; Default = "126"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Toggle Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\ToggleKeys"; Name = "Flags"; Expected = "58"; Default = "62"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Privacy {
    $rules = @()
    $rules += @{ UIDisplayName = "Privacy: Suppress UX Experience Reporting (Telemetry)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\ExperienceReporting"; Name = "SuppressExperienceReporting"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Block OS Telemetry & Data Collection"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Expected = 0; Default = 3; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable App Advertising ID"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Timeline & Activity History tracking"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Tailored Experiences"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Cloud Speech Recognition"; Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Restrict Implicit Ink/Text Collection"; Path = "HKCU:\Software\Microsoft\InputPersonalization"; Name = "RestrictImplicitInkCollection"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Background Apps: Block UWP apps from running globally"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Expected = 1; Default = 0; Type = "DWord" }
    
    $uwpBlocks = @("LetAppsRunInBackground", "LetAppsAccessSync", "LetAppsAccessIdentity", "LetAppsAccessBluetooth", "LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo")
    foreach ($app in $uwpBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" } }
    
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessCamera"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessCamera"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessMicrophone"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessMicrophone"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    
    $rules += @{ UIDisplayName = "Edge: Disable Startup Boost (Background Process)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Edge: Disable Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Defender: Prevent automatic sample submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; Expected = 2; Default = 1; Type = "DWord" }
    
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rules += @{ UIDisplayName = "Junk Blocker: Disable Content Delivery ($k)"; Path = $cdm; Name = $k; Expected = 0; Default = 1; Type = "DWord" } }
    
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_SystemBoot {
    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Block BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive Network Traffic Pre-Sign-In"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "PreventNetworkTrafficPreUserSignIn"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Remote Desktop (RDP) access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Disable Insider Preview Builds"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"; Name = "AllowBuildPreview"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Enable Verbose Status Messages"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "verbosestatus"; Expected = 1; Default = 0; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Mouse {
    $rules = @(
        @{ UIDisplayName = "Mouse: Disable 'Enhance pointer precision' (Raw Input)"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseSpeed"; Expected = "0"; Default = "1"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 1"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold1"; Expected = "0"; Default = "6"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 2"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold2"; Expected = "0"; Default = "10"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Gaming {
    $rules = @(
        @{ UIDisplayName = "Gaming: Disable Xbox GameDVR (Reduces stuttering)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Store Config"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Frame Rate Cap (VSync bypass)"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_CapFrameRate"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Optimize FullScreen Exclusive Behavior"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; Expected = 2; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Hardware Accelerated GPU Scheduling (HAGS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Expected = 2; Default = 1; ValidValues = @(2); Type = "DWord" }
        @{ UIDisplayName = "Kernel: Disable Paging Executive (Keeps core system in RAM)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS: System Responsiveness (Allocate 100% CPU to Games)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; Expected = 0; Default = 20; Type = "DWord" }
        @{ UIDisplayName = "Network: Remove MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Expected = 4294967295; Default = 10; Type = "DWord" }
        @{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Default = "Medium"; Type = "String" }
        @{ UIDisplayName = "Security: Disable Virtualization Based Security (VBS)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Hypervisor-protected Code Integrity (HVCI)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

# ------------------------------------------
# Z3: SRP (SOFTWARE RESTRICTION POLICIES) ENGINE
# ------------------------------------------
function Get-DeterministicSrpGuid {
    param([Parameter(Mandatory=$true)][string]$InputString)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InputString.ToLowerInvariant()))
    $md5.Dispose()
    return "{" + ([guid]::new($hashBytes)).ToString().ToUpper() + "}"
}

function Get-RegState_SRP {
    $targets = @(
        @{ UIDisplayName = "SRP+IFEO Lock: Windows Widgets (Widgets.exe)"; TargetPath = "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.WebExperience*\Dashboard\Widgets.exe"; ExeName = "Widgets.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Compatibility Telemetry (CompatTelRunner.exe)"; TargetPath = "$env:windir\System32\CompatTelRunner.exe"; ExeName = "CompatTelRunner.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Hardware Telemetry (DeviceCensus.exe)"; TargetPath = "$env:windir\System32\DeviceCensus.exe"; ExeName = "DeviceCensus.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: GameBar Telemetry (GameBarPresenceWriter.exe)"; TargetPath = "$env:windir\System32\GameBarPresenceWriter.exe"; ExeName = "GameBarPresenceWriter.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Edge Background Updater (MicrosoftEdgeUpdate.exe)"; TargetPath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"; ExeName = "MicrosoftEdgeUpdate.exe" }
    )
    
    $customKey = "HKLM:\SOFTWARE\WinUltix\SRP"
    if (Test-Path $customKey) {
        $customEntries = Get-Item -Path $customKey -ErrorAction SilentlyContinue
        if ($customEntries) {
            foreach ($prop in $customEntries.Property) {
                $customPath = (Get-ItemProperty -Path $customKey -Name $prop -ErrorAction SilentlyContinue).$prop
                if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                    $exeLeaf = [System.IO.Path]::GetFileName($customPath)
                    $targets += @{ UIDisplayName = "SRP+IFEO Lock (Custom): $prop"; TargetPath = $customPath; ExeName = $exeLeaf }
                }
            }
        }
    }

    $results = @()
    $srpBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    foreach ($target in $targets) {
        $guid = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $srpRuleExists = Test-Path -Path "$srpBase\$guid"
        
        $ifeoKey = "$ifeoBase\$($target.ExeName)"
        $ifeoDebugger = (Get-ItemProperty -Path $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
        $ifeoLocked = ($null -ne $ifeoDebugger -and $ifeoDebugger -match "systray\.exe")

        # Marked as detected (needs optimization) if either SRP or IFEO lock is missing
        $isDetected = -not ($srpRuleExists -and $ifeoLocked)
        
        $results += [PSCustomObject]@{
            UIDisplayName = $target.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $target
        }
    }
    return $results
}

# ------------------------------------------
# Z3: SRP (SOFTWARE RESTRICTION POLICIES) ENGINE
# ------------------------------------------
function Invoke-ApplySRP {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No execution locks selected."; return }
    $current = 0

    $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    $srpPaths = "$srpRoot\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $nullStub = "$env:SystemRoot\System32\systray.exe"
    
    if ($Operation -eq 'Apply') {
        if (-not (Test-Path $srpRoot)) { New-Item -Path $srpRoot -Force | Out-Null }
        
        $srpSettings = @{
            "AuthenticodeEnabled" = 0
            "DefaultLevel"        = 262144
            "TransparentEnabled"  = 1
            "PolicyScope"         = 0
        }
        foreach ($kvp in $srpSettings.GetEnumerator()) {
            Set-ItemProperty -Path $srpRoot -Name $kvp.Key -Value $kvp.Value -Type DWord -Force
        }
        
        $exeTypes = [string[]]@("BAT","CMD","COM","EXE","HTA","LNK","MSI","OCX","PIF","REG","SCR","VBS","WSF")
        Set-ItemProperty -Path $srpRoot -Name "ExecutableTypes" -Value $exeTypes -Type MultiString -Force
        
        if (-not (Test-Path "$srpRoot\0")) { New-Item -Path "$srpRoot\0" -Force | Out-Null }
        if (-not (Test-Path "$srpRoot\262144")) { New-Item -Path "$srpRoot\262144" -Force | Out-Null }
        if (-not (Test-Path $srpPaths)) { New-Item -Path $srpPaths -Force | Out-Null }
    }

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Removing" }
    $policyChanged = $false

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb) Execution Lock: $($item.UIDisplayName)"
        
        $target   = $item.ActionData
        $guid     = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey  = "$srpPaths\$guid"
        $ifeoKey  = "$ifeoBase\$($target.ExeName)"
        
        try {
            if ($Operation -eq 'Apply') {
                if (Test-Path $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -Path $srpPaths -ErrorAction SilentlyContinue)) {
                        $existingData = (Get-ItemProperty -Path $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($existingData -eq $target.TargetPath -and $subKey.PSChildName -ne $guid) {
                            Remove-Item -Path $subKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                New-Item -Path $ruleKey -Force | Out-Null
                Set-ItemProperty -Path $ruleKey -Name "Description" -Value "WinUltix Pro SRP Lockdown" -Type String -Force
                Set-ItemProperty -Path $ruleKey -Name "ItemData" -Value $target.TargetPath -Type String -Force
                Set-ItemProperty -Path $ruleKey -Name "SaferFlags" -Value 0 -Type DWord -Force

                if (-not (Test-Path $ifeoKey)) { New-Item -Path $ifeoKey -Force | Out-Null }
                Set-ItemProperty -Path $ifeoKey -Name "Debugger" -Value $nullStub -Type String -Force
                Set-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                
                $procName = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName)
                $activeProc = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($activeProc) { 
                    $activeProc | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-GUI "    [OK] Flushed active process ($procName) from memory."
                }
                $policyChanged = $true
            } else {
                if (Test-Path $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -Path $srpPaths -ErrorAction SilentlyContinue)) {
                        $itemData = (Get-ItemProperty -Path $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($subKey.PSChildName -eq $guid -or $itemData -eq $target.TargetPath) {
                            Remove-Item -Path $subKey.PSPath -Force -Recurse -ErrorAction Stop
                            $policyChanged = $true
                        }
                    }
                }

                if (Test-Path $ifeoKey) {
                    $isManaged = (Get-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -ErrorAction SilentlyContinue).WinUltixManaged
                    $dbgVal    = (Get-ItemProperty -Path $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
                    if ($isManaged -eq 1 -or $dbgVal -match "systray\.exe") {
                        Remove-ItemProperty -Path $ifeoKey -Name "Debugger" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -Force -ErrorAction SilentlyContinue
                        $remainingProps = (Get-Item -Path $ifeoKey -ErrorAction SilentlyContinue).Property
                        if (-not $remainingProps -or $remainingProps.Count -eq 0) {
                            Remove-Item -Path $ifeoKey -Force -ErrorAction SilentlyContinue
                        }
                        $policyChanged = $true
                    }
                }
                Write-GUI "    [OK] SRP & IFEO restriction rules purged from registry."
            }
        } catch { Write-GUI "    [!] Failed to modify execution lock: $($_.Exception.Message)" }
    }
    
    if ($policyChanged) {
        Write-GUI " -> Refreshing Safer API policy tokens (gpupdate in background)..."
        Update-Progress 85

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
            $gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
            $gpProc.WaitForExit()
            $gpProc.Dispose()
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated.`n"
        }
    } else {
        Update-Progress 0
        Write-GUI " -> Execution lock operation completed ($Operation).`n"
    }
}

# ------------------------------------------
# Z3: REGISTRY ENGINE
# ------------------------------------------
function Invoke-ApplyRegistry {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply'
    )
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No tweaks selected."; return }
    $current = 0

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Reverting" }

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        $reg = $item.ActionData
        
        $targetValue = if ($Operation -eq 'Apply') { $reg.Expected } else { $reg.Default }

        if ($null -eq $targetValue -and $Operation -eq 'Revert') {
            Write-GUI "    [!] Missing 'Default' property in array definition. Skipping."
            continue
        }

        try {
            if ($targetValue -eq 'DELETE_KEY') {
                if (Test-Path $reg.Path) { 
                    Remove-Item -Path $reg.Path -Recurse -Force -ErrorAction Stop | Out-Null 
                    $parentKey = Split-Path -Path $reg.Path -Parent
                    if ($parentKey -match "\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2\}$" -and (Test-Path $parentKey)) {
                        Remove-Item -Path $parentKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                continue
            }
            if ($targetValue -eq 'DELETE_VALUE') {
                if (Test-Path $reg.Path) { Remove-ItemProperty -Path $reg.Path -Name $reg.Name -Force -ErrorAction Stop | Out-Null }
                continue
            }

            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force -ErrorAction Stop | Out-Null }
            
            if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
                Set-Item -Path $reg.Path -Value $targetValue -Force -ErrorAction Stop | Out-Null
            } 
            else { 
                Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $targetValue -Type $reg.Type -Force -ErrorAction Stop | Out-Null 
            }
        } catch { Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
}

function Initialize-Z3UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabReg = New-Object System.Windows.Forms.TabPage
    $tabReg.Text = "Registry"
    $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # Taskbar & Start Menu
    $btnRegTaskbar = New-Object System.Windows.Forms.Button
    $btnRegTaskbar.Text = "Taskbar and Start Menu"
    $btnRegTaskbar.Location = New-Object System.Drawing.Point(15, 20)
    $btnRegTaskbar.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegTaskbar.ForeColor = [System.Drawing.Color]::White
    $btnRegTaskbar.FlatStyle = "Flat"
    $btnRegTaskbar.Add_MouseEnter({ Show-Description "Aligns the taskbar to the left, kills Bing assistants, and hides widgets." })
    $btnRegTaskbar.Add_Click({ 
        $auditData = Get-RegState_Taskbar
        $modalOutput = Show-ActionModal -Title "WinUltix - Taskbar Tweaks" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Taskbar" -Operation $modalOutput.Action
            Stop-Process -Name "SearchHost" -Force -ErrorAction SilentlyContinue
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Write-GUI "" 
        } 
    })
    
    $btnAudTaskbar = New-Object System.Windows.Forms.Button
    $btnAudTaskbar.Text = "?"
    $btnAudTaskbar.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudTaskbar.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudTaskbar.ForeColor = [System.Drawing.Color]::White
    $btnAudTaskbar.FlatStyle = "Flat"
    $btnAudTaskbar.Add_MouseEnter({ Show-Description "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, and Bing locks." })
    $btnAudTaskbar.Add_Click({ Write-GUI "--- AUDIT: Taskbar & Start Menu ---"; $state = Get-RegState_Taskbar; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # File Explorer
    $btnRegExplorer = New-Object System.Windows.Forms.Button
    $btnRegExplorer.Text = "File Explorer and Context Menu"
    $btnRegExplorer.Location = New-Object System.Drawing.Point(15, 70)
    $btnRegExplorer.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegExplorer.ForeColor = [System.Drawing.Color]::White
    $btnRegExplorer.FlatStyle = "Flat"
    $btnRegExplorer.Add_MouseEnter({ Show-Description "Restores the full context menu, launches folder processes in isolation." })
    $btnRegExplorer.Add_Click({ 
        $auditData = Get-RegState_Explorer
        $modalOutput = Show-ActionModal -Title "WinUltix - Explorer Tweaks" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Explorer" -Operation $modalOutput.Action
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Write-GUI "" 
        } 
    })

    $btnAudExplorer = New-Object System.Windows.Forms.Button
    $btnAudExplorer.Text = "?"
    $btnAudExplorer.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudExplorer.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudExplorer.ForeColor = [System.Drawing.Color]::White
    $btnAudExplorer.FlatStyle = "Flat"
    $btnAudExplorer.Add_MouseEnter({ Show-Description "AUDIT: Verifies the presence of classic context menu and Explorer performance flags." })
    $btnAudExplorer.Add_Click({ Write-GUI "--- AUDIT: File Explorer ---"; $state = Get-RegState_Explorer; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # OS Annoyances
    $btnRegAnnoyances = New-Object System.Windows.Forms.Button
    $btnRegAnnoyances.Text = "OS Annoyances (AutoRun / Sticky Keys)"
    $btnRegAnnoyances.Location = New-Object System.Drawing.Point(15, 120)
    $btnRegAnnoyances.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegAnnoyances.ForeColor = [System.Drawing.Color]::White
    $btnRegAnnoyances.FlatStyle = "Flat"
    $btnRegAnnoyances.Add_MouseEnter({ Show-Description "Deactivates AutoPlay and Accessibility shortcuts (Sticky Keys)." })
    $btnRegAnnoyances.Add_Click({ 
        $auditData = Get-RegState_Annoyances
        $modalOutput = Show-ActionModal -Title "WinUltix - OS Annoyances" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Annoyances" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudAnnoyances = New-Object System.Windows.Forms.Button
    $btnAudAnnoyances.Text = "?"
    $btnAudAnnoyances.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudAnnoyances.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudAnnoyances.ForeColor = [System.Drawing.Color]::White
    $btnAudAnnoyances.FlatStyle = "Flat"
    $btnAudAnnoyances.Add_MouseEnter({ Show-Description "AUDIT: Verifies AutoPlay and Sticky Keys blockade." })
    $btnAudAnnoyances.Add_Click({ Write-GUI "--- AUDIT: OS Annoyances ---"; $state = Get-RegState_Annoyances; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Privacy
    $btnRegPrivacy = New-Object System.Windows.Forms.Button
    $btnRegPrivacy.Text = "Privacy and Background Apps (AppPrivacy)"
    $btnRegPrivacy.Location = New-Object System.Drawing.Point(15, 170)
    $btnRegPrivacy.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegPrivacy.ForeColor = [System.Drawing.Color]::White
    $btnRegPrivacy.FlatStyle = "Flat"
    $btnRegPrivacy.Add_MouseEnter({ Show-Description "Blocks telemetry, background UWP apps execution, and limits Edge processes." })
    $btnRegPrivacy.Add_Click({ 
        $auditData = Get-RegState_Privacy
        $modalOutput = Show-ActionModal -Title "WinUltix - Privacy Policies" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Privacy" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudPrivacy = New-Object System.Windows.Forms.Button
    $btnAudPrivacy.Text = "?"
    $btnAudPrivacy.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudPrivacy.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudPrivacy.ForeColor = [System.Drawing.Color]::White
    $btnAudPrivacy.FlatStyle = "Flat"
    $btnAudPrivacy.Add_MouseEnter({ Show-Description "AUDIT: Checks the registry for telemetry, Edge, and background execution blocks." })
    $btnAudPrivacy.Add_Click({ Write-GUI "--- AUDIT: Privacy Policies ---"; $state = Get-RegState_Privacy; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Boot & Security
    $btnRegSystemBoot = New-Object System.Windows.Forms.Button
    $btnRegSystemBoot.Text = "Boot and WPBT (BIOS/UEFI Block)"
    $btnRegSystemBoot.Location = New-Object System.Drawing.Point(15, 220)
    $btnRegSystemBoot.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegSystemBoot.ForeColor = [System.Drawing.Color]::White
    $btnRegSystemBoot.FlatStyle = "Flat"
    $btnRegSystemBoot.Add_MouseEnter({ Show-Description "Disables Fast Boot, OneDrive, RDP, and blocks software injections from BIOS/UEFI (WPBT)." })
    $btnRegSystemBoot.Add_Click({ 
        $auditData = Get-RegState_SystemBoot
        $modalOutput = Show-ActionModal -Title "WinUltix - Boot & Security" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "SystemBoot" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudSystemBoot = New-Object System.Windows.Forms.Button
    $btnAudSystemBoot.Text = "?"
    $btnAudSystemBoot.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudSystemBoot.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSystemBoot.ForeColor = [System.Drawing.Color]::White
    $btnAudSystemBoot.FlatStyle = "Flat"
    $btnAudSystemBoot.Add_MouseEnter({ Show-Description "AUDIT: Verifies kernel hibernation logic (Fast Boot), WPBT, and RDP." })
    $btnAudSystemBoot.Add_Click({ Write-GUI "--- AUDIT: Boot & Security ---"; $state = Get-RegState_SystemBoot; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Mouse
    $btnRegMouse = New-Object System.Windows.Forms.Button
    $btnRegMouse.Text = "Hard Mouse Acceleration Disable (Raw Input)"
    $btnRegMouse.Location = New-Object System.Drawing.Point(15, 270)
    $btnRegMouse.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnRegMouse.ForeColor = [System.Drawing.Color]::White
    $btnRegMouse.FlatStyle = "Flat"
    $btnRegMouse.Add_MouseEnter({ Show-Description "Pure 1:1 input. Hard-disables 'Enhance pointer precision' to eliminate system smoothing." })
    $btnRegMouse.Add_Click({ 
        $auditData = Get-RegState_Mouse
        $modalOutput = Show-ActionModal -Title "WinUltix - Raw Input Enforcer" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Mouse" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudMouse = New-Object System.Windows.Forms.Button
    $btnAudMouse.Text = "?"
    $btnAudMouse.Location = New-Object System.Drawing.Point(345, 270)
    $btnAudMouse.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnAudMouse.ForeColor = [System.Drawing.Color]::White
    $btnAudMouse.FlatStyle = "Flat"
    $btnAudMouse.Add_MouseEnter({ Show-Description "AUDIT: Scans registry keys for system pointer acceleration." })
    $btnAudMouse.Add_Click({ Write-GUI "--- AUDIT: Mouse Acceleration ---"; $state = Get-RegState_Mouse; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Gaming
    $btnRegGaming = New-Object System.Windows.Forms.Button
    $btnRegGaming.Text = "Hardware and Gaming (Extreme)"
    $btnRegGaming.Location = New-Object System.Drawing.Point(15, 320)
    $btnRegGaming.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnRegGaming.ForeColor = [System.Drawing.Color]::White
    $btnRegGaming.FlatStyle = "Flat"
    $btnRegGaming.Add_MouseEnter({ Show-Description "Enforces MMCSS priorities, disables GameDVR, enabling maximum hardware performance." })
    $btnRegGaming.Add_Click({ 
        $auditData = Get-RegState_Gaming
        $modalOutput = Show-ActionModal -Title "WinUltix - Extreme Gaming Profile" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Gaming" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudGaming = New-Object System.Windows.Forms.Button
    $btnAudGaming.Text = "?"
    $btnAudGaming.Location = New-Object System.Drawing.Point(345, 320)
    $btnAudGaming.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnAudGaming.ForeColor = [System.Drawing.Color]::White
    $btnAudGaming.FlatStyle = "Flat"
    $btnAudGaming.Add_MouseEnter({ Show-Description "AUDIT: Verifies MMCSS limits, CPU priority, and HAGS acceleration." })
    $btnAudGaming.Add_Click({ Write-GUI "--- AUDIT: Hardware & Gaming ---"; $state = Get-RegState_Gaming; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # SRP Execution Locks (Main Button)
    $btnRegSRP = New-Object System.Windows.Forms.Button
    $btnRegSRP.Text = "Execution Blocks (SRP/Legacy Pro)"
    $btnRegSRP.Location = New-Object System.Drawing.Point(15, 420)
    $btnRegSRP.Size = New-Object System.Drawing.Size(240, 40)
    $btnRegSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegSRP.ForeColor = [System.Drawing.Color]::White
    $btnRegSRP.FlatStyle = "Flat"
    $btnRegSRP.Add_MouseEnter({ Show-Description "NATIVE KERNEL LOCK (Pro/Enterprise Only): Generates legacy Software Restriction Policies to block execution. May not work on Home editions or future OS builds." })


    # SRP: Add Custom Target [+]
    $btnAddSRP = New-Object System.Windows.Forms.Button
    $btnAddSRP.Text = "+"
    $btnAddSRP.Location = New-Object System.Drawing.Point(260, 420)
    $btnAddSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnAddSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 60)
    $btnAddSRP.ForeColor = [System.Drawing.Color]::White
    $btnAddSRP.FlatStyle = "Flat"
    $btnAddSRP.Add_MouseEnter({ Show-Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP block list." })
    $btnAddSRP.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Executables (*.exe)|*.exe"
        $dlg.Title = "Select Executable to Block (SRP)"
        $dlg.InitialDirectory = "$env:ProgramFiles"
        
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
            $exeName = [System.IO.Path]::GetFileName($dlg.FileName)
            Set-ItemProperty -Path $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
            Write-GUI " -> Added custom SRP target: $exeName"
        }
    })

    # SRP: Clear Custom Roster [-]
    $btnClrSRP = New-Object System.Windows.Forms.Button
    $btnClrSRP.Text = "-"
    $btnClrSRP.Location = New-Object System.Drawing.Point(305, 420)
    $btnClrSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnClrSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 60)
    $btnClrSRP.ForeColor = [System.Drawing.Color]::White
    $btnClrSRP.FlatStyle = "Flat"
    $btnClrSRP.Add_MouseEnter({ Show-Description "CLEAR CUSTOM TARGETS: Removes all custom executables from the WinUltix tracking list (does not unlock them if currently applied)." })
    $btnClrSRP.Add_Click({
        $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
        if (Test-Path $regKey) {
            Remove-Item -Path $regKey -Force -Recurse | Out-Null
            Write-GUI " -> Custom SRP tracking database purged."
        } else {
            Write-GUI " -> Custom SRP roster is already empty."
        }
    })

    # SRP Audit Button [?]
    $btnAudSRP = New-Object System.Windows.Forms.Button
    $btnAudSRP.Text = "?"
    $btnAudSRP.Location = New-Object System.Drawing.Point(350, 420)
    $btnAudSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSRP.ForeColor = [System.Drawing.Color]::White
    $btnAudSRP.FlatStyle = "Flat"
    $btnAudSRP.Add_MouseEnter({ Show-Description "AUDIT: Verifies active Software Restriction Policies." })
    $btnAudSRP.Add_Click({ 
        Write-GUI "--- AUDIT: Software Restriction Policies ---"
        $state = Get-RegState_SRP
        $detected = @($state | Where-Object { $_.IsDetected })
        
        if ($detected.Count -gt 0) { 
            foreach ($d in $detected) { Write-GUI "  [!] To Block: $($d.UIDisplayName)" } 
        } else { 
            Write-GUI "  [OK] Optimized." 
        }
        Write-GUI "" 
    })

    $btnRegSRP.Add_Click({ 
        $auditData = Get-RegState_SRP
        $modalOutput = Show-ActionModal -Title "WinUltix - SRP & IFEO Lockdown" -Description "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) { 
            Invoke-ApplySRP -SelectedItems $modalOutput.Items -Operation $modalOutput.Action -ControlsToDisable @($btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP)
        } 
    }.GetNewClosure())
    
    $tabReg.Controls.AddRange(@($btnRegTaskbar, $btnAudTaskbar, $btnRegExplorer, $btnAudExplorer, $btnRegAnnoyances, $btnAudAnnoyances, $btnRegPrivacy, $btnAudPrivacy, $btnRegSystemBoot, $btnAudSystemBoot, $btnRegMouse, $btnAudMouse, $btnRegGaming, $btnAudGaming, $btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP))
    $TabControl.Controls.Add($tabReg)
}
# <<< END INJECTED MODULE: Z3_Registry.ps1 <<<


# Z4_Services: Service state management and Task Scheduler control via centralized revert modals. Disables telemetry tasks, configures TCPNoDelay, and enforces strict service operational profiles with improved UI interactivity.
# . (Join-Path $ModulesDir "Z4_Services.ps1")
# >>> BEGIN INJECTED MODULE: Z4_Services.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z4_SERVICES.PS1 - SERVICES & SYSTEM MODULE
# Z4_Services: Manages services (Set-Service), Task Scheduler, and global tweaks. Disables telemetry tasks, optimizes Power Plans (sleep, monitor), clears Start Menu DB, and enforces service profiles (Light/Heavy).
# ==========================================

# ------------------------------------------
# Z4: AUDIT HELPERS
# ------------------------------------------
function Assert-Power { 
    param($Sub, $Setting, $MinSeconds, $Desc)
    $out = (powercfg /q SCHEME_CURRENT $Sub $Setting) -join " "
    if ($out -match "Current AC Power Setting Index: (0x[0-9a-fA-F]+)") { 
        $intVal = [convert]::ToInt32($matches[1], 16)
        if ($intVal -eq 0 -or $intVal -ge $MinSeconds) { Write-GUI "  [OK] $Desc ($intVal sec)"; return 0 } 
        else { Write-GUI "  [!] $Desc (Too short: $intVal sec)"; return 1 } 
    }
    Write-GUI "  [!] $Desc (Read error)"; return 1 
}

function Invoke-ServicesAudit {
    param([array]$Rules)
    
    $results = @()
    foreach ($rule in $Rules) {
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        
        $isDetected = $true
        if ($null -eq $currentStart -or $currentStart -eq $rule.ExpectedStart) {
            $isDetected = $false
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

# ------------------------------------------
# Z4: SERVICES & TASKS AUDITS
# ------------------------------------------
function Get-TelemetryTasksState { 
    $rules = @(
        @{ UIDisplayName = "Task: CEIP (Customer Experience Improvement Program)"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Feedback & Diagnostics"; TaskPath = "\Microsoft\Windows\Feedback\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Performance Trace"; TaskPath = "\Microsoft\Windows\PerformanceTrace\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Error Reporting (WER)"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Xbox Live Game Save DataSync"; TaskPath = "\Microsoft\XblGameSave\*"; ExpectedState = "Disabled" }
    )
    
    # Single COM/CIM query instead of querying Get-ScheduledTask 5 times in a loop
    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue
    
    $results = @()
    foreach ($rule in $rules) {
        $activeTasks = @($allTasks | Where-Object { $_.TaskPath -like $rule.TaskPath -and ($_.State -eq 'Ready' -or $_.State -eq 'Running') })
        
        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = ($activeTasks.Count -gt 0)
            ActionData    = $rule
        }
    }
    return $results
}

function Invoke-StartMenuAudit {
    Write-GUI "--- AUDIT: Start Menu Pins Database ---"
    $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($null -eq $pkgDir) {
        Write-GUI "  [OK] StartMenuExperienceHost package not found in current user profile."
        return
    }

    $localState = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
    $binFile    = Get-Item -Path (Join-Path $localState "start2.bin") -Force -ErrorAction SilentlyContinue
    $clearedSz  = (Get-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -ErrorAction SilentlyContinue).StartMenuClearedSize

    if ($null -ne $binFile) {
        $szKB = [math]::Round($binFile.Length / 1KB, 2)
        if ($null -ne $clearedSz -and [math]::Abs($binFile.Length - $clearedSz) -le 512) {
            Write-GUI "  [OK] Clean minimal layout active: start2.bin ($szKB KB - Edge, Settings, Explorer)."
        } else {
            Write-GUI "  [!] Active layout database detected: $($binFile.Name) ($szKB KB)."
        }
    } else {
        Write-GUI "  [OK] Start Menu binary database is not present."
    }

    $policyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
    $mdmLock = (Get-ItemProperty -Path $policyPath -Name "ConfigureStartPins_ProviderSet" -ErrorAction SilentlyContinue).ConfigureStartPins_ProviderSet
    if ($mdmLock -eq 1) {
        Write-GUI "  [!] Residual MDM Start Menu lock detected in PolicyManager."
    } else {
        Write-GUI "  [OK] No residual MDM Start Menu locks found."
    }
}

function Invoke-PowerAudit { 
    Write-GUI "--- AUDIT: Power Profile ---"; $err = 0
    $hiber = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue
    if ($hiber -and $hiber.HibernateEnabled -eq 0) { Write-GUI "  [OK] Hibernation (Disabled)" } else { Write-GUI "  [!] Hibernation (Likely active)"; $err++ }
    $err += Assert-Power "SUB_SLEEP" "STANDBYIDLE" 999999 "System Sleep"
    $err += Assert-Power "SUB_VIDEO" "VIDEOIDLE" 3600 "Display Turn Off"
    Write-GUI "-> STATUS: $err issues with power profile." 
}

function Get-ServicesState_Light {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

function Get-ServicesState_Heavy {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Device Inventory Service (InventorySvc)"; Name = "InventorySvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Networking: Connected Devices Platform (CDPSvc)"; Name = "CDPSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Location: Geolocation Service (lfsvc)"; Name = "lfsvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Performance: SysMain / Superfetch - Disables RAM caching (SysMain)"; Name = "SysMain"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Virtualization: Windows Subsystem for Linux (WSLService)"; Name = "WSLService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "AI: Windows AI Fabric Service (WSAIFabricSvc)"; Name = "WSAIFabricSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Printers: Print Spooler - Disables all printing (Spooler)"; Name = "Spooler"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Printers: Print Notify Service (PrintNotify)"; Name = "PrintNotify"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Printers: Fax Service (Fax)"; Name = "Fax"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Remote: Remote Desktop Services (TermService)"; Name = "TermService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Remote: Remote Registry (RemoteRegistry)"; Name = "RemoteRegistry"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Biometrics: Windows Biometric Service (WbioSrvc)"; Name = "WbioSrvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Data Service (SensorDataService)"; Name = "SensorDataService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Service (SensorService)"; Name = "SensorService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Monitoring Service (SensrSvc)"; Name = "SensrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Phone Service (PhoneSvc)"; Name = "PhoneSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: Windows Mobile Hotspot Service (icssvc)"; Name = "icssvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: WWAN AutoConfig (WwanSvc)"; Name = "WwanSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Search: Windows Search - Disables file indexing (WSearch)"; Name = "WSearch"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Networking: Offline Files (CscService)"; Name = "CscService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: Internet Connection Sharing (SharedAccess)"; Name = "SharedAccess"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Logitech: Lamp Array Service RGB (logi_lamparray_service)"; Name = "logi_lamparray_service"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Updates: Delivery Optimization (DoSvc)"; Name = "DoSvc"; ExpectedStart = 4; DefaultStart = 2 }
        
        @{ UIDisplayName = "Xbox: Xbox Live Auth Manager (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Game Save (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Networking Service (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Accessory Management (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server (FrameServer)"; Name = "FrameServer"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 4; DefaultStart = 3 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

function Get-GhostServicesState {
    $ghosts = @()
    
    $runningNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.Name) }
    Get-CimInstance -ClassName Win32_SystemDriver -Filter "State = 'Running'" -Property Name -ErrorAction SilentlyContinue | ForEach-Object { [void]$runningNames.Add($_.Name) }

    $services = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue
    
    foreach ($svc in $services) {
        $svcName = $svc.PSChildName
        if ($runningNames.Contains($svcName)) { continue }

        $props = Get-ItemProperty -Path $svc.PSPath -Name "ImagePath", "Type" -ErrorAction SilentlyContinue
        $imagePath = $props.ImagePath
        if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
        if ($imagePath -match '(?i)^\\(?:Driver|FileSystem)\\') { continue }
        
        $rawPath = $imagePath -replace '(?i)^\\SystemRoot\\', "$env:windir\"
        $rawPath = $rawPath -replace '^\\+?\?\?\\+', ''
        $rawPath = [System.Environment]::ExpandEnvironmentVariables($rawPath).Trim()
        
        if ($rawPath -match '^"([^"]+)"') { 
            $rawPath = $matches[1] 
        } elseif ($rawPath -match '(?i)^(.+?\.(?:exe|sys|dll))(?:$|\s)') {
            $rawPath = $matches[1]
        } else { 
            $rawPath = $rawPath.Split(' ')[0] 
        }
        
        if (-not [System.IO.Path]::IsPathRooted($rawPath)) {
            $candidateWinDir = Join-Path -Path $env:windir -ChildPath $rawPath
            $candidateSys32  = Join-Path -Path "$env:windir\System32" -ChildPath $rawPath
            $candidateDrv    = Join-Path -Path "$env:windir\System32\drivers" -ChildPath $rawPath
            
            if (Test-Path -Path $candidateWinDir -PathType Leaf) { $rawPath = $candidateWinDir }
            elseif (Test-Path -Path $candidateSys32 -PathType Leaf) { $rawPath = $candidateSys32 }
            elseif (Test-Path -Path $candidateDrv -PathType Leaf) { $rawPath = $candidateDrv }
            else { $rawPath = $candidateWinDir }
        }
        
        if (-not (Test-Path -Path $rawPath -PathType Leaf)) {
            $ghosts += [PSCustomObject]@{
                Name          = $svcName
                Path          = $rawPath
                UIDisplayName = "Ghost: $svcName (Missing: $rawPath)"
                IsDetected    = $true
            }
        }
    }
    return $ghosts
}

# ------------------------------------------
# Z4: SERVICES & SYSTEM ENGINE
# ------------------------------------------
function Optimize-PowerSettings { 
    powercfg.exe /hibernate off
    powercfg.exe /change standby-timeout-ac 0
    powercfg.exe /change standby-timeout-dc 0
    powercfg.exe /change monitor-timeout-ac 60
    powercfg.exe /change monitor-timeout-dc 60 
}

function Invoke-ApplyTasks { 
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply'
    )
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No tasks selected."; return }
    $current = 0

    $actionVerb = if ($Operation -eq 'Apply') { "Disabling" } else { "Enabling" }
    $allTasks = Get-ScheduledTask -ErrorAction SilentlyContinue

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        
        $taskRule = $item.ActionData
        try {
            $tasks = @($allTasks | Where-Object { $_.TaskPath -like $taskRule.TaskPath })
            foreach ($task in $tasks) { 
                if ($Operation -eq 'Apply') {
                    Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
                }
            }
        } catch { Write-GUI "    [!] Failed to modify task path: $($taskRule.TaskPath)" }
    }

    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Telemetry tasks lockdown completed ($Operation)."
}

function Invoke-ApplyServices {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply'
    )
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No services selected."; return }
    $current = 0

    $actionVerb = if ($Operation -eq 'Apply') { "Configuring" } else { "Reverting" }

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        $svc = $item.ActionData
        $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"

        if (-not (Test-Path -Path $svcRegPath)) {
            Write-GUI " -> Skipping absent service: $($svc.Name)"
            continue
        }

        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        $targetValue = if ($Operation -eq 'Apply') { $svc.ExpectedStart } else { $svc.DefaultStart }

        if ($null -eq $targetValue -and $Operation -eq 'Revert') {
            Write-GUI "    [!] Missing 'DefaultStart' property. Skipping."
            continue
        }

        try {
            if ($Operation -eq 'Apply') {
                Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            Set-ItemProperty -Path $svcRegPath -Name "Start" -Value $targetValue -Type DWord -ErrorAction Stop
        } catch { Write-GUI "    [!] Failed to modify service: $($svc.Name)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $ProfileName services enforcement completed ($Operation)."
}

function Clear-StartMenu {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Initializing deterministic Start Menu reset (Pinning: Edge, Settings, Explorer)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $logs = [System.Collections.Generic.List[string]]::new()
        $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($null -eq $pkgDir) {
            $logs.Add("    [!] StartMenuExperienceHost package directory not found. Aborting.")
            return $logs
        }

        $startStatePath   = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
        $provGuid         = "B5292708-1619-419B-9923-E5D9F3925E71"
        $enrollmentPath   = "HKLM:\SOFTWARE\Microsoft\Enrollments\$provGuid"
        $providerPath     = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid\default\Device\Start"
        $policyDevicePath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        $policyUserPath   = "HKCU:\Software\Microsoft\PolicyManager\current\user\Start"

        # Minimal 3-icon layout: Microsoft Edge, Windows Settings, File Explorer
        $cleanPinsJson = '{"pinnedList":[{"desktopAppId":"MSEdge"},{"packagedAppId":"windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"},{"desktopAppId":"Microsoft.Windows.Explorer"}]}'

        $createdEnrollment = $false

        try {
            # 1. Disable ContentDeliveryManager OEM/Stub placeholder tile injection
            $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (Test-Path $cdmPath) {
                foreach ($cdmName in @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "SubscribedContentEnabled")) {
                    Set-ItemProperty -Path $cdmPath -Name $cdmName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path "$cdmPath\SuggestedApps") {
                    Remove-Item -Path "$cdmPath\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # 2. Register temporary MDM Enrollment & Provider context required by 24H2/26H2 StartTileData.dll
            if (-not (Test-Path $enrollmentPath)) {
                New-Item -Path $enrollmentPath -Force -ErrorAction Stop | Out-Null
                $createdEnrollment = $true
            }
            Set-ItemProperty -Path $enrollmentPath -Name "EnrollmentState" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "EnrollmentType" -Value 6 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "IsFederated" -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $enrollmentPath -Name "ProviderID" -Value "MS DM Server" -Type String -Force

            if (-not (Test-Path $providerPath)) {
                New-Item -Path $providerPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $providerPath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -Path $providerPath -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -Force

            if (-not (Test-Path $policyDevicePath)) {
                New-Item -Path $policyDevicePath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -Force
            Set-ItemProperty -Path $policyDevicePath -Name "ConfigureStartPins_WinningProvider" -Value $provGuid -Type String -Force

            # 3. Purge CloudStore & Start caches BEFORE stopping shell processes
            $cloudStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current"
            if (Test-Path $cloudStoreRoot) {
                Get-ChildItem -Path $cloudStoreRoot -ErrorAction SilentlyContinue | Where-Object {
                    $_.PSChildName -match "start\.tilegrid|unifiedtile|start\.allapps|start\.properties"
                } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            $startRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
            if (Test-Path $startRegPath) {
                Remove-Item -Path $startRegPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            # 4. Stop Explorer (unloads StartTileData.dll in-memory cache) and StartMenuExperienceHost, then wipe start*.bin
            Stop-Process -Name "StartMenuExperienceHost", "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300

            for ($attempt = 1; $attempt -le 6; $attempt++) {
                Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $startStatePath -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
                if (-not (Test-Path (Join-Path $startStatePath "start2.bin"))) { break }
                Start-Sleep -Milliseconds 50
            }

            # Restart Explorer so StartTileData.dll initializes fresh and reads the 3-pin MDM policy
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
                Start-Sleep -Milliseconds 800
            }

            # 5. Trigger StartMenuExperienceHost respawn via COM IApplicationActivationManager so it compiles the 3-pin MDM layout
            try {
                if (-not ([System.Management.Automation.PSTypeName]'WinUltix.AppActivator').Type) {
                    Add-Type -TypeDefinition @"
                    using System;
                    using System.Runtime.CompilerServices;
                    using System.Runtime.InteropServices;
                    namespace WinUltix {
                        [ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
                        public interface IApplicationActivationManager {
                            IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
                        }
                        [ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
                        public class AppActivator : IApplicationActivationManager {
                            [MethodImpl(MethodImplOptions.InternalCall, MethodCodeType = MethodCodeType.Runtime)]
                            public extern IntPtr ActivateApplication([In] String appUserModelId, [In] String arguments, [In] UInt32 options, [Out] out UInt32 processId);
                        }
                    }
"@ -ErrorAction Stop
                }
                $appActivator = New-Object WinUltix.AppActivator
                [uint32]$activatedPid = 0
                [void]$appActivator.ActivateApplication("Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App", $null, 0, [ref]$activatedPid)
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($appActivator)
            } catch {}

            $compiledBinPath = Join-Path $startStatePath "start2.bin"
            $elapsed = 0
            while ($elapsed -lt 4000) {
                Start-Sleep -Milliseconds 250
                $elapsed += 250
                if (Test-Path -Path $compiledBinPath) {
                    Start-Sleep -Milliseconds 800
                    break
                }
            }

            if (Test-Path -Path $compiledBinPath) {
                $newBinSize = (Get-Item -LiteralPath $compiledBinPath -Force).Length
                if (-not (Test-Path "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Value $newBinSize -Type DWord -Force
            }

            $logs.Add("    [OK] Native start2.bin compiled (Pinned: Edge, Settings, File Explorer).")
        } catch {
            $logs.Add("    [!] Error during Start Menu native compilation: $($_.Exception.Message)")
        } finally {
            # 6. Clean up all temporary MDM locks so I can freely pin/unpin items afterwards
            foreach ($polPath in @($policyDevicePath, $policyUserPath)) {
                if (Test-Path -Path $polPath) {
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins_ProviderSet" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $polPath -Name "ConfigureStartPins_WinningProvider" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") {
                Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid" -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($createdEnrollment -and (Test-Path $enrollmentPath)) {
                Remove-Item -Path $enrollmentPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
        }

        # 7. Provision Default User profile with the same 3-icon layout
        $defaultShellPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
        if (-not (Test-Path -Path $defaultShellPath)) {
            New-Item -Path $defaultShellPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $defaultJsonPath = Join-Path -Path $defaultShellPath -ChildPath "LayoutModification.json"
        Set-Content -Path $defaultJsonPath -Value $cleanPinsJson -Encoding UTF8 -Force -ErrorAction SilentlyContinue

        $defaultPkgPath = "$env:SystemDrive\Users\Default\AppData\Local\Packages"
        if (Test-Path -Path $defaultPkgPath) {
            Get-ChildItem -Path $defaultPkgPath -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem -Path (Join-Path $_.FullName "LocalState") -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        $logs.Add("    [OK] Default User LayoutModification.json provisioned.")
        return $logs
    } -OnComplete {
        param($logLines)
        Update-Progress 0
        foreach ($line in $logLines) { Write-GUI $line }
        Write-GUI ""
    }
}

function Remove-GhostServices {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        
        Write-GUI " -> Removing: $($item.Name)"
        # SCM deletion might fail if driver is loaded (unlikely for ghosts) or locked. Registry brute-force is cleaner here.
        Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($item.Name)" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Ghost services purged from system registry."
}

function Initialize-Z4UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Services"
    $tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # Telemetry
    $btnTelemetry = New-Object System.Windows.Forms.Button
    $btnTelemetry.Text = "Disable Telemetry Tasks (Scheduler)"
    $btnTelemetry.Location = New-Object System.Drawing.Point(15, 20)
    $btnTelemetry.Size = New-Object System.Drawing.Size(320, 40)
    $btnTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnTelemetry.ForeColor = [System.Drawing.Color]::White
    $btnTelemetry.FlatStyle = "Flat"
    $btnTelemetry.Add_MouseEnter({ Show-Description "Paralyzes the Task Scheduler. Disables analytics, error reporting, Windows AI, and feedback." })
    $btnTelemetry.Add_Click({
        Write-GUI " -> Scanning Scheduled Tasks (Background Thread)..."
        $sb = (Get-Command -Name Get-TelemetryTasksState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnTelemetry, $btnAudTelemetry) -OnComplete {
            param($auditData)
            $modalOutput = Show-ActionModal -Title "WinUltix - Scheduled Tasks Lockdown" -Description "Select tasks to modify (Apply = Disable, Revert = Enable)." -AuditResults @($auditData) -EnableRevert
            if ($null -ne $modalOutput) {
                Invoke-ApplyTasks -SelectedItems $modalOutput.Items -Operation $modalOutput.Action
                Write-GUI ""
            }
        }
    }.GetNewClosure())

    $btnAudTelemetry = New-Object System.Windows.Forms.Button
    $btnAudTelemetry.Text = "?"
    $btnAudTelemetry.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudTelemetry.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudTelemetry.ForeColor = [System.Drawing.Color]::White
    $btnAudTelemetry.FlatStyle = "Flat"
    $btnAudTelemetry.Add_MouseEnter({ Show-Description "AUDIT: Verifies if telemetry tasks are active in the scheduler." })
    $btnAudTelemetry.Add_Click({
        Write-GUI "--- AUDIT: Scheduled Tasks (Background Thread) ---"
        $sb = (Get-Command -Name Get-TelemetryTasksState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnTelemetry, $btnAudTelemetry) -OnComplete {
            param($state)
            $detected = @($state | Where-Object { $_.IsDetected })
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] Active: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] All monitored tasks disabled."
            }
            Write-GUI ""
        }
    }.GetNewClosure())

    # Start Menu
    $btnStartMenu = New-Object System.Windows.Forms.Button
    $btnStartMenu.Text = "Reset Start Menu Layout (Unpin All)"
    $btnStartMenu.Location = New-Object System.Drawing.Point(15, 70)
    $btnStartMenu.Size = New-Object System.Drawing.Size(320, 40)
    $btnStartMenu.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnStartMenu.ForeColor = [System.Drawing.Color]::White
    $btnStartMenu.FlatStyle = "Flat"
    $btnStartMenu.Add_MouseEnter({ Show-Description "Wipes the internal Start Menu database (start2.bin) and removes MDM locks." })
    $btnStartMenu.Add_Click({
        $msgText = "This action will permanently wipe your Start Menu pins and layout database.`n`nStartMenuExperienceHost will be restarted in the background (System Tray remains intact).`n`nDo you want to proceed?"
        $msgResult = [System.Windows.Forms.MessageBox]::Show($msgText, "WinUltix - Destructive Action", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        
        if ($msgResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Clear-StartMenu -ControlsToDisable @($btnStartMenu, $btnAudStartMenu)
        } else {
            Write-GUI " -> Start Menu reset aborted by user.`n"
        }
    }.GetNewClosure())

    $btnAudStartMenu = New-Object System.Windows.Forms.Button
    $btnAudStartMenu.Text = "?"
    $btnAudStartMenu.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudStartMenu.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudStartMenu.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudStartMenu.ForeColor = [System.Drawing.Color]::White
    $btnAudStartMenu.FlatStyle = "Flat"
    $btnAudStartMenu.Add_MouseEnter({ Show-Description "AUDIT: Scans the size of the current Start Menu layout database." })
    $btnAudStartMenu.Add_Click({ Invoke-StartMenuAudit; Write-GUI "" })

    # Power
    $btnPower = New-Object System.Windows.Forms.Button
    $btnPower.Text = "Optimize Power and Display"
    $btnPower.Location = New-Object System.Drawing.Point(15, 120)
    $btnPower.Size = New-Object System.Drawing.Size(320, 40)
    $btnPower.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnPower.ForeColor = [System.Drawing.Color]::White
    $btnPower.FlatStyle = "Flat"
    $btnPower.Add_MouseEnter({ Show-Description "Disables the hibernation file, system sleep, and sets display turn-off to 60 minutes." })
    $btnPower.Add_Click({ Optimize-PowerSettings; Write-GUI "Completed."; Write-GUI "" })

    $btnAudPower = New-Object System.Windows.Forms.Button
    $btnAudPower.Text = "?"
    $btnAudPower.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudPower.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudPower.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudPower.ForeColor = [System.Drawing.Color]::White
    $btnAudPower.FlatStyle = "Flat"
    $btnAudPower.Add_MouseEnter({ Show-Description "AUDIT: Verifies power profile (hibernation, sleep state, and display)." })
    $btnAudPower.Add_Click({ Invoke-PowerAudit; Write-GUI "" })

    # Ghost Services
    $btnGhostSvc = New-Object System.Windows.Forms.Button
    $btnGhostSvc.Text = "Cleanup Ghost Services"
    $btnGhostSvc.Location = New-Object System.Drawing.Point(15, 170)
    $btnGhostSvc.Size = New-Object System.Drawing.Size(320, 40)
    $btnGhostSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnGhostSvc.ForeColor = [System.Drawing.Color]::White
    $btnGhostSvc.FlatStyle = "Flat"
    $btnGhostSvc.Add_MouseEnter({ Show-Description "Scans registry for services/drivers pointing to non-existent binaries and removes them." })
    $btnGhostSvc.Add_Click({
        Write-GUI "--- AUDIT: Ghost Services & Drivers (Background Thread) ---"
        $sb = (Get-Command -Name Get-GhostServicesState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnGhostSvc, $btnAudGhostSvc) -OnComplete {
            param($output)
            [array]$auditData = @($output)
            if ($auditData.Count -eq 0) {
                Write-GUI "  [OK] No orphaned services or drivers detected.`n"
                return
            }
            $modalOutput = Show-ActionModal -Title "WinUltix - Ghost Services Cleanup" -Description "Select orphaned items to remove." -AuditResults $auditData
            if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) {
                Remove-GhostServices -SelectedItems $modalOutput.Items
                Write-GUI ""
            }
        }
    }.GetNewClosure())

    $btnAudGhostSvc = New-Object System.Windows.Forms.Button
    $btnAudGhostSvc.Text = "?"
    $btnAudGhostSvc.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudGhostSvc.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGhostSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudGhostSvc.ForeColor = [System.Drawing.Color]::White
    $btnAudGhostSvc.FlatStyle = "Flat"
    $btnAudGhostSvc.Add_MouseEnter({ Show-Description "AUDIT: Detects orphaned service/driver registrations." })
    $btnAudGhostSvc.Add_Click({
        Write-GUI "--- AUDIT: Ghost Services & Drivers (Background Thread) ---"
        $sb = (Get-Command -Name Get-GhostServicesState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnGhostSvc, $btnAudGhostSvc) -OnComplete {
            param($output)
            [array]$state = @($output)
            if ($state.Count -gt 0) {
                foreach ($d in $state) { Write-GUI "  [!] Found: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] No orphaned services or drivers detected."
            }
            Write-GUI ""
        }
    }.GetNewClosure())
	
    # Profiles (Light/Heavy)
    $btnSvcLight = New-Object System.Windows.Forms.Button
    $btnSvcLight.Text = "Background Services: OFFICE PROFILE"
    $btnSvcLight.Location = New-Object System.Drawing.Point(15, 270)
    $btnSvcLight.Size = New-Object System.Drawing.Size(320, 40)
    $btnSvcLight.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnSvcLight.ForeColor = [System.Drawing.Color]::White
    $btnSvcLight.FlatStyle = "Flat"
    $btnSvcLight.Add_MouseEnter({ Show-Description "OFFICE PROFILE: Kills telemetry and tracking, leaving print and network services intact." })
    $btnSvcLight.Add_Click({ 
        $auditData = Get-ServicesState_Light
        $modalOutput = Show-ActionModal -Title "WinUltix - Office Services Profile" -Description "Select services to configure. Unoptimized services are checked by default." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput) { 
            Invoke-ApplyServices -SelectedItems $modalOutput.Items -ProfileName "Office Profile" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudSvcLight = New-Object System.Windows.Forms.Button
    $btnAudSvcLight.Text = "?"
    $btnAudSvcLight.Location = New-Object System.Drawing.Point(345, 270)
    $btnAudSvcLight.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSvcLight.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSvcLight.ForeColor = [System.Drawing.Color]::White
    $btnAudSvcLight.FlatStyle = "Flat"
    $btnAudSvcLight.Add_MouseEnter({ Show-Description "AUDIT: Verifies standard telemetry and background bloat services." })
    $btnAudSvcLight.Add_Click({ Write-GUI "--- AUDIT: Services (Office Profile) ---"; $state = Get-ServicesState_Light; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Disable: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    $btnSvcHeavy = New-Object System.Windows.Forms.Button
    $btnSvcHeavy.Text = "Background Services: GAMING PROFILE"
    $btnSvcHeavy.Location = New-Object System.Drawing.Point(15, 320)
    $btnSvcHeavy.Size = New-Object System.Drawing.Size(320, 40)
    $btnSvcHeavy.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnSvcHeavy.ForeColor = [System.Drawing.Color]::White
    $btnSvcHeavy.FlatStyle = "Flat"
    $btnSvcHeavy.Add_MouseEnter({ Show-Description "GAMING PROFILE: Disables almost everything in the background, including print spooler and file indexing." })
    $btnSvcHeavy.Add_Click({ 
        $auditData = Get-ServicesState_Heavy
        $modalOutput = Show-ActionModal -Title "WinUltix - Gaming Services Profile" -Description "Select services to configure. Unoptimized services are checked by default." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput) { 
            Invoke-ApplyServices -SelectedItems $modalOutput.Items -ProfileName "Gaming Profile" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudSvcHeavy = New-Object System.Windows.Forms.Button
    $btnAudSvcHeavy.Text = "?"
    $btnAudSvcHeavy.Location = New-Object System.Drawing.Point(345, 320)
    $btnAudSvcHeavy.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSvcHeavy.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSvcHeavy.ForeColor = [System.Drawing.Color]::White
    $btnAudSvcHeavy.FlatStyle = "Flat"
    $btnAudSvcHeavy.Add_MouseEnter({ Show-Description "AUDIT: Verifies heavy background services including indexer and print spooler." })
    $btnAudSvcHeavy.Add_Click({ Write-GUI "--- AUDIT: Services (Gaming Profile) ---"; $state = Get-ServicesState_Heavy; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Configure: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    $tabServices.Controls.AddRange(@(
        $btnTelemetry, $btnAudTelemetry,
        $btnStartMenu, $btnAudStartMenu,
        $btnPower, $btnAudPower,
        $btnGhostSvc, $btnAudGhostSvc,
        $btnSvcLight, $btnAudSvcLight,
        $btnSvcHeavy, $btnAudSvcHeavy
    ))

    $TabControl.Controls.Add($tabServices)
}
# <<< END INJECTED MODULE: Z4_Services.ps1 <<<


# Z5_Utilities: Interactive tools and applets via Out-GridView for selective package and service management. Includes DNS Enforcer and classic Windows applet launchers.
# . (Join-Path $ModulesDir "Z5_Utilities.ps1")
# >>> BEGIN INJECTED MODULE: Z5_Utilities.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - UTILITIES & APPLETS
# Z5_Utilities: Interactive tools and applets. Uses Out-GridView for selective removal of Appx, Provisioned packages, optional features, and services. Includes a DNS Enforcer (Cloudflare, Quad9, etc.) and classic Windows applet launchers.
# ==========================================

# ------------------------------------------
# Z5: INTERACTIVE GRIDS
# ------------------------------------------
function Show-AppxGrid { 
    Write-GUI " -> Generating installed Appx package table..."
    $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
    
    $selected = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | 
        Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } | 
        Select-Object Name, PackageFullName, IsFramework, Status | 
        Out-GridView -Title "Select packages to REMOVE (Protected system/gaming packages are hidden)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($app in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing Appx: $($app.Name)"
            try {
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                Write-GUI "    [OK] $($app.Name) removed."
            } catch {
                Write-GUI "    [!] Error removing $($app.Name): $($_.Exception.Message)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Appx removal cancelled."
    }
}

function Show-AppxProvGrid { 
    Write-GUI " -> Generating Provisioned Appx table..."
    $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"

    $selected = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -notmatch $protectedPattern } | 
        Select-Object DisplayName, PackageName, Version | 
        Out-GridView -Title "Select packages to DEPROVISION (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($app in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Deprovisioning: $($app.DisplayName)"
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($app.DisplayName) deprovisioned."
            } catch {
                Write-GUI "    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Deprovisioning cancelled."
    }
}

function Show-CapsGrid { 
    Write-GUI " -> Generating Capabilities (FOD) table..."
    $selected = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.State -eq 'Installed' } | 
        Select-Object Name | 
        Out-GridView -Title "Select features to REMOVE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($cap in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing capability: $($cap.Name)"
            try {
                Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($cap.Name) removed."
            } catch {
                Write-GUI "    [!] Failed to remove: $($cap.Name)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Capability removal cancelled."
    }
}

function Show-OptFeaturesGrid { 
    Write-GUI " -> Generating Optional Features table..."
    $selected = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.State -eq 'Enabled' } | 
        Select-Object FeatureName | 
        Out-GridView -Title "Select features to DISABLE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($feat in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Disabling feature: $($feat.FeatureName)"
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat.FeatureName -NoRestart -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($feat.FeatureName) disabled."
            } catch {
                Write-GUI "    [!] Failed to disable: $($feat.FeatureName)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Optional feature configuration cancelled."
    }
}

function Show-ServicesGrid { 
    Write-GUI " -> Generating system services table..."
    $selected = @(Get-Service | 
        Select-Object Status, Name, DisplayName, StartType | 
        Out-GridView -Title "Select services to HARD DISABLE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($svc in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Deactivating service: $($svc.Name)"
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-GUI "    [OK] $($svc.Name) stopped and disabled."
            } catch {
                Write-GUI "    [!] Failed to disable: $($svc.Name)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Service modification cancelled."
    }
}

function Show-StartupGrid { 
    Write-GUI " -> Generating interactive Startup table..."
    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";             Label = "Registry (HKLM x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Label = "Registry (HKLM x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";             Label = "Registry (HKCU)" }
    )

    foreach ($reg in $regTargets) {
        if (Test-Path $reg.Path) {
            $keyObj = Get-Item -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $keyObj) {
                foreach ($valName in $keyObj.Property) {
                    $valData = $keyObj.GetValue($valName)
                    $startupItems.Add([PSCustomObject]@{
                        Name     = $valName
                        Location = $reg.Label
                        Command  = [string]$valData
                        RegPath  = $reg.Path
                        Type     = "Registry"
                    })
                }
            }
        }
    }
    
    $folderTargets = @(
        @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Label = "Folder (All Users)" }
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Label = "Folder (Current User)" }
    )

    foreach ($fld in $folderTargets) {
        if (Test-Path $fld.Path) {
            Get-ChildItem -Path $fld.Path -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -ne "desktop.ini") {
                    $startupItems.Add([PSCustomObject]@{
                        Name     = $_.Name
                        Location = $fld.Label
                        Command  = $_.FullName
                        RegPath  = $null
                        Type     = "File"
                    })
                }
            }
        }
    }
    
    $selected = @($startupItems | 
        Select-Object Name, Location, Command, RegPath, Type | 
        Out-GridView -Title "Select Startup entries to REMOVE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($item in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing startup entry: $($item.Name) [$($item.Location)]"
            if ($item.Type -eq "Registry") { 
                Remove-ItemProperty -Path $item.RegPath -Name $item.Name -Force -ErrorAction SilentlyContinue 
            } else { 
                Remove-Item -Path $item.Command -Force -ErrorAction SilentlyContinue 
            } 
        }
        Update-Progress 0
        Write-GUI " -> Selected startup entries permanently removed." 
    } else { 
        Write-GUI " -> Startup cleaning cancelled." 
    } 
}

# ------------------------------------------
# Z5: DNS ENFORCER
# ------------------------------------------
function Set-CustomDNS { 
    param([string]$Provider)
    
    $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.DefaultIPGateway }

    if (-not $adapters) { 
        Write-GUI " [!] No active network adapters with a default gateway found."
        return 
    }
    
    foreach ($adapter in $adapters) { 
        if ($Provider -eq "Default (DHCP)") { 
            $res = Invoke-CimMethod -InputObject $adapter -MethodName SetDNSServerSearchOrder -Arguments @{ DNSServerSearchOrder = $null } -ErrorAction SilentlyContinue
            if ($null -ne $res -and $res.ReturnValue -eq 0) {
                Write-GUI " -> $($adapter.Description): Reverted to DHCP DNS." 
            } else {
                Write-GUI " [!] $($adapter.Description): Failed to reset DNS (ReturnCode: $($res.ReturnValue))."
            }
        } else { 
            $dnsServers = switch ($Provider) { 
                "Quad9 (9.9.9.9)"          { [string[]]@("9.9.9.9", "149.112.112.112") } 
                "Cloudflare (1.1.1.1)"     { [string[]]@("1.1.1.1", "1.0.0.1") } 
                "AdGuard (94.140.14.14)"   { [string[]]@("94.140.14.14", "94.140.15.15") } 
                "Google (8.8.8.8)"         { [string[]]@("8.8.8.8", "8.8.4.4") } 
                "OpenDNS (208.67.222.222)" { [string[]]@("208.67.222.222", "208.67.220.220") } 
            }
            if ($null -ne $dnsServers) {
                $res = Invoke-CimMethod -InputObject $adapter -MethodName SetDNSServerSearchOrder -Arguments @{ DNSServerSearchOrder = $dnsServers } -ErrorAction SilentlyContinue
                if ($null -ne $res -and $res.ReturnValue -eq 0) {
                    Write-GUI " -> $($adapter.Description): DNS enforced to $Provider" 
                } else {
                    Write-GUI " [!] $($adapter.Description): Failed to set DNS (ReturnCode: $($res.ReturnValue))."
                }
            }
        } 
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue 
    Update-DNSLabel
}

# ------------------------------------------
# Z5: CLASSIC APPLETS
# ------------------------------------------
function Start-ClassicNet      { Start-Process "ncpa.cpl" }
function Start-ClassicApps     { Start-Process "appwiz.cpl" }
function Start-ClassicSound    { Start-Process "mmsys.cpl" }
function Start-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }

function Initialize-Z5UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabUtil = New-Object System.Windows.Forms.TabPage
    $tabUtil.Text = "Utilities"
    $tabUtil.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # Inspection Labels & Tables
    $lblInspect = New-Object System.Windows.Forms.Label
    $lblInspect.Text = "WARNING: Advanced Tools (Use with caution)"
    $lblInspect.Location = New-Object System.Drawing.Point(15, 15)
    $lblInspect.Size = New-Object System.Drawing.Size(370, 20)
    $lblInspect.ForeColor = [System.Drawing.Color]::Red
    $lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblInspect.TextAlign = "MiddleLeft"

    $btnUtilAppx = New-Object System.Windows.Forms.Button
    $btnUtilAppx.Text = "Appx (Accounts)"
    $btnUtilAppx.Location = New-Object System.Drawing.Point(15, 40)
    $btnUtilAppx.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilAppx.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilAppx.ForeColor = [System.Drawing.Color]::White
    $btnUtilAppx.FlatStyle = "Flat"
    $btnUtilAppx.Add_MouseEnter({ Show-Description "Interactive Appx table. Use Ctrl+Click to remove selected apps." })
    $btnUtilAppx.Add_Click({ Show-AppxGrid; Write-GUI "" })

    $btnUtilAppxProv = New-Object System.Windows.Forms.Button
    $btnUtilAppxProv.Text = "Appx (Image)"
    $btnUtilAppxProv.Location = New-Object System.Drawing.Point(205, 40)
    $btnUtilAppxProv.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilAppxProv.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilAppxProv.ForeColor = [System.Drawing.Color]::White
    $btnUtilAppxProv.FlatStyle = "Flat"
    $btnUtilAppxProv.Add_MouseEnter({ Show-Description "Interactive Provisioned table. Use Ctrl+Click to deprovision installers." })
    $btnUtilAppxProv.Add_Click({ Show-AppxProvGrid; Write-GUI "" })

    $btnUtilCaps = New-Object System.Windows.Forms.Button
    $btnUtilCaps.Text = "Capabilities (FOD)"
    $btnUtilCaps.Location = New-Object System.Drawing.Point(15, 90)
    $btnUtilCaps.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilCaps.ForeColor = [System.Drawing.Color]::White
    $btnUtilCaps.FlatStyle = "Flat"
    $btnUtilCaps.Add_MouseEnter({ Show-Description "Interactive Capabilities (FOD) table. Select unnecessary packages to remove." })
    $btnUtilCaps.Add_Click({ Show-CapsGrid; Write-GUI "" })

    $btnUtilOpt = New-Object System.Windows.Forms.Button
    $btnUtilOpt.Text = "Optional Features"
    $btnUtilOpt.Location = New-Object System.Drawing.Point(205, 90)
    $btnUtilOpt.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilOpt.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilOpt.ForeColor = [System.Drawing.Color]::White
    $btnUtilOpt.FlatStyle = "Flat"
    $btnUtilOpt.Add_MouseEnter({ Show-Description "Interactive Optional Features table. Allows disabling unnecessary modules." })
    $btnUtilOpt.Add_Click({ Show-OptFeaturesGrid; Write-GUI "" })

    $btnUtilSvc = New-Object System.Windows.Forms.Button
    $btnUtilSvc.Text = "Running Services Management"
    $btnUtilSvc.Location = New-Object System.Drawing.Point(15, 140)
    $btnUtilSvc.Size = New-Object System.Drawing.Size(370, 40)
    $btnUtilSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilSvc.ForeColor = [System.Drawing.Color]::White
    $btnUtilSvc.FlatStyle = "Flat"
    $btnUtilSvc.Add_MouseEnter({ Show-Description "Interactive services table. Selected items will be forcefully stopped and disabled." })
    $btnUtilSvc.Add_Click({ Show-ServicesGrid; Write-GUI "" })

    $btnUtilStartup = New-Object System.Windows.Forms.Button
    $btnUtilStartup.Text = "Startup Management (Registry and Folders)"
    $btnUtilStartup.Location = New-Object System.Drawing.Point(15, 190)
    $btnUtilStartup.Size = New-Object System.Drawing.Size(370, 40)
    $btnUtilStartup.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnUtilStartup.ForeColor = [System.Drawing.Color]::White
    $btnUtilStartup.FlatStyle = "Flat"
    $btnUtilStartup.Add_MouseEnter({ Show-Description "Interactive table. Aggregates hidden shortcuts and registry keys starting with the system." })
    $btnUtilStartup.Add_Click({ Show-StartupGrid; Write-GUI "" })

    # Classic Applets
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Windows Applets"
    $lblClassic.Location = New-Object System.Drawing.Point(15, 245)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray

    $btnUtilNet = New-Object System.Windows.Forms.Button
    $btnUtilNet.Text = "Network Adapters (ncpa)"
    $btnUtilNet.Location = New-Object System.Drawing.Point(15, 270)
    $btnUtilNet.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilNet.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilNet.ForeColor = [System.Drawing.Color]::White
    $btnUtilNet.FlatStyle = "Flat"
    $btnUtilNet.Add_MouseEnter({ Show-Description "Quick access to the Network Adapters applet." })
    $btnUtilNet.Add_Click({ Start-ClassicNet; Write-GUI "" })

    $btnUtilSound = New-Object System.Windows.Forms.Button
    $btnUtilSound.Text = "Sound Settings"
    $btnUtilSound.Location = New-Object System.Drawing.Point(205, 270)
    $btnUtilSound.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilSound.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilSound.ForeColor = [System.Drawing.Color]::White
    $btnUtilSound.FlatStyle = "Flat"
    $btnUtilSound.Add_MouseEnter({ Show-Description "Quick access to playback and recording devices." })
    $btnUtilSound.Add_Click({ Start-ClassicSound; Write-GUI "" })

    $btnUtilApps = New-Object System.Windows.Forms.Button
    $btnUtilApps.Text = "Programs and Features"
    $btnUtilApps.Location = New-Object System.Drawing.Point(15, 320)
    $btnUtilApps.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilApps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilApps.ForeColor = [System.Drawing.Color]::White
    $btnUtilApps.FlatStyle = "Flat"
    $btnUtilApps.Add_MouseEnter({ Show-Description "Quick access to the classic Win32 installed software list." })
    $btnUtilApps.Add_Click({ Start-ClassicApps; Write-GUI "" })

    $btnUtilPrint = New-Object System.Windows.Forms.Button
    $btnUtilPrint.Text = "Devices and Printers"
    $btnUtilPrint.Location = New-Object System.Drawing.Point(205, 320)
    $btnUtilPrint.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilPrint.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilPrint.ForeColor = [System.Drawing.Color]::White
    $btnUtilPrint.FlatStyle = "Flat"
    $btnUtilPrint.Add_MouseEnter({ Show-Description "Trick opening a clean folder of the legacy printers applet." })
    $btnUtilPrint.Add_Click({ Start-ClassicPrinters; Write-GUI "" })

    # DNS Enforcer
    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Fast DNS Server Switch"
    $lblDNS.Location = New-Object System.Drawing.Point(15, 385)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 410)
    $comboDNS.Size = New-Object System.Drawing.Size(240, 25)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
    $comboDNS.SelectedIndex = 0

    $btnApplyDNS = New-Object System.Windows.Forms.Button
    $btnApplyDNS.Text = "Apply DNS"
    $btnApplyDNS.Location = New-Object System.Drawing.Point(265, 409)
    $btnApplyDNS.Size = New-Object System.Drawing.Size(120, 27)
    $btnApplyDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnApplyDNS.ForeColor = [System.Drawing.Color]::White
    $btnApplyDNS.FlatStyle = "Flat"
    $btnApplyDNS.Add_MouseEnter({ Show-Description "Applies the selected secure DNS server for all active network adapters and flushes the DNS resolver cache." })
    $btnApplyDNS.Add_Click({ 
        Set-CustomDNS -Provider $comboDNS.SelectedItem
        Write-GUI " -> DNS configuration completed.`r`n" 
    })

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from the main adapter..."
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 442)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 20)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $tabUtil.Controls.AddRange(@($lblInspect, $btnUtilAppx, $btnUtilAppxProv, $btnUtilCaps, $btnUtilOpt, $btnUtilSvc, $btnUtilStartup, $lblClassic, $btnUtilNet, $btnUtilApps, $btnUtilSound, $btnUtilPrint, $lblDNS, $comboDNS, $btnApplyDNS, $global:lblCurrentDNS))
    $TabControl.Controls.Add($tabUtil)
}
# <<< END INJECTED MODULE: Z5_Utilities.ps1 <<<


# Z6_Integrity: Advanced repair and reset module. Features WinSXS compression (DISM /ResetBase) with deployment auditing, full network stack refresh, Print Spooler subsystem reset, and core file repairs.
# . (Join-Path $ModulesDir "Z6_Integrity.ps1")
# >>> BEGIN INJECTED MODULE: Z6_Integrity.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE
# Z6_Integrity: Service and repair module. Executes asynchronous WinSxS analysis, ResetBase compression, network stack refresh, Print Spooler reset, and core OS repairs.
# ==========================================

# ------------------------------------------
# Z6: ASYNC EXTERNAL CONSOLE HELPER (NO ANR)
# ------------------------------------------
function Start-ExternalConsoleAsync {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CommandChain,
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable
    )

    Write-GUI " -> Launching external maintenance console: $Title..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        param($CmdTitle, $CmdChain)
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c title $CmdTitle & color 0A & $CmdChain" -PassThru
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $proc.Dispose()
        return [PSCustomObject]@{
            Title    = $CmdTitle
            ExitCode = $exitCode
        }
    } -Arguments @($Title, $CommandChain) -OnComplete {
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            Write-GUI " -> [$($res.Title)] finished (Exit Code: $($res.ExitCode)).`n"
        }
    }
}

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-WinSxSState {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dism.exe"
    $psi.Arguments = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $dismOutput = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $proc.Dispose()

    $recommended = ($dismOutput -match "Component Store Cleanup Recommended\s*:\s*Yes")
    $sizeMatch   = [regex]::Match($dismOutput, "Actual Size of Component Store\s*:\s*(.+?)(\r?\n|$)")
    $actualSize  = if ($sizeMatch.Success) { $sizeMatch.Groups[1].Value.Trim() } else { "Unknown" }

    $rebootPending = Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

    return [PSCustomObject]@{
        UIDisplayName = "WinSxS Payload (Actual Size: $actualSize)"
        IsDetected    = $recommended
        ActionData    = $actualSize
        RebootPending = $rebootPending
    }
}

function Optimize-WinSXS {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $warnMsg = "A pending Windows servicing reboot was detected in the CBS registry.`n`nRunning DISM /ResetBase while a reboot is pending on Windows 11 24H2/26H2 may fail with error 0x800f0806.`n`nDo you still want to force execution?"
        $ans = [System.Windows.Forms.MessageBox]::Show($warnMsg, "WinUltix - CBS Reboot Pending", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-GUI " -> WinSxS ResetBase aborted due to pending reboot.`n"
            return
        }
    }

    $cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & echo. & echo Operation finished. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-SystemIntegrity {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk C: /scan & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & echo. & echo All integrity checks completed. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Clear-NetworkStack {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo Flushing DNS resolver cache... & ipconfig /flushdns & echo. & echo Resetting Winsock Catalog... & netsh winsock reset & echo. & echo Resetting TCP/IP Stack... & netsh int ip reset & echo. & echo Network stack refreshed. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - Network Stack Refresh" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-PrintSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $logs = [System.Collections.Generic.List[string]]::new()
        try {
            $spoolerProc = Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue
            if ($spoolerProc) {
                $spoolerProc | Stop-Process -Force -ErrorAction SilentlyContinue
                $logs.Add(" -> Terminated locked spoolsv.exe process.")
            } else {
                Stop-Service -Name "Spooler" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }

            Start-Sleep -Milliseconds 800

            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path -Path $spoolPath) {
                $purgedCount = 0
                Get-ChildItem -Path "$spoolPath\*" -Include "*.SHD", "*.SPL", "*.TMP" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.Attributes = 'Normal'
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    $purgedCount++
                }
                $logs.Add(" -> Purged $purgedCount orphaned .SHD/.SPL print queue file(s).")
            }

            $printWorkflow = Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue
            if ($printWorkflow) {
                $printWorkflow | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $printWorkflow | Start-Service -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $logs.Add(" -> Restarted dynamic PrintWorkflowUserSvc service.")
            }

            Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
            $logs.Add(" -> Print Spooler service is back online.")
        } catch {
            $logs.Add(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
        }
        return $logs
    } -OnComplete {
        param($logEntries)
        Update-Progress 0
        foreach ($line in $logEntries) { Write-GUI $line }
        Write-GUI ""
    }
}

function Initialize-Z6UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabWinSXS = New-Object System.Windows.Forms.TabPage
    $tabWinSXS.Text = "Integrity"
    $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $btnCheckSystem = New-Object System.Windows.Forms.Button
    $btnCheckSystem.Text = "Scan System (ChkDisk + SFC + RestoreHealth)"
    $btnCheckSystem.Location = New-Object System.Drawing.Point(15, 20)
    $btnCheckSystem.Size = New-Object System.Drawing.Size(370, 40)
    $btnCheckSystem.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCheckSystem.ForeColor = [System.Drawing.Color]::White
    $btnCheckSystem.FlatStyle = "Flat"
    $btnCheckSystem.Add_MouseEnter({ Show-Description "System First Aid: Scans core Windows OS files for corruption and replaces damaged components using DISM RestoreHealth and SFC without freezing the GUI." })
    $btnCheckSystem.Add_Click({ Repair-SystemIntegrity -ControlsToDisable @($this) })

    $btnResetBase = New-Object System.Windows.Forms.Button
    $btnResetBase.Text = "Aggressive Cleanup (ResetBase)"
    $btnResetBase.Location = New-Object System.Drawing.Point(15, 70)
    $btnResetBase.Size = New-Object System.Drawing.Size(320, 40)
    $btnResetBase.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnResetBase.ForeColor = [System.Drawing.Color]::White
    $btnResetBase.FlatStyle = "Flat"
    $btnResetBase.Add_MouseEnter({ Show-Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." })

    $btnAudWinSxS = New-Object System.Windows.Forms.Button
    $btnAudWinSxS.Text = "?"
    $btnAudWinSxS.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudWinSxS.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudWinSxS.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudWinSxS.ForeColor = [System.Drawing.Color]::White
    $btnAudWinSxS.FlatStyle = "Flat"
    $btnAudWinSxS.Add_MouseEnter({ Show-Description "AUDIT: Asynchronously analyzes true WinSxS footprint in a background Runspace and checks for pending CBS reboots." })

    $btnResetBase.Add_Click({ Optimize-WinSXS -ControlsToDisable @($btnResetBase, $btnAudWinSxS) }.GetNewClosure())
    $btnAudWinSxS.Add_Click({
        Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
        Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
        Update-Progress 30

        $sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnAudWinSxS, $btnResetBase) -OnComplete {
            param($output)
            Update-Progress 0
            $auditResult = $output | Select-Object -First 1
            if ($null -ne $auditResult) {
                Write-GUI "  [*] Actual Store Size: $($auditResult.ActionData)"
                if ($auditResult.RebootPending) {
                    Write-GUI "  [!] WARNING: Pending CBS reboot detected! Reboot before running ResetBase to avoid 0x800f0806."
                }
                if ($auditResult.IsDetected) {
                    Write-GUI "  [!] Cleanup Recommended by OS."
                } else {
                    Write-GUI "  [OK] CBS reports no mandatory cleanup, though I can still force ResetBase payload amputation."
                }
                Write-GUI ""
            }
        }
    }.GetNewClosure())

    $btnNetFix = New-Object System.Windows.Forms.Button
    $btnNetFix.Text = "Refresh Network (DNS/Winsock)"
    $btnNetFix.Location = New-Object System.Drawing.Point(15, 120)
    $btnNetFix.Size = New-Object System.Drawing.Size(370, 40)
    $btnNetFix.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 100, 100)
    $btnNetFix.ForeColor = [System.Drawing.Color]::White
    $btnNetFix.FlatStyle = "Flat"
    $btnNetFix.Add_MouseEnter({ Show-Description "Network Fix: Flushes DNS cache, resets Winsock catalog, and resets TCP/IP stack parameters." })
    $btnNetFix.Add_Click({ Clear-NetworkStack -ControlsToDisable @($this) })

    $btnFixPrinters = New-Object System.Windows.Forms.Button
    $btnFixPrinters.Text = "Reset Print Subsystem (Spooler)"
    $btnFixPrinters.Location = New-Object System.Drawing.Point(15, 170)
    $btnFixPrinters.Size = New-Object System.Drawing.Size(370, 40)
    $btnFixPrinters.BackColor = [System.Drawing.Color]::FromArgb(255, 120, 80, 40)
    $btnFixPrinters.ForeColor = [System.Drawing.Color]::White
    $btnFixPrinters.FlatStyle = "Flat"
    $btnFixPrinters.Add_MouseEnter({ Show-Description "Printer First-Aid: Kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files in System32, restarts PrintWorkflowUserSvc, and resumes Spooler." })
    $btnFixPrinters.Add_Click({ Repair-PrintSubsystem -ControlsToDisable @($this) })

    $tabWinSXS.Controls.AddRange(@($btnCheckSystem, $btnResetBase, $btnAudWinSxS, $btnNetFix, $btnFixPrinters))
    $TabControl.Controls.Add($tabWinSXS)
}
# <<< END INJECTED MODULE: Z6_Integrity.ps1 <<<


# Z7_Hardware: Low-level hardware diagnostics and tuning with interactive modals. Includes Affinity Lasso, CPPC P-State control, MSI Interrupt Enforcer, WHEA APIC decoder, Network NDIS offload tuning, System Timer (TSC) configuration, and NVMe APST/ASPM power management.
# . (Join-Path $ModulesDir "Z7_Hardware.ps1")
# >>> BEGIN INJECTED MODULE: Z7_Hardware.ps1 <<<
# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z7_HARDWARE.PS1 - HARDWARE & DIAGNOSTICS
# Z7_Hardware: Advanced hardware diagnostics. Contains Affinity Lasso (core locking), CPPC P-State Unhider (EPP, Demote/Promote), MSI Interrupt Enforcer (forcing IRQs on PCI bus), WHEA error logger (decoding APIC IDs for CPU/RAM), applies TCPNoDelay (Nagle's Algorithm), and Pre-Flight shortcut generator.
# ==========================================

# ------------------------------------------
# Z7: HARDWARE & DIAGNOSTICS AUDITS
# ------------------------------------------
function Get-CPUTopologyProfile {
    $cpu = Get-CimInstance -ClassName Win32_Processor -Property Name, NumberOfCores, NumberOfLogicalProcessors -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cpu) {
        return [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Unknown CPU"; CoreDesc = "N/A"; SmtEnabled = $true }
    }

    $cores   = [int]$cpu.NumberOfCores
    $logical = [int]$cpu.NumberOfLogicalProcessors
    $smt     = ($logical -gt $cores)
    $name    = $cpu.Name

    # Case 1: AMD 8-Core Single-CCD (e.g., 9800X3D, 7800X3D, 5800X3D, 9700X) -> Lock background apps to Cores 0-1
    if ($name -match "AMD" -and $cores -eq 8) {
        $mask = if ($smt) { [System.IntPtr]15 } else { [System.IntPtr]3 }
        $desc = if ($smt) { "Cores 0-1 (Threads 0-3)" } else { "Cores 0-1 (No SMT)" }
        return [PSCustomObject]@{ IsSupported = $true; Mask = $mask; Label = "AMD 8C Single-CCD"; CoreDesc = $desc; SmtEnabled = $smt }
    }

    # Case 2: AMD Dual-CCD (12C/16C, e.g., 7900X3D, 7950X3D, 9950X3D) -> Isolate background apps to the last 4 threads on CCD1
    if ($name -match "AMD" -and $cores -gt 8 -and $logical -ge 12) {
        $shift = [math]::Max(0, ($logical - 4))
        $maskVal = [int64]15 -shl $shift
        return [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "AMD Dual-CCD"; CoreDesc = "CCD1 Tail (Threads $shift-$($logical - 1))"; SmtEnabled = $smt }
    }

    # Case 3: Intel Hybrid (P+E Cores) or 6+ Core CPUs -> Isolate background apps to the last 4 threads (E-Cores)
    if ($cores -ge 6 -and $logical -ge 8) {
        $shift = [math]::Max(0, ($logical - 4))
        $maskVal = [int64]15 -shl $shift
        return [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "Multi-Core / Hybrid"; CoreDesc = "Tail Threads ($shift-$($logical - 1))"; SmtEnabled = $smt }
    }

    return [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Unsupported (<6C)"; CoreDesc = "N/A"; SmtEnabled = $smt }
}

function Test-CPUTopology {
    return (Get-CPUTopologyProfile).IsSupported
}

function Get-HardwareState_Affinity {
    $whitelist = @("systemsettings.exe", "shellexperiencehost.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "applicationframehost.exe", "rundll32.exe", "dllhost.exe", "ngciso.exe", "wmiadap.exe", "csrss.exe", "lsass.exe", "smss.exe", "services.exe", "svchost.exe", "wininit.exe", "winlogon.exe", "explorer.exe", "System", "Idle", "Registry", "dwm.exe", "fontdrvhost.exe", "Taskmgr.exe", "conhost.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe", "SearchHost.exe", "StartMenuExperienceHost.exe", "SecurityHealthService.exe", "SecurityHealthSystray.exe", "MsMpEng.exe", "NisSrv.exe", "LsaIso.exe", "audiodg.exe", "WmiPrvSE.exe", "TiWorker.exe", "TrustedInstaller.exe", "spoolsv.exe", "WUDFHost.exe", "System.exe", "Idle.exe", "Registry.exe", "Secure System.exe", "ctfmon.exe", "MpDefenderCoreService.exe", "NVDisplay.Container.exe", "ShellHost.exe", "iFiUsbAudioCpl.exe", "Windows11FirewallService.exe", "Windows11FirewallControl.exe", "AmdPpkgSvc.exe", "nvcontainer.exe", "MoUsoCoreWorker.exe", "SearchIndexer.exe", "smartscreen.exe", "AppActions.exe", "SDXHelper.exe", "QuickControls.exe", "armsvc.exe", "BudsManager.exe")
    $dictionary = @("Discord.exe", "Spotify.exe", "msedgewebview2.exe", "steamwebhelper.exe", "EpicGamesLauncher.exe", "obs64.exe", "ArmouryCrate.exe", "iCUE.exe", "Razer Synapse Service.exe", "firefox.exe", "chrome.exe", "msedge.exe", "brave.exe", "opera.exe", "GalaxyClient.exe", "GOG Galaxy.exe", "EADesktop.exe", "upc.exe", "Battle.net.exe", "WhatsApp.exe", "Telegram.exe", "Teams.exe", "slack.exe", "Overwolf.exe", "LGHUB.exe", "LGHUB_Agent.exe", "MSIAfterburner.exe", "RTSS.exe", "NZXT CAM.exe", "vgc.exe", "vgtray.exe", "OneDrive.exe")
    
    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

    # Single batch CIM query to replace deprecated per-process Get-WmiObject and wmic.exe calls
    $cimProcMap = @{}
    Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.ExecutablePath) { $cimProcMap[[int]$_.ProcessId] = $_.ExecutablePath }
    }

    $liveProcsGrouped = @{}
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $pName = "$($_.ProcessName).exe"
        if (-not $liveProcsGrouped.ContainsKey($pName)) {
            $liveProcsGrouped[$pName] = $_
        }
    }

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $savedApps = @()
    if (Test-Path $configPath) {
        $savedApps = (Get-ItemProperty -Path $configPath -ErrorAction SilentlyContinue).PSObject.Properties | Where-Object { $_.Name -match "\.exe$" } | Select-Object -ExpandProperty Name
    }

    $combined = ($dictionary + $liveProcsGrouped.Keys + $savedApps) | Where-Object { $_ -notin $whitelist } | Select-Object -Unique

    $listRunning  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $listSaved    = [System.Collections.Generic.List[PSCustomObject]]::new()
    $listTemplate = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($app in $combined) {
        $procName = $app -replace '\.exe$', ''
        $activeProc = $liveProcsGrouped[$app]
        $isDetected = ($app -in $savedApps)
        
        $procPath = ""
        if ($null -ne $activeProc) {
            try { $procPath = $activeProc.Path } catch {}
            if (-not $procPath) { try { $procPath = $activeProc.MainModule.FileName } catch {} }
            if (-not $procPath -and $cimProcMap.ContainsKey($activeProc.Id)) {
                $procPath = $cimProcMap[$activeProc.Id]
            }
            if (-not $procPath) { continue }
        }

        $priority = "---"
        if ($null -ne $activeProc) {
            try { $priority = $activeProc.PriorityClass.ToString() } catch { $priority = "Access Denied" }
            if ($activeProc.ProcessorAffinity -eq $targetMask) {
                $listRunning.Add([PSCustomObject]@{ UIDisplayName = "[LOCKED]   $app"; IsDetected = $isDetected; Path = $procPath; Priority = $priority; ActionData = @{ ExeName = $app; ProcName = $procName } })
            } else {
                $listRunning.Add([PSCustomObject]@{ UIDisplayName = "[RUNNING]  $app"; IsDetected = $isDetected; Path = $procPath; Priority = $priority; ActionData = @{ ExeName = $app; ProcName = $procName } })
            }
        } elseif ($app -in $savedApps) {
            $listSaved.Add([PSCustomObject]@{ UIDisplayName = "[SAVED]    $app"; IsDetected = $true; Path = "---"; Priority = "---"; ActionData = @{ ExeName = $app; ProcName = $procName } })
        } else {
            $listTemplate.Add([PSCustomObject]@{ UIDisplayName = "[TEMPLATE] $app"; IsDetected = $false; Path = "---"; Priority = "---"; ActionData = @{ ExeName = $app; ProcName = $procName } })
        }
    }

    return @(($listRunning | Sort-Object UIDisplayName) + ($listSaved | Sort-Object UIDisplayName) + ($listTemplate | Sort-Object UIDisplayName))
}

function Get-HardwareState_CPPC {
    $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"
    
    function Get-Pcfg ($sub, $set) {
        if ($null -eq $set) { $out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR $sub 2>$null }
        else { $out = powercfg.exe /qh SCHEME_CURRENT $sub $set 2>$null }
        
        if (-not $out) { return $null }
        
        # Scan for lines ending with a hex value (locale-independent)
        $hexLines = @($out -match ':\s*(0x[0-9a-fA-F]+)\s*$')
        if ($hexLines.Count -ge 1) {
            # First match in powercfg output is always AC Power
            if ($hexLines[0] -match '(0x[0-9a-fA-F]+)\s*$') {
                return [convert]::ToInt32($matches[1], 16)
            }
        }
        return $null
    }
    
    $e  = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' $null
    $d  = Get-Pcfg '4b92d758-5a24-4851-a470-815d78aee119' $null
    $pr = Get-Pcfg '7b224883-b3cc-4d79-819f-8374152cbe7c' $null

    $dispE  = if ($null -ne $e) { "$e%" } else { "Unknown" }
    $dispD  = if ($null -ne $d) { "$d%" } else { "Unknown" }
    $dispPr = if ($null -ne $pr) { "$pr%" } else { "Unknown" }

    $rules = @(
        @{ UIDisplayName = "Unhide: EPP [Current AC: $dispE]"; Path = "$basePath\36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ UIDisplayName = "Unhide: Idle Demote [Current AC: $dispD]"; Path = "$basePath\4b92d758-5a24-4851-a470-815d78aee119"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ UIDisplayName = "Unhide: Idle Promote [Current AC: $dispPr]"; Path = "$basePath\7b224883-b3cc-4d79-819f-8374152cbe7c"; Name = "Attributes"; Expected = 2; Type = "Registry" }
    )

    $results = @()
    foreach ($rule in $rules) {
        $isDetected = $true
        $val = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
        if ($null -ne $val -and $val -eq $rule.Expected) { $isDetected = $false }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

function Get-HardwareState_IRQ {
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $venKeys = Get-ChildItem -Path $pciPath -ErrorAction SilentlyContinue
    
    foreach ($ven in $venKeys) {
        $instances = Get-ChildItem -Path $ven.PSPath -ErrorAction SilentlyContinue
        
        foreach ($inst in $instances) {
            $msiPath = "$($inst.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            
            if (Test-Path $msiPath) {
                $devName = (Get-ItemProperty -Path $inst.PSPath -Name "FriendlyName" -ErrorAction SilentlyContinue).FriendlyName
                if (-not $devName) { 
                    $devName = (Get-ItemProperty -Path $inst.PSPath -Name "DeviceDesc" -ErrorAction SilentlyContinue).DeviceDesc 
                }
                
                if ($devName -match ";([^;]+)$") { $devName = $matches[1] }
                if (-not $devName) { $devName = "Unknown PCI Device" }
                
                $msiVal = (Get-ItemProperty -Path $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                $isMsiEnabled = ($msiVal -eq 1)
                
                $results.Add([PSCustomObject]@{
                    UIDisplayName = $devName
                    IsDetected    = $isMsiEnabled
                    ActionData    = @{ Path = $msiPath; DevicePath = $inst.PSPath }
                })
            }
        }
    }
    
    return @($results | Sort-Object UIDisplayName)
}

function Get-HardwareState_WHEA {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # Self-contained SMT check for Runspace isolation
    $cpu = Get-CimInstance -ClassName Win32_Processor -Property NumberOfCores, NumberOfLogicalProcessors -ErrorAction SilentlyContinue | Select-Object -First 1
    $smtEnabled = if ($null -ne $cpu) { ([int]$cpu.NumberOfLogicalProcessors -gt [int]$cpu.NumberOfCores) } else { $true }

    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 500 -ErrorAction Stop
        
        foreach ($evt in $events) {
            $apicId = "N/A"
            $coreInfo = ""
            $msg = $evt.Message
            $id = $evt.Id

            # Primary locale-independent XML extraction for APIC ID
            try {
                $xml = [xml]$evt.ToXml()
                $xmlApic = ($xml.Event.EventData.Data | Where-Object { $_.Name -match '^(APICId|ProcessorId)$' } | Select-Object -First 1).'#text'
                if ($xmlApic -match '^\d+$') { $apicId = $xmlApic }
                elseif ($xmlApic -match '^0x([0-9a-fA-F]+)$') { $apicId = [convert]::ToInt32($matches[1], 16).ToString() }
            } catch {}

            if ($apicId -eq "N/A" -and $msg -match "APIC ID:\s*(\d+)") { 
                $apicId = $matches[1]
            }

            if ($apicId -match '^\d+$') {
                $coreNum = if ($smtEnabled) { [math]::Floor([int]$apicId / 2) } else { [int]$apicId }
                $coreInfo = "(Core $coreNum)"
            }

            $humanReadable = "Unknown Hardware Error"
            if ($id -eq 18) { 
                $humanReadable = "[CPU] Cache/Core Error -> Vcore too low or Curve Optimizer too aggressive!" 
            } elseif ($id -eq 19) { 
                $humanReadable = "[IF/SoC] Interconnect Error -> FCLK unstable or VSOC/VDDG too low!" 
            } elseif ($id -eq 47) { 
                $humanReadable = "[RAM] Memory Controller -> tREFI/tRFC too tight or VDDQ too low!" 
            } else {
                if ($msg -match "Error Type:\s*(.+?)\r?\n") { $humanReadable = $matches[1] }
            }

            $time = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")

            $results.Add([PSCustomObject]@{
                UIDisplayName = "WHEA ID $id | APIC: $apicId"
                IsDetected    = $true
                Time          = $time
                EventID       = $id
                ApicID        = "$apicId $coreInfo".Trim()
                ErrorType     = $humanReadable
                RawMessage    = $msg
            })
        }
    } catch {}
    return $results
}

function Get-HardwareState_Network {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # 0. Global TCP/IP Stack Settings
    $globalOffload = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($globalOffload) {
        $isGlobalRssOpt = ($globalOffload.ReceiveSideScaling -eq 'Enabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Receive-Side Scaling (RSS)"; IsOptimized = $isGlobalRssOpt; ActionData = @{ Type="GlobalRSS" } })
        
        $isGlobalRscOpt = ($globalOffload.ReceiveSegmentCoalescing -eq 'Disabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Recv Segment Coalescing (RSC)"; IsOptimized = $isGlobalRscOpt; ActionData = @{ Type="GlobalRSC" } })
    }

    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue

    foreach ($adapter in $adapters) {
        $name = $adapter.Name
        $statusSuffix = if ($adapter.Status -ne 'Up') { " (Offline)" } else { "" }
        $adapterDispName = "$name$statusSuffix"
        
        # 1. TCP NoDelay & AckFrequency
        $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
        $tcpNoDelay = (Get-ItemProperty -Path $tcpPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay
        $tcpAck = (Get-ItemProperty -Path $tcpPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
        $isTcpOpt = ($tcpNoDelay -eq 1 -and $tcpAck -eq 1)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] TCPNoDelay & AckFrequency"; IsOptimized = $isTcpOpt; ActionData = @{ Type="TCP"; Adapter=$adapter } })

        # 2. Power Management (Registry PnPCapabilities)
        $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnPDeviceID)"
        $caps = (Get-ItemProperty -Path $enumPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
        # Default state is usually $null or 0. Value 24 (0x18) explicitly disables OS power management.
        $isPowerOpt = ($caps -eq 24)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Power Management (Sleep)"; IsOptimized = $isPowerOpt; ActionData = @{ Type="Power"; RegPath=$enumPath } })

        # 3. NDIS Advanced Properties (Separated variable $propDispName to prevent shadowing $adapterDispName)
        $ndisTweaks = @{
            "*InterruptModeration" = "0"
            "*FlowControl"         = "0"
            "*JumboPacket"         = "1514"
            "*EEE"                 = "0"
            "AdvancedEEE"          = "0"
            "EnableGreenEthernet"  = "0"
            "PowerSavingMode"      = "0"
        }
        foreach ($key in $ndisTweaks.Keys) {
            $prop = Get-NetAdapterAdvancedProperty -Name $name -RegistryKeyword $key -ErrorAction SilentlyContinue
            if ($prop) {
                $isNdisOpt = ($prop.RegistryValue -eq $ndisTweaks[$key])
                $propDispName = $prop.DisplayName
                $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] NDIS: $propDispName"; IsOptimized = $isNdisOpt; ActionData = @{ Type="NDIS"; Adapter=$adapter; Key=$key; Value=$ndisTweaks[$key] } })
            }
        }

        # 4. Offloads & RSS
        $rss = Get-NetAdapterRss -Name $name -ErrorAction SilentlyContinue
        if ($rss) { 
            $isRssOpt = ([bool]$rss.Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Receive Side Scaling (RSS)"; IsOptimized = $isRssOpt; ActionData = @{ Type="RSS"; Adapter=$adapter } }) 
        }

        $rsc = Get-NetAdapterRsc -Name $name -ErrorAction SilentlyContinue
        if ($rsc) { 
            $isRscOpt = ([bool]$rsc.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Recv Segment Coalescing (RSC)"; IsOptimized = $isRscOpt; ActionData = @{ Type="RSC"; Adapter=$adapter } }) 
        }

        $lso = Get-NetAdapterLso -Name $name -ErrorAction SilentlyContinue
        if ($lso) { 
            $isLsoOpt = ([bool]$lso.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Large Send Offload (LSO)"; IsOptimized = $isLsoOpt; ActionData = @{ Type="LSO"; Adapter=$adapter } }) 
        }

        $cso = Get-NetAdapterChecksumOffload -Name $name -ErrorAction SilentlyContinue
        if ($cso) { 
            $isCsoOpt = ([bool]$cso.IpIPv4Enabled -eq $true -and [bool]$cso.TcpIPv4Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Checksum Offload (CSO)"; IsOptimized = $isCsoOpt; ActionData = @{ Type="CSO"; Adapter=$adapter } }) 
        }
    }
    return $results
}

function Get-HardwareState_Timer {
    $results = @()
    
    # 1. Global Timer Resolution Requests (Win11 Kernel Fix)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $val = (Get-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
    $isGlobalOpt = ($null -ne $val -and $val -eq 1)
    $results += [PSCustomObject]@{ UIDisplayName = "Global Timer Resolution (Kernel Fix)"; IsOptimized = $isGlobalOpt; ActionData = @{ Type="Reg"; Path=$regPath; Name="GlobalTimerResolutionRequests"; Value=1 } }
    
    # 2. High Precision Event Timer (HPET) Device State
    $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
    if ($null -ne $hpet) {
        # ConfigManagerErrorCode 22 means the device is explicitly disabled
        $isHpetDisabled = ($hpet.ConfigManagerErrorCode -eq 22)
        $results += [PSCustomObject]@{ UIDisplayName = "Disable HPET (Device Manager)"; IsOptimized = $isHpetDisabled; ActionData = @{ Type="PNP"; Instance=$hpet.InstanceId } }
    }

    # 3. BCDedit Diagnostics (TSC Enforcement)
    $bcd = (bcdedit.exe /enum "{current}" 2>$null) -join " "
    
    $dynTickOpt = ($bcd -match "(?i)disabledynamictick\s+(Yes|Tak|True|1)")
    $results += [PSCustomObject]@{ UIDisplayName = "Disable Dynamic Tick (Power Saving)"; IsOptimized = $dynTickOpt; ActionData = @{ Type="BCD"; Cmd="disabledynamictick yes" } }
    
    $platClockOpt = ($bcd -match "(?i)useplatformclock\s+(No|Nie|False|0)")
    $results += [PSCustomObject]@{ UIDisplayName = "Disable Platform Clock (Force TSC)"; IsOptimized = $platClockOpt; ActionData = @{ Type="BCD"; Cmd="useplatformclock no" } }
	
    return $results
}

function Get-CurrentTimerResolution {
    $type = [System.Management.Automation.PSTypeName]'WinUltix.NtDll'
    if (-not $type.Type) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        namespace WinUltix {
            public class NtDll {
                [DllImport("ntdll.dll")]
                private static extern int NtQueryTimerResolution(out uint MaximumTime, out uint MinimumTime, out uint CurrentTime);
                
                public static uint[] GetTimerData() {
                    uint max, min, cur;
                    NtQueryTimerResolution(out max, out min, out cur);
                    return new uint[] { max, min, cur };
                }
            }
        }
"@
    }
    
    $data = [WinUltix.NtDll]::GetTimerData()
    
    return [PSCustomObject]@{
        DefaultMs = [math]::Round($data[0] / 10000.0, 4)
        LimitMs   = [math]::Round($data[1] / 10000.0, 4)
        CurrentMs = [math]::Round($data[2] / 10000.0, 4)
    }
}

function Get-HardwareState_NVMe {
    $results = @()
    
    # 1. Global PCIe Bus Lock (pci.sys)
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters"
    $aspm = (Get-ItemProperty -Path $pciPath -Name "DisableASPM" -ErrorAction SilentlyContinue).DisableASPM
    $isAspmOpt = ($null -ne $aspm -and $aspm -eq 1)
    $results += [PSCustomObject]@{ UIDisplayName = "PCIe ASPM Global Bus Lock (DisableASPM)"; IsOptimized = $isAspmOpt; ActionData = @{ Type="Reg"; Path=$pciPath; Name="DisableASPM"; Val=1 } }

    # 2. StorNVMe APST Driver Lock (stornvme.sys)
    $nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
    $nvmeIdle = (Get-ItemProperty -Path $nvmePath -Name "IdlePowerMode" -ErrorAction SilentlyContinue).IdlePowerMode
    $isNvmeIdleOpt = ($null -ne $nvmeIdle -and $nvmeIdle -eq 0)
    $results += [PSCustomObject]@{ UIDisplayName = "StorNVMe APST Driver Lock (IdlePowerMode)"; IsOptimized = $isNvmeIdleOpt; ActionData = @{ Type="Reg"; Path=$nvmePath; Name="IdlePowerMode"; Val=0 } }

    # 3. System Memory Compression (MMAgent)
    $mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
    $isMemOpt = ($null -ne $mmAgent -and $mmAgent.MemoryCompression -eq $false)
    $results += [PSCustomObject]@{ UIDisplayName = "System Memory Compression (MMAgent)"; IsOptimized = $isMemOpt; ActionData = @{ Type="MMAgent" } }

    return $results
}

# ------------------------------------------
# Z7: HARDWARE & DIAGNOSTICS ENGINE
# ------------------------------------------
function Set-AppAffinity {
    param([array]$SelectedItems, [bool]$Execute = $true)
    if ($SelectedItems.Count -eq 0) { return }

    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    if (-not (Test-Path $configPath)) { New-Item -Path $configPath -Force -ErrorAction SilentlyContinue | Out-Null }

    foreach ($item in $SelectedItems) {
        $exeName = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        Set-ItemProperty -Path $configPath -Name $exeName -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                Write-GUI " -> Live Locking ($($topo.CoreDesc)): $exeName ($($procs.Count) instances)"
                foreach ($p in $procs) {
                    try { 
                        $p.ProcessorAffinity = $targetMask 
                        $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                    } catch { Write-GUI "    [!] Access denied: PID $($p.Id) (System lock)" }
                }
            } else { Write-GUI " -> Saved to config (Currently not running): $exeName" }
        } else { Write-GUI " -> Saved to Target Roster: $exeName" }
    }
}

function Remove-AppAffinity {
    param([array]$SelectedItems, [bool]$Execute = $true, [bool]$KeepConfig = $false)
    if ($SelectedItems.Count -eq 0) { return }

    $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $lpCount = [Environment]::ProcessorCount
    $fullMaskVal = if ($lpCount -ge 64) { -1 } else { ([int64]1 -shl $lpCount) - 1 }
    $systemAffinity = [System.IntPtr]$fullMaskVal

    foreach ($item in $SelectedItems) {
        $exeName = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        if (-not $KeepConfig -and (Test-Path $configPath)) { 
            Remove-ItemProperty -Path $configPath -Name $exeName -ErrorAction SilentlyContinue 
        }

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                $needsUnlock = $false
                foreach ($p in $procs) {
                    try {
                        if ($p.ProcessorAffinity -ne $systemAffinity -or $p.PriorityClass -ne [System.Diagnostics.ProcessPriorityClass]::Normal) {
                            $needsUnlock = $true
                            break
                        }
                    } catch {}
                }

                if ($needsUnlock) {
                    Write-GUI " -> Releasing CPU Restraints: $exeName"
                    foreach ($p in $procs) { 
                        try { 
                            $p.ProcessorAffinity = $systemAffinity 
                            $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                        } catch { } 
                    }
                }
            }
        } else { 
            if (-not $KeepConfig) { Write-GUI " -> Removed from Target Roster: $exeName" }
        }
    }
}

function Invoke-ApplyCPPC {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> CPPC settings are already fully unhidden."; return }

    foreach ($item in $SelectedItems) {
        $rule = $item.ActionData
        Write-GUI " -> Unlocking Visibility: $($rule.UIDisplayName)"
        try {
            Set-ItemProperty -Path $rule.Path -Name $rule.Name -Value $rule.Expected -Type DWord -Force -ErrorAction Stop | Out-Null
        } catch { Write-GUI "    [!] Failed to unhide: $($rule.UIDisplayName)" }
    }
}

function Clear-WHEALogs {
    Write-GUI " -> Clearing System Event Log (WHEA Records)..."
    try {
        & wevtutil.exe cl System 2>$null
        Write-GUI "    [OK] System log successfully wiped."
    } catch { 
        Write-GUI "    [!] Failed to clear System log. Administrator privileges missing?" 
    }
}

function Invoke-ApplyNetworkTweaks {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No network modifications selected."; return }

    foreach ($item in $SelectedItems) {
        $data = $item.ActionData
        $name = if ($null -ne $data.Adapter) { $data.Adapter.Name } else { "" }
        Write-GUI " -> Configuring: $($item.UIDisplayName)"
        
        try {
            switch ($data.Type) {
                "GlobalRSS" { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction Stop }
                "GlobalRSC" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction Stop }
                "TCP" {
                    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($data.Adapter.InterfaceGuid)"
                    New-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
                    New-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null 
                }
                "Power" {
                    Set-ItemProperty -Path $data.RegPath -Name "PnPCapabilities" -Value 24 -Type DWord -Force -ErrorAction Stop
                }
                "NDIS" { Set-NetAdapterAdvancedProperty -Name $name -RegistryKeyword $data.Key -RegistryValue $data.Value -ErrorAction SilentlyContinue }
                "RSS"  { Enable-NetAdapterRss -Name $name -ErrorAction SilentlyContinue }
                "RSC"  { Disable-NetAdapterRsc -Name $name -ErrorAction SilentlyContinue }
                "LSO"  { Disable-NetAdapterLso -Name $name -ErrorAction SilentlyContinue }
                "CSO"  { 
                    Enable-NetAdapterChecksumOffload -Name $name -IpIPv4 -ErrorAction SilentlyContinue
                    Enable-NetAdapterChecksumOffload -Name $name -TcpIPv4 -ErrorAction SilentlyContinue
                    Enable-NetAdapterChecksumOffload -Name $name -UdpIPv4 -ErrorAction SilentlyContinue
                }
            }
        } catch { Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)" }
    }
}

function Invoke-ApplyTimerTweaks {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No Timer modifications selected."; return }

    foreach ($item in $SelectedItems) {
        $data = $item.ActionData
        Write-GUI " -> Configuring Timer Subsystem: $($item.UIDisplayName)"
        
        try {
            if ($data.Type -eq "Reg") {
                if (-not (Test-Path $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $data.Path -Name $data.Name -Value $data.Value -Type DWord -Force -ErrorAction Stop
            } elseif ($data.Type -eq "BCD") {
                $cmdArgs = $data.Cmd.Split(' ')
                Start-Process -FilePath "bcdedit.exe" -ArgumentList "/set `{current`} $($cmdArgs[0]) $($cmdArgs[1])" -NoNewWindow -Wait
            } elseif ($data.Type -eq "PNP") {
                Disable-PnpDevice -InstanceId $data.Instance -Confirm:$false -ErrorAction Stop
            }
        } catch { Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)" }
    }
}

function Invoke-ApplyNVMeTweaks {
    param([array]$SelectedItems)
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No I/O or Memory modifications selected."; return }

    foreach ($item in $SelectedItems) {
        $data = $item.ActionData
        Write-GUI " -> Configuring Subsystem: $($item.UIDisplayName)"
        
        try {
            if ($data.Type -eq "Reg") {
                if (-not (Test-Path $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $data.Path -Name $data.Name -Value $data.Val -Type DWord -Force -ErrorAction Stop
            } elseif ($data.Type -eq "MMAgent") {
                Disable-MMAgent -MemoryCompression -ErrorAction Stop
            }
        } catch { 
            Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)"
            Write-GUI "    [DEBUG] $($_.Exception.Message)"
        }
    }
}

# ------------------------------------------
# Z7: DEDICATED HARDWARE MODALS
# ------------------------------------------
function Show-AffinityModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 720); $modal.MinimumSize = New-Object System.Drawing.Size(850, 720); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = "Refresh List"; $btnRefresh.Location = New-Object System.Drawing.Point(715, 15); $btnRefresh.Size = New-Object System.Drawing.Size(100, 35); $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRefresh.FlatStyle = "Flat"; $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 480); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $listView.Font = New-Object System.Drawing.Font("Consolas", 11.5)
    $listView.Anchor = 'Top, Bottom, Left, Right'
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true; $listView.FullRowSelect = $true; $listView.GridLines = $true

    $listView.Columns.Add("Status & App Name", 250) | Out-Null
    $listView.Columns.Add("Priority", 110) | Out-Null
    $listView.Columns.Add("Executable Path", 410) | Out-Null
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $listView.BeginUpdate()
        $listView.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Affinity
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.UIDisplayName)
            $lvItem.SubItems.Add($item.Priority)
            $lvItem.SubItems.Add($item.Path)
            $lvItem.Checked = $item.IsDetected
            [void]$listView.Items.Add($lvItem)
        }
        $listView.EndUpdate()
    }
    &$refreshData
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $txtCustom = New-Object System.Windows.Forms.TextBox; $txtCustom.Location = New-Object System.Drawing.Point(15, 555); $txtCustom.Size = New-Object System.Drawing.Size(250, 25); $txtCustom.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $txtCustom.ForeColor = [System.Drawing.Color]::White; $txtCustom.Font = New-Object System.Drawing.Font("Segoe UI", 10); $txtCustom.Anchor = 'Bottom, Left'
    $btnAddExe = New-Object System.Windows.Forms.Button; $btnAddExe.Text = "+ Add Custom .exe"; $btnAddExe.Location = New-Object System.Drawing.Point(275, 554); $btnAddExe.Size = New-Object System.Drawing.Size(140, 27); $btnAddExe.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnAddExe.FlatStyle = "Flat"; $btnAddExe.Anchor = 'Bottom, Left'
    
    $btnAddExe.Add_Click({
        $exe = $txtCustom.Text.Trim()
        if ($exe -ne "" -and $exe -match "\.exe$") {
            $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
            if (!(Test-Path $configPath)) { New-Item -Path $configPath -Force | Out-Null }
            Set-ItemProperty -Path $configPath -Name $exe -Value 1 -Type DWord -Force | Out-Null
            $txtCustom.Text = ""
            &$refreshData 
        } else { [System.Windows.Forms.MessageBox]::Show("Process must end with .exe", "Invalid Input") }
    }.GetNewClosure())

    $btnDelExe = New-Object System.Windows.Forms.Button; $btnDelExe.Text = "- Remove Selected"; $btnDelExe.Location = New-Object System.Drawing.Point(425, 554); $btnDelExe.Size = New-Object System.Drawing.Size(140, 27); $btnDelExe.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 60); $btnDelExe.FlatStyle = "Flat"; $btnDelExe.Anchor = 'Bottom, Left'
    $btnDelExe.Add_Click({
        $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
        $removed = 0
        foreach ($item in $listView.SelectedItems) {
            $exe = $localData[$item.Index].ActionData.ExeName
            if (Test-Path $configPath) {
                Remove-ItemProperty -Path $configPath -Name $exe -ErrorAction SilentlyContinue | Out-Null
                $removed++
            }
        }
        if ($removed -gt 0) { &$refreshData }
    }.GetNewClosure())

    $getDelta = {
        $apply = @(); $remove = @()
        for ($i = 0; $i -lt $listView.Items.Count; $i++) {
            $item = $localData[$i]
            $wasChecked = $item.IsDetected
            $isChecked = $listView.Items[$i].Checked
            if ($isChecked -and -not $wasChecked) { $apply += $item } elseif (-not $isChecked -and $wasChecked) { $remove += $item }
        }
        return @{ Apply = $apply; Remove = $remove }
    }

    $btnSave = New-Object System.Windows.Forms.Button; $btnSave.Text = "Save Roster"; $btnSave.Location = New-Object System.Drawing.Point(15, 595); $btnSave.Size = New-Object System.Drawing.Size(150, 35); $btnSave.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnSave.FlatStyle = "Flat"; $btnSave.Anchor = 'Bottom, Left'
    $btnSave.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $false }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $false -KeepConfig $false }
        &$refreshData
    }.GetNewClosure())

    $btnEngage = New-Object System.Windows.Forms.Button; $btnEngage.Text = "ENGAGE (Lock)"; $btnEngage.Location = New-Object System.Drawing.Point(175, 595); $btnEngage.Size = New-Object System.Drawing.Size(150, 35); $btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnEngage.FlatStyle = "Flat"; $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $true }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $true -KeepConfig $false }
        
        $allItems = @()
        for ($i = 0; $i -lt $listView.Items.Count; $i++) { if ($listView.Items[$i].Checked) { $allItems += $localData[$i] } }
        if ($allItems.Count -gt 0) { Set-AppAffinity -SelectedItems $allItems -Execute $true }
        &$refreshData 
    }.GetNewClosure())

    $btnRelease = New-Object System.Windows.Forms.Button; $btnRelease.Text = "RELEASE (Unlock)"; $btnRelease.Location = New-Object System.Drawing.Point(335, 595); $btnRelease.Size = New-Object System.Drawing.Size(150, 35); $btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60); $btnRelease.FlatStyle = "Flat"; $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        Remove-AppAffinity -SelectedItems $localData -Execute $true -KeepConfig $true
        &$refreshData 
    }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(495, 595); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $lblTip = New-Object System.Windows.Forms.Label
    $lblTip.Text = "INFO: 'Save Roster' stores your preset in the registry. You can instantly apply it later before gaming using the 'Pre-Flight' desktop shortcut."
    $lblTip.Location = New-Object System.Drawing.Point(15, 640)
    $lblTip.Size = New-Object System.Drawing.Size(800, 25)
    $lblTip.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblTip.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTip.Anchor = 'Bottom, Left'

    $modal.Controls.AddRange(@($lblDesc, $btnRefresh, $listView, $txtCustom, $btnAddExe, $btnDelExe, $btnSave, $btnEngage, $btnRelease, $btnClose, $lblTip))
    try { [void]$modal.ShowDialog() } finally { $modal.Dispose() }
}

function Show-CPPCModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 450); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 450)

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 60); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightGreen; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    # Locale-independent AC hex parser
    $getAcHex = {
        param([string]$Guid)
        $out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR $Guid 2>$null
        if (-not $out) { return $null }
        $hexLines = @($out -match ':\s*(0x[0-9a-fA-F]+)\s*$')
        if ($hexLines.Count -ge 1 -and $hexLines[0] -match '(0x[0-9a-fA-F]+)\s*$') {
            return [convert]::ToInt32($matches[1], 16)
        }
        return $null
    }

    $refreshData = {
        $chkList.Items.Clear()
        $basePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"
        
        $e  = &$getAcHex '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        $d  = &$getAcHex '4b92d758-5a24-4851-a470-815d78aee119'
        $pr = &$getAcHex '7b224883-b3cc-4d79-819f-8374152cbe7c'

        $dispE  = if ($null -ne $e) { "$e%" } else { "Unknown" }
        $dispD  = if ($null -ne $d) { "$d%" } else { "Unknown" }
        $dispPr = if ($null -ne $pr) { "$pr%" } else { "Unknown" }

        $rules = @(
            @{ UIDisplayName = "EPP [Current AC: $dispE]"; Path = "$basePath\36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name = "Attributes"; Expected = 2; Type = "Registry" }
            @{ UIDisplayName = "Idle Demote [Current AC: $dispD]"; Path = "$basePath\4b92d758-5a24-4851-a470-815d78aee119"; Name = "Attributes"; Expected = 2; Type = "Registry" }
            @{ UIDisplayName = "Idle Promote [Current AC: $dispPr]"; Path = "$basePath\7b224883-b3cc-4d79-819f-8374152cbe7c"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        )
        $script:cppcRules = $rules 

        foreach ($rule in $rules) {
            $val = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
            if ($null -ne $val -and $val -eq $rule.Expected) { [void]$chkList.Items.Add("[ UNHIDDEN ] " + $rule.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ HIDDEN ]   " + $rule.UIDisplayName, $true) }
        }
    }
    
    &$refreshData 

    $btnUnhide = New-Object System.Windows.Forms.Button; $btnUnhide.Text = "Unhide Checked"; $btnUnhide.Location = New-Object System.Drawing.Point(15, 355); $btnUnhide.Size = New-Object System.Drawing.Size(120, 35); $btnUnhide.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnUnhide.FlatStyle = "Flat"; $btnUnhide.Anchor = 'Bottom, Left'
    $btnUnhide.Add_Click({
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) {
                $r = $script:cppcRules[$i]
                Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Expected -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                Write-GUI " -> Unhidden CPPC attribute: $($r.UIDisplayName)"
            }
        }
        &$refreshData 
    }.GetNewClosure())

    $btnEngage = New-Object System.Windows.Forms.Button; $btnEngage.Text = "ENGAGE Max CPPC"; $btnEngage.Location = New-Object System.Drawing.Point(145, 355); $btnEngage.Size = New-Object System.Drawing.Size(150, 35); $btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnEngage.FlatStyle = "Flat"; $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        # 1. Global Backup to HKLM (preserve original values if not already in Max CPPC state)
        $p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        $e  = &$getAcHex '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        $d  = &$getAcHex '4b92d758-5a24-4851-a470-815d78aee119'
        $pr = &$getAcHex '7b224883-b3cc-4d79-819f-8374152cbe7c'

        if ($null -ne $e -and -not ($e -eq 0 -and $d -eq 100 -and $pr -eq 100)) {
            Set-ItemProperty -Path $p -Name 'EPP' -Value $e -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Demote' -Value $d -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Promote' -Value $pr -Type DWord -Force
        }

        # 2. Register SYSTEM-level Dead Man's Switch in Task Scheduler (Triggers AtStartup + AtLogon)
        $tsCmd = "`$p='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path `$p){ `$r=Get-ItemProperty `$p; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
        $tsAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$tsCmd`""
        $tsTriggers = @(
            (New-ScheduledTaskTrigger -AtStartup),
            (New-ScheduledTaskTrigger -AtLogon)
        )
        $tsPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Action $tsAction -Trigger $tsTriggers -Principal $tsPrincipal -Force | Out-Null

        # 3. Engage maximum performance CPPC parameters
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setactive SCHEME_CURRENT
        Write-GUI " -> Engaged Max CPPC (EPP 0%, Demote/Promote 100%). Dead Man's Switch armed."
        &$refreshData
    }.GetNewClosure())

    $btnRelease = New-Object System.Windows.Forms.Button; $btnRelease.Text = "RELEASE CPPC"; $btnRelease.Location = New-Object System.Drawing.Point(305, 355); $btnRelease.Size = New-Object System.Drawing.Size(130, 35); $btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60); $btnRelease.FlatStyle = "Flat"; $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        $p = 'HKLM:\SOFTWARE\WinUltix\CPPC'; $e=50; $d=40; $pr=60
        if (Test-Path $p) { $reg=Get-ItemProperty -Path $p -ErrorAction SilentlyContinue; if ($null -ne $reg.EPP) { $e=$reg.EPP }; if ($null -ne $reg.Demote) { $d=$reg.Demote }; if ($null -ne $reg.Promote) { $pr=$reg.Promote } }
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr; powercfg.exe /setactive SCHEME_CURRENT
        
        Unregister-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-GUI " -> Released CPPC lock (Restored EPP: $e%, Demote: $d%, Promote: $pr%). Failsafe disarmed."
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(445, 355); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList, $btnUnhide, $btnEngage, $btnRelease, $btnClose))
    try { [void]$modal.ShowDialog() } finally { $modal.Dispose() }
}

function Show-MsiModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 480); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 480)

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply new IRQ vectors."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(600, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightGreen; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_IRQ
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            $prefix = if ($item.IsDetected) { "[ENABLED]  " } else { "[DISABLED] " }
            $shouldCheck = -not $item.IsDetected
            [void]$chkList.Items.Add($prefix + $item.UIDisplayName, $shouldCheck)
        }
    }
    
    &$refreshData

    $btnForceMSI = New-Object System.Windows.Forms.Button; $btnForceMSI.Text = "Force MSI Mode"; $btnForceMSI.Location = New-Object System.Drawing.Point(15, 385); $btnForceMSI.Size = New-Object System.Drawing.Size(150, 35); $btnForceMSI.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnForceMSI.FlatStyle = "Flat"; $btnForceMSI.Anchor = 'Bottom, Left'
    $btnForceMSI.Add_Click({
        $changed = 0
        $b = "HKCU:\Software\WinUltix\MSI_Backup"
        if (!(Test-Path $b)) { New-Item -Path $b -Force | Out-Null }
        
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) {
                $dev = $localData[$i]
                $p = $dev.ActionData.Path
                $safeName = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($p))
                
                # Only back up original factory state if not already backed up
                $existingBackup = (Get-ItemProperty -Path $b -Name $safeName -ErrorAction SilentlyContinue).$safeName
                if ($null -eq $existingBackup) {
                    $old = (Get-ItemProperty -Path $p -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                    if ($null -eq $old) { $old = 255 }
                    Set-ItemProperty -Path $b -Name $safeName -Value $old -Type DWord -Force | Out-Null
                }

                Set-ItemProperty -Path $p -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                Write-GUI " -> Forced MSI Mode (MSISupported=1): $($dev.UIDisplayName)"
                $changed++
            }
        }
        &$refreshData
        if ($changed -gt 0) { [System.Windows.Forms.MessageBox]::Show("Successfully forced MSI mode for $changed device(s).`nOriginal states backed up.`nPlease reboot your PC.", "Reboot Required") }
    }.GetNewClosure())

    $btnRevertMSI = New-Object System.Windows.Forms.Button; $btnRevertMSI.Text = "Restore Original State"; $btnRevertMSI.Location = New-Object System.Drawing.Point(175, 385); $btnRevertMSI.Size = New-Object System.Drawing.Size(170, 35); $btnRevertMSI.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 100, 100); $btnRevertMSI.FlatStyle = "Flat"; $btnRevertMSI.Anchor = 'Bottom, Left'
    $btnRevertMSI.Add_Click({
        $b = "HKCU:\Software\WinUltix\MSI_Backup"
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) {
                $dev = $localData[$i]
                $p = $dev.ActionData.Path
                $safeName = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($p))
                
                $old = (Get-ItemProperty -Path $b -Name $safeName -ErrorAction SilentlyContinue).$safeName
                if ($null -ne $old) {
                    if ($old -eq -1 -or $old -eq 255 -or $old -eq 4294967295) { 
                        Remove-ItemProperty -Path $p -Name "MSISupported" -ErrorAction SilentlyContinue | Out-Null 
                    } else { 
                        Set-ItemProperty -Path $p -Name "MSISupported" -Value $old -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null 
                    }
                    Remove-ItemProperty -Path $b -Name $safeName -ErrorAction SilentlyContinue | Out-Null
                } else {
                    Set-ItemProperty -Path $p -Name "MSISupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                }
                Write-GUI " -> Reverted MSI Mode to factory state: $($dev.UIDisplayName)"
            }
        }
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(355, 385); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList, $btnForceMSI, $btnRevertMSI, $btnClose))
    try { [void]$modal.ShowDialog() } finally { $modal.Dispose() }
}

function Show-WHEAModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 500); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(850, 500)
    
    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = "Scan Now"; $btnRefresh.Location = New-Object System.Drawing.Point(715, 15); $btnRefresh.Size = New-Object System.Drawing.Size(100, 35); $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRefresh.FlatStyle = "Flat"; $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 330); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::White; $listView.Font = New-Object System.Drawing.Font("Consolas", 10); $listView.Anchor = 'Top, Bottom, Left, Right'; $listView.View = [System.Windows.Forms.View]::Details; $listView.FullRowSelect = $true; $listView.GridLines = $true

    $listView.Columns.Add("Time", 170) | Out-Null
    $listView.Columns.Add("Event ID", 90) | Out-Null
    $listView.Columns.Add("APIC ID", 120) | Out-Null
    $listView.Columns.Add("Error Source / Details", 390) | Out-Null

    $btnClear = New-Object System.Windows.Forms.Button; $btnClear.Text = "Wipe Logs (Prepare for Test)"; $btnClear.Location = New-Object System.Drawing.Point(15, 405); $btnClear.Size = New-Object System.Drawing.Size(220, 35); $btnClear.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnClear.FlatStyle = "Flat"; $btnClear.Anchor = 'Bottom, Left'
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(245, 405); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    # Asynchronous WHEA Event Log scanner using Invoke-AsyncTask
    $refreshData = {
        # Explicitly bind UI references into Scope 0 so GetNewClosure() captures them
        $uiModal    = $modal
        $uiListView = $listView

        $uiListView.Items.Clear()
        $loadingItem = New-Object System.Windows.Forms.ListViewItem("Scanning...")
        $loadingItem.SubItems.Add("---")
        $loadingItem.SubItems.Add("---")
        $loadingItem.SubItems.Add("Parsing System WHEA Event Log in background Runspace...")
        $loadingItem.ForeColor = [System.Drawing.Color]::LightSkyBlue
        [void]$uiListView.Items.Add($loadingItem)

        $sb = (Get-Command -Name Get-HardwareState_WHEA).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnRefresh, $btnClear) -OnComplete ({
            param($output)
            if ($null -eq $uiModal -or $uiModal.IsDisposed -or $null -eq $uiListView -or $uiListView.IsDisposed) { return }
            
            $uiListView.BeginUpdate()
            $uiListView.Items.Clear()
            [array]$auditData = @($output | Where-Object { $null -ne $_ })
            
            if ($auditData.Count -gt 0) {
                foreach ($item in $auditData) {
                    $lvItem = New-Object System.Windows.Forms.ListViewItem($item.Time)
                    $lvItem.SubItems.Add([string]$item.EventID)
                    
                    if ($item.ApicID -ne "N/A") {
                        $lvItem.UseItemStyleForSubItems = $false
                        $lvItem.SubItems.Add($item.ApicID).ForeColor = [System.Drawing.Color]::OrangeRed
                    } else {
                        $lvItem.SubItems.Add($item.ApicID)
                    }
                    
                    $lvItem.SubItems.Add($item.ErrorType)
                    [void]$uiListView.Items.Add($lvItem)
                }
            } else {
                $lvItem = New-Object System.Windows.Forms.ListViewItem("---")
                $lvItem.SubItems.Add("---")
                $lvItem.SubItems.Add("---")
                $lvItem.SubItems.Add("No WHEA errors found. Hardware is perfectly stable.")
                $lvItem.ForeColor = [System.Drawing.Color]::LightGreen
                [void]$uiListView.Items.Add($lvItem)
            }
            $uiListView.EndUpdate()
        }.GetNewClosure())
    }
    
    &$refreshData
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClear.Add_Click({
        Clear-WHEALogs
        &$refreshData
        [System.Windows.Forms.MessageBox]::Show("System Event Log wiped. Ready for next stability test.", "Logs Cleared")
    }.GetNewClosure())

    $modal.Controls.AddRange(@($lblDesc, $btnRefresh, $listView, $btnClear, $btnClose))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-NetworkModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(750, 550); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(750, 550)

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(700, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] Applying NDIS settings will momentarily disconnect the network adapter."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(700, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(700, 370); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $btnEngage = New-Object System.Windows.Forms.Button; $btnEngage.Text = "Optimize Checked Items"; $btnEngage.Location = New-Object System.Drawing.Point(15, 465); $btnEngage.Size = New-Object System.Drawing.Size(200, 35); $btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnEngage.FlatStyle = "Flat"; $btnEngage.Anchor = 'Bottom, Left'
    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = "Refresh Audit"; $btnRefresh.Location = New-Object System.Drawing.Point(225, 465); $btnRefresh.Size = New-Object System.Drawing.Size(120, 35); $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRefresh.FlatStyle = "Flat"; $btnRefresh.Anchor = 'Bottom, Left'
    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(355, 465); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    # Asynchronous NDIS & TCP/IP scanner via Invoke-AsyncTask
    $refreshData = {
        # Explicitly bind UI and data references into Scope 0 so GetNewClosure() captures them
        $uiModal     = $modal
        $uiChkList   = $chkList
        $uiLocalData = $localData

        $uiChkList.Items.Clear()
        $uiLocalData.Clear()
        [void]$uiChkList.Items.Add("Scanning physical adapters & NDIS properties in background...", $false)

        $sb = (Get-Command -Name Get-HardwareState_Network).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnEngage, $btnRefresh) -OnComplete ({
            param($output)
            if ($null -eq $uiModal -or $uiModal.IsDisposed -or $null -eq $uiChkList -or $uiChkList.IsDisposed) { return }
            
            $uiChkList.Items.Clear()
            $uiLocalData.Clear()
            [array]$auditData = @($output | Where-Object { $null -ne $_ })
            
            foreach ($item in $auditData) {
                [void]$uiLocalData.Add($item)
                if ($item.IsOptimized) { 
                    [void]$uiChkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) 
                } else { 
                    [void]$uiChkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) 
                }
            }
        }.GetNewClosure())
    }
    
    &$refreshData 

    $btnEngage.Add_Click({
        $applyQueue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i) -and $i -lt $localData.Count) {
                $applyQueue += $localData[$i]
            }
        }
        
        if ($applyQueue.Count -gt 0) {
            Invoke-ApplyNetworkTweaks -SelectedItems $applyQueue
            Write-GUI " -> Waiting for adapter re-initialization (2s)..."
            Start-Sleep -Seconds 2
        }
        
        &$refreshData
    }.GetNewClosure())

    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList, $btnEngage, $btnRefresh, $btnClose))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-TimerModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 400); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 400)

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] BCD modifications require a system reboot to lock the TSC hardware timer."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(600, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblCurrentTimer = New-Object System.Windows.Forms.Label
    $lblCurrentTimer.Location = New-Object System.Drawing.Point(15, 345)
    $lblCurrentTimer.Size = New-Object System.Drawing.Size(600, 20)
    $lblCurrentTimer.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblCurrentTimer.ForeColor = [System.Drawing.Color]::Yellow
    $lblCurrentTimer.Anchor = 'Bottom, Left'
	
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 200); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Timer
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
        }
        
        # Query kernel timer resolution via P/Invoke NtQueryTimerResolution
        $timerStats = Get-CurrentTimerResolution
        $lblCurrentTimer.Text = "Active Timer: $($timerStats.CurrentMs) ms (Hardware limit: $($timerStats.LimitMs) ms | Default: $($timerStats.DefaultMs) ms)"
    }
    &$refreshData 

    $btnEngage = New-Object System.Windows.Forms.Button; $btnEngage.Text = "Enforce 0.5ms & TSC"; $btnEngage.Location = New-Object System.Drawing.Point(15, 300); $btnEngage.Size = New-Object System.Drawing.Size(180, 35); $btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnEngage.FlatStyle = "Flat"; $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $applyQueue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $applyQueue += $localData[$i] }
        }
        if ($applyQueue.Count -gt 0) {
            Invoke-ApplyTimerTweaks -SelectedItems $applyQueue
            [System.Windows.Forms.MessageBox]::Show("Hardware timers optimized. Reboot required for BCD changes.", "Action Completed")
        }
        &$refreshData
    }.GetNewClosure())

    $btnRevert = New-Object System.Windows.Forms.Button
    $btnRevert.Text = "Restore OS Defaults"
    $btnRevert.Location = New-Object System.Drawing.Point(205, 300)
    $btnRevert.Size = New-Object System.Drawing.Size(160, 35)
    $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 100, 100)
    $btnRevert.FlatStyle = "Flat"
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
        Remove-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue | Out-Null
        
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} disabledynamictick" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformclock" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformtick" -NoNewWindow -Wait
        
        # Restore HPET if it exists and is disabled
        $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
        if ($null -ne $hpet -and $hpet.ConfigManagerErrorCode -eq 22) { 
            Enable-PnpDevice -InstanceId $hpet.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null 
        }
        
        Write-GUI " -> Reverted Timer Subsystem & BCD flags to OS defaults."
        [System.Windows.Forms.MessageBox]::Show("Default OS timer mechanisms and BCD values restored. HPET enabled. Reboot required.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = "Refresh Audit"; $btnRefresh.Location = New-Object System.Drawing.Point(375, 300); $btnRefresh.Size = New-Object System.Drawing.Size(120, 35); $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRefresh.FlatStyle = "Flat"; $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(505, 300); $btnClose.Size = New-Object System.Drawing.Size(120, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList, $lblCurrentTimer, $btnEngage, $btnRevert, $btnRefresh, $btnClose))
    try { [void]$modal.ShowDialog() } finally { $modal.Dispose() }
}

function Show-NVMeModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 360); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 360)

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply PCI bus and NVMe driver changes."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(600, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 160); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_NVMe
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
        }
    }
    &$refreshData 

    $btnEngage = New-Object System.Windows.Forms.Button; $btnEngage.Text = "Disable Power States"; $btnEngage.Location = New-Object System.Drawing.Point(15, 260); $btnEngage.Size = New-Object System.Drawing.Size(180, 35); $btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60); $btnEngage.FlatStyle = "Flat"; $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $applyQueue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $applyQueue += $localData[$i] }
        }
        if ($applyQueue.Count -gt 0) {
            Invoke-ApplyNVMeTweaks -SelectedItems $applyQueue
            [System.Windows.Forms.MessageBox]::Show("NVMe APST and PCIe ASPM disabled.", "Optimization Completed")
        }
        &$refreshData
    }.GetNewClosure())

    $btnRevert = New-Object System.Windows.Forms.Button; $btnRevert.Text = "Restore OS Defaults"; $btnRevert.Location = New-Object System.Drawing.Point(205, 260); $btnRevert.Size = New-Object System.Drawing.Size(160, 35); $btnRevert.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 100, 100); $btnRevert.FlatStyle = "Flat"; $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters" -Name "DisableASPM" -ErrorAction SilentlyContinue | Out-Null
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" -Name "IdlePowerMode" -ErrorAction SilentlyContinue | Out-Null
        
        Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        
        Write-GUI " -> Restored default PCI ASPM, StorNVMe APST, and MMAgent settings."
        [System.Windows.Forms.MessageBox]::Show("Standard PCI/NVMe drivers and Memory Compression restored. Reboot is required to apply bus changes.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnRefresh = New-Object System.Windows.Forms.Button; $btnRefresh.Text = "Refresh Audit"; $btnRefresh.Location = New-Object System.Drawing.Point(375, 260); $btnRefresh.Size = New-Object System.Drawing.Size(120, 35); $btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150); $btnRefresh.FlatStyle = "Flat"; $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-Object System.Windows.Forms.Button; $btnClose.Text = "Close"; $btnClose.Location = New-Object System.Drawing.Point(505, 260); $btnClose.Size = New-Object System.Drawing.Size(115, 35); $btnClose.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60); $btnClose.FlatStyle = "Flat"; $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList, $btnEngage, $btnRevert, $btnRefresh, $btnClose, $lblWarning))
    try { [void]$modal.ShowDialog() } finally { $modal.Dispose() }
}

function New-PreFlightShortcut {
    $appDataFolder = "$env:LOCALAPPDATA\WinUltix"
    if (-not (Test-Path $appDataFolder)) { 
        try { New-Item -Path $appDataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null } 
        catch { [System.Windows.Forms.MessageBox]::Show("Failed to create WinUltix AppData directory.", "Error"); return }
    }
    
    $ps1Path = "$appDataFolder\PreFlight.ps1"
    $topo = Get-CPUTopologyProfile
    $maskInt64 = $topo.Mask.ToInt64()

    # Dynamic GUI bindings based on detected CPU topology
    $affState  = if ($topo.IsSupported) { "`$true" } else { "`$false" }
    $affString = if ($topo.IsSupported) { "Affinity Lasso ($($topo.CoreDesc))" } else { "Affinity Lasso (Unsupported CPU - Disabled)" }
    $affColor  = if ($topo.IsSupported) { "White" } else { "DarkGray" }

    $code = @"
`$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not `$isAdmin) {
    `$argList = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + `$PSCommandPath + '"'
    Start-Process powershell.exe -ArgumentList `$argList -Verb RunAs
    exit
}

Add-Type -AssemblyName System.Windows.Forms
`$frm = New-Object System.Windows.Forms.Form
`$frm.Text = "Pre-Flight Game Mode"
`$frm.Size = New-Object System.Drawing.Size(350, 180)
`$frm.StartPosition = "CenterScreen"
`$frm.FormBorderStyle = "FixedDialog"
`$frm.MaximizeBox = `$false
`$frm.TopMost = `$true
`$frm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
`$frm.ForeColor = [System.Drawing.Color]::White

`$chkAff = New-Object System.Windows.Forms.CheckBox
`$chkAff.Text = "$affString"
`$chkAff.Location = New-Object System.Drawing.Point(20, 15)
`$chkAff.Size = New-Object System.Drawing.Size(300, 25)
`$chkAff.Checked = $affState
`$chkAff.Enabled = $affState
`$chkAff.ForeColor = [System.Drawing.Color]::$affColor

`$chkCPPC = New-Object System.Windows.Forms.CheckBox
`$chkCPPC.Text = "Max CPPC (EPP 0%, Disable C-States)"
`$chkCPPC.Location = New-Object System.Drawing.Point(20, 45)
`$chkCPPC.Size = New-Object System.Drawing.Size(300, 25)
`$chkCPPC.Checked = `$true

`$btnEngage = New-Object System.Windows.Forms.Button
`$btnEngage.Text = "ENGAGE"
`$btnEngage.Location = New-Object System.Drawing.Point(15, 90)
`$btnEngage.Size = New-Object System.Drawing.Size(95, 30)
`$btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
`$btnEngage.FlatStyle = "Flat"
`$btnEngage.DialogResult = "Yes"

`$btnRelease = New-Object System.Windows.Forms.Button
`$btnRelease.Text = "RELEASE"
`$btnRelease.Location = New-Object System.Drawing.Point(120, 90)
`$btnRelease.Size = New-Object System.Drawing.Size(95, 30)
`$btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60)
`$btnRelease.FlatStyle = "Flat"
`$btnRelease.DialogResult = "No"

`$btnCancel = New-Object System.Windows.Forms.Button
`$btnCancel.Text = "Cancel"
`$btnCancel.Location = New-Object System.Drawing.Point(225, 90)
`$btnCancel.Size = New-Object System.Drawing.Size(95, 30)
`$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
`$btnCancel.FlatStyle = "Flat"
`$btnCancel.DialogResult = "Cancel"

`$frm.Controls.AddRange(@(`$chkAff, `$chkCPPC, `$btnEngage, `$btnRelease, `$btnCancel))
`$res = `$frm.ShowDialog()

`$c = 'HKCU:\Software\WinUltix\AffinityLasso'
`$p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
function Get-Pcfg (`$g) {
    `$out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR `$g 2>`$null
    if (-not `$out) { return `$null }
    `$hexLines = @(`$out -match ':\s*(0x[0-9a-fA-F]+)\s*`$')
    if (`$hexLines.Count -ge 1 -and `$hexLines[0] -match '(0x[0-9a-fA-F]+)\s*`$') {
        return [convert]::ToInt32(`$matches[1], 16)
    }
    return `$null
}

if (`$res -eq "Yes") {
    if (`$chkAff.Checked -and (Test-Path `$c)) { 
        (Get-ItemProperty `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
            `$n = `$_.Name -replace '\.exe`$',''
            Get-Process -Name `$n -ErrorAction SilentlyContinue | ForEach-Object { 
                try { `$_.ProcessorAffinity = [System.IntPtr]([int64]$maskInt64); `$_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch {} 
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        if (-not (Test-Path `$p)) { New-Item -Path `$p -Force | Out-Null }
        `$e = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        `$d = Get-Pcfg '4b92d758-5a24-4851-a470-815d78aee119'
        `$pr = Get-Pcfg '7b224883-b3cc-4d79-819f-8374152cbe7c'
        
        if (`$null -ne `$e -and -not (`$e -eq 0 -and `$d -eq 100 -and `$pr -eq 100)) {
            Set-ItemProperty -Path `$p -Name 'EPP' -Value `$e -Type DWord -Force
            Set-ItemProperty -Path `$p -Name 'Demote' -Value `$d -Type DWord -Force
            Set-ItemProperty -Path `$p -Name 'Promote' -Value `$pr -Type DWord -Force
        }
        
        `$tsCmd = "`$bp='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path `$bp){ `$r=Get-ItemProperty `$bp; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
        `$tsAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"`$tsCmd`""
        `$tsTriggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon))
        `$tsPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Action `$tsAction -Trigger `$tsTriggers -Principal `$tsPrincipal -Force | Out-Null

        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setactive SCHEME_CURRENT
    }
} elseif (`$res -eq "No") {
    if (`$chkAff.Checked) { 
        `$lpCount = [Environment]::ProcessorCount
        `$fullMaskVal = if (`$lpCount -ge 64) { -1 } else { ([int64]1 -shl `$lpCount) - 1 }
        `$sys = [System.IntPtr]`$fullMaskVal
        if (Test-Path `$c) { 
            (Get-ItemProperty `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
                `$n = `$_.Name -replace '\.exe`$',''
                Get-Process -Name `$n -ErrorAction SilentlyContinue | ForEach-Object { 
                    try { `$_.ProcessorAffinity = `$sys; `$_.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal } catch {} 
                } 
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        `$e = 50; `$d = 40; `$pr = 60
        if (Test-Path `$p) { 
            `$reg = Get-ItemProperty -Path `$p -ErrorAction SilentlyContinue
            if (`$null -ne `$reg.EPP) { `$e = `$reg.EPP }
            if (`$null -ne `$reg.Demote) { `$d = `$reg.Demote }
            if (`$null -ne `$reg.Promote) { `$pr = `$reg.Promote } 
        }
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$e; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$e
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$d; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$d
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$pr; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$pr; powercfg.exe /setactive SCHEME_CURRENT
        
        Unregister-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Confirm:`$false -ErrorAction SilentlyContinue | Out-Null
    }
}
"@

    try {
        Set-Content -Path $ps1Path -Value $code -Encoding UTF8 -ErrorAction Stop
        $desktop = [Environment]::GetFolderPath("Desktop")
        $WshShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
        $Shortcut = $WshShell.CreateShortcut("$desktop\WinUltix Pre-Flight Mode.lnk")
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""
        $Shortcut.WindowStyle = 7
        $Shortcut.IconLocation = "shell32.dll, 137"
        $Shortcut.Save()
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell)
        
        Write-GUI " -> Generated Pre-Flight shortcut on Desktop ($($topo.Label))."
        [System.Windows.Forms.MessageBox]::Show("Pre-Flight Shortcut generated on Desktop.", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to construct COM object or write file.`n`nError: $($_.Exception.Message)", "Shortcut Generation Failed")
    }
}

function Initialize-Z7UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = "Hardware"
    $tab.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

    $btnAffinity = New-Object System.Windows.Forms.Button
    $btnAffinity.Location = New-Object System.Drawing.Point(15, 20)
    $btnAffinity.Size = New-Object System.Drawing.Size(240, 40)
    $btnAffinity.FlatStyle = "Flat"

    $topo = Get-CPUTopologyProfile

    if ($topo.IsSupported) {
        $btnAffinity.Text = "Affinity Lasso (CPU Core Lock)"
        $btnAffinity.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
        $btnAffinity.ForeColor = [System.Drawing.Color]::White
        $btnAffinity.Add_MouseEnter({ Show-Description "Lock background apps to specific cores ($($topo.CoreDesc)) to free up prime gaming cores." }.GetNewClosure())
        $btnAffinity.Add_MouseLeave({ Restore-Log })
        $btnAffinity.Add_Click({ Show-AffinityModal "Affinity Lasso - $($topo.Label)" "Lock background processes to $($topo.CoreDesc) with BelowNormal priority." }.GetNewClosure())
    } else {
        $btnAffinity.Text = "Affinity Lasso (Unsupported CPU)"
        $btnAffinity.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
        $btnAffinity.ForeColor = [System.Drawing.Color]::DarkGray
        $btnAffinity.Enabled = $false
        # Note: Disabled controls in WinForms do not trigger MouseEnter/MouseLeave events natively.
    }

    $btnCPPC = New-Object System.Windows.Forms.Button
    $btnCPPC.Text = "CPPC P-State Unhider"
    $btnCPPC.Location = New-Object System.Drawing.Point(15, 70)
    $btnCPPC.Size = New-Object System.Drawing.Size(240, 40)
    $btnCPPC.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 150)
    $btnCPPC.ForeColor = [System.Drawing.Color]::White
    $btnCPPC.FlatStyle = "Flat"
    $btnCPPC.Add_MouseEnter({ Show-Description "Unhide and manage advanced AMD/Intel CPPC power states." })
    $btnCPPC.Add_MouseLeave({ Restore-Log })
    $btnCPPC.Add_Click({ Show-CPPCModal "CPPC Management" "Unhide advanced power plan settings (EPP, Demote, Promote)." })

    $btnMSI = New-Object System.Windows.Forms.Button
    $btnMSI.Text = "MSI Interrupt Enforcer"
    $btnMSI.Location = New-Object System.Drawing.Point(15, 120)
    $btnMSI.Size = New-Object System.Drawing.Size(370, 40)
    $btnMSI.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 100, 100)
    $btnMSI.ForeColor = [System.Drawing.Color]::White
    $btnMSI.FlatStyle = "Flat"
    $btnMSI.Add_MouseEnter({ Show-Description "Force Message Signaled Interrupts (MSI) to reduce DPC latency." })
    $btnMSI.Add_MouseLeave({ Restore-Log })
    $btnMSI.Add_Click({ Show-MsiModal "MSI Mode Enforcer" "Force drivers into MSI mode. Reduces latency and CPU overhead." })

    $btnWHEA = New-Object System.Windows.Forms.Button
    $btnWHEA.Text = "WHEA Hardware Error Logger"
    $btnWHEA.Location = New-Object System.Drawing.Point(15, 170)
    $btnWHEA.Size = New-Object System.Drawing.Size(370, 40)
    $btnWHEA.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60)
    $btnWHEA.ForeColor = [System.Drawing.Color]::White
    $btnWHEA.FlatStyle = "Flat"
    $btnWHEA.Add_MouseEnter({ Show-Description "Scan system logs for hardware instability (Curve Optimizer / RAM)." })
    $btnWHEA.Add_MouseLeave({ Restore-Log })
    $btnWHEA.Add_Click({ Show-WHEAModal "WHEA Logger" "Analyze hardware errors to find unstable CPU cores or RAM." })

    $btnPreFlight = New-Object System.Windows.Forms.Button
    $btnPreFlight.Text = "Generate Pre-Flight Shortcut"
    $btnPreFlight.Location = New-Object System.Drawing.Point(265, 20)
    $btnPreFlight.Size = New-Object System.Drawing.Size(120, 90)
    $btnPreFlight.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnPreFlight.ForeColor = [System.Drawing.Color]::White
    $btnPreFlight.FlatStyle = "Flat"
    $btnPreFlight.Add_MouseEnter({ Show-Description "Create a desktop shortcut to instantly apply Affinity and CPPC rules." })
    $btnPreFlight.Add_MouseLeave({ Restore-Log })
    $btnPreFlight.Add_Click({ New-PreFlightShortcut })

    $btnNetwork = New-Object System.Windows.Forms.Button
    $btnNetwork.Text = "Network NDIS & TCP Optimizer"
    $btnNetwork.Location = New-Object System.Drawing.Point(15, 220)
    $btnNetwork.Size = New-Object System.Drawing.Size(370, 40)
    $btnNetwork.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnNetwork.ForeColor = [System.Drawing.Color]::White
    $btnNetwork.FlatStyle = "Flat"
    $btnNetwork.Add_MouseEnter({ Show-Description "Configure low-latency NDIS parameters, TCP properties, and offloads." })
    $btnNetwork.Add_MouseLeave({ Restore-Log })
    $btnNetwork.Add_Click({ Show-NetworkModal "Network Optimizer" "Disable flow control, power saving, interrupt moderation, and enforce TCPNoDelay." })
	
    $btnTimer = New-Object System.Windows.Forms.Button
    $btnTimer.Text = "System Timer & TSC Fix (0.5ms)"
    $btnTimer.Location = New-Object System.Drawing.Point(15, 270)
    $btnTimer.Size = New-Object System.Drawing.Size(370, 40)
    $btnTimer.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 100, 100)
    $btnTimer.ForeColor = [System.Drawing.Color]::White
    $btnTimer.FlatStyle = "Flat"
    $btnTimer.Add_MouseEnter({ Show-Description "Fix Windows 11 API to allow global 0.5ms High Resolution Timers and force CPU TSC." })
    $btnTimer.Add_MouseLeave({ Restore-Log })
    $btnTimer.Add_Click({ Show-TimerModal "Timer Resolution Subsystem" "Enable legacy 0.5ms requests globally and stabilize DPC latency." })

    $btnNVMe = New-Object System.Windows.Forms.Button
    $btnNVMe.Text = "I/O & Memory Latency Optimizer"
    $btnNVMe.Location = New-Object System.Drawing.Point(15, 320)
    $btnNVMe.Size = New-Object System.Drawing.Size(370, 40)
    $btnNVMe.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 150)
    $btnNVMe.ForeColor = [System.Drawing.Color]::White
    $btnNVMe.FlatStyle = "Flat"
    $btnNVMe.Add_MouseEnter({ Show-Description "Disable NVMe APST, PCIe ASPM, and System Memory Compression to reduce CPU overhead and micro-stuttering." })
    $btnNVMe.Add_MouseLeave({ Restore-Log })
    $btnNVMe.Add_Click({ Show-NVMeModal "I/O & Memory Optimizer" "Prevent NVMe and PCIe bus from entering low-power states (D3hot/L1.2) and disable RAM compression." })
    
    $tab.Controls.AddRange(@($btnAffinity, $btnCPPC, $btnMSI, $btnWHEA, $btnPreFlight, $btnNetwork, $btnTimer, $btnNVMe))

    $TabControl.Controls.Add($tab)
}
# <<< END INJECTED MODULE: Z7_Hardware.ps1 <<<


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

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
    try {
        [void]$aboutForm.ShowDialog($global:form)
    } finally {
        $aboutForm.Dispose()
    }
})

$global:form.Controls.AddRange(@($btnClearLog, $btnExportLog, $global:progBar, $btnCredits, $global:descBox, $global:tabControl, $global:infoBox))

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

Update-DNSLabel
try {
    [void]$global:form.ShowDialog()
} finally {
    $global:form.Dispose()
}
