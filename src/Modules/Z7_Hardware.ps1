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