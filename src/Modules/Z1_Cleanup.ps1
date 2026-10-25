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