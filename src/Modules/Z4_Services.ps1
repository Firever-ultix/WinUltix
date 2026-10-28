# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z4_SERVICES.PS1 - SERVICES & SYSTEM MODULE (v3.0.0)
# Z4_Services: Manages services (Set-ProtectedServiceStart with TrustedInstaller DACL escalation), Task Scheduler lockdown, locale-independent Power Plan audits, deterministic Start Menu native compilation (COM AppActivator), Ghost Service sweeping, and Light/Heavy service profiles.
# ==========================================

# ------------------------------------------
# Z4: AUDIT HELPERS
# ------------------------------------------

function Invoke-ServicesAudit {
    param([array]$Rules)
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $Rules.Count
    $current = 0

    foreach ($rule in $Rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }

        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        
        $isDetected = $true
        if ($null -eq $currentStart -or $currentStart -eq $rule.ExpectedStart) {
            $isDetected = $false
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

# ------------------------------------------
# Z4: SERVICES & TASKS AUDITS (RUNSPACE-SAFE WORKERS)
# ------------------------------------------
function Get-TelemetryTasksState { 
    if ($null -ne $UltixSync) { $UltixSync.Progress = 15 }

    $rules = @(
        @{ UIDisplayName = "Task: CEIP (Customer Experience Improvement Program)"; TaskPath = "\Microsoft\Windows\Customer Experience Improvement Program\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Feedback & Diagnostics"; TaskPath = "\Microsoft\Windows\Feedback\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Performance Trace"; TaskPath = "\Microsoft\Windows\PerformanceTrace\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Windows Error Reporting (WER)"; TaskPath = "\Microsoft\Windows\Windows Error Reporting\*"; ExpectedState = "Disabled" }
        @{ UIDisplayName = "Task: Xbox Live Game Save DataSync"; TaskPath = "\Microsoft\XblGameSave\*"; ExpectedState = "Disabled" }
    )
    
    # Single COM/CIM query instead of querying Get-ScheduledTask 5 times in a loop
    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    if ($null -ne $UltixSync) { $UltixSync.Progress = 70 }
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($rule in $rules) {
        $activeTasks = @($allTasks | Where-Object { $_.TaskPath -like $rule.TaskPath -and ($_.State -eq 'Ready' -or $_.State -eq 'Running') })
        
        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = ($activeTasks.Count -gt 0)
            ActionData    = $rule
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results)
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

function Get-ServicesState_Light {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (WaaSMedicSvc)"; Name = "WaaSMedicSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting Service (WerSvc)"; Name = "WerSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $rules.Count
    $current = 0

    foreach ($rule in $rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        $isDetected   = ($null -ne $currentStart -and $currentStart -ne $rule.ExpectedStart)

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
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

        # Diagnostics & SRUM Disk I/O Elimination
        @{ UIDisplayName = "Diagnostics: Diagnostic Policy Service - Stops SRUM disk logging (DPS)"; Name = "DPS"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Diagnostics: Diagnostic Service Host (WdiServiceHost)"; Name = "WdiServiceHost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Diagnostics: Diagnostic System Host (WdiSystemHost)"; Name = "WdiSystemHost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Telemetry: Windows Insider Service (wisvc)"; Name = "wisvc"; ExpectedStart = 4; DefaultStart = 3 }

        # File System & Backup Overhead
        @{ UIDisplayName = "FileSystem: Distributed Link Tracking Client (TrkWks)"; Name = "TrkWks"; ExpectedStart = 4; DefaultStart = 2 }
        @{ UIDisplayName = "Backup: Windows File History Service (fhsvc)"; Name = "fhsvc"; ExpectedStart = 4; DefaultStart = 3 }

        # Mobile, NFC & Time Zone Bloat
        @{ UIDisplayName = "Bloat: Microsoft Wallet Service (WalletService)"; Name = "WalletService"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Payments and NFC/SE Manager (SEMgrSvc)"; Name = "SEMgrSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Mobile: Cellular Time Synchronization (autotimesvc)"; Name = "autotimesvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Location: Auto Time Zone Updater (tzautoupdate)"; Name = "tzautoupdate"; ExpectedStart = 4; DefaultStart = 4 }

        # Legacy Network Discovery (UPnP / SSDP / NetBIOS)
        @{ UIDisplayName = "Network: SSDP Multicast Discovery (SSDPSRV)"; Name = "SSDPSRV"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: UPnP Device Host (upnphost)"; Name = "upnphost"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Network: TCP/IP NetBIOS Helper (lmhosts)"; Name = "lmhosts"; ExpectedStart = 4; DefaultStart = 3 }
        
        @{ UIDisplayName = "Xbox: Xbox Live Auth Manager (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Game Save (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Networking Service (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Accessory Management (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server (FrameServer)"; Name = "FrameServer"; ExpectedStart = 4; DefaultStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 4; DefaultStart = 3 }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $rules.Count
    $current = 0

    foreach ($rule in $rules) {
        $current++
        if ($null -ne $UltixSync -and $total -gt 0) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        $isDetected   = ($null -ne $currentStart -and $currentStart -ne $rule.ExpectedStart)

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

function Get-GhostServicesState {
    $ghosts = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $runningNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.Name) }
    Get-CimInstance -ClassName Win32_SystemDriver -Filter "State = 'Running'" -Property Name -ErrorAction SilentlyContinue | ForEach-Object { [void]$runningNames.Add($_.Name) }

    $services = @(Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction SilentlyContinue)
    $total = $services.Count
    $current = 0

    foreach ($svc in $services) {
        $current++
        if ($null -ne $UltixSync -and ($current % 15 -eq 0 -or $current -eq $total)) {
            $UltixSync.Progress = [int](($current / $total) * 100)
        }

        $svcName = $svc.PSChildName
        if ($runningNames.Contains($svcName)) { continue }

        $props = Get-ItemProperty -Path $svc.PSPath -Name "ImagePath", "Type" -ErrorAction SilentlyContinue
        if ($null -eq $props) { continue }

        # Skip Per-User service templates and dynamic session instances (SERVICE_USER_SERVICE bit 0x40)
        if ($null -ne $props.Type -and (($props.Type -band 0x40) -ne 0)) { continue }

        $imagePath = $props.ImagePath
        if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
        if ($imagePath -match '(?i)^\\(?:Driver|FileSystem)\\') { continue }
        
        # Normalize kernel and relative root prefixes (\SystemRoot\, SystemRoot\, \System32\, system32\)
        $rawPath = $imagePath.Trim()
        $rawPath = $rawPath -replace '^\\+?\?\?\\+', ''
        $rawPath = $rawPath -replace '(?i)^\\?SystemRoot\\', "$env:windir\"
        $rawPath = $rawPath -replace '(?i)^\\?System32\\', "$env:windir\System32\"
        $rawPath = $rawPath -replace '(?i)^\\?SysWOW64\\', "$env:windir\SysWOW64\"
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
            
            if (Test-Path -LiteralPath $candidateWinDir -PathType Leaf) { $rawPath = $candidateWinDir }
            elseif (Test-Path -LiteralPath $candidateSys32 -PathType Leaf) { $rawPath = $candidateSys32 }
            elseif (Test-Path -LiteralPath $candidateDrv -PathType Leaf) { $rawPath = $candidateDrv }
            else { $rawPath = $candidateWinDir }
        }
        
        if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            $ghosts.Add([PSCustomObject]@{
                Name          = $svcName
                Path          = $rawPath
                UIDisplayName = "Ghost: $svcName (Missing: $rawPath)"
                IsDetected    = $true
            })
        }
    }
    return $ghosts
}

# ------------------------------------------
# Z4: SERVICES & SYSTEM ENGINE
# ------------------------------------------

function Get-PowerDisplayState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 1. System Hibernation (hiberfil.sys)
    $hiberVal = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Power: Disable Hibernation & Purge hiberfil.sys"
        IsDetected    = ($null -eq $hiberVal -or $hiberVal -ne 0)
        ActionData    = @{ Type = "Hiber" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }

    # 2. System Standby / Sleep Timeout (SUB_SLEEP -> STANDBYIDLE)
    $standbySec = Get-UltixPowerAcIndex -SubGroupGuid "238c9fa8-0aad-41ed-83f4-97be242c8f20" -SettingGuid "29f6c1db-86da-48c5-9fdb-f2b67b1f44da" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Power: Disable System Sleep / Standby Timeout (Current AC: $(if ($null -ne $standbySec) { "$standbySec s" } else { 'N/A' }))"
        IsDetected    = ($null -eq $standbySec -or $standbySec -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "238c9fa8-0aad-41ed-83f4-97be242c8f20"; Guid = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"; OptAC = 0; OptDC = 0; DefAC = 1800; DefDC = 900 }
    })

    # 3. Display Turn-Off Timeout (SUB_VIDEO -> VIDEOIDLE >= 3600s or 0)
    $videoSec = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Display: Set Monitor Turn-Off Timeout to 60 Min (Current AC: $(if ($null -ne $videoSec) { "$([math]::Round($videoSec / 60)) min" } else { 'N/A' }))"
        IsDetected    = ($null -eq $videoSec -or ($videoSec -ne 0 -and $videoSec -lt 3600))
        ActionData    = @{ Type = "PowerCfg"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"; OptAC = 3600; OptDC = 3600; DefAC = 900; DefDC = 300 }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 50 }

    # 4. Hard Disk / SATA AHCI Spin-Down Timeout (SUB_DISK -> DISKIDLE = 0)
    $diskSec = Get-UltixPowerAcIndex -SubGroupGuid "0012ee47-9041-4b5d-9b77-535fba8b1442" -SettingGuid "6738e2c4-e8a5-4a42-b16a-e040e769756e" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Storage: Disable HDD / SATA Controller Spin-Down (Current AC: $(if ($null -ne $diskSec) { "$diskSec s" } else { 'N/A' }))"
        IsDetected    = ($null -eq $diskSec -or $diskSec -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "0012ee47-9041-4b5d-9b77-535fba8b1442"; Guid = "6738e2c4-e8a5-4a42-b16a-e040e769756e"; OptAC = 0; OptDC = 0; DefAC = 1200; DefDC = 600 }
    })

    # 5. USB Selective Suspend (SUB_USB -> USBSELECTIVESUSPEND = 0)
    $usbVal = Get-UltixPowerAcIndex -SubGroupGuid "2a737441-1930-4402-8d77-b2bebba308a3" -SettingGuid "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" -IncludeHidden
    $usbLabel = if ($usbVal -eq 0) { "Disabled" } elseif ($usbVal -eq 1) { "Enabled" } else { "N/A" }
    $results.Add([PSCustomObject]@{
        UIDisplayName = "USB: Disable USB Selective Suspend - Protects DACs/VR/Dongles (Current: $usbLabel)"
        IsDetected    = ($null -eq $usbVal -or $usbVal -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "2a737441-1930-4402-8d77-b2bebba308a3"; Guid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 1 }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }

    # 6. Power Plan PCIe Link State Power Management (SUB_PCIEXPRESS -> ASPM = 0)
    $pcieVal = Get-UltixPowerAcIndex -SubGroupGuid "501a4d13-42af-4429-9fd1-a8218c268e20" -SettingGuid "ee12f906-d277-404b-b6da-e5fa1a576df5" -IncludeHidden
    $pcieLabel = switch ($pcieVal) { 0 { "Off" } 1 { "Moderate" } 2 { "Max Saving" } default { "N/A" } }
    $results.Add([PSCustomObject]@{
        UIDisplayName = "PCIe: Disable Plan Link State Power Management (Current AC: $pcieLabel)"
        IsDetected    = ($null -eq $pcieVal -or $pcieVal -ne 0)
        ActionData    = @{ Type = "PowerCfg"; Sub = "501a4d13-42af-4429-9fd1-a8218c268e20"; Guid = "ee12f906-d277-404b-b6da-e5fa1a576df5"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 2 }
    })

    # 7. Processor Minimum State on AC (SUB_PROCESSOR -> PROCTHROTTLEMIN = 100%)
    $minCpu = Get-UltixPowerAcIndex -SubGroupGuid "54533251-82be-4824-96c1-47b60b740d00" -SettingGuid "893dee8e-2bef-41e0-89c6-b55d0929964c" -IncludeHidden
    $results.Add([PSCustomObject]@{
        UIDisplayName = "CPU: Lock Minimum Processor State to 100% on AC (Current AC: $(if ($null -ne $minCpu) { "$minCpu%" } else { 'N/A' }))"
        IsDetected    = ($null -eq $minCpu -or $minCpu -lt 100)
        ActionData    = @{ Type = "PowerCfg"; Sub = "54533251-82be-4824-96c1-47b60b740d00"; Guid = "893dee8e-2bef-41e0-89c6-b55d0929964c"; OptAC = 100; OptDC = 5; DefAC = 5; DefDC = 5 }
    })

    # 8. Display Content Adaptive Brightness Control (CABC / Adaptive Dimming = 0)
    $cabcVal = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "aded5e82-b909-4619-9949-f5d71dac0bcb" -IncludeHidden
    $cabcReg = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "DisableCABC" -ErrorAction SilentlyContinue).DisableCABC
    $isCabcOpt = (($null -eq $cabcVal -or $cabcVal -eq 0) -and $cabcReg -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Display: Disable Content Adaptive Brightness (CABC / OLED Auto-Dimming)"
        IsDetected    = (-not $isCabcOpt)
        ActionData    = @{ Type = "CABC"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "aded5e82-b909-4619-9949-f5d71dac0bcb" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results)
}

function Invoke-ApplyPowerDisplay {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No power/display items selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)
        $total   = $Items.Count
        $current = 0
        $verb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 90)
                $UltixSync.Logs.Enqueue(" -> $($verb): $($item.UIDisplayName)")
            }

            $d = $item.ActionData
            try {
                if ($d.Type -eq "Hiber") {
                    if ($Op -eq 'Apply') {
                        powercfg.exe /hibernate off 2>$null
                    } else {
                        powercfg.exe /hibernate on 2>$null
                    }
                } elseif ($d.Type -eq "PowerCfg") {
                    $acVal = if ($Op -eq 'Apply') { $d.OptAC } else { $d.DefAC }
                    $dcVal = if ($Op -eq 'Apply') { $d.OptDC } else { $d.DefDC }
                    powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $acVal 2>$null
                    powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $dcVal 2>$null
                } elseif ($d.Type -eq "CABC") {
                    $gfxKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
                    if ($Op -eq 'Apply') {
                        powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid 0 2>$null
                        powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid 0 2>$null
                        Set-ItemProperty -Path $gfxKey -Name "DisableCABC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -Path $gfxKey -Name "DisableCABC" -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed on $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }

        powercfg.exe /setactive SCHEME_CURRENT 2>$null
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Power & Display subsystem configuration completed ($Operation).`n"
    }.GetNewClosure()
}
function Invoke-ApplyTasks { 
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No tasks selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)
        
        $total = $Items.Count
        $current = 0
        $actionVerb = if ($Op -eq 'Apply') { "Disabling" } else { "Enabling" }
        $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)")
            }
            
            $taskRule = $item.ActionData
            try {
                $tasks = @($allTasks | Where-Object { $_.TaskPath -like $taskRule.TaskPath })
                foreach ($task in $tasks) { 
                    if ($Op -eq 'Apply') {
                        Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                    } else {
                        Enable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify task path: $($taskRule.TaskPath)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Telemetry tasks lockdown completed ($Operation).`n"
    }.GetNewClosure()
}

function Invoke-ApplyServices {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$ProfileName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No services selected."; return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $ProfileName, $Operation) -ScriptBlock {
        param([array]$Items, [string]$ProfName, [string]$Op)

        $total = $Items.Count
        $current = 0
        $actionVerb = if ($Op -eq 'Apply') { "Configuring" } else { "Reverting" }

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
            }

            $svc = $item.ActionData
            $svcRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)"

            if (-not (Test-Path -Path $svcRegPath)) {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Skipping absent service: $($svc.Name)") }
                continue
            }

            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)") }
            $targetValue = if ($Op -eq 'Apply') { $svc.ExpectedStart } else { $svc.DefaultStart }

            if ($null -eq $targetValue -and $Op -eq 'Revert') {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Missing 'DefaultStart' property. Skipping.") }
                continue
            }

            try {
                if ($Op -eq 'Apply') {
                    Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                }
                # Uses Set-ProtectedServiceStart pre-hydrated by Core_Helpers InitialSessionState
                Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue $targetValue
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify service $($svc.Name): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> $ProfileName services enforcement completed ($Operation).`n"
    }.GetNewClosure()
}

function Clear-StartMenu {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Initializing deterministic Start Menu reset (Pinning: Edge, Settings, Explorer)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($null -eq $pkgDir) {
            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] StartMenuExperienceHost package directory not found. Aborting.") }
            return
        }

        $startStatePath   = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
        $provGuid         = "B5292708-1619-419B-9923-E5D9F3925E71"
        $enrollmentPath   = "HKLM:\SOFTWARE\Microsoft\Enrollments\$provGuid"
        $providerPath     = "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid\default\Device\Start"
        $policyDevicePath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        $policyLegacyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\device\Start"
        $policyUserPath   = "HKCU:\Software\Microsoft\PolicyManager\current\user\Start"

        # Minimal 3-icon layout: Microsoft Edge, Windows Settings, File Explorer
        $cleanPinsJson = '{"pinnedList":[{"desktopAppId":"MSEdge"},{"packagedAppId":"windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"},{"desktopAppId":"Microsoft.Windows.Explorer"}]}'

        $createdEnrollment = $false

        try {
            # Stage 1: ContentDeliveryManager lockdown
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 15
                $UltixSync.Logs.Enqueue(" -> [1/7] Disabling ContentDeliveryManager silent tile injection...")
            }
            $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (Test-Path $cdmPath) {
                foreach ($cdmName in @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "SubscribedContentEnabled")) {
                    Set-ItemProperty -Path $cdmPath -Name $cdmName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path "$cdmPath\SuggestedApps") {
                    Remove-Item -Path "$cdmPath\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            # Stage 2: Temporary MDM Provider Registration
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 30
                $UltixSync.Logs.Enqueue(" -> [2/7] Injecting temporary MDM PolicyManager provider context...")
            }
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

            # Stage 3: Purge CloudStore caches
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 45
                $UltixSync.Logs.Enqueue(" -> [3/7] Purging CloudStore tile grid and Start registry caches...")
            }
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

            # Stage 4: Stop shell processes and wipe start*.bin
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 60
                $UltixSync.Logs.Enqueue(" -> [4/7] Recycling Explorer & wiping locked start2.bin database...")
            }
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

            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
                Start-Sleep -Milliseconds 800
            }

            # Stage 5: Trigger native compilation via Core_Helpers [WinUltix.AppActivator] COM interop
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 75
                $UltixSync.Logs.Enqueue(" -> [5/7] Invoking COM IApplicationActivationManager to compile clean start2.bin...")
            }
            try {
                $appActivator = New-Object WinUltix.AppActivator
                [uint32]$activatedPid = 0
                [void]$appActivator.ActivateApplication("Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App", $null, 0, [ref]$activatedPid)
                [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($appActivator)
            } catch {}

            $compiledBinPath = Join-Path $startStatePath "start2.bin"
            $elapsed = 0
            while ($elapsed -lt 4500) {
                Start-Sleep -Milliseconds 250
                $elapsed += 250
                if (Test-Path -LiteralPath $compiledBinPath) {
                    $fileInfo = Get-Item -LiteralPath $compiledBinPath -Force -ErrorAction SilentlyContinue
                    if ($null -ne $fileInfo -and $fileInfo.Length -gt 1024) {
                        Start-Sleep -Milliseconds 600
                        break
                    }
                }
            }

            if (Test-Path -LiteralPath $compiledBinPath) {
                $newBinSize = (Get-Item -LiteralPath $compiledBinPath -Force).Length
                if (-not (Test-Path "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Value $newBinSize -Type DWord -Force
            }

            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [OK] Native start2.bin compiled (Pinned: Edge, Settings, File Explorer).")
            }
        } catch {
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [!] Error during Start Menu native compilation: $($_.Exception.Message)")
            }
        } finally {
            # Stage 6: Deterministic MDM cleanup so pins remain unlocked
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 90
                $UltixSync.Logs.Enqueue(" -> [6/7] Stripping temporary MDM PolicyManager locks...")
            }
            foreach ($polPath in @($policyDevicePath, $policyLegacyPath, $policyUserPath)) {
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

        # Stage 7: Default User provisioning
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [7/7] Provisioning Default User profile LayoutModification.json...")
        }
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
        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue("    [OK] Default User LayoutModification.json provisioned.")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
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
        Update-Progress ([int](($current / $total) * 100))
        
        Write-GUI " -> Removing: $($item.Name)"
        # SCM deletion might fail if driver is loaded (unlikely for ghosts) or locked. Registry brute-force is cleaner here.
        Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($item.Name)" -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Update-Progress 0
    Write-GUI " -> Ghost services purged from system registry.`n"
}

# ------------------------------------------
# Z4: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z4UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Services"
    $tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. Telemetry Scheduled Tasks
    $rowTelemetry = New-UltixActionRow -Parent $tabServices -Y 20 `
        -Text "Disable Telemetry Tasks (Scheduler)" `
        -Description "Paralyzes the Task Scheduler. Disables analytics, error reporting, Windows AI, and feedback." `
        -AuditDescription "AUDIT: Verifies if telemetry tasks are active in the scheduler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ModalTitle "WinUltix - Scheduled Tasks Lockdown" -ModalDescription "Select tasks to modify (Apply = Disable, Revert = Enable)." -ExecutorFunction "Invoke-ApplyTasks" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Active"
        }.GetNewClosure())

    # 2. Start Menu Reset
    $rowStartMenu = New-UltixActionRow -Parent $tabServices -Y 70 `
        -Text "Reset Start Menu Layout (Unpin All)" `
        -Description "Wipes the internal Start Menu database (start2.bin) and removes MDM locks." `
        -AuditDescription "AUDIT: Scans the size of the current Start Menu layout database." `
        -OnClick ({
            $msgText = "This action will permanently wipe your Start Menu pins and layout database.`n`nStartMenuExperienceHost will be restarted in the background (System Tray remains intact).`n`nDo you want to proceed?"
            $msgResult = [System.Windows.Forms.MessageBox]::Show($msgText, "WinUltix - Destructive Action", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($msgResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                Clear-StartMenu -ControlsToDisable $allTabButtons.ToArray()
            } else {
                Write-GUI " -> Start Menu reset aborted by user.`n"
            }
        }.GetNewClosure()) `
        -OnAudit ({ Invoke-StartMenuAudit; Write-GUI "" })

    # 3. Power & Display
    $rowPower = New-UltixActionRow -Parent $tabServices -Y 120 `
        -Text "Optimize Power and Display" `
        -Description "Interactive Power & Display tuner: Hibernation, Sleep/Monitor timeouts, SATA spin-down, USB Selective Suspend, PCIe ASPM, and OLED/CABC dimming." `
        -AuditDescription "AUDIT: Verifies active Power Plan timeouts, USB Selective Suspend, PCIe ASPM, and Hibernation state." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ModalTitle "WinUltix - Power & Display Optimizer" -ModalDescription "Select power and display parameters to enforce or revert to Windows defaults." -ExecutorFunction "Invoke-ApplyPowerDisplay" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unoptimized"
        }.GetNewClosure())

    # 4. Ghost Services & Drivers
    $rowGhostSvc = New-UltixActionRow -Parent $tabServices -Y 170 `
        -Text "Cleanup Ghost Services" `
        -Description "Scans registry for services/drivers pointing to non-existent binaries and removes them." `
        -AuditDescription "AUDIT: Detects orphaned service/driver registrations." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ModalTitle "WinUltix - Ghost Services Cleanup" -ModalDescription "Select orphaned items to remove." -ExecutorFunction "Remove-GhostServices" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Found"
        }.GetNewClosure())

    # 5. Office Services Profile (Light)
    $rowSvcLight = New-UltixActionRow -Parent $tabServices -Y 270 `
        -Text "Background Services: OFFICE PROFILE" `
        -MainRGB @(60, 100, 150) `
        -Description "OFFICE PROFILE: Kills telemetry and tracking, leaving print and network services intact." `
        -AuditDescription "AUDIT: Verifies standard telemetry and background bloat services." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ModalTitle "WinUltix - Office Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Office Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Disable"
        }.GetNewClosure())

    # 6. Gaming Services Profile (Heavy)
    $rowSvcHeavy = New-UltixActionRow -Parent $tabServices -Y 320 `
        -Text "Background Services: GAMING PROFILE" `
        -MainRGB @(150, 60, 60) `
        -Description "GAMING PROFILE: Disables almost everything in the background, including print spooler and file indexing." `
        -AuditDescription "AUDIT: Verifies heavy background services including indexer and print spooler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ModalTitle "WinUltix - Gaming Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Gaming Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Configure"
        }.GetNewClosure())

    foreach ($row in @($rowTelemetry, $rowStartMenu, $rowPower, $rowGhostSvc, $rowSvcLight, $rowSvcHeavy)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabServices)
}