# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z7_HARDWARE.PS1 - HARDWARE & DIAGNOSTICS MODULE (v3.0.0)
# Z7_Hardware: Low-level hardware diagnostics and kernel latency tuning. Uses Core_Helpers P/Invoke runtime ([WinUltix.CpuTopology], [WinUltix.NtDll], [WinUltix.NativeMethods]) and asynchronous Runspace workers ($UltixSync) for Topology-Aware Affinity Lasso, CPPC P-State Unhider & SYSTEM Dead Man's Switch, MSI & IRQ Core 0 Offload Enforcer with Live NtQuerySystemInformation DPC Telemetry, WHEA APIC XML Decoder, Symmetric NDIS/TCP Optimizer, 0.5ms TSC Timer Lock, NVMe APST / PCIe ASPM Lockdown, Profile Snapshot hooks, and Pre-Flight Game Mode macro generation.
# ==========================================

# Cached physical core masks and CPU topology profile from kernel32!GetLogicalProcessorInformationEx
$script:UltixCoreMasks   = $null
$script:UltixCpuTopology = $null

function Get-UltixPhysicalCoreMasks {
    if ($null -eq $script:UltixCoreMasks) {
        $cores = @([WinUltix.CpuTopology]::GetProcessorCores())
        if ($cores.Count -gt 0) {
            $script:UltixCoreMasks = @($cores | ForEach-Object { [int64]$_.Mask })
        } else {
            $lpCount = [Environment]::ProcessorCount
            $fallback = [System.Collections.Generic.List[int64]]::new()
            for ($i = 0; $i -lt $lpCount; $i += 2) {
                $m = ([int64]1 -shl $i)
                if (($i + 1) -lt $lpCount) { $m = $m -bor ([int64]1 -shl ($i + 1)) }
                $fallback.Add($m)
            }
            $script:UltixCoreMasks = @($fallback)
        }
    }
    return $script:UltixCoreMasks
}

# ------------------------------------------
# Z7: SHARED HARDWARE & TOPOLOGY HELPERS
# ------------------------------------------
function Get-CPUTopologyProfile {
    if ($null -ne $script:UltixCpuTopology) {
        return $script:UltixCpuTopology
    }

    $nativeCores  = @([WinUltix.CpuTopology]::GetProcessorCores())
    $nativeCaches = @([WinUltix.CpuTopology]::GetL3Caches())

    $logical = [int][Environment]::ProcessorCount
    $cores   = if ($nativeCores.Count -gt 0) { $nativeCores.Count } else { [math]::Max(1, [int]($logical / 2)) }
    $smt     = ($logical -gt $cores)

    # Read CPU name directly from kernel hardware registry (<0.1ms) instead of slow Win32_Processor WMI query (~1500ms)
    $name = (Get-ItemProperty -LiteralPath "HKLM:\HARDWARE\Description\System\CentralProcessor\0" -Name "ProcessorNameString" -ErrorAction SilentlyContinue).ProcessorNameString
    if ([string]::IsNullOrWhiteSpace($name)) { $name = "Unknown CPU" }

    $profileResult = $null

    # Case 1: Intel Hybrid Architecture (P+E Cores detected via EfficiencyClass)
    if ($nativeCores.Count -ge 6) {
        $effClasses = @($nativeCores | Select-Object -ExpandProperty EfficiencyClass -Unique | Sort-Object)
        if ($effClasses.Count -gt 1) {
            $minEff = $effClasses[0]
            [int64]$eCoreMask = 0
            $eCoreCount = 0
            foreach ($c in $nativeCores) {
                if ($c.EfficiencyClass -eq $minEff) {
                    $eCoreMask = $eCoreMask -bor $c.Mask
                    $eCoreCount++
                }
            }
            if ($eCoreMask -gt 0) {
                $profileResult = [PSCustomObject]@{
                    IsSupported = $true
                    Mask        = [System.IntPtr]$eCoreMask
                    Label       = "Intel Hybrid ($eCoreCount E-Cores)"
                    CoreDesc    = "E-Core Cluster (Mask: 0x$($eCoreMask.ToString('X')))"
                    SmtEnabled  = $smt
                }
            }
        }
    }

    # Case 2: AMD 8-Core Single-CCD (e.g., 9800X3D, 7800X3D, 5800X3D, 9700X) -> Lock background apps to Cores 0-1
    if ($null -eq $profileResult -and $name -match "AMD" -and $cores -eq 8) {
        [int64]$c01Mask = if ($nativeCores.Count -ge 2) {
            $nativeCores[0].Mask -bor $nativeCores[1].Mask
        } elseif ($smt) { 15 } else { 3 }
        $desc = if ($smt) { "Cores 0-1 (Threads 0-3)" } else { "Cores 0-1 (No SMT)" }
        $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$c01Mask; Label = "AMD 8C Single-CCD"; CoreDesc = $desc; SmtEnabled = $smt }
    }

    # Case 3: AMD Dual-CCD (12C/16C, e.g., 7900X3D, 7950X3D, 9950X3D) -> Inspect L3 Cache domains to protect 3D V-Cache CCD
    if ($null -eq $profileResult -and $name -match "AMD" -and $cores -gt 8 -and $logical -ge 12) {
        if ($nativeCaches.Count -ge 2) {
            $sortedL3 = @($nativeCaches | Sort-Object SizeBytes)
            $smallestL3 = $sortedL3[0]
            $largestL3  = $sortedL3[$sortedL3.Count - 1]
            $isAsymmetricX3D = ($largestL3.SizeBytes -gt $smallestL3.SizeBytes)

            $targetDomain = if ($isAsymmetricX3D) { $smallestL3 } else { $nativeCaches[$nativeCaches.Count - 1] }
            $tailMask = [WinUltix.CpuTopology]::GetTailThreadsMask($targetDomain.Mask, 4)
            $l3MB = [math]::Round($targetDomain.SizeBytes / 1MB, 0)
            $labelStr = if ($isAsymmetricX3D) { "AMD Dual-CCD X3D" } else { "AMD Dual-CCD" }
            $profileResult = [PSCustomObject]@{
                IsSupported = $true
                Mask        = [System.IntPtr]$tailMask
                Label       = $labelStr
                CoreDesc    = "Secondary CCD (${l3MB}MB L3 Tail, Mask: 0x$($tailMask.ToString('X')))"
                SmtEnabled  = $smt
            }
        } else {
            $shift = [math]::Max(0, ($logical - 4))
            $maskVal = [int64]15 -shl $shift
            $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "AMD Dual-CCD"; CoreDesc = "CCD1 Tail (Threads $shift-$($logical - 1))"; SmtEnabled = $smt }
        }
    }

    # Case 4: Standard Multi-Core (6+ Core CPUs) -> Isolate background apps to the last 4 threads
    if ($null -eq $profileResult -and $cores -ge 6 -and $logical -ge 8) {
        $shift = [math]::Max(0, ($logical - 4))
        $maskVal = [int64]15 -shl $shift
        $profileResult = [PSCustomObject]@{ IsSupported = $true; Mask = [System.IntPtr]$maskVal; Label = "Multi-Core CPU"; CoreDesc = "Tail Threads ($shift-$($logical - 1))"; SmtEnabled = $smt }
    }

    if ($null -eq $profileResult) {
        $profileResult = [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Unsupported (<6C)"; CoreDesc = "N/A"; SmtEnabled = $smt }
    }

    $script:UltixCpuTopology = $profileResult
    return $script:UltixCpuTopology
}

function Test-CPUTopology {
    return (Get-CPUTopologyProfile).IsSupported
}

function Get-KernelInterruptSnapshot {
    param([uint32[]]$PreviousCounts = $null)

    [uint32[]]$currentCounts = [WinUltix.NtDll]::GetProcessorDpcCounts()
    if ($null -eq $currentCounts -or $currentCounts.Count -eq 0) {
        return $null
    }

    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    $coreCount = $coreMasks.Count
    [int64]$core0Mask = if ($coreCount -ge 1) { $coreMasks[0] } else { [int64]3 }

    [uint64[]]$bootByCore  = New-Object uint64[] $coreCount
    [uint64[]]$deltaByCore = New-Object uint64[] $coreCount

    [uint64]$bootTotal    = 0
    [uint64]$bootCore0    = 0
    [uint64]$bootPeakVal  = 0
    $bootPeakThread       = 0

    [uint64]$deltaTotal   = 0
    [uint64]$deltaCore0   = 0
    [uint64]$deltaPeakVal = 0
    $deltaPeakThread      = 0

    $hasValidDelta = ($null -ne $PreviousCounts -and $PreviousCounts.Count -eq $currentCounts.Count)

    for ($i = 0; $i -lt $currentCounts.Count; $i++) {
        $threadBit = ([int64]1 -shl $i)
        $isCore0Thread = (($core0Mask -band $threadBit) -ne 0)
        $curVal = [uint64]$currentCounts[$i]

        $bootTotal += $curVal
        if ($isCore0Thread) { $bootCore0 += $curVal }
        if ($curVal -gt $bootPeakVal) {
            $bootPeakVal    = $curVal
            $bootPeakThread = $i
        }

        [uint64]$diff = 0
        if ($hasValidDelta) {
            $prevVal = [uint64]$PreviousCounts[$i]
            $diff = if ($curVal -ge $prevVal) { $curVal - $prevVal } else { 0 }
            $deltaTotal += $diff
            if ($isCore0Thread) { $deltaCore0 += $diff }
            if ($diff -gt $deltaPeakVal) {
                $deltaPeakVal    = $diff
                $deltaPeakThread = $i
            }
        }

        for ($c = 0; $c -lt $coreCount; $c++) {
            if (($coreMasks[$c] -band $threadBit) -ne 0) {
                $bootByCore[$c] += $curVal
                if ($hasValidDelta) { $deltaByCore[$c] += $diff }
                break
            }
        }
    }

    $bootCore0Pct = if ($bootTotal -gt 0) { [math]::Round(($bootCore0 / $bootTotal) * 100.0, 1) } else { 0.0 }
    $bootPeakPct  = if ($bootTotal -gt 0) { [math]::Round(($bootPeakVal / $bootTotal) * 100.0, 1) } else { 0.0 }

    if ($hasValidDelta -and $deltaTotal -gt 0) {
        $liveCore0Pct = [math]::Round(($deltaCore0 / $deltaTotal) * 100.0, 1)
        $hotPct       = [math]::Round(($deltaPeakVal / $deltaTotal) * 100.0, 1)
        $hotThreadIdx = $deltaPeakThread
        $hasLiveDelta = $true
    } else {
        $liveCore0Pct = $bootCore0Pct
        $hotPct       = $bootPeakPct
        $hotThreadIdx = $bootPeakThread
        $hasLiveDelta = $false
    }

    $bootCorePcts = New-Object double[] $coreCount
    $liveCorePcts = New-Object double[] $coreCount
    $bootParts    = [System.Collections.Generic.List[string]]::new()
    $liveParts    = [System.Collections.Generic.List[string]]::new()

    for ($c = 0; $c -lt $coreCount; $c++) {
        $bPct = if ($bootTotal -gt 0) { [math]::Round(($bootByCore[$c] / $bootTotal) * 100.0, 1) } else { 0.0 }
        $lPct = if ($hasLiveDelta -and $deltaTotal -gt 0) { [math]::Round(($deltaByCore[$c] / $deltaTotal) * 100.0, 1) } else { $bPct }
        $bootCorePcts[$c] = $bPct
        $liveCorePcts[$c] = $lPct

        $bootParts.Add(("C{0}:{1,2:0}%" -f $c, [math]::Round($bPct, 0)))
        $liveParts.Add(("C{0}:{1,2:0}%" -f $c, [math]::Round($lPct, 0)))
    }

    return [PSCustomObject]@{
        RawCounts      = $currentCounts
        HasLiveDelta   = $hasLiveDelta
        CoreCount      = $coreCount
        Core0SharePct  = $liveCore0Pct
        HotThread      = $hotThreadIdx
        HotThreadPct   = $hotPct
        DpcRatePerSec  = $deltaTotal
        BootCore0Pct   = $bootCore0Pct
        BootPeakThread = $bootPeakThread
        BootPeakPct    = $bootPeakPct
        BootTotalDpc   = $bootTotal
        BootCorePcts   = $bootCorePcts
        LiveCorePcts   = $liveCorePcts
        BootCoreLine   = ($bootParts -join " ")
        LiveCoreLine   = ($liveParts -join " ")
    }
}

function Update-UltixDpcMonitorUI {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Label]$TargetLabel,
        [Parameter(Mandatory=$true)][hashtable]$State,
        [switch]$CompactMode
    )

    if ($TargetLabel.IsDisposed) { return }

    $snap = Get-KernelInterruptSnapshot -PreviousCounts $State.PrevCounts
    if ($null -eq $snap) {
        $TargetLabel.Text = "BOOT BASELINE | Kernel interrupt telemetry unavailable.`r`nLIVE 1s DELTA | N/A`r`nPER-CORE MAP  | N/A"
        return
    }

    $State.PrevCounts = $snap.RawCounts
    $State.LastSnap   = $snap

    if ($CompactMode) {
        $line1 = "BOOT AVG | C0: $($snap.BootCore0Pct)% | Peak: LP#$($snap.BootPeakThread) ($($snap.BootPeakPct)%)"
        if (-not $State.IsRunning) {
            $line2 = "LIVE 1s  | [Paused - Click Start below for 1Hz stream]"
            $line3 = "CORES AVG| $($snap.BootCoreLine)"
        } elseif ($snap.HasLiveDelta) {
            $line2 = "LIVE 1s  | C0: $($snap.Core0SharePct)% | Hot : LP#$($snap.HotThread) ($($snap.HotThreadPct)%) | $($snap.DpcRatePerSec)/s"
            $line3 = "CORES 1s | $($snap.LiveCoreLine)"
        } else {
            $line2 = "LIVE 1s  | Sampling 1000ms kernel interrupt delta..."
            $line3 = "CORES AVG| $($snap.BootCoreLine)"
        }
    } else {
        $line1 = "BOOT BASELINE | Core 0 Share: $($snap.BootCore0Pct)% | Peak: LP#$($snap.BootPeakThread) ($($snap.BootPeakPct)%) | Total: $($snap.BootTotalDpc.ToString('N0')) DPCs"
        if ($snap.HasLiveDelta) {
            $line2 = "LIVE 1s DELTA | Core 0 Share: $($snap.Core0SharePct)% | Hot : LP#$($snap.HotThread) ($($snap.HotThreadPct)%) | Rate : $($snap.DpcRatePerSec) DPC/s"
            $line3 = "PER-CORE (1s) | $($snap.LiveCoreLine)"
        } else {
            $line2 = "LIVE 1s DELTA | Sampling kernel interrupt counters (1s window)..."
            $line3 = "PER-CORE (AVG)| $($snap.BootCoreLine)"
        }
    }

    $TargetLabel.Text = "$line1`r`n$line2`r`n$line3"

    $activeC0 = if (($State.IsRunning -or -not $CompactMode) -and $snap.HasLiveDelta) { $snap.Core0SharePct } else { $snap.BootCore0Pct }
    if ($activeC0 -ge 55.0) {
        $TargetLabel.ForeColor = [System.Drawing.Color]::OrangeRed
    } elseif ($activeC0 -ge 30.0) {
        $TargetLabel.ForeColor = [System.Drawing.Color]::Yellow
    } else {
        $TargetLabel.ForeColor = [System.Drawing.Color]::LightGreen
    }
}

function Write-UltixDpcReport {
    param([PSCustomObject]$Snapshot = $null)

    if ($null -eq $Snapshot -or -not $Snapshot.HasLiveDelta) {
        Write-GUI " -> Sampling kernel interrupt counters over a 1000ms window..."
        $s1 = Get-KernelInterruptSnapshot
        Start-Sleep -Milliseconds 1000
        $Snapshot = Get-KernelInterruptSnapshot -PreviousCounts $s1.RawCounts
    }
    if ($null -eq $Snapshot) { return }

    [int64[]]$masks = Get-UltixPhysicalCoreMasks
    Write-GUI "=== KERNEL DPC & INTERRUPT DISTRIBUTION REPORT ==="
    Write-GUI " -> Global DPC Rate (1s) : $($Snapshot.DpcRatePerSec) DPC/s (Boot: $($Snapshot.BootTotalDpc.ToString('N0')))"
    Write-GUI " -> Physical Core 0 Load : $($Snapshot.Core0SharePct)% Live | $($Snapshot.BootCore0Pct)% Boot Avg"
    Write-GUI " -> Hottest Thread       : LP#$($Snapshot.HotThread) ($($Snapshot.HotThreadPct)% Live | Boot Peak: LP#$($Snapshot.BootPeakThread))"
    Write-GUI " -> Per-Core Map (C# = Physical Core | LP# = Logical Threads):"

    for ($c = 0; $c -lt $Snapshot.CoreCount; $c++) {
        $m = $masks[$c]
        $lpNums = [System.Collections.Generic.List[string]]::new()
        for ($b = 0; $b -lt 64; $b++) {
            if (($m -band ([int64]1 -shl $b)) -ne 0) { $lpNums.Add(("{0:D2}" -f $b)) }
        }
        $lpStr = "LP#" + ($lpNums -join ",")
        $roleTag = if ($c -eq 0) { "[OS Timer / Default IRQ]" } elseif ($c -eq 1) { "[Core 0 Offload Target]" } else { "[Prime Gaming Core]" }
        Write-GUI ("  * C{0} ({1,-8}) | 1s:{2,5:0.0}% | Boot:{3,5:0.0}% {4}" -f $c, $lpStr, $Snapshot.LiveCorePcts[$c], $Snapshot.BootCorePcts[$c], $roleTag)
    }

    Write-GUI " -> [LEGEND]: Green (<30% C0) = Optimal | Yellow (30-54%) = Moderate"
    Write-GUI "    Red (>=55% C0) = Bottleneck (Offload ★ GPU/NIC to C1 in MSI Modal)`n"
}

# ------------------------------------------
# Z7: HARDWARE & DIAGNOSTICS AUDITS
# ------------------------------------------
function Get-HardwareState_Affinity {
    $whitelist = @("systemsettings.exe", "shellexperiencehost.exe", "cmd.exe", "powershell.exe", "pwsh.exe", "applicationframehost.exe", "rundll32.exe", "dllhost.exe", "ngciso.exe", "wmiadap.exe", "csrss.exe", "lsass.exe", "smss.exe", "services.exe", "svchost.exe", "wininit.exe", "winlogon.exe", "explorer.exe", "System", "Idle", "Registry", "dwm.exe", "fontdrvhost.exe", "Taskmgr.exe", "conhost.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe", "SearchHost.exe", "StartMenuExperienceHost.exe", "SecurityHealthService.exe", "SecurityHealthSystray.exe", "MsMpEng.exe", "NisSrv.exe", "LsaIso.exe", "audiodg.exe", "WmiPrvSE.exe", "TiWorker.exe", "TrustedInstaller.exe", "spoolsv.exe", "WUDFHost.exe", "System.exe", "Idle.exe", "Registry.exe", "Secure System.exe", "ctfmon.exe", "MpDefenderCoreService.exe", "NVDisplay.Container.exe", "ShellHost.exe", "iFiUsbAudioCpl.exe", "Windows11FirewallService.exe", "Windows11FirewallControl.exe", "AmdPpkgSvc.exe", "nvcontainer.exe", "MoUsoCoreWorker.exe", "SearchIndexer.exe", "smartscreen.exe", "AppActions.exe", "SDXHelper.exe", "QuickControls.exe", "armsvc.exe", "BudsManager.exe")
    $dictionary = @("Discord.exe", "Spotify.exe", "msedgewebview2.exe", "steamwebhelper.exe", "EpicGamesLauncher.exe", "obs64.exe", "ArmouryCrate.exe", "iCUE.exe", "Razer Synapse Service.exe", "firefox.exe", "chrome.exe", "msedge.exe", "brave.exe", "opera.exe", "GalaxyClient.exe", "GOG Galaxy.exe", "EADesktop.exe", "upc.exe", "Battle.net.exe", "WhatsApp.exe", "Telegram.exe", "Teams.exe", "slack.exe", "Overwolf.exe", "LGHUB.exe", "LGHUB_Agent.exe", "MSIAfterburner.exe", "RTSS.exe", "NZXT CAM.exe", "vgc.exe", "vgtray.exe", "OneDrive.exe")
    
    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

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
    
    $e  = Get-UltixPowerAcIndex -SettingGuid '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' -IncludeHidden
    $d  = Get-UltixPowerAcIndex -SettingGuid '4b92d758-5a24-4851-a470-815d78aee119' -IncludeHidden
    $pr = Get-UltixPowerAcIndex -SettingGuid '7b224883-b3cc-4d79-819f-8374152cbe7c' -IncludeHidden

    $dispE  = if ($null -ne $e)  { "$e%" }  else { "Unknown" }
    $dispD  = if ($null -ne $d)  { "$d%" }  else { "Unknown" }
    $dispPr = if ($null -ne $pr) { "$pr%" } else { "Unknown" }

    $rules = @(
        @{ KeyId = "EPP";     UIDisplayName = "Unhide: EPP [Current AC: $dispE]";          Path = "$basePath\36687f9e-e3a5-4dbf-b1dc-15eb381c6863"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ KeyId = "Demote";  UIDisplayName = "Unhide: Idle Demote [Current AC: $dispD]";  Path = "$basePath\4b92d758-5a24-4851-a470-815d78aee119"; Name = "Attributes"; Expected = 2; Type = "Registry" }
        @{ KeyId = "Promote"; UIDisplayName = "Unhide: Idle Promote [Current AC: $dispPr]"; Path = "$basePath\7b224883-b3cc-4d79-819f-8374152cbe7c"; Name = "Attributes"; Expected = 2; Type = "Registry" }
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($rule in $rules) {
        $isDetected = $true
        $val = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
        if ($null -ne $val -and $val -eq $rule.Expected) { $isDetected = $false }

        $results.Add([PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        })
    }
    return @($results)
}

function Get-HardwareState_IRQ {
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    [uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
    [uint64]$core1Mask  = if ($coreMasks.Count -ge 2) { [uint64]$coreMasks[1] } else { 12 }
    
    $venKeys = Get-ChildItem -Path $pciPath -ErrorAction SilentlyContinue
    
    foreach ($ven in $venKeys) {
        $instances = Get-ChildItem -Path $ven.PSPath -ErrorAction SilentlyContinue
        
        foreach ($inst in $instances) {
            $irqMgmtPath  = "$($inst.PSPath)\Device Parameters\Interrupt Management"
            $msiPath      = "$irqMgmtPath\MessageSignaledInterruptProperties"
            $affinityPath = "$irqMgmtPath\Affinity Policy"
            
            if (Test-Path $msiPath) {
                $instProps = Get-ItemProperty -Path $inst.PSPath -Name "FriendlyName", "DeviceDesc", "Service", "Class" -ErrorAction SilentlyContinue
                $devName   = $instProps.FriendlyName
                if (-not $devName) { $devName = $instProps.DeviceDesc }
                if ($devName -match ";([^;]+)$") { $devName = $matches[1] }
                if (-not $devName) { $devName = "Unknown PCI Device" }

                $svcName  = [string]$instProps.Service
                $devClass = [string]$instProps.Class
                
                $msiVal = (Get-ItemProperty -Path $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                $isMsiEnabled = ($msiVal -eq 1)

                $prioVal   = $null
                $policyVal = $null
                $maskBytes = $null
                if (Test-Path $affinityPath) {
                    $affProps  = Get-ItemProperty -Path $affinityPath -ErrorAction SilentlyContinue
                    if ($null -ne $affProps) {
                        $prioVal   = $affProps.InterruptPriority
                        $policyVal = $affProps.DevicePolicy
                        $maskBytes = $affProps.AssignmentSetOverride
                    }
                }

                $prioLabel = switch ($prioVal) {
                    1 { "Low" }
                    2 { "Normal" }
                    3 { "High" }
                    default { "Default" }
                }

                $affLabel = "Default"
                [uint64]$maskInt = 0
                if ($policyVal -eq 4 -and $null -ne $maskBytes -and $maskBytes.Length -ge 1) {
                    for ($b = 0; $b -lt [math]::Min(8, $maskBytes.Length); $b++) {
                        $maskInt = $maskInt -bor ([uint64]$maskBytes[$b] -shl ($b * 8))
                    }
                    $coreHint = if ($maskInt -eq $core1Mask) { " (C1)" } elseif (($maskInt -band $core0Mask) -ne 0) { " (C0)" } else { "" }
                    $affLabel = "0x$($maskInt.ToString('X'))$coreHint"
                } elseif ($policyVal -eq 5) {
                    $affLabel = "Spread"
                }

                $isOnCore0 = ($policyVal -ne 5) -and (($policyVal -ne 4) -or (($maskInt -band $core0Mask) -ne 0))
                $isGpu     = ($devClass -match '^(?i)Display$' -or $svcName -match '^(?i)(nvlddmkm|amdkmdag|amdwddmg|igfx)$' -or $devName -match '(?i)(GeForce|Radeon|Arc )')
                $isNic     = ($devClass -match '^(?i)Net$' -or $devName -match '(?i)(Ethernet|GbE|Network|Wi-Fi|Wireless|I225|I226|Killer|Realtek PCIe)')
                $isUsb     = ($devClass -match '^(?i)USB$' -or $svcName -match '^(?i)(USBXHCI|USB4|usbuhci|usbehci)$' -or $devName -match '(?i)(eXtensible Host|USB4)')
                $isStorage = ($policyVal -eq 5 -or $svcName -match '^(?i)(stornvme|secnvme|storahci|iaStor)' -or $devName -match '(?i)(NVM Express|SATA AHCI)')

                $sortRank      = 50
                $adviceText    = "Standard PCI Bus"
                $isRecommended = $false
                $drvTag        = if ($svcName) { "$svcName.sys" } else { "pci.sys" }

                if ($isGpu) {
                    if ($isOnCore0) {
                        $sortRank      = 1
                        $isRecommended = $true
                        $adviceText    = "★ OFFLOAD TO C1 (Heavy GPU DPC)"
                    } else {
                        $sortRank      = 10
                        $adviceText    = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isNic) {
                    if ($isOnCore0) {
                        $sortRank      = 2
                        $isRecommended = $true
                        $adviceText    = "★ OFFLOAD TO C1 (NDIS Network DPC)"
                    } else {
                        $sortRank      = 11
                        $adviceText    = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isUsb) {
                    if ($isOnCore0) {
                        $sortRank   = 3
                        $adviceText = "Optional C1 (USB HID Polling)"
                    } else {
                        $sortRank   = 12
                        $adviceText = "✓ Offloaded ($affLabel)"
                    }
                } elseif ($isStorage) {
                    $sortRank   = 40
                    $adviceText = "Keep Spread (Multi-Queue I/O)"
                }

                $msiBadge = if ($isMsiEnabled) { "ON" } else { "OFF" }

                $results.Add([PSCustomObject]@{
                    UIDisplayName        = "$devName [MSI: $msiBadge | Prio: $prioLabel | Mask: $affLabel | $adviceText]"
                    MsiStatus            = $msiBadge
                    RawDeviceName        = $devName
                    ServiceName          = $svcName
                    DriverTag            = $drvTag
                    PrioLabel            = $prioLabel
                    AffinityLabel        = $affLabel
                    AdviceText           = $adviceText
                    IsDetected           = $isMsiEnabled
                    IsRecommendedOffload = $isRecommended
                    SortRank             = $sortRank
                    Priority             = $prioVal
                    DevicePolicy         = $policyVal
                    ActionData           = @{
                        Path         = $msiPath
                        AffinityPath = $affinityPath
                        DevicePath   = $inst.PSPath
                    }
                })
            }
        }
    }
    
    return @($results | Sort-Object SortRank, RawDeviceName)
}

function Get-HardwareState_WHEA {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $nativeCores = @([WinUltix.CpuTopology]::GetProcessorCores())
    $smtEnabled = if ($nativeCores.Count -gt 0) { ([Environment]::ProcessorCount -gt $nativeCores.Count) } else { $true }

    try {
        if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }
        $events = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -MaxEvents 500 -ErrorAction Stop)
        $totalEvents = $events.Count
        $idx = 0

        foreach ($evt in $events) {
            $idx++
            if ($null -ne $UltixSync -and $totalEvents -gt 0 -and ($idx % 10 -eq 0 -or $idx -eq $totalEvents)) {
                $UltixSync.Progress = 25 + [int](($idx / $totalEvents) * 75)
            }

            $apicId = "N/A"
            $coreInfo = ""
            $msg = $evt.Message
            $id = $evt.Id

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
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-HardwareState_Network {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # 0. Global TCP/IP Stack Settings
    $globalOffload = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($globalOffload) {
        $isGlobalRssOpt = ($globalOffload.ReceiveSideScaling -eq 'Enabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Receive-Side Scaling (RSS)"; IsOptimized = $isGlobalRssOpt; ActionData = @{ Type="GlobalRSS" } })
        
        $isGlobalRscOpt = ($globalOffload.ReceiveSegmentCoalescing -eq 'Disabled')
        $results.Add([PSCustomObject]@{ UIDisplayName = "[Global] TCP Recv Segment Coalescing (RSC)"; IsOptimized = $isGlobalRscOpt; ActionData = @{ Type="GlobalRSC" } })
    }

    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
    $totalAdapters = [math]::Max(1, $adapters.Count)
    $adapterIdx = 0

    foreach ($adapter in $adapters) {
        $adapterIdx++
        $baseProg = 15 + [int]((($adapterIdx - 1) / $totalAdapters) * 80)
        if ($null -ne $UltixSync) { $UltixSync.Progress = $baseProg }

        $name = $adapter.Name
        $statusSuffix = if ($adapter.Status -ne 'Up') { " (Offline)" } else { "" }
        $adapterDispName = "$name$statusSuffix"
        
        # 1. TCP NoDelay & AckFrequency
        $tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
        $tcpNoDelay = (Get-ItemProperty -Path $tcpPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay
        $tcpAck = (Get-ItemProperty -Path $tcpPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency
        $isTcpOpt = ($tcpNoDelay -eq 1 -and $tcpAck -eq 1)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] TCPNoDelay & AckFrequency"; IsOptimized = $isTcpOpt; ActionData = @{ Type="TCP"; AdapterName=$name; InterfaceGuid=$adapter.InterfaceGuid } })

        # 2. Power Management (Registry PnPCapabilities)
        $enumPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($adapter.PnPDeviceID)"
        $caps = (Get-ItemProperty -Path $enumPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
        $isPowerOpt = ($caps -eq 24)
        $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Power Management (Sleep)"; IsOptimized = $isPowerOpt; ActionData = @{ Type="Power"; RegPath=$enumPath; InterfaceGuid=$adapter.InterfaceGuid } })

        # 3. NDIS Advanced Properties (Single CIM query per adapter + exact -eq match to prevent *EEE wildcard collisions)
        $ndisTweaks = [ordered]@{
            "*InterruptModeration" = @{ Opt = "0";    Def = "1" }
            "*FlowControl"         = @{ Opt = "0";    Def = "3" }
            "*JumboPacket"         = @{ Opt = "1514"; Def = "1514" }
            "*EEE"                 = @{ Opt = "0";    Def = "1" }
            "EEELinkAdvertisement" = @{ Opt = "0";    Def = "1" }
            "AdvancedEEE"          = @{ Opt = "0";    Def = "1" }
            "EnableGreenEthernet"  = @{ Opt = "0";    Def = "1" }
            "PowerSavingMode"      = @{ Opt = "0";    Def = "1" }
        }
        $allAdvProps = @(Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue)
        foreach ($key in $ndisTweaks.Keys) {
            $prop = $allAdvProps | Where-Object { $_.RegistryKeyword -eq $key } | Select-Object -First 1
            if ($null -ne $prop) {
                $optVal = $ndisTweaks[$key].Opt
                $defVal = $ndisTweaks[$key].Def
                $curVal = [string]($prop.RegistryValue | Select-Object -First 1)
                $isNdisOpt = ($curVal -eq $optVal)
                $propDispName = [string]$prop.DisplayName
                $results.Add([PSCustomObject]@{
                    UIDisplayName = "[$adapterDispName] NDIS: $propDispName"
                    IsOptimized   = $isNdisOpt
                    ActionData    = @{
                        Type          = "NDIS"
                        AdapterName   = $name
                        InterfaceGuid = $adapter.InterfaceGuid
                        Key           = $key
                        Value         = $optVal
                        DefaultValue  = $defVal
                    }
                })
            }
        }

        if ($null -ne $UltixSync) { $UltixSync.Progress = [math]::Min(95, $baseProg + 40) }

        # 4. Offloads & RSS
        $rss = Get-NetAdapterRss -Name $name -ErrorAction SilentlyContinue
        if ($rss) { 
            $isRssOpt = ([bool]$rss.Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Receive Side Scaling (RSS)"; IsOptimized = $isRssOpt; ActionData = @{ Type="RSS"; AdapterName=$name } }) 
        }

        $rsc = Get-NetAdapterRsc -Name $name -ErrorAction SilentlyContinue
        if ($rsc) { 
            $isRscOpt = ([bool]$rsc.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Recv Segment Coalescing (RSC)"; IsOptimized = $isRscOpt; ActionData = @{ Type="RSC"; AdapterName=$name } }) 
        }

        $lso = Get-NetAdapterLso -Name $name -ErrorAction SilentlyContinue
        if ($lso) { 
            $isLsoOpt = ([bool]$lso.IPv4Enabled -eq $false)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Large Send Offload (LSO)"; IsOptimized = $isLsoOpt; ActionData = @{ Type="LSO"; AdapterName=$name } }) 
        }

        $cso = Get-NetAdapterChecksumOffload -Name $name -ErrorAction SilentlyContinue
        if ($cso) { 
            $isCsoOpt = ([bool]$cso.IpIPv4Enabled -eq $true -and [bool]$cso.TcpIPv4Enabled -eq $true)
            $results.Add([PSCustomObject]@{ UIDisplayName = "[$adapterDispName] Checksum Offload (CSO)"; IsOptimized = $isCsoOpt; ActionData = @{ Type="CSO"; AdapterName=$name } }) 
        }
    }
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-HardwareState_Timer {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
    $val = (Get-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
    $isGlobalOpt = ($null -ne $val -and $val -eq 1)
    $results.Add([PSCustomObject]@{ UIDisplayName = "Global Timer Resolution (Kernel Fix)"; IsOptimized = $isGlobalOpt; ActionData = @{ Type="Reg"; Path=$regPath; Name="GlobalTimerResolutionRequests"; Value=1 } })
    
    $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
    if ($null -ne $hpet) {
        $isHpetDisabled = ($hpet.ConfigManagerErrorCode -eq 22)
        $results.Add([PSCustomObject]@{ UIDisplayName = "Disable HPET (Device Manager)"; IsOptimized = $isHpetDisabled; ActionData = @{ Type="PNP"; Instance=$hpet.InstanceId } })
    }

    $bcd = (bcdedit.exe /enum "{current}" 2>$null) -join " "
    
    $dynTickOpt = ($bcd -match "(?i)disabledynamictick\s+(Yes|Tak|True|1)")
    $results.Add([PSCustomObject]@{ UIDisplayName = "Disable Dynamic Tick (Power Saving)"; IsOptimized = $dynTickOpt; ActionData = @{ Type="BCD"; Cmd="disabledynamictick yes" } })
    
    $platClockOpt = ($bcd -match "(?i)useplatformclock\s+(No|Nie|False|0)")
    $results.Add([PSCustomObject]@{ UIDisplayName = "Disable Platform Clock (Force TSC)"; IsOptimized = $platClockOpt; ActionData = @{ Type="BCD"; Cmd="useplatformclock no" } })
	
    return @($results)
}

function Get-CurrentTimerResolution {
    $data = [WinUltix.NtDll]::GetTimerData()
    return [PSCustomObject]@{
        DefaultMs = [math]::Round($data[0] / 10000.0, 4)
        LimitMs   = [math]::Round($data[1] / 10000.0, 4)
        CurrentMs = [math]::Round($data[2] / 10000.0, 4)
    }
}

function Get-HardwareState_NVMe {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $pciPath = "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters"
    $aspm = (Get-ItemProperty -Path $pciPath -Name "DisableASPM" -ErrorAction SilentlyContinue).DisableASPM
    $isAspmOpt = ($null -ne $aspm -and $aspm -eq 1)
    $results.Add([PSCustomObject]@{ UIDisplayName = "PCIe ASPM Global Bus Lock (DisableASPM)"; IsOptimized = $isAspmOpt; ActionData = @{ Type="Reg"; Path=$pciPath; Name="DisableASPM"; Val=1 } })

    $nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
    $nvmeIdle = (Get-ItemProperty -Path $nvmePath -Name "IdlePowerMode" -ErrorAction SilentlyContinue).IdlePowerMode
    $isNvmeIdleOpt = ($null -ne $nvmeIdle -and $nvmeIdle -eq 0)
    $results.Add([PSCustomObject]@{ UIDisplayName = "StorNVMe APST Driver Lock (IdlePowerMode)"; IsOptimized = $isNvmeIdleOpt; ActionData = @{ Type="Reg"; Path=$nvmePath; Name="IdlePowerMode"; Val=0 } })

    $mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
    $isMemOpt = ($null -ne $mmAgent -and $mmAgent.MemoryCompression -eq $false)
    $results.Add([PSCustomObject]@{ UIDisplayName = "System Memory Compression (MMAgent)"; IsOptimized = $isMemOpt; ActionData = @{ Type="MMAgent" } })

    return @($results)
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

function Set-UltixCPPCState {
    param([Parameter(Mandatory=$true)][ValidateSet('Engage', 'Release')][string]$Mode)
    $p = 'HKLM:\SOFTWARE\WinUltix\CPPC'

    if ($Mode -eq 'Engage') {
        if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
        $e  = Get-UltixPowerAcIndex -SettingGuid '36687f9e-e3a5-4dbf-b1dc-15eb381c6863' -IncludeHidden
        $d  = Get-UltixPowerAcIndex -SettingGuid '4b92d758-5a24-4851-a470-815d78aee119' -IncludeHidden
        $pr = Get-UltixPowerAcIndex -SettingGuid '7b224883-b3cc-4d79-819f-8374152cbe7c' -IncludeHidden

        # Only archive when current values are neither already Engaged (0/100/100) nor corrupted all-zeros (0/0/0)
        if ($null -ne $e -and -not ($e -eq 0 -and $d -eq 100 -and $pr -eq 100) -and -not ($e -eq 0 -and $d -eq 0 -and $pr -eq 0)) {
            Set-ItemProperty -Path $p -Name 'EPP' -Value $e -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Demote' -Value $d -Type DWord -Force
            Set-ItemProperty -Path $p -Name 'Promote' -Value $pr -Type DWord -Force
        }

        $tsCmd = "`$p='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path `$p){ `$r=Get-ItemProperty `$p; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
        $tsAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -Command `"$tsCmd`""
        $tsTriggers = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogon))
        $tsPrincipal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Action $tsAction -Trigger $tsTriggers -Principal $tsPrincipal -Force | Out-Null

        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 0
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 100
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c 100
        powercfg.exe /setactive SCHEME_CURRENT
        Write-GUI " -> Engaged Max CPPC (EPP 0%, Demote/Promote 100%). Dead Man's Switch armed."
    } else {
        $e = 50; $d = 40; $pr = 60
        if (Test-Path $p) {
            $reg = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($null -ne $reg.EPP -and $null -ne $reg.Demote -and $null -ne $reg.Promote) {
                # Self-heal if previous regex bug stored 0/0/0 into backup key
                if ($reg.EPP -eq 0 -and $reg.Demote -eq 0 -and $reg.Promote -eq 0) {
                    Remove-ItemProperty -Path $p -Name 'EPP', 'Demote', 'Promote' -Force -ErrorAction SilentlyContinue
                } else {
                    $e  = $reg.EPP
                    $d  = $reg.Demote
                    $pr = $reg.Promote
                }
            }
        }
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 $e
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 $d
        powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c $pr
        powercfg.exe /setactive SCHEME_CURRENT
        
        Unregister-ScheduledTask -TaskName "WinUltix_CPPC_Failsafe" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-GUI " -> Released CPPC lock (Restored EPP: $e%, Demote: $d%, Promote: $pr%). Failsafe disarmed."
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

function Update-NetworkModalList {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Modal,
        [Parameter(Mandatory=$true)][System.Windows.Forms.CheckedListBox]$ChkList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.ArrayList]$LocalData,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable
    )

    if ($Modal.IsDisposed -or $ChkList.IsDisposed) { return }

    $uiModal     = $Modal
    $uiChkList   = $ChkList
    $uiLocalData = $LocalData

    $uiChkList.Items.Clear()
    $uiLocalData.Clear()
    [void]$uiChkList.Items.Add("Scanning physical adapters & NDIS properties in background...", $false)

    $sb = (Get-Command -Name Get-HardwareState_Network).ScriptBlock
    Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $ControlsToDisable -OnComplete ({
        param($output)
        Update-Progress 0
        if ($null -eq $uiModal -or $uiModal.IsDisposed -or $null -eq $uiChkList -or $uiChkList.IsDisposed) { return }

        $uiChkList.BeginUpdate()
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
        $uiChkList.EndUpdate()
    }.GetNewClosure())
}

function Start-NetworkOptimizationAsync {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Mode = 'Apply',
        [Parameter(Mandatory=$true)][System.Windows.Forms.Form]$Modal,
        [Parameter(Mandatory=$true)][System.Windows.Forms.CheckedListBox]$ChkList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][System.Collections.ArrayList]$LocalData,
        [AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    if ($SelectedItems.Count -eq 0) {
        Write-GUI " -> No network items selected."
        return
    }

    $uiModal     = $Modal
    $uiChkList   = $ChkList
    $uiLocalData = $LocalData
    $uiButtons   = $ControlsToDisable
    $verb        = if ($Mode -eq 'Apply') { "Optimization" } else { "Revert" }

    Write-GUI " -> Dispatching network adapter $verb worker to background Runspace..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $uiButtons -Arguments @($SelectedItems, $Mode) -ScriptBlock {
        param([array]$Items, [string]$Operation)

        $total = $Items.Count
        $current = 0
        $backupRoot = "HKLM:\SOFTWARE\WinUltix\Network_Backup"

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 80)
            }

            $data = $item.ActionData
            $name = if ($data.ContainsKey("AdapterName")) { $data.AdapterName } elseif ($null -ne $data.Adapter) { $data.Adapter.Name } else { "" }
            $guid = if ($data.ContainsKey("InterfaceGuid")) { $data.InterfaceGuid } elseif ($null -ne $data.Adapter) { $data.Adapter.InterfaceGuid } else { "Global" }
            $bKey = "$backupRoot\$guid"

            if ($Operation -eq 'Apply') {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Optimizing: $($item.UIDisplayName)") }
                try {
                    switch ($data.Type) {
                        "GlobalRSS" { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction Stop }
                        "GlobalRSC" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction Stop }
                        "TCP" {
                            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
                            New-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null
                            New-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -PropertyType DWORD -Force -ErrorAction Stop | Out-Null 
                        }
                        "Power" {
                            if (-not (Test-Path -LiteralPath $bKey)) { New-Item -Path $bKey -Force | Out-Null }
                            if ($null -eq (Get-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities) {
                                $oldPnp = (Get-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
                                if ($null -eq $oldPnp) { $oldPnp = -1 }
                                Set-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -Value $oldPnp -Type DWord -Force
                            }
                            Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value 24 -Type DWord -Force -ErrorAction Stop
                        }
                        "NDIS" {
                            if (-not (Test-Path -LiteralPath $bKey)) { New-Item -Path $bKey -Force | Out-Null }
                            $targetProp = Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                                Where-Object { $_.RegistryKeyword -eq $data.Key } |
                                Select-Object -First 1

                            if ($null -ne $targetProp) {
                                $curVal = [string]($targetProp.RegistryValue | Select-Object -First 1)
                                if ($null -eq (Get-ItemProperty -LiteralPath $bKey -Name $data.Key -ErrorAction SilentlyContinue).$($data.Key)) {
                                    if (-not [string]::IsNullOrWhiteSpace($curVal)) {
                                        Set-ItemProperty -LiteralPath $bKey -Name $data.Key -Value $curVal -Type String -Force
                                    }
                                }
                                $targetProp | Set-NetAdapterAdvancedProperty -RegistryValue $data.Value -NoRestart -ErrorAction Stop
                            }
                        }
                        "RSS"  { Enable-NetAdapterRss -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "RSC"  { Disable-NetAdapterRsc -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "LSO"  { Disable-NetAdapterLso -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "CSO"  { Enable-NetAdapterChecksumOffload -Name $name -IpIPv4 -TcpIPv4 -UdpIPv4 -NoRestart -ErrorAction SilentlyContinue }
                    }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to apply: $($item.UIDisplayName) ($($_.Exception.Message))") }
                }
            } else {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue(" -> Reverting to Default: $($item.UIDisplayName)") }
                try {
                    switch ($data.Type) {
                        "GlobalRSS" { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction Stop }
                        "GlobalRSC" { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Enabled -ErrorAction Stop }
                        "TCP" {
                            $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
                            Remove-ItemProperty -Path $path -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -Path $path -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
                        }
                        "Power" {
                            $oldPnp = (Get-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -ErrorAction SilentlyContinue).PnPCapabilities
                            if ($null -ne $oldPnp) {
                                if ($oldPnp -eq -1 -or $oldPnp -eq 4294967295) {
                                    Remove-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Force -ErrorAction SilentlyContinue
                                } else {
                                    Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value $oldPnp -Type DWord -Force -ErrorAction SilentlyContinue
                                }
                                Remove-ItemProperty -LiteralPath $bKey -Name "PnPCapabilities" -Force -ErrorAction SilentlyContinue
                            } else {
                                Set-ItemProperty -LiteralPath $data.RegPath -Name "PnPCapabilities" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                            }
                        }
                        "NDIS" {
                            $savedVal = (Get-ItemProperty -LiteralPath $bKey -Name $data.Key -ErrorAction SilentlyContinue).$($data.Key)
                            $targetVal = if (-not [string]::IsNullOrWhiteSpace($savedVal)) { $savedVal } else { $data.DefaultValue }
                            $targetProp = Get-NetAdapterAdvancedProperty -Name $name -ErrorAction SilentlyContinue |
                                Where-Object { $_.RegistryKeyword -eq $data.Key } |
                                Select-Object -First 1

                            if ($null -ne $targetProp) {
                                $targetProp | Set-NetAdapterAdvancedProperty -RegistryValue $targetVal -NoRestart -ErrorAction Stop
                            }
                            if (Test-Path -LiteralPath $bKey) {
                                Remove-ItemProperty -LiteralPath $bKey -Name $data.Key -Force -ErrorAction SilentlyContinue
                            }
                        }
                        "RSS"  { Enable-NetAdapterRss -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "RSC"  { Enable-NetAdapterRsc -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "LSO"  { Enable-NetAdapterLso -Name $name -NoRestart -ErrorAction SilentlyContinue }
                        "CSO"  { Enable-NetAdapterChecksumOffload -Name $name -IpIPv4 -TcpIPv4 -UdpIPv4 -NoRestart -ErrorAction SilentlyContinue }
                    }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to revert: $($item.UIDisplayName) ($($_.Exception.Message))") }
                }
            }
        }

        $touchedAdapters = @($Items | ForEach-Object { $_.ActionData.AdapterName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        foreach ($aName in $touchedAdapters) {
            Restart-NetAdapter -Name $aName -ErrorAction SilentlyContinue
        }

        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue(" -> Waiting for NDIS adapter re-initialization (2s)...")
            $UltixSync.Progress = 95
        }
        Start-Sleep -Seconds 2
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete ({
        Update-Progress 0
        Write-GUI " -> Network adapter $verb completed.`n"
        Update-NetworkModalList -Modal $uiModal -ChkList $uiChkList -LocalData $uiLocalData -ControlsToDisable $uiButtons
    }.GetNewClosure())
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
# Z7: PROFILE SNAPSHOT INTEGRATION (EXPORT / IMPORT)
# ------------------------------------------
function Export-UltixHardwareSnapshot {
    $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
    $affinityRoster = if (Test-Path $affPath) {
        @((Get-ItemProperty -Path $affPath -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -match '\.exe$' } |
            Select-Object -ExpandProperty Name)
    } else { @() }

    $cppcUnhidden = @(Get-HardwareState_CPPC | Where-Object { -not $_.IsDetected } | ForEach-Object { $_.ActionData.KeyId })
    $timerTweaks  = @(Get-HardwareState_Timer | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)
    $nvmeTweaks   = @(Get-HardwareState_NVMe  | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)

    $globalNet = [System.Collections.Generic.List[string]]::new()
    $globalOffload = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($null -ne $globalOffload) {
        if ($globalOffload.ReceiveSideScaling -eq 'Enabled')         { $globalNet.Add("[Global] TCP Receive-Side Scaling (RSS)") }
        if ($globalOffload.ReceiveSegmentCoalescing -eq 'Disabled')  { $globalNet.Add("[Global] TCP Recv Segment Coalescing (RSC)") }
    }

    return [ordered]@{
        AffinityLasso = @($affinityRoster)
        CPPCUnhidden  = @($cppcUnhidden)
        TimerTweaks   = @($timerTweaks)
        NVMeTweaks    = @($nvmeTweaks)
        GlobalNetwork = @($globalNet)
    }
}

function Import-UltixHardwareSnapshot {
    param([Parameter(Mandatory=$true)]$ProfileData)

    $affList = @($ProfileData.AffinityLasso)
    if ($affList.Count -gt 0) {
        $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
        if (-not (Test-Path $affPath)) { New-Item -Path $affPath -Force | Out-Null }
        foreach ($exe in $affList) {
            Set-ItemProperty -Path $affPath -Name $exe -Value 1 -Type DWord -Force
        }
        Write-GUI " -> Restored $($affList.Count) process(es) to Affinity Lasso roster."
    }

    $hwLocks = $ProfileData.HardwareLocks
    if ($null -eq $hwLocks) { return }

    if (@($hwLocks.CPPCUnhidden).Count -gt 0) {
        $cppcSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($k in $hwLocks.CPPCUnhidden) { [void]$cppcSet.Add([string]$k) }
        $toUnhide = @(Get-HardwareState_CPPC | Where-Object { $cppcSet.Contains($_.ActionData.KeyId) -and $_.IsDetected })
        if ($toUnhide.Count -gt 0) { Invoke-ApplyCPPC -SelectedItems $toUnhide }
    }

    if (@($hwLocks.TimerTweaks).Count -gt 0) {
        $timerSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $hwLocks.TimerTweaks) { [void]$timerSet.Add([string]$t) }
        $toApplyTimer = @(Get-HardwareState_Timer | Where-Object { $timerSet.Contains($_.UIDisplayName) -and -not $_.IsOptimized })
        if ($toApplyTimer.Count -gt 0) { Invoke-ApplyTimerTweaks -SelectedItems $toApplyTimer }
    }

    if (@($hwLocks.NVMeTweaks).Count -gt 0) {
        $nvmeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($n in $hwLocks.NVMeTweaks) { [void]$nvmeSet.Add([string]$n) }
        $toApplyNvme = @(Get-HardwareState_NVMe | Where-Object { $nvmeSet.Contains($_.UIDisplayName) -and -not $_.IsOptimized })
        if ($toApplyNvme.Count -gt 0) { Invoke-ApplyNVMeTweaks -SelectedItems $toApplyNvme }
    }

    if (@($hwLocks.GlobalNetwork).Count -gt 0) {
        foreach ($gNet in $hwLocks.GlobalNetwork) {
            if ($gNet -match "RSS") { Set-NetOffloadGlobalSetting -ReceiveSideScaling Enabled -ErrorAction SilentlyContinue }
            if ($gNet -match "RSC") { Set-NetOffloadGlobalSetting -ReceiveSegmentCoalescing Disabled -ErrorAction SilentlyContinue }
        }
        Write-GUI " -> Enforced Global TCP RSS/RSC offload profile."
    }
}

# ------------------------------------------
# Z7: DEDICATED HARDWARE MODALS
# ------------------------------------------
function Show-AffinityModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 720); $modal.MinimumSize = New-Object System.Drawing.Size(850, 720); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh List" -X 715 -Y 15 -Width 100 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 480); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $listView.Font = New-Object System.Drawing.Font("Consolas", 11.5)
    $listView.Anchor = 'Top, Bottom, Left, Right'
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true; $listView.FullRowSelect = $true; $listView.GridLines = $true
    Enable-UltixDoubleBuffer -Control $listView

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
    $btnAddExe = New-UltixButton -Parent $modal -Text "+ Add Custom .exe" -X 275 -Y 554 -Width 140 -Height 27 -RGB @(60, 60, 60)
    $btnAddExe.Anchor = 'Bottom, Left'
    $btnAddExe.Add_Click({
        $exe = $txtCustom.Text.Trim()
        if ($exe -ne "" -and $exe -match "\.exe$") {
            $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
            if (-not (Test-Path $configPath)) { New-Item -Path $configPath -Force | Out-Null }
            Set-ItemProperty -Path $configPath -Name $exe -Value 1 -Type DWord -Force | Out-Null
            $txtCustom.Text = ""
            &$refreshData 
        } else { [System.Windows.Forms.MessageBox]::Show("Process must end with .exe", "Invalid Input") }
    }.GetNewClosure())

    $btnDelExe = New-UltixButton -Parent $modal -Text "- Remove Selected" -X 425 -Y 554 -Width 140 -Height 27 -RGB @(100, 60, 60)
    $btnDelExe.Anchor = 'Bottom, Left'
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

    $btnSave = New-UltixButton -Parent $modal -Text "Save Roster" -X 15 -Y 595 -Width 150 -Height 35 -RGB @(60, 100, 150)
    $btnSave.Anchor = 'Bottom, Left'
    $btnSave.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $false }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $false -KeepConfig $false }
        &$refreshData
    }.GetNewClosure())

    $btnEngage = New-UltixButton -Parent $modal -Text "ENGAGE (Lock)" -X 175 -Y 595 -Width 150 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        $delta = &$getDelta
        if ($delta.Apply.Count -gt 0) { Set-AppAffinity -SelectedItems $delta.Apply -Execute $true }
        if ($delta.Remove.Count -gt 0) { Remove-AppAffinity -SelectedItems $delta.Remove -Execute $true -KeepConfig $false }
        
        $allItems = @()
        for ($i = 0; $i -lt $listView.Items.Count; $i++) { if ($listView.Items[$i].Checked) { $allItems += $localData[$i] } }
        if ($allItems.Count -gt 0) { Set-AppAffinity -SelectedItems $allItems -Execute $true }
        &$refreshData 
    }.GetNewClosure())

    $btnRelease = New-UltixButton -Parent $modal -Text "RELEASE (Unlock)" -X 335 -Y 595 -Width 150 -Height 35 -RGB @(150, 100, 60)
    $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        Remove-AppAffinity -SelectedItems $localData -Execute $true -KeepConfig $true
        &$refreshData 
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 495 -Y 595 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $lblTip = New-Object System.Windows.Forms.Label
    $lblTip.Text = "INFO: 'Save Roster' stores your preset in the registry. You can instantly apply it later before gaming using the 'Pre-Flight' desktop shortcut."
    $lblTip.Location = New-Object System.Drawing.Point(15, 640)
    $lblTip.Size = New-Object System.Drawing.Size(800, 25)
    $lblTip.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $lblTip.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTip.Anchor = 'Bottom, Left'

    $modal.Controls.AddRange(@($lblDesc, $listView, $txtCustom, $lblTip))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-CPPCModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 450); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 450)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 60); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightGreen; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_CPPC
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if (-not $item.IsDetected) {
                [void]$chkList.Items.Add("[ UNHIDDEN ] " + $item.UIDisplayName, $false)
            } else {
                [void]$chkList.Items.Add("[ HIDDEN ]   " + $item.UIDisplayName, $true)
            }
        }
    }
    &$refreshData 

    $btnUnhide = New-UltixButton -Parent $modal -Text "Unhide Checked" -X 15 -Y 355 -Width 120 -Height 35 -RGB @(60, 100, 150)
    $btnUnhide.Anchor = 'Bottom, Left'
    $btnUnhide.Add_Click({
        $toUnhide = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i)) { $toUnhide += $localData[$i] }
        }
        if ($toUnhide.Count -gt 0) { Invoke-ApplyCPPC -SelectedItems $toUnhide }
        &$refreshData 
    }.GetNewClosure())

    $btnEngage = New-UltixButton -Parent $modal -Text "ENGAGE Max CPPC" -X 145 -Y 355 -Width 150 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
    $btnEngage.Add_Click({
        Set-UltixCPPCState -Mode 'Engage'
        &$refreshData
    }.GetNewClosure())

    $btnRelease = New-UltixButton -Parent $modal -Text "RELEASE CPPC" -X 305 -Y 355 -Width 130 -Height 35 -RGB @(150, 100, 60)
    $btnRelease.Anchor = 'Bottom, Left'
    $btnRelease.Add_Click({
        Set-UltixCPPCState -Mode 'Release'
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 445 -Y 355 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-MsiModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(920, 660); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(880, 620)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 10); $lblDesc.Size = New-Object System.Drawing.Size(875, 24); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply new MSI vectors, Interrupt Priority, and Core Affinity."; $lblWarning.Location = New-Object System.Drawing.Point(15, 36); $lblWarning.Size = New-Object System.Drawing.Size(875, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblDpcMonitor = New-Object System.Windows.Forms.Label
    $lblDpcMonitor.Location = New-Object System.Drawing.Point(15, 60)
    $lblDpcMonitor.Size = New-Object System.Drawing.Size(875, 68)
    $lblDpcMonitor.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblDpcMonitor.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblDpcMonitor.Font = New-Object System.Drawing.Font("Consolas", 9.2, [System.Drawing.FontStyle]::Bold)
    $lblDpcMonitor.TextAlign = "TopLeft"
    $lblDpcMonitor.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 4)
    $lblDpcMonitor.BorderStyle = "FixedSingle"
    $lblDpcMonitor.Anchor = 'Top, Left, Right'

    $lblDpcLegend = New-Object System.Windows.Forms.Label
    $lblDpcLegend.Text = "Legend: C0..Cn = Physical Cores (SMT: C0=LP#0-1, C1=LP#2-3) | Green (<30% C0 Optimal), Yellow (30-54%), Red (>=55% C0 Bottleneck - Offload ★ items)"
    $lblDpcLegend.Location = New-Object System.Drawing.Point(15, 131)
    $lblDpcLegend.Size = New-Object System.Drawing.Size(875, 18)
    $lblDpcLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
    $lblDpcLegend.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcLegend.Anchor = 'Top, Left, Right'

    $dpcState = @{ PrevCounts = $null; IsRunning = $true; LastSnap = $null }
    Update-UltixDpcMonitorUI -TargetLabel $lblDpcMonitor -State $dpcState

    $dpcTimer = New-Object System.Windows.Forms.Timer
    $dpcTimer.Interval = 1000
    $dpcTimer.Tag = @{
        Modal = $modal
        Label = $lblDpcMonitor
        State = $dpcState
    }
    $dpcTimer.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State
    })
    $dpcTimer.Start()

    $lblPrio = New-Object System.Windows.Forms.Label
    $lblPrio.Text = "Interrupt Priority:"
    $lblPrio.Location = New-Object System.Drawing.Point(15, 156)
    $lblPrio.Size = New-Object System.Drawing.Size(112, 22)
    $lblPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblPrio.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $comboPrio = New-Object System.Windows.Forms.ComboBox
    $comboPrio.Location = New-Object System.Drawing.Point(128, 153)
    $comboPrio.Size = New-Object System.Drawing.Size(165, 25)
    $comboPrio.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $comboPrio.ForeColor = [System.Drawing.Color]::White
    $comboPrio.DropDownStyle = "DropDownList"
    $comboPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    [void]$comboPrio.Items.AddRange(@("Keep Current", "High (3)", "Normal (2)", "Low (1)", "Undefined (Default)"))
    $comboPrio.SelectedIndex = 0

    $chkOffloadCore0 = New-Object System.Windows.Forms.CheckBox
    $chkOffloadCore0.Text = "Offload IRQ from Core 0 (Pin to Secondary Core C1)"
    $chkOffloadCore0.Location = New-Object System.Drawing.Point(305, 154)
    $chkOffloadCore0.Size = New-Object System.Drawing.Size(340, 24)
    $chkOffloadCore0.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $chkOffloadCore0.ForeColor = [System.Drawing.Color]::LightGray
    $chkOffloadCore0.Checked = $false

    $btnSelRec = New-UltixButton -Parent $modal -Text "Select ★ GPU/NIC" -X 695 -Y 152 -Width 195 -Height 27 -RGB @(50, 85, 120)
    $btnSelRec.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btnSelRec.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 186)
    $listView.Size = New-Object System.Drawing.Size(875, 355)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 42, 42, 42)
    $listView.ForeColor = [System.Drawing.Color]::LightGreen
    $listView.Font = New-Object System.Drawing.Font("Consolas", 9.8)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.Anchor = 'Top, Bottom, Left, Right'
    Enable-UltixDoubleBuffer -Control $listView

    $sorter = New-Object WinUltix.ListViewColumnSorter
    $listView.ListViewItemSorter = $sorter

    [void]$listView.Columns.Add("MSI", 70)
    [void]$listView.Columns.Add("PCI Device Name", 285)
    [void]$listView.Columns.Add("Driver", 110)
    [void]$listView.Columns.Add("Priority", 75)
    [void]$listView.Columns.Add("IRQ Mask", 95)
    [void]$listView.Columns.Add("DPC Assessment / Advice", 215)

    $listView.Add_ColumnClick({
        param($src, $e)
        if ($e.Column -eq $sorter.ColumnToSort) {
            if ($sorter.OrderOfSort -eq [System.Windows.Forms.SortOrder]::Ascending) {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending
            } else {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
            }
        } else {
            $sorter.ColumnToSort = $e.Column
            $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
        }
        $listView.Sort()
    }.GetNewClosure())

    $refreshData = {
        $listView.BeginUpdate()
        $listView.ListViewItemSorter = $null
        $listView.Items.Clear()
        $auditData = Get-HardwareState_IRQ
        foreach ($item in $auditData) {
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.MsiStatus)
            [void]$lvItem.SubItems.Add($item.RawDeviceName)
            [void]$lvItem.SubItems.Add($item.DriverTag)
            [void]$lvItem.SubItems.Add($item.PrioLabel)
            [void]$lvItem.SubItems.Add($item.AffinityLabel)
            [void]$lvItem.SubItems.Add($item.AdviceText)
            $lvItem.Tag = $item
            $lvItem.Checked = (-not $item.IsDetected)

            if ($item.IsRecommendedOffload) {
                $lvItem.ForeColor = [System.Drawing.Color]::Gold
            } elseif (-not $item.IsDetected) {
                $lvItem.ForeColor = [System.Drawing.Color]::LightSkyBlue
            } else {
                $lvItem.ForeColor = [System.Drawing.Color]::LightGreen
            }
            [void]$listView.Items.Add($lvItem)
        }
        $listView.ListViewItemSorter = $sorter
        $listView.EndUpdate()
    }
    &$refreshData

    $btnSelRec.Tag = @{
        ListView   = $listView
        ChkOffload = $chkOffloadCore0
        ComboPrio  = $comboPrio
    }
    $btnSelRec.Add_Click({
        $ctx = $this.Tag
        $lv  = $ctx.ListView
        $lv.BeginUpdate()
        foreach ($lvItem in $lv.Items) {
            $dev = $lvItem.Tag
            $lvItem.Checked = ($null -ne $dev -and [bool]$dev.IsRecommendedOffload)
        }
        $lv.EndUpdate()
        $ctx.ChkOffload.Checked = $true
        if ($ctx.ComboPrio.SelectedIndex -eq 0) { $ctx.ComboPrio.SelectedIndex = 1 }
    })

    $getOffloadMaskBytes = {
        [int64[]]$masks = Get-UltixPhysicalCoreMasks
        [uint64]$maskVal = if ($masks.Count -ge 2) {
            [uint64]$masks[1]
        } else {
            12
        }
        $fullBytes = [BitConverter]::GetBytes($maskVal)
        $len = 8
        while ($len -gt 1 -and $fullBytes[$len - 1] -eq 0) { $len-- }
        [byte[]]$trimmed = New-Object byte[] $len
        [Array]::Copy($fullBytes, 0, $trimmed, 0, $len)
        return ,$trimmed
    }

    $getSafeBackupKeyName = {
        param([string]$FullMsiPath)
        $relPciPath = $FullMsiPath -replace '^(?i).*?\\Enum\\', '' -replace '(?i)\\Device Parameters\\.*$', ''
        $b64Safe = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($relPciPath)).Replace('/', '_')
        if ($b64Safe.Length -gt 240) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($FullMsiPath))).Replace('-', '')
            $md5.Dispose()
            return "PCI_$hash"
        }
        return $b64Safe
    }

    $btnForceMSI = New-UltixButton -Parent $modal -Text "Apply MSI & Policy" -X 15 -Y 555 -Width 180 -Height 35 -RGB @(150, 60, 60)
    $btnForceMSI.Anchor = 'Bottom, Left'
    $btnForceMSI.Add_Click({
        $changed = 0
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        if (-not (Test-Path -LiteralPath $bRoot)) { New-Item -Path $bRoot -Force | Out-Null }
        $prioSelection = [string]$comboPrio.SelectedItem
        $doOffload     = $chkOffloadCore0.Checked
        [byte[]]$offloadBytes = if ($doOffload) { &$getOffloadMaskBytes } else { $null }
        
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev) { continue }
            $msiPath = $dev.ActionData.Path
            $affPath = $dev.ActionData.AffinityPath
            $safeKey = &$getSafeBackupKeyName $msiPath
            $devBackupKey = "$bRoot\$safeKey"
            
            if (-not (Test-Path -LiteralPath $devBackupKey)) {
                New-Item -Path $devBackupKey -Force | Out-Null
                Set-ItemProperty -LiteralPath $devBackupKey -Name "DeviceName" -Value ([string]$dev.RawDeviceName) -Type String -Force
                $oldMsi = (Get-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported
                if ($null -eq $oldMsi) { $oldMsi = 255 }
                Set-ItemProperty -LiteralPath $devBackupKey -Name "MSISupported" -Value $oldMsi -Type DWord -Force

                if (Test-Path -LiteralPath $affPath) {
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "AffinityKeyExisted" -Value 1 -Type DWord -Force
                    $affProps = Get-ItemProperty -LiteralPath $affPath -ErrorAction SilentlyContinue
                    $oldPrio  = if ($null -ne $affProps.InterruptPriority) { $affProps.InterruptPriority } else { 255 }
                    $oldPol   = if ($null -ne $affProps.DevicePolicy) { $affProps.DevicePolicy } else { 255 }
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "InterruptPriority" -Value $oldPrio -Type DWord -Force
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "DevicePolicy" -Value $oldPol -Type DWord -Force
                    if ($null -ne $affProps.AssignmentSetOverride) {
                        Set-ItemProperty -LiteralPath $devBackupKey -Name "AssignmentSetOverride" -Value ([byte[]]$affProps.AssignmentSetOverride) -Type Binary -Force
                    }
                } else {
                    Set-ItemProperty -LiteralPath $devBackupKey -Name "AffinityKeyExisted" -Value 0 -Type DWord -Force
                }
            }

            Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

            if ($prioSelection -ne "Keep Current") {
                if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction SilentlyContinue | Out-Null }
                switch ($prioSelection) {
                    "High (3)"            { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Normal (2)"          { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Low (1)"             { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue }
                    "Undefined (Default)" { Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue }
                }
            }

            if ($doOffload -and $null -ne $offloadBytes) {
                if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction SilentlyContinue | Out-Null }
                Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 4 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value $offloadBytes -Type Binary -Force -ErrorAction SilentlyContinue
            }

            Write-GUI " -> Configured IRQ/MSI policy: $($dev.RawDeviceName)"
            $changed++
        }
        &$refreshData
        if ($changed -gt 0) { [System.Windows.Forms.MessageBox]::Show("Successfully configured MSI & IRQ policy for $changed device(s).`nOriginal states backed up.`nPlease reboot your PC.", "Reboot Required") }
    }.GetNewClosure())

    $btnRevertMSI = New-UltixButton -Parent $modal -Text "Restore Original State" -X 205 -Y 555 -Width 190 -Height 35 -RGB @(100, 100, 100)
    $btnRevertMSI.Anchor = 'Bottom, Left'
    $btnRevertMSI.Add_Click({
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev) { continue }
            $msiPath = $dev.ActionData.Path
            $affPath = $dev.ActionData.AffinityPath
            $safeKey = &$getSafeBackupKeyName $msiPath
            $devBackupKey = "$bRoot\$safeKey"
            
            if (Test-Path -LiteralPath $devBackupKey) {
                $bProps = Get-ItemProperty -LiteralPath $devBackupKey -ErrorAction SilentlyContinue
                if ($null -ne $bProps.MSISupported) {
                    if ($bProps.MSISupported -eq 255 -or $bProps.MSISupported -eq -1) {
                        Remove-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value $bProps.MSISupported -Type DWord -Force -ErrorAction SilentlyContinue
                    }
                }

                if ($bProps.AffinityKeyExisted -eq 0) {
                    if (Test-Path -LiteralPath $affPath) { Remove-Item -LiteralPath $affPath -Recurse -Force -ErrorAction SilentlyContinue }
                } elseif (Test-Path -LiteralPath $affPath) {
                    if ($bProps.InterruptPriority -eq 255 -or $null -eq $bProps.InterruptPriority) {
                        Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value $bProps.InterruptPriority -Type DWord -Force -ErrorAction SilentlyContinue
                    }

                    if ($bProps.DevicePolicy -eq 255 -or $null -eq $bProps.DevicePolicy) {
                        Remove-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Force -ErrorAction SilentlyContinue
                    } else {
                        Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value $bProps.DevicePolicy -Type DWord -Force -ErrorAction SilentlyContinue
                    }

                    if ($null -ne $bProps.AssignmentSetOverride) {
                        Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value ([byte[]]$bProps.AssignmentSetOverride) -Type Binary -Force -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                    }
                }
                Remove-Item -LiteralPath $devBackupKey -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $affPath) {
                    Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "DevicePolicy", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                }
            }
            Write-GUI " -> Reverted IRQ/MSI state to factory defaults: $($dev.RawDeviceName)"
        }
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 405 -Y 555 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $lblDpcMonitor, $lblDpcLegend, $lblPrio, $comboPrio, $chkOffloadCore0, $listView))
    try {
        [void]$modal.ShowDialog($global:form)
    } finally {
        $dpcTimer.Stop()
        $dpcTimer.Dispose()
        $modal.Dispose()
    }
}

function Show-WHEAModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(850, 500); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(850, 500)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })
    
    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $btnRefresh = New-UltixButton -Parent $modal -Text "Scan Now" -X 715 -Y 15 -Width 100 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView; $listView.Location = New-Object System.Drawing.Point(15, 60); $listView.Size = New-Object System.Drawing.Size(800, 330); $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $listView.ForeColor = [System.Drawing.Color]::White; $listView.Font = New-Object System.Drawing.Font("Consolas", 10); $listView.Anchor = 'Top, Bottom, Left, Right'; $listView.View = [System.Windows.Forms.View]::Details; $listView.FullRowSelect = $true; $listView.GridLines = $true
    Enable-UltixDoubleBuffer -Control $listView

    $listView.Columns.Add("Time", 170) | Out-Null
    $listView.Columns.Add("Event ID", 90) | Out-Null
    $listView.Columns.Add("APIC ID", 120) | Out-Null
    $listView.Columns.Add("Error Source / Details", 390) | Out-Null

    $btnClear = New-UltixButton -Parent $modal -Text "Wipe Logs (Prepare for Test)" -X 15 -Y 405 -Width 220 -Height 35 -RGB @(150, 60, 60)
    $btnClear.Anchor = 'Bottom, Left'

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 245 -Y 405 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $refreshData = {
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
            Update-Progress 0
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

    $modal.Controls.AddRange(@($lblDesc, $listView))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-NetworkModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(760, 560); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(710, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] Applying or reverting NDIS settings will momentarily re-initialize the network adapter."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(710, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(710, 375); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $btnEngage  = New-UltixButton -Parent $modal -Text "Optimize Checked" -X 15 -Y 470 -Width 175 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'

    $btnRevert  = New-UltixButton -Parent $modal -Text "Restore Checked Defaults" -X 200 -Y 470 -Width 195 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh Audit" -X 405 -Y 470 -Width 140 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'

    $btnClose   = New-UltixButton -Parent $modal -Text "Close" -X 555 -Y 470 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $actionButtons = @($btnEngage, $btnRevert, $btnRefresh)

    $btnRefresh.Add_Click({
        Update-NetworkModalList -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $btnEngage.Add_Click({
        $queue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i) -and $i -lt $localData.Count) {
                $queue += $localData[$i]
            }
        }
        Start-NetworkOptimizationAsync -SelectedItems $queue -Mode "Apply" -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $btnRevert.Add_Click({
        $queue = @()
        for ($i = 0; $i -lt $chkList.Items.Count; $i++) {
            if ($chkList.GetItemChecked($i) -and $i -lt $localData.Count) {
                $queue += $localData[$i]
            }
        }
        Start-NetworkOptimizationAsync -SelectedItems $queue -Mode "Revert" -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons
    }.GetNewClosure())

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList))

    Update-NetworkModalList -Modal $modal -ChkList $chkList -LocalData $localData -ControlsToDisable $actionButtons

    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

function Show-TimerModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(700, 410); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(700, 410)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(650, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] BCD modifications require a system reboot to lock the TSC hardware timer."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(650, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblCurrentTimer = New-Object System.Windows.Forms.Label
    $lblCurrentTimer.Location = New-Object System.Drawing.Point(15, 345)
    $lblCurrentTimer.Size = New-Object System.Drawing.Size(650, 20)
    $lblCurrentTimer.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $lblCurrentTimer.ForeColor = [System.Drawing.Color]::Yellow
    $lblCurrentTimer.Anchor = 'Bottom, Left, Right'
	
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(650, 200); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList
    $testLockState = @{ IsLocked = $false }

    $updateTimerLabel = {
        param([System.Windows.Forms.Label]$Lbl)
        if ($null -eq $Lbl -or $Lbl.IsDisposed) { return }
        $tStats = Get-CurrentTimerResolution
        $modeTag = if ($testLockState.IsLocked) { " [0.5ms TEST ACTIVE]" } else { "" }
        $Lbl.Text = "LIVE TIMER (2Hz): $($tStats.CurrentMs) ms (Max precision: $($tStats.LimitMs) ms | Default: $($tStats.DefaultMs) ms)$modeTag"
        if ($tStats.CurrentMs -le 0.55) {
            $Lbl.ForeColor = [System.Drawing.Color]::LightGreen
        } elseif ($tStats.CurrentMs -le 1.05) {
            $Lbl.ForeColor = [System.Drawing.Color]::Yellow
        } else {
            $Lbl.ForeColor = [System.Drawing.Color]::OrangeRed
        }
    }

    $refreshData = {
        $chkList.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Timer
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
            else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
        }
        &$updateTimerLabel $lblCurrentTimer
    }
    &$refreshData

    $timerPoll = New-Object System.Windows.Forms.Timer
    $timerPoll.Interval = 500
    $timerPoll.Tag = @{
        Modal  = $modal
        Label  = $lblCurrentTimer
        Update = $updateTimerLabel
    }
    $timerPoll.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        & $ctx.Update $ctx.Label
    })
    $timerPoll.Start()

    $btnEngage = New-UltixButton -Parent $modal -Text "Enforce 0.5ms & TSC" -X 15 -Y 300 -Width 155 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
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

    $btnRevert = New-UltixButton -Parent $modal -Text "Restore Defaults" -X 178 -Y 300 -Width 135 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel"
        Remove-ItemProperty -Path $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue | Out-Null
        
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} disabledynamictick" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformclock" -NoNewWindow -Wait
        Start-Process -FilePath "bcdedit.exe" -ArgumentList "/deletevalue `{current`} useplatformtick" -NoNewWindow -Wait
        
        $hpet = Get-PnpDevice -Class System -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match "PNP0103" }
        if ($null -ne $hpet -and $hpet.ConfigManagerErrorCode -eq 22) { 
            Enable-PnpDevice -InstanceId $hpet.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null 
        }
        
        Write-GUI " -> Reverted Timer Subsystem & BCD flags to OS defaults."
        [System.Windows.Forms.MessageBox]::Show("Default OS timer mechanisms and BCD values restored. HPET enabled. Reboot required.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnTestPulse = New-UltixButton -Parent $modal -Text "Test 0.5ms Lock" -X 321 -Y 300 -Width 140 -Height 35 -RGB @(45, 110, 65)
    $btnTestPulse.Anchor = 'Bottom, Left'
    $btnTestPulse.Add_Click({
        if (-not $testLockState.IsLocked) {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $true)
            $testLockState.IsLocked = $true
            $this.Text = "Stop 0.5ms Test"
            $this.BackColor = [System.Drawing.Color]::FromArgb(255, 160, 90, 40)
            Write-GUI " -> Engaged live NtSetTimerResolution(5000) 0.5ms kernel clock test."
        } else {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $false)
            $testLockState.IsLocked = $false
            $this.Text = "Test 0.5ms Lock"
            $this.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 110, 65)
            Write-GUI " -> Released 0.5ms kernel clock test lock."
        }
        &$updateTimerLabel $lblCurrentTimer
    }.GetNewClosure())

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh" -X 469 -Y 300 -Width 90 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 567 -Y 300 -Width 98 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $chkList, $lblCurrentTimer))
    try {
        [void]$modal.ShowDialog($global:form)
    } finally {
        if ($testLockState.IsLocked) {
            [void][WinUltix.NtDll]::SetTimerResolution(5000, $false)
            Write-GUI " -> Released 0.5ms kernel clock test lock (Modal closed)."
        }
        $timerPoll.Stop()
        $timerPoll.Dispose()
        $modal.Dispose()
    }
}

function Show-NVMeModal {
    param ([string]$Title, [string]$Description)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(650, 360); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(650, 360)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 15); $lblDesc.Size = New-Object System.Drawing.Size(600, 40); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'

    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply PCI bus and NVMe driver changes."; $lblWarning.Location = New-Object System.Drawing.Point(15, 55); $lblWarning.Size = New-Object System.Drawing.Size(600, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 160); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45); $chkList.ForeColor = [System.Drawing.Color]::LightSkyBlue; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
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

    $btnEngage = New-UltixButton -Parent $modal -Text "Disable Power States" -X 15 -Y 260 -Width 180 -Height 35 -RGB @(150, 60, 60)
    $btnEngage.Anchor = 'Bottom, Left'
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

    $btnRevert = New-UltixButton -Parent $modal -Text "Restore OS Defaults" -X 205 -Y 260 -Width 160 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters" -Name "DisableASPM" -ErrorAction SilentlyContinue | Out-Null
        Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" -Name "IdlePowerMode" -ErrorAction SilentlyContinue | Out-Null
        
        Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        
        Write-GUI " -> Restored default PCI ASPM, StorNVMe APST, and MMAgent settings."
        [System.Windows.Forms.MessageBox]::Show("Standard PCI/NVMe drivers and Memory Compression restored. Reboot is required to apply bus changes.", "Revert Completed")
        &$refreshData
    }.GetNewClosure())

    $btnRefresh = New-UltixButton -Parent $modal -Text "Refresh Audit" -X 375 -Y 260 -Width 120 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 505 -Y 260 -Width 115 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $chkList, $lblWarning))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
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

if (-not ([System.Management.Automation.PSTypeName]'WinUltix.PreFlightNative').Type) {
    Add-Type -TypeDefinition @'
    using System;
    using System.Runtime.InteropServices;
    namespace WinUltix {
        public static class PreFlightNative {
            [DllImport("dwmapi.dll", PreserveSig = true)]
            private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

            [DllImport("user32.dll", SetLastError = true)]
            private static extern bool SetProcessDpiAwarenessContext(IntPtr value);

            public static void EnableDarkTitleBar(IntPtr handle) {
                if (handle == IntPtr.Zero) return;
                int useDark = 1;
                if (DwmSetWindowAttribute(handle, 20, ref useDark, sizeof(int)) != 0) {
                    DwmSetWindowAttribute(handle, 19, ref useDark, sizeof(int));
                }
            }

            public static void EnableGdiDpiScaling() {
                try { SetProcessDpiAwarenessContext(new IntPtr(-5)); } catch { }
            }
        }
    }
'@ -ErrorAction SilentlyContinue
}

[WinUltix.PreFlightNative]::EnableGdiDpiScaling()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

`$c = 'HKCU:\Software\WinUltix\AffinityLasso'
`$p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
function Get-Pcfg (`$g) {
    `$out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR `$g 2>`$null
    if (-not `$out) { return `$null }
    `$hexLines = @(`$out -match ':\s*(0x[0-9a-fA-F]+)\s*`$')
    if (`$hexLines.Count -ge 2 -and `$hexLines[-2] -match '(0x[0-9a-fA-F]+)\s*`$') {
        return [convert]::ToInt32(`$matches[1], 16)
    }
    return `$null
}

`$curEpp = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
`$failsafeTask = Get-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -ErrorAction SilentlyContinue
`$isEngaged = ((`$null -ne `$failsafeTask) -or (`$curEpp -eq 0))
`$eppDisp = if (`$null -ne `$curEpp) { "`$curEpp%" } else { "N/A" }

`$frm = New-Object System.Windows.Forms.Form
`$frm.Text = "WinUltix - Pre-Flight Game Mode"
`$frm.Size = New-Object System.Drawing.Size(370, 215)
`$frm.StartPosition = "CenterScreen"
`$frm.FormBorderStyle = "FixedDialog"
`$frm.MaximizeBox = `$false
`$frm.MinimizeBox = `$false
`$frm.TopMost = `$true
`$frm.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
`$frm.ForeColor = [System.Drawing.Color]::White
`$frm.Add_HandleCreated({ [WinUltix.PreFlightNative]::EnableDarkTitleBar(`$this.Handle) })

`$lblStatus = New-Object System.Windows.Forms.Label
`$lblStatus.Location = New-Object System.Drawing.Point(20, 12)
`$lblStatus.Size = New-Object System.Drawing.Size(320, 22)
`$lblStatus.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
if (`$isEngaged) {
    `$lblStatus.Text = "STATUS: ENGAGED [EPP: `$eppDisp | ARMED]"
    `$lblStatus.ForeColor = [System.Drawing.Color]::LightGreen
} else {
    `$lblStatus.Text = "STATUS: RELEASED [EPP: `$eppDisp | STANDBY]"
    `$lblStatus.ForeColor = [System.Drawing.Color]::LightSkyBlue
}

`$chkAff = New-Object System.Windows.Forms.CheckBox
`$chkAff.Text = "$affString"
`$chkAff.Location = New-Object System.Drawing.Point(20, 42)
`$chkAff.Size = New-Object System.Drawing.Size(320, 25)
`$chkAff.Checked = $affState
`$chkAff.Enabled = $affState
`$chkAff.ForeColor = [System.Drawing.Color]::$affColor

`$chkCPPC = New-Object System.Windows.Forms.CheckBox
`$chkCPPC.Text = "Max CPPC (EPP 0%, Disable C-States)"
`$chkCPPC.Location = New-Object System.Drawing.Point(20, 72)
`$chkCPPC.Size = New-Object System.Drawing.Size(320, 25)
`$chkCPPC.Checked = `$true

`$btnEngage = New-Object System.Windows.Forms.Button
`$btnEngage.Text = "ENGAGE"
`$btnEngage.Location = New-Object System.Drawing.Point(20, 118)
`$btnEngage.Size = New-Object System.Drawing.Size(100, 32)
`$btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
`$btnEngage.FlatStyle = "Flat"
`$btnEngage.DialogResult = "Yes"

`$btnRelease = New-Object System.Windows.Forms.Button
`$btnRelease.Text = "RELEASE"
`$btnRelease.Location = New-Object System.Drawing.Point(128, 118)
`$btnRelease.Size = New-Object System.Drawing.Size(100, 32)
`$btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 100, 60)
`$btnRelease.FlatStyle = "Flat"
`$btnRelease.DialogResult = "No"

`$btnCancel = New-Object System.Windows.Forms.Button
`$btnCancel.Text = "Cancel"
`$btnCancel.Location = New-Object System.Drawing.Point(236, 118)
`$btnCancel.Size = New-Object System.Drawing.Size(100, 32)
`$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
`$btnCancel.FlatStyle = "Flat"
`$btnCancel.DialogResult = "Cancel"

`$frm.Controls.AddRange(@(`$lblStatus, `$chkAff, `$chkCPPC, `$btnEngage, `$btnRelease, `$btnCancel))
`$res = `$frm.ShowDialog()
`$frm.Dispose()

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
        
        if (`$null -ne `$e -and -not (`$e -eq 0 -and `$d -eq 100 -and `$pr -eq 100) -and -not (`$e -eq 0 -and `$d -eq 0 -and `$pr -eq 0)) {
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
            if (`$null -ne `$reg.EPP -and `$null -ne `$reg.Demote -and `$null -ne `$reg.Promote) {
                if (-not (`$reg.EPP -eq 0 -and `$reg.Demote -eq 0 -and `$reg.Promote -eq 0)) {
                    `$e = `$reg.EPP; `$d = `$reg.Demote; `$pr = `$reg.Promote
                }
            }
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

# ------------------------------------------
# Z7: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z7UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = "Hardware"
    $tab.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)

    $topo = Get-CPUTopologyProfile

    if ($topo.IsSupported) {
        [void](New-UltixButton -Parent $tab -X 15 -Y 20 -Width 240 -Height 40 -RGB @(150, 60, 60) `
            -Text "Affinity Lasso (CPU Core Lock)" `
            -Description "Lock background apps to specific cores ($($topo.CoreDesc)) to free up prime gaming cores." `
            -OnClick ({ Show-AffinityModal "Affinity Lasso - $($topo.Label)" "Lock background processes to $($topo.CoreDesc) with BelowNormal priority." }.GetNewClosure()))
    } else {
        $btnAffinity = New-UltixButton -Parent $tab -X 15 -Y 20 -Width 240 -Height 40 -RGB @(45, 45, 45) `
            -ForeColor ([System.Drawing.Color]::DarkGray) `
            -Text "Affinity Lasso (Unsupported CPU)"
        $btnAffinity.Enabled = $false
    }

    [void](New-UltixButton -Parent $tab -X 265 -Y 20 -Width 120 -Height 90 -RGB @(60, 100, 150) `
        -Text "Generate Pre-Flight Shortcut" `
        -Description "Create a desktop shortcut to instantly apply Affinity and CPPC rules." `
        -OnClick { New-PreFlightShortcut })

    [void](New-UltixButton -Parent $tab -X 15 -Y 70 -Width 240 -Height 40 -RGB @(100, 60, 150) `
        -Text "CPPC P-State Unhider" `
        -Description "Unhide and manage advanced AMD/Intel CPPC power states." `
        -OnClick { Show-CPPCModal "CPPC Management" "Unhide advanced power plan settings (EPP, Demote, Promote)." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 120 -Width 370 -Height 40 -RGB @(100, 100, 100) `
        -Text "MSI & IRQ Affinity Enforcer" `
        -Description "Force Message Signaled Interrupts (MSI), set Interrupt Priority, offload IRQs from Core 0, and monitor live kernel DPCs." `
        -OnClick { Show-MsiModal "MSI & IRQ Affinity Enforcer" "Force PCI devices into MSI mode, adjust interrupt priority, and offload high-DPC drivers (GPU/NIC) from Core 0." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 170 -Width 370 -Height 40 -RGB @(150, 100, 60) `
        -Text "WHEA Hardware Error Logger" `
        -Description "Scan system logs for hardware instability (Curve Optimizer / RAM)." `
        -OnClick { Show-WHEAModal "WHEA Logger" "Analyze hardware errors to find unstable CPU cores or RAM." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 220 -Width 370 -Height 40 -RGB @(60, 100, 150) `
        -Text "Network NDIS & TCP Optimizer" `
        -Description "Configure low-latency NDIS parameters, TCP properties, and offloads with full symmetric revert." `
        -OnClick { Show-NetworkModal "Network Optimizer" "Disable flow control, power saving, interrupt moderation, and enforce TCPNoDelay." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 270 -Width 370 -Height 40 -RGB @(100, 100, 100) `
        -Text "System Timer & TSC Fix (0.5ms)" `
        -Description "Fix Windows 11 API to allow global 0.5ms High Resolution Timers and force CPU TSC." `
        -OnClick { Show-TimerModal "Timer Resolution Subsystem" "Enable legacy 0.5ms requests globally and stabilize DPC latency." })

    [void](New-UltixButton -Parent $tab -X 15 -Y 320 -Width 370 -Height 40 -RGB @(100, 60, 150) `
        -Text "I/O & Memory Latency Optimizer" `
        -Description "Disable NVMe APST, PCIe ASPM, and System Memory Compression to reduce CPU overhead and micro-stuttering." `
        -OnClick { Show-NVMeModal "I/O & Memory Optimizer" "Prevent NVMe and PCIe bus from entering low-power states (D3hot/L1.2) and disable RAM compression." })

    # Dedicated 3-Line Live Kernel Interrupt / DPC Telemetry Panel on Hardware Tab
    $lblDpcHeader = New-Object System.Windows.Forms.Label
    $lblDpcHeader.Text = "Live Kernel Interrupt / DPC Distribution Monitor (ntdll.dll)"
    $lblDpcHeader.Location = New-Object System.Drawing.Point(15, 374)
    $lblDpcHeader.Size = New-Object System.Drawing.Size(370, 20)
    $lblDpcHeader.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblTabDpc = New-Object System.Windows.Forms.Label
    $lblTabDpc.Location = New-Object System.Drawing.Point(15, 396)
    $lblTabDpc.Size = New-Object System.Drawing.Size(370, 68)
    $lblTabDpc.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblTabDpc.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblTabDpc.Font = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)
    $lblTabDpc.TextAlign = "TopLeft"
    $lblTabDpc.BorderStyle = "FixedSingle"
    $lblTabDpc.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 4)

    $lblTabLegend = New-Object System.Windows.Forms.Label
    $lblTabLegend.Text = "C0..Cn = Physical Cores (SMT: 2 LP#/Core) | LP# = Logical Thread`r`nColor = Core 0 Load: Green (<30%) | Yellow (30-54%) | Red (>=55%)"
    $lblTabLegend.Location = New-Object System.Drawing.Point(15, 468)
    $lblTabLegend.Size = New-Object System.Drawing.Size(370, 30)
    $lblTabLegend.ForeColor = [System.Drawing.Color]::DarkGray
    $lblTabLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)

    $tabDpcState = @{ PrevCounts = $null; IsRunning = $false; LastSnap = $null }
    Update-UltixDpcMonitorUI -TargetLabel $lblTabDpc -State $tabDpcState -CompactMode

    $tabDpcTimer = New-Object System.Windows.Forms.Timer
    $tabDpcTimer.Interval = 1000
    $tabDpcTimer.Tag = @{
        TabControl = $TabControl
        Tab        = $tab
        Label      = $lblTabDpc
        State      = $tabDpcState
    }
    $tabDpcTimer.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        if ($ctx.TabControl.SelectedTab -eq $ctx.Tab) {
            Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State -CompactMode
        }
    })

    $btnToggleDpc = New-UltixButton -Parent $tab -X 15 -Y 502 -Width 320 -Height 34 -RGB @(50, 75, 100) `
        -Text "Start Live DPC Monitor (1Hz Stream)" `
        -Description "Toggles real-time 1Hz polling of ntdll!NtQuerySystemInformation (SystemInterruptInformation). Automatically pauses if you switch tabs."

    $btnHelpDpc = New-UltixButton -Parent $tab -X 345 -Y 502 -Width 40 -Height 34 -RGB @(80, 80, 80) `
        -Text "?" `
        -Description "DPC LEGEND & REPORT: Samples per-core DPC distribution over 1s and prints a compact breakdown of all physical cores (C0..Cn) and logical threads (LP#) to the log."

    $uiContext = @{
        Timer = $tabDpcTimer
        Label = $lblTabDpc
        State = $tabDpcState
    }
    $btnToggleDpc.Tag = $uiContext
    $btnHelpDpc.Tag   = $uiContext

    $btnToggleDpc.Add_Click({
        $ctx   = $this.Tag
        $state = $ctx.State
        $timer = $ctx.Timer
        $lbl   = $ctx.Label

        if (-not $state.IsRunning) {
            $state.IsRunning  = $true
            $state.PrevCounts = $null
            $this.Text        = "Stop Live DPC Monitor [ACTIVE - 1Hz]"
            $this.BackColor   = [System.Drawing.Color]::FromArgb(255, 45, 110, 65)
            Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
            $timer.Start()
            Write-GUI " -> Live Kernel DPC Monitor started (1Hz polling)."
        } else {
            $timer.Stop()
            $state.IsRunning = $false
            $this.Text       = "Start Live DPC Monitor (1Hz Stream)"
            $this.BackColor  = [System.Drawing.Color]::FromArgb(255, 50, 75, 100)
            if ($null -ne $state.LastSnap -and $state.LastSnap.HasLiveDelta) {
                Write-UltixDpcReport -Snapshot $state.LastSnap
            } else {
                Write-GUI " -> Live Kernel DPC Monitor stopped.`n"
            }
            Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
        }
    })

    $btnHelpDpc.Add_Click({
        $ctx   = $this.Tag
        $state = $ctx.State
        $lbl   = $ctx.Label
        Write-UltixDpcReport -Snapshot $state.LastSnap
        Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
    })

    $tab.Tag = $tabDpcTimer
    $tab.Add_Disposed({
        $t = $this.Tag
        if ($null -ne $t) {
            $t.Stop()
            $t.Dispose()
        }
    })

    $tab.Controls.AddRange(@($lblDpcHeader, $lblTabDpc, $lblTabLegend))
    $TabControl.Controls.Add($tab)
}