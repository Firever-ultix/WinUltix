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
function Invoke-TelemetryTasksAudit { 
    $rules = @(
        @{ UIDisplayName = "Task: CEIP (Customer Experience Improvement Program)"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Feedback & Diagnostics"; TaskPath = "\Microsoft\Windows\Feedback\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Performance Trace"; TaskPath = "\Microsoft\Windows\PerformanceTrace\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Error Reporting (WER)"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Xbox Live Game Save DataSync"; TaskPath = "\Microsoft\XblGameSave\*"; ExpectedState = "Disabled" }
    )
    
    $results = @()
    foreach ($rule in $rules) {
        # Szukamy aktywnych/gotowych zadań pasujących do ścieżki
        $activeTasks = Get-ScheduledTask | Where-Object { $_.TaskPath -like $rule.TaskPath -and ($_.State -eq 'Ready' -or $_.State -eq 'Running') }
        
        $isDetected = $false
        if ($activeTasks -and $activeTasks.Count -gt 0) {
            $isDetected = $true # Znalazł aktywne = zła wiadomość = DETECTED
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
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

    $smPath = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState\start2.bin"
    if (Test-Path -Path $smPath) {
        $sz = (Get-Item -Path $smPath).Length
        Write-GUI "  [!] Menu layout database found ($([math]::Round($sz / 1KB, 2)) KB)."
        Write-GUI "  -> Action will wipe this database to unpin all items."
    } else {
        Write-GUI "  [OK] Start Menu database is fresh/empty."
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
        @{ UIDisplayName = "Updates: Windows Update Medic Service (wuqisvc)"; Name = "wuqisvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Health Service (whesvc)"; Name = "whesvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4; DefaultStart = 3 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

function Get-ServicesState_Heavy {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (wuqisvc)"; Name = "wuqisvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Health Service (whesvc)"; Name = "whesvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 3 }
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
        @{ UIDisplayName = "Remote: Remote Registry (RemoteRegistry)"; Name = "RemoteRegistry"; ExpectedStart = 4; DefaultStart = 4 }
        @{ UIDisplayName = "Biometrics: Windows Biometric Service (WbioSrvc)"; Name = "WbioSrvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Data Service (SensorDataService)"; Name = "SensorDataService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Service (SensorService)"; Name = "SensorService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Sensors: Sensor Monitoring Service (SensrSvc)"; Name = "SensrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Phone Service (PhoneSvc)"; Name = "PhoneSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: Windows Mobile Hotspot Service (icssvc)"; Name = "icssvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: WWAN AutoConfig (WwanSvc)"; Name = "WwanSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Search: Windows Search - Disables file indexing (WSearch)"; Name = "WSearch"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Networking: Offline Files (CscService)"; Name = "CscService"; ExpectedStart = 4; DefaultStart = 4 }
        @{ UIDisplayName = "Network: Internet Connection Sharing (SharedAccess)"; Name = "SharedAccess"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting (wermgr)"; Name = "wermgr"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Logitech: Lamp Array Service RGB (logi_lamparray_service)"; Name = "logi_lamparray_service"; ExpectedStart = 4; DefaultStart = 3 }
        
        @{ UIDisplayName = "Xbox: Xbox Live Auth Manager [Manual] (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 3; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Game Save [Manual] (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 3; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Networking Service [Manual] (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 3; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Accessory Management [Manual] (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 3; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server [Manual] (FrameServer)"; Name = "FrameServer"; ExpectedStart = 3; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor [Manual] (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 3; DefaultStart = 3 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

function Invoke-GhostServicesAudit {
    Write-GUI "--- AUDIT: Ghost Services & Drivers ---"
    $ghosts = @()
    $services = Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services"
    
    foreach ($svc in $services) {
        $imagePath = (Get-ItemProperty -Path $svc.PSPath -Name "ImagePath" -ErrorAction SilentlyContinue).ImagePath
        if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
        
        # SAFEGUARD 1: Skip if the service/driver is actively running in OS
        $activeState = Get-Service -Name $svc.PSChildName -ErrorAction SilentlyContinue
        if ($null -ne $activeState -and $activeState.Status -eq 'Running') { continue }
        
        # Strip kernel prefixes and expand environment variables
        $rawPath = $imagePath -replace '(?i)^\\SystemRoot\\', "$env:windir\"
        $rawPath = $rawPath -replace '^\\+?\?\?\\+', ''
        $rawPath = [System.Environment]::ExpandEnvironmentVariables($rawPath)
        
        # SAFEGUARD 2: Advanced path parsing for unquoted paths with spaces
        if ($rawPath -match '^"([^"]+)"') { 
            # Handled quoted paths
            $rawPath = $matches[1] 
        } elseif ($rawPath -match '(?i)^(.+\.(?:exe|sys|dll))(?:$|\s)') {
            # Handled unquoted paths containing spaces, ending with valid extension
            $rawPath = $matches[1]
        } else { 
            # Fallback for Edge-cases
            $rawPath = $rawPath.Split(' ')[0] 
        }
        
        # Root relative paths mapped to system32
        if (-not [System.IO.Path]::IsPathRooted($rawPath)) {
            $rawPath = Join-Path -Path $env:windir -ChildPath $rawPath
        }
        
        # Verify binary presence
        if (-not (Test-Path -Path $rawPath -PathType Leaf)) {
            $ghosts += [PSCustomObject]@{
                Name          = $svc.PSChildName
                Path          = $rawPath
                UIDisplayName = "Ghost: $($svc.PSChildName) (Missing binary)"
                IsDetected    = $true
            }
        }
    }
    
    if ($ghosts.Count -eq 0) { Write-GUI "  [OK] No orphaned services detected." }
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

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        
        $taskRule = $item.ActionData
        try {
            $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -like $taskRule.TaskPath }
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
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        $svc = $item.ActionData
        
        $targetValue = if ($Operation -eq 'Apply') { $svc.ExpectedStart } else { $svc.DefaultStart }

        if ($null -eq $targetValue -and $Operation -eq 'Revert') {
            Write-GUI "    [!] Missing 'DefaultStart' property. Skipping."
            continue
        }

        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)" -Name "Start" -Value $targetValue -Type DWord -ErrorAction Stop
            
        } catch { Write-GUI "    [!] Failed to modify service: $($svc.Name)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $ProfileName services enforcement completed ($Operation)."
}

function Clear-StartMenu { 
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -ErrorAction SilentlyContinue
    
    $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $pkgDir) {
        $startStatePath = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
        if (Test-Path "$startStatePath\start.bin") { Remove-Item -Path "$startStatePath\start.bin" -Force -ErrorAction SilentlyContinue }
        if (Test-Path "$startStatePath\start2.bin") { Remove-Item -Path "$startStatePath\start2.bin" -Force -ErrorAction SilentlyContinue }
    }
    
    Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
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
        $auditData = Invoke-TelemetryTasksAudit
        $modalOutput = Show-ActionModal -Title "WinUltix - Scheduled Tasks Lockdown" -Description "Select tasks to modify (Apply = Disable, Revert = Enable)." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput) { 
            Invoke-ApplyTasks -SelectedItems $modalOutput.Items -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudTelemetry = New-Object System.Windows.Forms.Button
    $btnAudTelemetry.Text = "?"
    $btnAudTelemetry.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudTelemetry.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudTelemetry.ForeColor = [System.Drawing.Color]::White
    $btnAudTelemetry.FlatStyle = "Flat"
    $btnAudTelemetry.Add_MouseEnter({ Show-Description "AUDIT: Verifies if telemetry tasks are active in the scheduler." })
    $btnAudTelemetry.Add_Click({ 
        Write-GUI "--- AUDIT: Scheduled Tasks ---"
        $state = Invoke-TelemetryTasksAudit
        $detected = $state | Where-Object { $_.IsDetected }
        if ($detected.Count -gt 0) { 
            foreach ($d in $detected) { Write-GUI "  [!] Active: $($d.UIDisplayName)" } 
        } else { 
            Write-GUI "  [OK] All monitored tasks disabled." 
        }
        Write-GUI "" 
    })

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
        $msgText = "This action will permanently wipe your Start Menu pins and layout database.`n`nExplorer and StartMenuExperienceHost processes will be forcefully restarted.`n`nDo you want to proceed?"
        $msgResult = [System.Windows.Forms.MessageBox]::Show($msgText, "WinUltix - Destructive Action", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        
        if ($msgResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-GUI " -> Resetting Start Menu layout..."
            Clear-StartMenu
            Write-GUI "    [OK] Start Menu layout database wiped successfully."
            Write-GUI ""
        } else {
            Write-GUI " -> Start Menu reset aborted by user."
            Write-GUI ""
        }
    })

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
    $btnPower.Text = "Optimize Power & Display"
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
        $auditData = Invoke-GhostServicesAudit
        $modalOutput = Show-ActionModal -Title "WinUltix - Ghost Services Cleanup" -Description "Select orphaned items to remove." -AuditResults $auditData
        
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) { 
            Remove-GhostServices -SelectedItems $modalOutput.Items
            Write-GUI "" 
        } 
    })

    $btnAudGhostSvc = New-Object System.Windows.Forms.Button
    $btnAudGhostSvc.Text = "?"
    $btnAudGhostSvc.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudGhostSvc.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGhostSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudGhostSvc.ForeColor = [System.Drawing.Color]::White
    $btnAudGhostSvc.FlatStyle = "Flat"
    $btnAudGhostSvc.Add_MouseEnter({ Show-Description "AUDIT: Detects orphaned service/driver registrations." })
    $btnAudGhostSvc.Add_Click({ 
        $state = Invoke-GhostServicesAudit
        if ($state.Count -gt 0) { foreach ($d in $state) { Write-GUI "  [!] Found: $($d.UIDisplayName)" } }
        Write-GUI "" 
    })
	
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