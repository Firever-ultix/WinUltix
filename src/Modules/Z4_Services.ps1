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