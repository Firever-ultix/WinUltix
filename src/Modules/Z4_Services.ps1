# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z4_SERVICES.PS1 - SERVICES & SYSTEM MODULE (v3.1.0)
# Z4_Services: Symmetrically revertible Office (Light) and Gaming (Heavy) service profiles, Telemetry Scheduled Tasks lockdown, and 3 interactive managers (System Services, Scheduled Tasks, and Deep Startup Manager).
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
        @{ UIDisplayName = "Location: Auto Time Zone Updater (tzautoupdate)"; Name = "tzautoupdate"; ExpectedStart = 4; DefaultStart = 3 }

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

# ------------------------------------------
# Z4: SERVICES & TASKS ENGINE
# ------------------------------------------
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
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Telemetry tasks lockdown completed ($Operation).`n"
    }.GetNewClosure())
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
                Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue $targetValue
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify service $($svc.Name): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> $ProfileName services enforcement completed ($Operation).`n"
    }.GetNewClosure())
}

# ------------------------------------------
# Z4: INTERACTIVE SERVICES, TASKS & STARTUP MANAGERS (MOVED FROM Z5)
# ------------------------------------------
function Show-ServicesGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Generating complete system services table (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        # Critical kernel/SCM/RPC services protected from modification
        $criticalServices = "^(RpcSs|DcomLaunch|RpcEptMapper|LSM|SamSs|PlugPlay|EventLog|BFE|mpssvc|nsi|ProfSvc|gpsvc|CryptSvc|TrustedInstaller|WinDefend|WdNisSvc|SecurityHealthService|Dhcp|Dnscache|Winmgmt|Schedule|UserManager|CoreMessagingRegistrar|SystemEventsBroker|Power|BrokerInfrastructure)$"
        
        $svcs = @(Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            $isCrit = ($_.Name -match $criticalServices)
            $startDisp = if ($isCrit) { "$($_.StartType) [CRITICAL - LOCKED]" } else { [string]$_.StartType }
            [PSCustomObject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                Status      = [string]$_.Status
                StartType   = $startDisp
                IsLocked    = $isCrit
            }
        } | Sort-Object Status, Name)
        return $svcs
    } -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$svcs = @($output | Where-Object { $null -ne $_ })

        $cols = @(
            @{ Header = "Service Name"; Property = "Name";        Width = 200 }
            @{ Header = "Status";       Property = "Status";      Width = 95  }
            @{ Header = "Start Type";   Property = "StartType";   Width = 175 }
            @{ Header = "Display Name"; Property = "DisplayName"; Width = 375 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - System Services Manager" `
            -Description "Select services to HARD DISABLE or restore to Manual. Critical OS/RPC/Defender services (Red) are visible for inspection but locked against modification." `
            -Data $svcs -Columns $cols -PrimaryButtonText "Stop & Disable Selected" `
            -SecondaryButtonText "Restore to Manual (Demand)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Service modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0
            foreach ($svc in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                if ($svc.IsLocked) { continue }

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Disabling service: $($svc.Name) ($($svc.DisplayName))")
                    try {
                        Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 4
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) stopped and locked to Disabled (Start=4).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to disable $($svc.Name): $($_.Exception.Message)")
                    }
                } else {
                    $UltixSync.Logs.Enqueue(" -> Restoring service to Manual: $($svc.Name)")
                    try {
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 3
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) set to Manual (Start=3).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to modify $($svc.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Service operations completed.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

function Get-StartupState_Worker {
    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Resolve-StartupApprovedState {
        param([string]$ApprovedRegPath, [string]$EntryName)
        if ([string]::IsNullOrWhiteSpace($ApprovedRegPath) -or -not (Test-Path $ApprovedRegPath)) {
            return "Enabled"
        }
        try {
            $key = Get-Item -Path $ApprovedRegPath -ErrorAction SilentlyContinue
            if ($null -eq $key) { return "Enabled" }
            try {
                [byte[]]$bin = $key.GetValue($EntryName, $null)
            } finally {
                $key.Dispose()
            }
            if ($null -eq $bin -or $bin.Length -lt 1) { return "Enabled" }

            # In Windows Task Manager, byte[0] == 0x02 or 0x06 indicates Enabled; odd/other bytes (0x03, 0x01) mean Disabled
            $header = [int]$bin[0]
            if ($header -eq 2 -or $header -eq 6) {
                return "Enabled"
            } else {
                if ($bin.Length -ge 12) {
                    $ft = [BitConverter]::ToInt64($bin, 4)
                    if ($ft -gt 0) {
                        $dt = [DateTime]::FromFileTimeUtc($ft).ToLocalTime().ToString("yyyy-MM-dd")
                        return "Disabled ($dt)"
                    }
                }
                return "Disabled (TaskMgr)"
            }
        } catch {
            return "Enabled"
        }
    }

    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKLM Run (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";       Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Label = "HKLM Run (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKCU Run" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKLM RunOnce (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce";   Approved = "";                                                                               Label = "HKLM RunOnce (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKCU RunOnce" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKLM)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKCU)" }
    )

    foreach ($reg in $regTargets) {
        if (Test-Path $reg.Path) {
            $keyObj = Get-Item -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $keyObj) {
                try {
                    foreach ($valName in $keyObj.Property) {
                        $valData = [string]$keyObj.GetValue($valName)
                        $state = if ($reg.Approved -ne "") {
                            Resolve-StartupApprovedState -ApprovedRegPath $reg.Approved -EntryName $valName
                        } else {
                            "Enabled (Always)"
                        }
                        $startupItems.Add([PSCustomObject]@{
                            Name         = $valName
                            State        = $state
                            Location     = $reg.Label
                            Command      = $valData
                            RegPath      = $reg.Path
                            ApprovedPath = $reg.Approved
                            Type         = "Registry"
                        })
                    }
                } finally {
                    $keyObj.Dispose()
                }
            }
        }
    }

    $folderTargets = @(
        @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (All Users)" }
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (Current User)" }
    )

    foreach ($fld in $folderTargets) {
        if (Test-Path $fld.Path) {
            Get-ChildItem -Path $fld.Path -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -ne "desktop.ini") {
                    $state = Resolve-StartupApprovedState -ApprovedRegPath $fld.Approved -EntryName $_.Name
                    $startupItems.Add([PSCustomObject]@{
                        Name         = $_.Name
                        State        = $state
                        Location     = $fld.Label
                        Command      = $_.FullName
                        RegPath      = $null
                        ApprovedPath = $fld.Approved
                        Type         = "File"
                    })
                }
            }
        }
    }

    return @($startupItems | Sort-Object Location, Name)
}

function Show-StartupGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Run, RunOnce, GPO Run, Startup Folders, and StartupApproved binary states..."
    Update-Progress 20

    $sb = (Get-Command -Name Get-StartupState_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No startup items detected across registry or folders.`n"
            return
        }

        $cols = @(
            @{ Header = "Entry Name"; Property = "Name";     Width = 210 }
            @{ Header = "State";      Property = "State";    Width = 145 }
            @{ Header = "Location";   Property = "Location"; Width = 155 }
            @{ Header = "Command";    Property = "Command";  Width = 340 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Deep Startup Inspector" `
            -Description "Inspect Run, RunOnce, GPO, and StartupApproved states. You can permanently delete entries or toggle their TaskMgr state." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Permanent)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Startup modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Deleting startup entry: $($item.Name) [$($item.Location)]")
                    try {
                        if ($item.Type -eq "Registry") {
                            Remove-ItemProperty -Path $item.RegPath -Name $item.Name -Force -ErrorAction Stop
                        } else {
                            Remove-Item -LiteralPath $item.Command -Force -ErrorAction Stop
                        }
                        if (-not [string]::IsNullOrWhiteSpace($item.ApprovedPath) -and (Test-Path $item.ApprovedPath)) {
                            Remove-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Force -ErrorAction SilentlyContinue
                        }
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    if ([string]::IsNullOrWhiteSpace($item.ApprovedPath)) {
                        $UltixSync.Logs.Enqueue("    [!] $($item.Name) [$($item.Location)] does not support TaskMgr StartupApproved toggling.")
                        continue
                    }
                    try {
                        if (-not (Test-Path $item.ApprovedPath)) {
                            New-Item -Path $item.ApprovedPath -Force | Out-Null
                        }
                        if ($item.State -match "^Disabled") {
                            [byte[]]$enableBytes = @(0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $enableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.Name) [$($item.Location)]")
                        } else {
                            [byte[]]$headerBytes = @(0x03, 0x00, 0x00, 0x00)
                            [byte[]]$timeBytes   = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())
                            [byte[]]$disableBytes = $headerBytes + $timeBytes
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $disableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.Name) [$($item.Location)]")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Startup configuration updated.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

function Get-ScheduledTasks_Worker {
    $taskItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Test-TaskExecutableExists {
        param([string]$RawExecute)
        if ([string]::IsNullOrWhiteSpace($RawExecute)) { return $true }

        $clean = [System.Environment]::ExpandEnvironmentVariables($RawExecute.Trim().Trim('"')).Trim()
        if ($clean -match '^"([^"]+)"') {
            $clean = $matches[1]
        } elseif ($clean -match '(?i)^(.+?\.(?:exe|bat|cmd|vbs|ps1|msc))(?:$|\s)') {
            $clean = $matches[1]
        } else {
            $clean = $clean.Split(' ')[0]
        }

        if ($clean -match '^\$\(' -or $clean -match '^[a-zA-Z]+://') { return $true }

        if ([System.IO.Path]::IsPathRooted($clean)) {
            return [System.IO.File]::Exists($clean)
        } else {
            $leaf = if ($clean -notmatch '\.') { "$clean.exe" } else { $clean }
            foreach ($dir in @("$env:windir\System32", $env:windir, "$env:windir\SysWOW64", "$env:windir\System32\wbem", "$env:windir\System32\WindowsPowerShell\v1.0")) {
                if ([System.IO.File]::Exists((Join-Path $dir $leaf))) { return $true }
            }
            return $true
        }
    }

    function ConvertTo-TriggerSummary {
        param([array]$Triggers)
        if ($null -eq $Triggers -or $Triggers.Count -eq 0) { return "OnDemand" }
        $tags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $Triggers) {
            $className = [string]$t.CimClass.CimClassName
            switch -Wildcard ($className) {
                "*LogonTrigger*"              { [void]$tags.Add("AtLogon") }
                "*BootTrigger*"               { [void]$tags.Add("AtStartup") }
                "*DailyTrigger*"              { [void]$tags.Add("Daily") }
                "*WeeklyTrigger*"             { [void]$tags.Add("Weekly") }
                "*TimeTrigger*"               { [void]$tags.Add("Time/Once") }
                "*IdleTrigger*"               { [void]$tags.Add("OnIdle") }
                "*EventTrigger*"              { [void]$tags.Add("OnEvent") }
                "*SessionStateChangeTrigger*" { [void]$tags.Add("SessionChange") }
                "*RegistrationTrigger*"       { [void]$tags.Add("OnRegister") }
                default                       { [void]$tags.Add("Custom") }
            }
            if ($null -ne $t.Repetition -and -not [string]::IsNullOrWhiteSpace($t.Repetition.Interval)) {
                [void]$tags.Add("Periodic")
            }
        }
        return ($tags -join ", ")
    }

    $protectedTaskNames = "^(WinUltix_CPPC_Failsafe|MpIdleTask|Windows Defender.*|BitLocker.*)$"
    $msTelemetryPaths   = "(?i)^\\Microsoft\\Windows\\(Application Experience|Autochk|Customer Experience Improvement Program|DiskDiagnostic|Feedback|Location|Maps|Mobile Broadband Accounts|NetTrace|Power Efficiency Diagnostics|PushToInstall|RetailDemo|CloudExperienceHost|Windows Error Reporting|WaaSMedic)\\"

    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    $total = [math]::Max(1, $allTasks.Count)
    $idx = 0

    foreach ($task in $allTasks) {
        $idx++
        if ($null -ne $UltixSync -and ($idx % 15 -eq 0 -or $idx -eq $total)) {
            $UltixSync.Progress = [int](($idx / $total) * 100)
        }

        $tName  = [string]$task.TaskName
        $tPath  = [string]$task.TaskPath
        $tState = [string]$task.State

        if ($tName -match $protectedTaskNames) { continue }

        $execAction = $task.Actions | Where-Object { $null -ne $_.Execute -and $_.Execute -ne "" } | Select-Object -First 1
        $cmdLine = ""
        $isGhost = $false

        if ($null -ne $execAction) {
            $rawExe  = [string]$execAction.Execute
            $rawArgs = [string]$execAction.Arguments
            $cmdLine = "$rawExe $rawArgs".Trim()
            if (-not (Test-TaskExecutableExists -RawExecute $rawExe)) {
                $isGhost = $true
            }
        } else {
            $comAction = $task.Actions | Where-Object { $null -ne $_.ClassId } | Select-Object -First 1
            if ($null -ne $comAction) {
                $cmdLine = "[COM Handler] $($comAction.ClassId)"
            } else {
                $cmdLine = "[Internal Handler]"
            }
        }

        $category = ""
        if ($isGhost) {
            $category = "[GHOST / Missing Exe]"
        } elseif ($tPath -notlike "\Microsoft\Windows\*") {
            if ($tPath -like "\Microsoft\*") {
                $category = "[MS App / Updater]"
            } else {
                $category = "[3rd-Party / Root]"
            }
        } elseif ($tPath -match $msTelemetryPaths -or $tPath -like "\Microsoft\XblGameSave\*") {
            $category = "[MS Telemetry / Bloat]"
        } else {
            continue
        }

        $trigSummary = ConvertTo-TriggerSummary -Triggers @($task.Triggers)

        $taskItems.Add([PSCustomObject]@{
            Name     = $tName
            Category = $category
            State    = $tState
            Triggers = $trigSummary
            TaskPath = $tPath
            Command  = $cmdLine
        })
    }

    return @($taskItems | Sort-Object Category, TaskPath, Name)
}

function Show-TasksGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Task Scheduler for 3rd-party updaters, telemetry, and orphaned ghost tasks..."
    Update-Progress 10

    $sb = (Get-Command -Name Get-ScheduledTasks_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No third-party, telemetry, or orphaned scheduled tasks found.`n"
            return
        }

        $cols = @(
            @{ Header = "Task Name"; Property = "Name";     Width = 195 }
            @{ Header = "Category";  Property = "Category"; Width = 155 }
            @{ Header = "State";     Property = "State";    Width = 80  }
            @{ Header = "Triggers";  Property = "Triggers"; Width = 120 }
            @{ Header = "Folder";    Property = "TaskPath"; Width = 140 }
            @{ Header = "Action";    Property = "Command";  Width = 280 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Scheduled Tasks Inspector (3rd-Party, Telemetry & Ghosts)" `
            -Description "Core Windows tasks are hidden. Inspect 3rd-party updaters, MS bloat, and [GHOST] tasks with missing binaries." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Unregister)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Scheduled tasks operation cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Unregistering task: $($item.TaskPath)$($item.Name)")
                    try {
                        Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                        Unregister-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -Confirm:$false -ErrorAction Stop
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    try {
                        if ($item.State -eq "Disabled") {
                            Enable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.TaskPath)$($item.Name)")
                        } else {
                            Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                            Disable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.TaskPath)$($item.Name)")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Scheduled Tasks operations completed.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

# ------------------------------------------
# Z4: UI INITIALIZATION (SERVICES, SCHEDULER & AUTORUNS)
# ------------------------------------------
function Initialize-Z4UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabServices = New-Object System.Windows.Forms.TabPage
    $tabServices.Text = "Services"
    $tabServices.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. Office Services Profile (Light)
    $rowSvcLight = New-UltixActionRow -Parent $tabServices -Y 20 -MainRGB @(45, 85, 125) `
        -Text "Background Services: OFFICE PROFILE" `
        -Description "OFFICE PROFILE (Light): Disables 9 telemetry and diagnostics services while keeping Printing, Windows Search, and LAN sharing 100% intact." `
        -AuditDescription "AUDIT: Verifies standard telemetry and background bloat services." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ModalTitle "WinUltix - Office Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Office Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Light" -AuditLabel "Services (Office Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Disable"
        }.GetNewClosure())

    # 2. Gaming Services Profile (Heavy)
    $rowSvcHeavy = New-UltixActionRow -Parent $tabServices -Y 70 -MainRGB @(135, 50, 50) `
        -Text "Background Services: GAMING PROFILE" `
        -Description "GAMING PROFILE (Heavy): Symmetrically disables up to 51 background services (SysMain, WSearch, Spooler, DPS/SRUM disk logging, Xbox, Diagnostics)." `
        -AuditDescription "AUDIT: Verifies 51 heavy background services including indexer, SRUM, and print spooler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ModalTitle "WinUltix - Gaming Services Profile" -ModalDescription "Select services to configure. Unoptimized services are checked by default." -ExecutorFunction "Invoke-ApplyServices" -ExecutorExtraParams @{ ProfileName = "Gaming Profile" } -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-ServicesState_Heavy" -AuditLabel "Services (Gaming Profile)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "To Configure"
        }.GetNewClosure())

    # 3. Telemetry Scheduled Tasks Preset
    $rowTelemetry = New-UltixActionRow -Parent $tabServices -Y 120 -MainRGB @(55, 58, 64) `
        -Text "Disable Telemetry Tasks (Scheduler)" `
        -Description "Disables 5 core Microsoft telemetry task branches in Task Scheduler: CEIP, Feedback, PerformanceTrace, Windows Error Reporting (WER), and XblGameSave." `
        -AuditDescription "AUDIT: Verifies if Microsoft telemetry scheduled tasks are active in Task Scheduler." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ModalTitle "WinUltix - Scheduled Tasks Lockdown" -ModalDescription "Select tasks to modify (Apply = Disable, Revert = Enable)." -ExecutorFunction "Invoke-ApplyTasks" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-TelemetryTasksState" -AuditLabel "Scheduled Tasks" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Active"
        }.GetNewClosure())

    # 4. Interactive Service, Task & Startup Inspectors (Sortable Grids)
    $lblManagers = New-Object System.Windows.Forms.Label
    $lblManagers.Text = "Interactive Service, Task & Startup Inspectors"
    $lblManagers.Location = New-Object System.Drawing.Point(15, 172)
    $lblManagers.Size = New-Object System.Drawing.Size(370, 18)
    $lblManagers.ForeColor = [System.Drawing.Color]::DarkGray
    $lblManagers.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblWarnMgr = New-Object System.Windows.Forms.Label
    $lblWarnMgr.Text = "[!] MANUAL INSPECTORS ONLY — DO NOT SELECT ALL!`r`nUse to inspect remaining services/tasks after running profiles."
    $lblWarnMgr.Location = New-Object System.Drawing.Point(15, 193)
    $lblWarnMgr.Size = New-Object System.Drawing.Size(370, 40)
    $lblWarnMgr.BackColor = [System.Drawing.Color]::FromArgb(255, 58, 35, 20)
    $lblWarnMgr.ForeColor = [System.Drawing.Color]::Gold
    $lblWarnMgr.BorderStyle = "FixedSingle"
    $lblWarnMgr.TextAlign = "MiddleCenter"
    $lblWarnMgr.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tabServices.Controls.AddRange(@($lblManagers, $lblWarnMgr))

    $btnSvcGrid = New-UltixButton -Parent $tabServices -X 15 -Y 242 -Width 370 -Height 40 -RGB @(45, 85, 125) `
        -Text "System Services Manager (Interactive Grid)" `
        -Description "MANUAL INSPECTOR: Sortable dark Services Manager with instant live search. Inspect remaining services (Critical OS services are locked in Red)." `
        -OnClick ({ Show-ServicesGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $btnTasksGrid = New-UltixButton -Parent $tabServices -X 15 -Y 292 -Width 370 -Height 40 -RGB @(45, 85, 125) `
        -Text "Scheduled Tasks Inspector (3rd-Party / Ghosts)" `
        -Description "MANUAL INSPECTOR: Exposes 3rd-party updaters, Microsoft telemetry bloat, and orphaned [GHOST] tasks pointing to missing .exe files." `
        -OnClick ({ Show-TasksGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $btnStartupGrid = New-UltixButton -Parent $tabServices -X 15 -Y 342 -Width 370 -Height 40 -RGB @(45, 85, 125) `
        -Text "Deep Startup Manager (Run / StartupApproved)" `
        -Description "MANUAL INSPECTOR: Audits Run, RunOnce, GPO Run, and Startup folders across x64/x86 hives, and decodes Task Manager StartupApproved binary states." `
        -OnClick ({ Show-StartupGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    foreach ($row in @($rowSvcLight, $rowSvcHeavy, $rowTelemetry)) {
        $allTabButtons.AddRange($row.Controls)
    }
    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@($btnSvcGrid, $btnTasksGrid, $btnStartupGrid))

    $TabControl.Controls.Add($tabServices)
}