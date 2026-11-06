# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z7_HARDWARE.PS1 - HARDWARE & DIAGNOSTICS MODULE (v3.14)
# Z7_Hardware: Low-level hardware & latency cockpit (Topology-Aware Affinity Lasso, CPPC Unhider + Dead Man's Switch, Pre-Flight Shortcut, Quantum Scheduler Matrix, MSI & Core 0 IRQ Offload, 0.5ms TSC Timer, USB XHCI Topology Mapper, NVMe/PCIe locks, NDIS/TCP Tuner, WHEA Decoder, and 1Hz DPC Monitor).
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
        $profileResult = [PSCustomObject]@{ IsSupported = $false; Mask = [System.IntPtr]15; Label = "Standard (<6C - Lasso Off)"; CoreDesc = "N/A"; SmtEnabled = $smt }
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
    $whitelist = @(
        "systemsettings.exe", "shellexperiencehost.exe", "cmd.exe", "powershell.exe", "pwsh.exe",
        "applicationframehost.exe", "rundll32.exe", "dllhost.exe", "ngciso.exe", "wmiadap.exe",
        "csrss.exe", "lsass.exe", "smss.exe", "services.exe", "svchost.exe", "wininit.exe",
        "winlogon.exe", "explorer.exe", "System", "Idle", "Registry", "dwm.exe", "fontdrvhost.exe",
        "Taskmgr.exe", "conhost.exe", "sihost.exe", "taskhostw.exe", "RuntimeBroker.exe",
        "SearchHost.exe", "StartMenuExperienceHost.exe", "SecurityHealthService.exe",
        "SecurityHealthSystray.exe", "MsMpEng.exe", "NisSrv.exe", "LsaIso.exe", "audiodg.exe",
        "WmiPrvSE.exe", "TiWorker.exe", "TrustedInstaller.exe", "spoolsv.exe", "WUDFHost.exe",
        "System.exe", "Idle.exe", "Registry.exe", "Secure System.exe", "ctfmon.exe",
        "MpDefenderCoreService.exe", "NVDisplay.Container.exe", "ShellHost.exe",
        "iFiUsbAudioCpl.exe", "Windows11FirewallService.exe", "Windows11FirewallControl.exe",
        "AmdPpkgSvc.exe", "nvcontainer.exe", "MoUsoCoreWorker.exe", "SearchIndexer.exe",
        "smartscreen.exe", "AppActions.exe", "SDXHelper.exe", "QuickControls.exe",
        "armsvc.exe", "BudsManager.exe", "WinUltix.exe"
    )
    $dictionary = @(
        "Discord.exe", "Spotify.exe", "msedgewebview2.exe", "steamwebhelper.exe",
        "EpicGamesLauncher.exe", "obs64.exe", "ArmouryCrate.exe", "iCUE.exe",
        "Razer Synapse Service.exe", "firefox.exe", "chrome.exe", "msedge.exe",
        "brave.exe", "opera.exe", "GalaxyClient.exe", "GOG Galaxy.exe", "EADesktop.exe",
        "upc.exe", "Battle.net.exe", "WhatsApp.exe", "Telegram.exe", "Teams.exe",
        "slack.exe", "Overwolf.exe", "LGHUB.exe", "LGHUB_Agent.exe", "MSIAfterburner.exe",
        "RTSS.exe", "NZXT CAM.exe", "vgc.exe", "vgtray.exe", "OneDrive.exe"
    )

    $whitelistSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($w in $whitelist) { [void]$whitelistSet.Add($w) }

    $topo = Get-CPUTopologyProfile
    $targetMask = $topo.Mask

    $liveProcsGrouped = @{}
    $allProcs = @(Get-Process -ErrorAction SilentlyContinue)
    try {
        foreach ($p in $allProcs) {
            $pName = "$($p.ProcessName).exe"
            if (-not $liveProcsGrouped.ContainsKey($pName)) {
                $liveProcsGrouped[$pName] = $p
            } else {
                $p.Dispose()
            }
        }

        $configPath = "HKCU:\Software\WinUltix\AffinityLasso"
        $savedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if (Test-Path -LiteralPath $configPath) {
            $regProps = (Get-ItemProperty -LiteralPath $configPath -ErrorAction SilentlyContinue).PSObject.Properties
            foreach ($prop in $regProps) {
                if ($prop.Name -match '\.exe$') { [void]$savedSet.Add($prop.Name) }
            }
        }

        # Case-insensitive union preserving canonical casing from dictionary/saved roster
        $combinedMap = [ordered]@{}
        foreach ($src in @($dictionary, @($savedSet), @($liveProcsGrouped.Keys))) {
            foreach ($exe in $src) {
                if ([string]::IsNullOrWhiteSpace($exe) -or $whitelistSet.Contains($exe)) { continue }
                $keyLower = $exe.ToLowerInvariant()
                if (-not $combinedMap.Contains($keyLower)) {
                    $combinedMap[$keyLower] = $exe
                }
            }
        }

        $listRunning  = [System.Collections.Generic.List[PSCustomObject]]::new()
        $listSaved    = [System.Collections.Generic.List[PSCustomObject]]::new()
        $listTemplate = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($app in $combinedMap.Values) {
            $procName   = $app -replace '\.exe$', ''
            $activeProc = $liveProcsGrouped[$app]
            $isDetected = $savedSet.Contains($app)

            if ($null -ne $activeProc) {
                $procPath = [WinUltix.NativeMethods]::GetProcessExecutablePath([int]$activeProc.Id)
                if ([string]::IsNullOrWhiteSpace($procPath)) {
                    if ($isDetected) {
                        $procPath = "[Protected Process]"
                    } else {
                        continue
                    }
                }

                $priority = "---"
                try { $priority = $activeProc.PriorityClass.ToString() } catch { $priority = "Protected" }

                $isLockedNow = $false
                try { $isLockedNow = ($activeProc.ProcessorAffinity -eq $targetMask) } catch { }

                $statusTag = if ($isLockedNow) { "[LOCKED]  " } else { "[RUNNING] " }
                $listRunning.Add([PSCustomObject]@{
                    UIDisplayName = "$statusTag $app"
                    IsDetected    = $isDetected
                    Path          = $procPath
                    Priority      = $priority
                    ActionData    = @{ ExeName = $app; ProcName = $procName }
                })
            } elseif ($isDetected) {
                $listSaved.Add([PSCustomObject]@{
                    UIDisplayName = "[SAVED]    $app"
                    IsDetected    = $true
                    Path          = "---"
                    Priority      = "---"
                    ActionData    = @{ ExeName = $app; ProcName = $procName }
                })
            } else {
                $listTemplate.Add([PSCustomObject]@{
                    UIDisplayName = "[TEMPLATE] $app"
                    IsDetected    = $false
                    Path          = "---"
                    Priority      = "---"
                    ActionData    = @{ ExeName = $app; ProcName = $procName }
                })
            }
        }

        return @(($listRunning | Sort-Object UIDisplayName) + ($listSaved | Sort-Object UIDisplayName) + ($listTemplate | Sort-Object UIDisplayName))
    } finally {
        foreach ($p in $liveProcsGrouped.Values) {
            if ($null -ne $p) { $p.Dispose() }
        }
    }
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

function Grant-UltixRegistryKeyAccess {
    param([Parameter(Mandatory=$true)][string]$RegistryPath)
    $subKeyPath = $RegistryPath -replace '^(?i)(HKLM:\\|Registry::HKEY_LOCAL_MACHINE\\)', ''
    if ([string]::IsNullOrWhiteSpace($subKeyPath)) { return }

    try {
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeTakeOwnershipPrivilege")
        [WinUltix.PrivilegeEnabler]::EnablePrivilege("SeRestorePrivilege")
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

        $keyOwn = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $subKeyPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::TakeOwnership
        )
        if ($null -ne $keyOwn) {
            try {
                $aclOwn = $keyOwn.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
                $aclOwn.SetOwner($adminSid)
                $keyOwn.SetAccessControl($aclOwn)
            } finally {
                $keyOwn.Dispose()
            }
        }

        $keyAcl = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
            $subKeyPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [System.Security.AccessControl.RegistryRights]::ChangePermissions
        )
        if ($null -ne $keyAcl) {
            try {
                $acl = $keyAcl.GetAccessControl()
                $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                    $adminSid,
                    [System.Security.AccessControl.RegistryRights]::FullControl,
                    ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow
                )
                $acl.SetAccessRule($rule)
                $keyAcl.SetAccessControl($acl)
            } finally {
                $keyAcl.Dispose()
            }
        }
    } catch { }
}

function Get-HardwareState_IRQ {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    [uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
    [uint64]$core1Mask  = if ($coreMasks.Count -ge 2) { [uint64]$coreMasks[1] } else { 12 }

    $pciRoot  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum\PCI", $false)
    $enumRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum", $false)
    $svcRoot  = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
    if ($null -eq $pciRoot) {
        if ($null -ne $enumRoot) { $enumRoot.Dispose() }
        if ($null -ne $svcRoot)  { $svcRoot.Dispose() }
        return @()
    }

    $svcBinaryCache = @{}

    try {
        foreach ($venName in $pciRoot.GetSubKeyNames()) {
            $venKey = $pciRoot.OpenSubKey($venName, $false)
            if ($null -eq $venKey) { continue }
            try {
                foreach ($instName in $venKey.GetSubKeyNames()) {
                    $instanceId = "PCI\$venName\$instName"
                    # Skip phantom/disconnected historical PCI devices
                    if ([WinUltix.PnpTree]::GetDeviceConfigStatus($instanceId) -ne 0) { continue }

                    $instKey = $venKey.OpenSubKey($instName, $false)
                    if ($null -eq $instKey) { continue }
                    try {
                        $msiKey = $instKey.OpenSubKey("Device Parameters\Interrupt Management\MessageSignaledInterruptProperties", $false)
                        if ($null -eq $msiKey) { continue }

                        $msiVal = $null
                        try {
                            $msiVal = $msiKey.GetValue("MSISupported", $null)
                        } finally {
                            $msiKey.Dispose()
                        }

                        $rawDevName = [string]$instKey.GetValue("FriendlyName", "")
                        if ([string]::IsNullOrWhiteSpace($rawDevName)) { $rawDevName = [string]$instKey.GetValue("DeviceDesc", "") }
                        $devName = Format-UltixDeviceName -RawName $rawDevName
                        if ([string]::IsNullOrWhiteSpace($devName)) { $devName = "Unknown PCI Device" }

                        $svcName  = [string]$instKey.GetValue("Service", "")
                        $devClass = [string]$instKey.GetValue("Class", "")
                        $clsGuid  = [string]$instKey.GetValue("ClassGUID", "")
                        $locInfo  = [string]$instKey.GetValue("LocationInformation", "")
                        $isMsiEnabled = ($msiVal -eq 1)

                        # Extract compact PCI Bus:Device.Function tag (e.g. B0E:00.3) from LocationInformation
                        $bdfTag = ""
                        if ($locInfo -match '\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)\s*$') {
                            $bdfTag = ("B{0:X2}:{1:X2}.{2}" -f [int]$matches[1], [int]$matches[2], [int]$matches[3])
                        }

                        # Resolve actual kernel driver binary name from Services\<svcName>\ImagePath (e.g. igfx/igfxn -> igdkmd64.sys/igdkmdn64.sys)
                        $etwModuleKey = ""
                        $drvTag       = "N/A (Bus)"

                        if (-not [string]::IsNullOrWhiteSpace($svcName)) {
                            $etwModuleKey = $svcName.ToLowerInvariant()
                            $drvTag       = "$etwModuleKey.sys"
                            if ($null -ne $svcRoot) {
                                if (-not $svcBinaryCache.ContainsKey($svcName)) {
                                    $resolvedMod = $svcName.ToLowerInvariant()
                                    $sKey = $svcRoot.OpenSubKey($svcName, $false)
                                    if ($null -ne $sKey) {
                                        try {
                                            $imgPath = [string]$sKey.GetValue("ImagePath", "")
                                            if ($imgPath -match '(?i)([^\\]+\.sys)\b') {
                                                $resolvedMod = [System.IO.Path]::GetFileNameWithoutExtension($matches[1]).ToLowerInvariant()
                                            }
                                        } finally {
                                            $sKey.Dispose()
                                        }
                                    }
                                    $svcBinaryCache[$svcName] = $resolvedMod
                                }
                                $etwModuleKey = $svcBinaryCache[$svcName]
                                $drvTag       = "$etwModuleKey.sys"
                            }
                        }

                        $prioVal   = $null
                        $policyVal = $null
                        [byte[]]$maskBytes = $null

                        $affKey = $instKey.OpenSubKey("Device Parameters\Interrupt Management\Affinity Policy", $false)
                        if ($null -ne $affKey) {
                            try {
                                $prioVal   = $affKey.GetValue("InterruptPriority", $null)
                                $policyVal = $affKey.GetValue("DevicePolicy", $null)
                                $maskBytes = $affKey.GetValue("AssignmentSetOverride", $null)
                            } finally {
                                $affKey.Dispose()
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
                            $coreHint = ""
                            for ($cIdx = 0; $cIdx -lt $coreMasks.Count; $cIdx++) {
                                $cm = [uint64]$coreMasks[$cIdx]
                                if ($maskInt -ne 0 -and (($maskInt -band $cm) -eq $maskInt)) {
                                    $coreHint = " (C$cIdx)"
                                    break
                                }
                            }
                            if ([string]::IsNullOrEmpty($coreHint) -and ($maskInt -band $core0Mask) -ne 0) {
                                $coreHint = " (C0+)"
                            }
                            $affLabel = "0x$($maskInt.ToString('X'))$coreHint"
                        } elseif ($policyVal -eq 5) {
                            $affLabel = "Spread"
                        }

                        $isOnCore0 = ($policyVal -ne 5) -and (($policyVal -ne 4) -or (($maskInt -band $core0Mask) -ne 0))
                        $isGpu     = ($devClass -match '^(?i)Display$' -or $clsGuid -match '(?i)4d36e968-e325-11ce-bfc1-08002be10318' -or $svcName -match '^(?i)(nvlddmkm|amdkmdag|amdwddmg|igfx|igfxn)$' -or $devName -match '(?i)(GeForce|Radeon|Arc |HD Graphics|UHD Graphics|Iris)')
                        $isNic     = ($devClass -match '^(?i)Net$' -or $clsGuid -match '(?i)4d36e972-e325-11ce-bfc1-08002be10318' -or $devName -match '(?i)(Ethernet|GbE|Network|Wi-Fi|WiFi|Wireless|802\.11|I219|I225|I226|Killer|Realtek PCI|AQtion|ConnectX)')
                        $isUsb     = ($devClass -match '^(?i)USB$' -or $clsGuid -match '(?i)36fc9e60-c465-11cf-8056-444553540000' -or $svcName -match '^(?i)(USBXHCI|USB4|usbuhci|usbehci)$' -or $devName -match '(?i)(eXtensible Host|Enhanced Host|USB4)')
                        $isStorage = ($policyVal -eq 5 -or $clsGuid -match '(?i)(4d36e96a|4d36e97b)-e325-11ce-bfc1-08002be10318' -or $svcName -match '^(?i)(stornvme|secnvme|storahci|iaStor)' -or $devName -match '(?i)(NVM Express|SATA AHCI)')
                        $isAudio   = ($svcName -match '^(?i)(HDAudBus|IntcAzAudAddService|IntcOED)$' -or $devName -match '(?i)High Definition Audio')

                        # Disambiguate generic NVMe/SATA controllers by attached physical drive name, and USB controllers by PCI B:D.F
                        if ($isStorage -and $null -ne $enumRoot) {
                            $diskNames = [System.Collections.Generic.List[string]]::new()
                            foreach ($descEntry in ([WinUltix.PnpTree]::GetDescendants($instanceId))) {
                                $childId = ($descEntry -split '\|', 2)[1]
                                if ([string]::IsNullOrWhiteSpace($childId)) { continue }
                                $childKey = $enumRoot.OpenSubKey($childId, $false)
                                if ($null -ne $childKey) {
                                    try {
                                        $cClass = [string]$childKey.GetValue("Class", "")
                                        $cName  = [string]$childKey.GetValue("FriendlyName", "")
                                        if ($cClass -eq "DiskDrive" -and -not [string]::IsNullOrWhiteSpace($cName)) {
                                            $shortDisk = ($cName -replace '(?i)\s*(SCSI Disk Device|NVMe Disk Device|ATA Device)\s*$', '').Trim()
                                            if ($shortDisk.Length -gt 22) { $shortDisk = $shortDisk.Substring(0, 22).Trim() }
                                            $diskNames.Add($shortDisk)
                                        }
                                    } finally {
                                        $childKey.Dispose()
                                    }
                                }
                            }
                            $shortCtrl = $devName -replace '^Standard\s+', ''
                            if ($diskNames.Count -gt 0) {
                                $devName = "$shortCtrl [$($diskNames -join ', ')]"
                            } elseif (-not [string]::IsNullOrEmpty($bdfTag)) {
                                $devName = "$shortCtrl [Empty $bdfTag]"
                            }
                        } elseif ($isUsb -and -not [string]::IsNullOrEmpty($bdfTag)) {
                            $shortUsb = ($devName -replace '\s*-\s*\d+\.\d+\s*\(Microsoft\)', '' -replace '\s*\(Microsoft\)', '' -replace 'eXtensible Host Controller', 'XHCI').Trim()
                            $devName  = "$shortUsb [$bdfTag]"
                        }

                        $deviceRole    = "Other"
                        $sortRank      = 50
                        $adviceText    = "Standard PCI Bus"
                        $isRecommended = $false

                        # Keep GPU and NIC at the top of the table (SortRank 1..4) even after being offloaded to C1
                        if ($isGpu) {
                            $deviceRole = "GPU"
                            if ($isOnCore0) {
                                $sortRank      = 1
                                $isRecommended = $true
                                $adviceText    = "★ OFFLOAD TO C1 (Heavy GPU DPC)"
                            } else {
                                $sortRank   = 3
                                $adviceText = "✓ Offloaded (Drives dxgkrnl)"
                            }
                        } elseif ($isNic) {
                            $deviceRole = "NIC"
                            if ($isOnCore0) {
                                $sortRank      = 2
                                $isRecommended = $true
                                $adviceText    = "★ OFFLOAD TO C1 (Drives ndis.sys)"
                            } else {
                                $sortRank   = 4
                                $adviceText = "✓ Offloaded (Drives ndis.sys)"
                            }
                        } elseif ($isUsb) {
                            $deviceRole = "USB"
                            if ($isOnCore0) {
                                $sortRank   = 10
                                $adviceText = "Optional C1 (HID via Wdf01000)"
                            } else {
                                $sortRank   = 11
                                $adviceText = "✓ Offloaded (HID via Wdf01000)"
                            }
                        } elseif ($isStorage) {
                            $deviceRole = "Storage"
                            $sortRank   = 20
                            $adviceText = "Keep Spread (Multi-Queue I/O)"
                        } elseif ($isAudio) {
                            $deviceRole = "Audio"
                            $sortRank   = 30
                            $adviceText = "Audio Bus (Keep Default MSI)"
                        }

                        $msiBadge     = if ($isMsiEnabled) { "ON" } else { "OFF" }
                        $instFullPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId"
                        $irqMgmtPath  = "$instFullPath\Device Parameters\Interrupt Management"

                        $results.Add([PSCustomObject]@{
                            UIDisplayName        = "$devName [MSI: $msiBadge | Prio: $prioLabel | Mask: $affLabel | $adviceText]"
                            MsiStatus            = $msiBadge
                            RawDeviceName        = $devName
                            DeviceRole           = $deviceRole
                            ServiceName          = $etwModuleKey
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
                                IrqMgmtPath  = $irqMgmtPath
                                Path         = "$irqMgmtPath\MessageSignaledInterruptProperties"
                                AffinityPath = "$irqMgmtPath\Affinity Policy"
                                DevicePath   = $instFullPath
                            }
                        })
                    } finally {
                        $instKey.Dispose()
                    }
                }
            } finally {
                $venKey.Dispose()
            }
        }
    } finally {
        $pciRoot.Dispose()
        if ($null -ne $enumRoot) { $enumRoot.Dispose() }
        if ($null -ne $svcRoot)  { $svcRoot.Dispose() }
    }

    return @($results | Sort-Object SortRank, RawDeviceName)
}

function Get-HardwareState_WHEA {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    $coreCount = $coreMasks.Count

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

            $apicId   = "N/A"
            $coreInfo = ""
            $msg      = $evt.Message
            $id       = $evt.Id

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
                $lpIdx = [int]$apicId
                $matchedCore = -1
                if ($lpIdx -ge 0 -and $lpIdx -lt 63) {
                    $threadBit = ([int64]1 -shl $lpIdx)
                    for ($c = 0; $c -lt $coreCount; $c++) {
                        if (($coreMasks[$c] -band $threadBit) -ne 0) {
                            $matchedCore = $c
                            break
                        }
                    }
                }
                if ($matchedCore -ge 0) {
                    $coreInfo = "(Core $matchedCore)"
                } else {
                    $coreInfo = "(LP#$lpIdx)"
                }
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
    $val = (Get-ItemProperty -LiteralPath $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue).GlobalTimerResolutionRequests
    $isGlobalOpt = ($null -ne $val -and $val -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Global Timer Resolution (Kernel Fix)"
        IsOptimized   = $isGlobalOpt
        ActionData    = @{ Type = "Reg"; Path = $regPath; Name = "GlobalTimerResolutionRequests"; Value = 1 }
    })
    
    $hpetInstance = $null
    $hpetRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\PNP0103"
    if (Test-Path -LiteralPath $hpetRoot) {
        foreach ($sub in (Get-ChildItem -LiteralPath $hpetRoot -ErrorAction SilentlyContinue)) {
            $candId = "ACPI\PNP0103\$($sub.PSChildName)"
            if ([WinUltix.PnpTree]::GetDeviceConfigStatus($candId) -ge 0) {
                $hpetInstance = $candId
                break
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($hpetInstance)) {
        $isHpetDisabled = [WinUltix.PnpTree]::IsDeviceDisabled($hpetInstance)
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Disable HPET (Device Manager)"
            IsOptimized   = $isHpetDisabled
            ActionData    = @{ Type = "PNP"; Instance = $hpetInstance }
        })
    }

    $bcd = (bcdedit.exe /enum "{current}" 2>$null) -join " "
    
    $dynTickOpt = ($bcd -match "(?i)disabledynamictick\s+(Yes|Tak|True|1)")
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Disable Dynamic Tick (Power Saving)"
        IsOptimized   = $dynTickOpt
        ActionData    = @{ Type = "BCD"; Cmd = "disabledynamictick yes" }
    })
    
    $platClockOpt = (-not ($bcd -match "(?i)useplatformclock\s+(Yes|Tak|True|1)"))
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Disable Platform Clock (Force TSC)"
        IsOptimized   = $platClockOpt
        ActionData    = @{ Type = "BCD"; Cmd = "useplatformclock no" }
    })
	
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
    $aspm = (Get-ItemProperty -LiteralPath $pciPath -Name "DisableASPM" -ErrorAction SilentlyContinue).DisableASPM
    $isAspmOpt = ($null -ne $aspm -and $aspm -eq 1)
    $results.Add([PSCustomObject]@{ UIDisplayName = "PCIe ASPM Global Bus Lock (DisableASPM)"; IsOptimized = $isAspmOpt; ActionData = @{ Type="Reg"; Path=$pciPath; Name="DisableASPM"; Val=1 } })

    $nvmePath = "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device"
    $nvmeIdle = (Get-ItemProperty -LiteralPath $nvmePath -Name "IdlePowerMode" -ErrorAction SilentlyContinue).IdlePowerMode
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
    if (-not (Test-Path -LiteralPath $configPath)) { New-Item -Path $configPath -Force -ErrorAction SilentlyContinue | Out-Null }

    foreach ($item in $SelectedItems) {
        $exeName  = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        Set-ItemProperty -LiteralPath $configPath -Name $exeName -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                try {
                    Write-GUI " -> Live Locking ($($topo.CoreDesc)): $exeName ($($procs.Count) instances)"
                    foreach ($p in $procs) {
                        try { 
                            $p.ProcessorAffinity = $targetMask 
                            $p.PriorityClass     = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                        } catch {
                            Write-GUI "    [!] Access denied: PID $($p.Id) (System lock)"
                        }
                    }
                } finally {
                    foreach ($p in $procs) { if ($null -ne $p) { $p.Dispose() } }
                }
            } else {
                Write-GUI " -> Saved to config (Currently not running): $exeName"
            }
        } else {
            Write-GUI " -> Saved to Target Roster: $exeName"
        }
    }
}

function Remove-AppAffinity {
    param([array]$SelectedItems, [bool]$Execute = $true, [bool]$KeepConfig = $false)
    if ($SelectedItems.Count -eq 0) { return }

    $configPath     = "HKCU:\Software\WinUltix\AffinityLasso"
    $lpCount        = [Environment]::ProcessorCount
    $fullMaskVal    = if ($lpCount -ge 64) { -1 } else { ([int64]1 -shl $lpCount) - 1 }
    $systemAffinity = [System.IntPtr]$fullMaskVal

    foreach ($item in $SelectedItems) {
        $exeName  = $item.ActionData.ExeName
        $procName = $item.ActionData.ProcName
        
        if (-not $KeepConfig -and (Test-Path -LiteralPath $configPath)) { 
            Remove-ItemProperty -LiteralPath $configPath -Name $exeName -Force -ErrorAction SilentlyContinue 
        }

        if ($Execute) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -gt 0) {
                try {
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
                                $p.PriorityClass     = [System.Diagnostics.ProcessPriorityClass]::Normal
                            } catch { } 
                        }
                    }
                } finally {
                    foreach ($p in $procs) { if ($null -ne $p) { $p.Dispose() } }
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
                if (-not (Test-Path -LiteralPath $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -LiteralPath $data.Path -Name $data.Name -Value $data.Value -Type DWord -Force -ErrorAction Stop
            } elseif ($data.Type -eq "BCD") {
                $cmdArgs = $data.Cmd.Split(' ')
                if ($cmdArgs[0] -eq "useplatformclock" -and $cmdArgs[1] -eq "no") {
                    $null = & bcdedit.exe /deletevalue "{current}" useplatformclock 2>&1
                } else {
                    $null = & bcdedit.exe /set "{current}" $cmdArgs[0] $cmdArgs[1] 2>&1
                }
            } elseif ($data.Type -eq "PNP") {
                $null = & pnputil.exe /disable-device "$($data.Instance)" 2>&1
                if (-not [WinUltix.PnpTree]::IsDeviceDisabled($data.Instance)) {
                    throw "pnputil failed to disable $($data.Instance)"
                }
            }
        } catch {
            Write-GUI "    [!] Failed to apply: $($item.UIDisplayName)"
        }
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
                if (-not (Test-Path -LiteralPath $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -LiteralPath $data.Path -Name $data.Name -Value $data.Val -Type DWord -Force -ErrorAction Stop
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
    $affRoster = [System.Collections.Generic.List[string]]::new()
    $affPath   = "HKCU:\Software\WinUltix\AffinityLasso"
    if (Test-Path -LiteralPath $affPath) {
        $regObj = Get-Item -LiteralPath $affPath -ErrorAction SilentlyContinue
        if ($null -ne $regObj) {
            try {
                foreach ($p in $regObj.Property) {
                    if ($p -match '\.exe$') { $affRoster.Add($p) }
                }
            } finally {
                $regObj.Dispose()
            }
        }
    }

    $cppcUnhidden = @(Get-HardwareState_CPPC | Where-Object { -not $_.IsDetected } | ForEach-Object { [string]$_.ActionData.KeyId })
    $timerOpt     = @(Get-HardwareState_Timer | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)
    $nvmeOpt      = @(Get-HardwareState_NVMe  | Where-Object { $_.IsOptimized } | Select-Object -ExpandProperty UIDisplayName)

    $globalNet = [System.Collections.Generic.List[string]]::new()
    $offload   = Get-NetOffloadGlobalSetting -ErrorAction SilentlyContinue
    if ($null -ne $offload) {
        if ($offload.ReceiveSideScaling -eq 'Enabled')          { $globalNet.Add("[Global] TCP Receive-Side Scaling (RSS)") }
        if ($offload.ReceiveSegmentCoalescing -eq 'Disabled')   { $globalNet.Add("[Global] TCP Recv Segment Coalescing (RSC)") }
    }

    return [ordered]@{
        AffinityLasso = @($affRoster)
        CPPCUnhidden  = @($cppcUnhidden)
        TimerTweaks   = @($timerOpt)
        NVMeTweaks    = @($nvmeOpt)
        GlobalNetwork = @($globalNet)
    }
}

function Import-UltixHardwareSnapshot {
    param([Parameter(Mandatory=$true)]$ProfileData)

    $affList = @($ProfileData.AffinityLasso)
    if ($affList.Count -gt 0) {
        $affPath = "HKCU:\Software\WinUltix\AffinityLasso"
        if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force | Out-Null }

        $affItems = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($exe in $affList) {
            if ([string]::IsNullOrWhiteSpace($exe)) { continue }
            Set-ItemProperty -LiteralPath $affPath -Name $exe -Value 1 -Type DWord -Force
            $affItems.Add([PSCustomObject]@{
                ActionData = @{
                    ExeName  = [string]$exe
                    ProcName = ([string]$exe -replace '\.exe$', '')
                }
            })
        }

        $topo = Get-CPUTopologyProfile
        if ($topo.IsSupported -and $affItems.Count -gt 0) {
            Set-AppAffinity -SelectedItems @($affItems) -Execute $true
        } else {
            Write-GUI " -> Restored $($affList.Count) process(es) to Affinity Lasso roster."
        }
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

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 60)
    $listView.Size = New-Object System.Drawing.Size(800, 480)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $listView.BorderStyle = "FixedSingle"
    $listView.Font = New-Object System.Drawing.Font("Consolas", 10.5)
    $listView.Anchor = 'Top, Bottom, Left, Right'
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.GridLines = $false
    Enable-UltixDoubleBuffer -Control $listView

    $listView.Columns.Add("Status & App Name", 250) | Out-Null
    $listView.Columns.Add("Priority", 110) | Out-Null
    $listView.Columns.Add("Executable Path", 415) | Out-Null
    
    $bgEven = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $bgOdd  = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $listView.BeginUpdate()
        $listView.Items.Clear(); $localData.Clear()
        $auditData = Get-HardwareState_Affinity
        $rIdx = 0
        foreach ($item in $auditData) {
            [void]$localData.Add($item)
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.UIDisplayName)
            $lvItem.SubItems.Add($item.Priority)
            $lvItem.SubItems.Add($item.Path)
            $lvItem.Checked = $item.IsDetected
            $lvItem.BackColor = if (($rIdx % 2) -eq 0) { $bgEven } else { $bgOdd }

            if ($item.UIDisplayName -match '^\[LOCKED\]') {
                $lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 145, 230, 165)
            } elseif ($item.UIDisplayName -match '^\[RUNNING\]') {
                $lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 215, 250)
            } elseif ($item.UIDisplayName -match '^\[SAVED\]') {
                $lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 225, 232)
            } else {
                $lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 140, 148, 158)
            }

            [void]$listView.Items.Add($lvItem)
            $rIdx++
        }
        $listView.EndUpdate()
    }
    &$refreshData
    $btnRefresh.Add_Click({ &$refreshData }.GetNewClosure())

    $txtCustom = New-Object System.Windows.Forms.TextBox; $txtCustom.Location = New-Object System.Drawing.Point(15, 555); $txtCustom.Size = New-Object System.Drawing.Size(250, 25); $txtCustom.BackColor = [System.Drawing.Color]::FromArgb(255, 38, 40, 45); $txtCustom.ForeColor = [System.Drawing.Color]::White; $txtCustom.BorderStyle = "FixedSingle"; $txtCustom.Font = New-Object System.Drawing.Font("Segoe UI", 10); $txtCustom.Anchor = 'Bottom, Left'
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
        $toRemove = @()
        foreach ($item in $listView.SelectedItems) {
            if ($item.Index -ge 0 -and $item.Index -lt $localData.Count) {
                $toRemove += $localData[$item.Index]
            }
        }
        if ($toRemove.Count -gt 0) {
            Remove-AppAffinity -SelectedItems $toRemove -Execute $true -KeepConfig $false
            &$refreshData
        }
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
    
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 60); $chkList.Size = New-Object System.Drawing.Size(600, 280); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
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
    $modal.Text = $Title; $modal.Size = New-Object System.Drawing.Size(1280, 800); $modal.StartPosition = "CenterParent"; $modal.FormBorderStyle = "Sizable"; $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30); $modal.ForeColor = [System.Drawing.Color]::White
    $modal.MinimumSize = New-Object System.Drawing.Size(1180, 700)
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label; $lblDesc.Text = $Description; $lblDesc.Location = New-Object System.Drawing.Point(15, 10); $lblDesc.Size = New-Object System.Drawing.Size(1235, 22); $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 10); $lblDesc.Anchor = 'Top, Left, Right'
    
    $lblWarning = New-Object System.Windows.Forms.Label; $lblWarning.Text = "[!] System reboot is strictly required to apply new MSI vectors, Interrupt Priority, and Core Affinity."; $lblWarning.Location = New-Object System.Drawing.Point(15, 34); $lblWarning.Size = New-Object System.Drawing.Size(1235, 20); $lblWarning.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $lblWarning.ForeColor = [System.Drawing.Color]::Orange; $lblWarning.Anchor = 'Top, Left, Right'

    $lblDpcMonitor = New-Object System.Windows.Forms.Label
    $lblDpcMonitor.Location = New-Object System.Drawing.Point(15, 58)
    $lblDpcMonitor.Size = New-Object System.Drawing.Size(1235, 84)
    $lblDpcMonitor.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblDpcMonitor.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblDpcMonitor.Font = New-Object System.Drawing.Font("Consolas", 9.0, [System.Drawing.FontStyle]::Bold)
    $lblDpcMonitor.TextAlign = "TopLeft"
    $lblDpcMonitor.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 4)
    $lblDpcMonitor.BorderStyle = "FixedSingle"
    $lblDpcMonitor.Anchor = 'Top, Left, Right'

    $lblDpcLegend = New-Object System.Windows.Forms.Label
    $lblDpcLegend.Text = "Metrics: Avg Load = Session average (µs/s) | Max = Worst single-call latency spike (µs) | 1s = Last second total (µs/s) | Colors: Orange (Max >=350 µs) | Red (Max >=1000 µs)"
    $lblDpcLegend.Location = New-Object System.Drawing.Point(15, 145)
    $lblDpcLegend.Size = New-Object System.Drawing.Size(1235, 18)
    $lblDpcLegend.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
    $lblDpcLegend.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcLegend.Anchor = 'Top, Left, Right'

    $lblPrio = New-Object System.Windows.Forms.Label
    $lblPrio.Text = "Priority:"
    $lblPrio.Location = New-Object System.Drawing.Point(15, 170)
    $lblPrio.Size = New-Object System.Drawing.Size(55, 22)
    $lblPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $lblPrio.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $comboPrio = New-Object System.Windows.Forms.ComboBox
    $comboPrio.Location = New-Object System.Drawing.Point(72, 167)
    $comboPrio.Size = New-Object System.Drawing.Size(140, 25)
    $comboPrio.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $comboPrio.ForeColor = [System.Drawing.Color]::White
    $comboPrio.DropDownStyle = "DropDownList"
    $comboPrio.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    [void]$comboPrio.Items.AddRange(@("Keep Current", "High (3)", "Normal (2)", "Low (1)", "Undefined (Default)"))
    $comboPrio.SelectedIndex = 0

    $chkOffloadCore0 = New-Object System.Windows.Forms.CheckBox
    $chkOffloadCore0.Text = "Offload C0 -> C1"
    $chkOffloadCore0.Location = New-Object System.Drawing.Point(222, 168)
    $chkOffloadCore0.Size = New-Object System.Drawing.Size(135, 24)
    $chkOffloadCore0.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $chkOffloadCore0.ForeColor = [System.Drawing.Color]::LightGray
    $chkOffloadCore0.Checked = $false

    $chkShowKernel = New-Object System.Windows.Forms.CheckBox
    $chkShowKernel.Text = "Show OS Kernel .sys"
    $chkShowKernel.Location = New-Object System.Drawing.Point(362, 168)
    $chkShowKernel.Size = New-Object System.Drawing.Size(150, 24)
    $chkShowKernel.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $chkShowKernel.ForeColor = [System.Drawing.Color]::Cyan
    $chkShowKernel.Checked = $true

    $lblSort = New-Object System.Windows.Forms.Label
    $lblSort.Text = "Sort By:"
    $lblSort.Location = New-Object System.Drawing.Point(518, 170)
    $lblSort.Size = New-Object System.Drawing.Size(52, 22)
    $lblSort.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $lblSort.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $comboSort = New-Object System.Windows.Forms.ComboBox
    $comboSort.Location = New-Object System.Drawing.Point(572, 167)
    $comboSort.Size = New-Object System.Drawing.Size(225, 25)
    $comboSort.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)
    $comboSort.ForeColor = [System.Drawing.Color]::White
    $comboSort.DropDownStyle = "DropDownList"
    $comboSort.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    [void]$comboSort.Items.AddRange(@(
        "Default (Offload Advice ★)",
        "Avg Driver Load (µs/s) [Reliable]",
        "Peak Driver Spike (Max µs)",
        "Live 1s Driver Load (µs/s)",
        "Device / Subsystem Name (A-Z)",
        "Driver Name (.sys)"
    ))
    $comboSort.SelectedIndex = 0

    $btnResetStats = New-UltixButton -Parent $modal -Text "Reset Stats" -X 940 -Y 166 -Width 110 -Height 27 -RGB @(65, 70, 78)
    $btnResetStats.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btnResetStats.Anchor = 'Top, Right'

    $btnSelRec = New-UltixButton -Parent $modal -Text "Select ★ GPU/NIC" -X 1060 -Y 166 -Width 190 -Height 27 -RGB @(50, 85, 120)
    $btnSelRec.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $btnSelRec.Anchor = 'Top, Right'

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 200)
    $listView.Size = New-Object System.Drawing.Size(1235, 498)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 230, 236, 242)
    $listView.BorderStyle = "FixedSingle"
    $listView.Font = New-Object System.Drawing.Font("Consolas", 9.0)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.CheckBoxes = $true
    $listView.FullRowSelect = $true
    $listView.GridLines = $false
    $listView.Anchor = 'Top, Bottom, Left, Right'
    Enable-UltixDoubleBuffer -Control $listView

    # Zero-glare dark engineering palette matching Show-UltixGridModal
    $bgEven   = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $bgOdd    = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
    $bgRec    = [System.Drawing.Color]::FromArgb(255, 44, 38, 22)
    $bgWarn   = [System.Drawing.Color]::FromArgb(255, 48, 36, 20)
    $bgSpike  = [System.Drawing.Color]::FromArgb(255, 54, 26, 28)

    $fgPciOk  = [System.Drawing.Color]::FromArgb(255, 225, 232, 240)
    $fgMsiOff = [System.Drawing.Color]::FromArgb(255, 165, 205, 245)
    $fgRec    = [System.Drawing.Color]::FromArgb(255, 255, 215, 105)
    $fgKernel = [System.Drawing.Color]::FromArgb(255, 135, 195, 225)
    $fgWarn   = [System.Drawing.Color]::FromArgb(255, 255, 190, 95)
    $fgSpike  = [System.Drawing.Color]::FromArgb(255, 255, 150, 150)

    $sorter = New-Object WinUltix.ListViewColumnSorter
    $listView.ListViewItemSorter = $sorter

    [void]$listView.Columns.Add("MSI", 78)
    [void]$listView.Columns.Add("PCI Device / OS Subsystem", 275)
    [void]$listView.Columns.Add("Driver", 140)
    [void]$listView.Columns.Add("Avg (µs/s)", 100)
    [void]$listView.Columns.Add("Peak | 1s Load", 206)
    [void]$listView.Columns.Add("Priority", 70)
    [void]$listView.Columns.Add("IRQ Mask", 95)
    [void]$listView.Columns.Add("DPC Assessment", 248)

    $styleMsiRow = {
        param(
            [System.Windows.Forms.ListViewItem]$LvItem,
            [int]$RowIndex,
            $LoadRecord = $null
        )
        $dev = $LvItem.Tag
        $targetBg = if (($RowIndex % 2) -eq 0) { $bgEven } else { $bgOdd }
        $targetFg = $fgPciOk

        if ($null -ne $LoadRecord -and ($LoadRecord.MaxPeakUs -ge 1000.0 -or $LoadRecord.AvgUsPerSec -ge 50000.0)) {
            $targetBg = $bgSpike
            $targetFg = $fgSpike
        } elseif ($null -ne $LoadRecord -and $LoadRecord.MaxPeakUs -ge 350.0) {
            $targetBg = $bgWarn
            $targetFg = $fgWarn
        } elseif ($null -ne $dev) {
            if ($dev.IsKernelOnly -eq $true) {
                $targetFg = $fgKernel
            } elseif ($dev.IsRecommendedOffload) {
                $targetBg = $bgRec
                $targetFg = $fgRec
            } elseif (-not $dev.IsDetected) {
                $targetFg = $fgMsiOff
            }
        }

        if ($LvItem.BackColor -ne $targetBg) { $LvItem.BackColor = $targetBg }
        if ($LvItem.ForeColor -ne $targetFg) { $LvItem.ForeColor = $targetFg }
    }

    $reapplyAllRowShading = {
        for ($idx = 0; $idx -lt $listView.Items.Count; $idx++) {
            $it = $listView.Items[$idx]
            $dev = $it.Tag
            $curBg = $it.BackColor
            if ($curBg -ne $bgSpike -and $curBg -ne $bgWarn) {
                $newBg = if ($null -ne $dev -and $dev.IsRecommendedOffload -and $dev.IsKernelOnly -ne $true) {
                    $bgRec
                } elseif (($idx % 2) -eq 0) {
                    $bgEven
                } else {
                    $bgOdd
                }
                if ($it.BackColor -ne $newBg) { $it.BackColor = $newBg }
            }
        }
    }

    $listView.Add_ItemCheck({
        param($src, $e)
        $lvItem = $src.Items[$e.Index]
        if ($null -ne $lvItem -and $null -ne $lvItem.Tag -and $lvItem.Tag.IsKernelOnly -eq $true) {
            $e.NewValue = [System.Windows.Forms.CheckState]::Unchecked
        }
    })

    $applySortMode = {
        $listView.BeginUpdate()
        switch ($comboSort.SelectedIndex) {
            0 {
                $listView.ListViewItemSorter = $null
                $sortedItems = @($listView.Items | Sort-Object { $_.Tag.SortRank }, { $_.Tag.RawDeviceName })
                $listView.Items.Clear()
                foreach ($si in $sortedItems) { [void]$listView.Items.Add($si) }
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::None
                $listView.ListViewItemSorter = $sorter
            }
            1 { $sorter.ColumnToSort = 3;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
            2 { $sorter.ColumnToSort = 4;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
            3 { $sorter.ColumnToSort = -1; $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending; $listView.Sort() }
            4 { $sorter.ColumnToSort = 1;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending;  $listView.Sort() }
            5 { $sorter.ColumnToSort = 2;  $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending;  $listView.Sort() }
        }
        & $reapplyAllRowShading
        $listView.EndUpdate()
    }

    $comboSort.Add_SelectedIndexChanged({ & $applySortMode }.GetNewClosure())

    $chkShowKernel.Add_CheckedChanged({
        if (-not $chkShowKernel.Checked) {
            $listView.BeginUpdate()
            for ($i = $listView.Items.Count - 1; $i -ge 0; $i--) {
                if ($listView.Items[$i].Tag.IsKernelOnly -eq $true) {
                    $listView.Items.RemoveAt($i)
                }
            }
            & $reapplyAllRowShading
            $listView.EndUpdate()
        }
    }.GetNewClosure())

    $listView.Add_ColumnClick({
        param($src, $e)
        $listView.BeginUpdate()
        if ($e.Column -eq $sorter.ColumnToSort) {
            if ($sorter.OrderOfSort -eq [System.Windows.Forms.SortOrder]::Descending) {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Ascending
            } else {
                $sorter.OrderOfSort = [System.Windows.Forms.SortOrder]::Descending
            }
        } else {
            $sorter.ColumnToSort = $e.Column
            $sorter.OrderOfSort = if ($e.Column -in @(3, 4)) {
                [System.Windows.Forms.SortOrder]::Descending
            } else {
                [System.Windows.Forms.SortOrder]::Ascending
            }
        }
        $listView.Sort()
        & $reapplyAllRowShading
        $listView.EndUpdate()
    }.GetNewClosure())

    $etwStarted = $false
    try { $etwStarted = [WinUltix.DpcDriverProfiler]::Start() } catch { $etwStarted = $false }

    $btnResetStats.Add_Click({
        if ($etwStarted) {
            [WinUltix.DpcDriverProfiler]::ResetStats()
            $listView.BeginUpdate()
            for ($i = $listView.Items.Count - 1; $i -ge 0; $i--) {
                $lvItem = $listView.Items[$i]
                $dev = $lvItem.Tag
                if ($null -ne $dev -and $dev.IsKernelOnly -eq $true) {
                    $listView.Items.RemoveAt($i)
                    continue
                }
                $lvItem.SubItems[3].Text = "   0.0 µs/s"
                $lvItem.SubItems[4].Text = "Max:    0 µs (1s: 0.0)"
            }
            for ($r = 0; $r -lt $listView.Items.Count; $r++) {
                & $styleMsiRow $listView.Items[$r] $r $null
            }
            $listView.EndUpdate()
        }
    }.GetNewClosure())

    $pciServiceKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roleMaskMap    = @{
        "GPU"     = "-> Default"
        "NIC"     = "-> Default"
        "USB"     = "-> Default"
        "Storage" = "-> Spread"
        "System"  = "All / C0"
    }

    $kernelRoleCatalog = @{
        "dxgkrnl"   = @{ Name = "[OS] DirectX Graphics Kernel";        Role = "GPU";     Advice = "Follows GPU IRQ (nvlddmkm/amdkmdag)" }
        "dxgmms2"   = @{ Name = "[OS] DirectX Video Memory Manager";   Role = "GPU";     Advice = "Follows GPU VRAM Paging / IRQ" }
        "wdf01000"  = @{ Name = "[OS] KMDF Driver Framework Runtime";  Role = "USB";     Advice = "Aggregates USBXHCI / HID / Audio DPCs" }
        "ndis"      = @{ Name = "[OS] NDIS Network Subsystem";         Role = "NIC";     Advice = "Aggregates NIC IRQ (Offload NIC -> C1)" }
        "tcpip"     = @{ Name = "[OS] Windows TCP/IP Network Stack";   Role = "NIC";     Advice = "Follows NIC RSS / Interrupt Core" }
        "usbport"   = @{ Name = "[OS] USB 2.0 EHCI Port Driver";       Role = "USB";     Advice = "Legacy USB 2.0 EHCI Host Wrapper" }
        "ntoskrnl"  = @{ Name = "[OS] Windows NT Executive & Timer";   Role = "System";  Advice = "OS Scheduler & Timer (Core 0 / All)" }
        "hal"       = @{ Name = "[OS] Hardware Abstraction Layer";     Role = "System";  Advice = "Hardware Timer & APIC Routing" }
        "acpi"      = @{ Name = "[OS] ACPI Power & Thermal Driver";    Role = "System";  Advice = "BIOS AML / EC Polling (Core 0)" }
        "storport"  = @{ Name = "[OS] Storage Port Miniport Driver";   Role = "Storage"; Advice = "Aggregates NVMe / SATA Multi-Queue" }
        "classpnp"  = @{ Name = "[OS] Storage Class PnP Driver";       Role = "Storage"; Advice = "Follows Disk / Storage I/O Stack" }
        "fltmgr"    = @{ Name = "[OS] Filesystem Filter Manager";      Role = "Storage"; Advice = "Storage I/O Minifilter Stack" }
        "ntfs"      = @{ Name = "[OS] NTFS File System Driver";        Role = "Storage"; Advice = "Volume Metadata & File I/O Stack" }
        "iorate"    = @{ Name = "[OS] Volume I/O Rate Filter Driver";  Role = "Storage"; Advice = "OS Disk QoS & Storage I/O Limiter" }
        "symcryptk" = @{ Name = "[OS] Windows Kernel Crypto Library";  Role = "System";  Advice = "IPsec / SMB / TLS Kernel Crypto" }
        "mouclass"  = @{ Name = "[OS] Mouse Class Driver";             Role = "USB";     Advice = "Follows USB XHCI / HID Core" }
        "kbdclass"  = @{ Name = "[OS] Keyboard Class Driver";          Role = "USB";     Advice = "Follows USB XHCI / HID Core" }
    }

    $refreshData = {
        $previouslyChecked = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($chkIt in $listView.CheckedItems) {
            if ($null -ne $chkIt.Tag -and $null -ne $chkIt.Tag.ActionData -and $chkIt.Tag.ActionData.DevicePath) {
                [void]$previouslyChecked.Add([string]$chkIt.Tag.ActionData.DevicePath)
            }
        }

        $listView.BeginUpdate()
        $listView.ListViewItemSorter = $null
        $listView.Items.Clear()
        $pciServiceKeys.Clear()
        $auditData = Get-HardwareState_IRQ

        # Compute inherited IRQ Mask summary per hardware role (GPU, NIC, USB, Storage) for KERNEL rows
        foreach ($rName in @("GPU", "NIC", "USB", "Storage")) {
            $rItems = @($auditData | Where-Object { $_.DeviceRole -eq $rName })
            if ($rItems.Count -eq 0) {
                $roleMaskMap[$rName] = if ($rName -eq "Storage") { "-> Spread" } else { "-> Default" }
                continue
            }
            $uMasks = @($rItems | Select-Object -ExpandProperty AffinityLabel -Unique)
            if ($uMasks.Count -eq 1) {
                $roleMaskMap[$rName] = "-> $($uMasks[0])"
            } else {
                $customMasks = @($uMasks | Where-Object { $_ -ne "Default" -and $_ -ne "Spread" })
                if ($customMasks.Count -gt 0) {
                    $roleMaskMap[$rName] = "-> $($customMasks[0])*"
                } elseif ($uMasks -contains "Spread") {
                    $roleMaskMap[$rName] = "-> Spread"
                } else {
                    $roleMaskMap[$rName] = "-> Default"
                }
            }
        }

        $rIdx = 0
        foreach ($item in $auditData) {
            if (-not [string]::IsNullOrWhiteSpace($item.ServiceName)) {
                [void]$pciServiceKeys.Add($item.ServiceName.ToLowerInvariant())
            }
            $item | Add-Member -NotePropertyName IsKernelOnly -NotePropertyValue $false -Force
            $lvItem = New-Object System.Windows.Forms.ListViewItem($item.MsiStatus)
            [void]$lvItem.SubItems.Add($item.RawDeviceName)
            [void]$lvItem.SubItems.Add($item.DriverTag)
            $initAvg  = if ($etwStarted) { "   0.0 µs/s" } else { "N/A (ETW Busy)" }
            $initPeak = if ($etwStarted) { "Max:    0 µs (1s: 0.0)" } else { "N/A" }
            [void]$lvItem.SubItems.Add($initAvg)
            [void]$lvItem.SubItems.Add($initPeak)
            [void]$lvItem.SubItems.Add($item.PrioLabel)
            [void]$lvItem.SubItems.Add($item.AffinityLabel)
            [void]$lvItem.SubItems.Add($item.AdviceText)
            $lvItem.Tag = $item
            $lvItem.Checked = $previouslyChecked.Contains([string]$item.ActionData.DevicePath)

            & $styleMsiRow $lvItem $rIdx $null
            [void]$listView.Items.Add($lvItem)
            $rIdx++
        }
        $listView.ListViewItemSorter = $sorter
        $listView.EndUpdate()
        & $applySortMode
    }
    &$refreshData

    $dpcState = @{ PrevCounts = $null; IsRunning = $true; LastSnap = $null }
    Update-UltixDpcMonitorUI -TargetLabel $lblDpcMonitor -State $dpcState
    if ($etwStarted) {
        $lblDpcMonitor.Text += "`r`nTOP .SYS (AVG) | Sampling real-time kernel ETW ISR/DPC driver routines..."
    } else {
        $lblDpcMonitor.Text += "`r`nTOP .SYS (AVG) | [Kernel ETW session occupied by another profiler]"
    }

    $dpcTimer = New-Object System.Windows.Forms.Timer
    $dpcTimer.Interval = 1000
    $dpcTimer.Tag = @{
        Modal          = $modal
        Label          = $lblDpcMonitor
        ListView       = $listView
        Sorter         = $sorter
        ChkKernel      = $chkShowKernel
        PciKeys        = $pciServiceKeys
        KernelCatalog  = $kernelRoleCatalog
        RoleMasks      = $roleMaskMap
        State          = $dpcState
        EtwEnabled     = $etwStarted
        StyleRow       = $styleMsiRow
    }
    $dpcTimer.Add_Tick({
        $ctx = $this.Tag
        if ($null -eq $ctx -or $ctx.Modal.IsDisposed -or $ctx.Label.IsDisposed) {
            $this.Stop()
            return
        }
        Update-UltixDpcMonitorUI -TargetLabel $ctx.Label -State $ctx.State

        if (-not $ctx.EtwEnabled) {
            $ctx.Label.Text += "`r`nTOP .SYS (AVG) | [Kernel ETW session occupied by another profiler]"
            return
        }

        $drvSamples = @([WinUltix.DpcDriverProfiler]::SampleDriverLoads())
        $drvLookup  = @{}
        $elapsedSec = 1
        foreach ($rec in $drvSamples) {
            $drvLookup[$rec.ServiceKey] = $rec
            if ($rec.ElapsedSec -gt $elapsedSec) { $elapsedSec = $rec.ElapsedSec }
        }

        $topDrivers = @($drvSamples | Sort-Object @{Expression="AvgUsPerSec"; Descending=$true}, @{Expression="MaxPeakUs"; Descending=$true} | Select-Object -First 3)
        $timeTag = if ($elapsedSec -ge 600) { "{0}m" -f [int]($elapsedSec / 60) } else { "{0}s" -f $elapsedSec }
        $hdrTag  = ("TOP .SYS ({0,4})" -f $timeTag)

        if ($topDrivers.Count -gt 0) {
            $topParts = [System.Collections.Generic.List[string]]::new()
            $rank = 1
            foreach ($td in $topDrivers) {
                $topParts.Add("$rank. $($td.DriverName) (Avg: $($td.AvgUsPerSec) µs/s | Max: $([math]::Round($td.MaxPeakUs, 0)) µs)")
                $rank++
            }
            $ctx.Label.Text += "`r`n$hdrTag | " + ($topParts -join "   ")
        } else {
            $ctx.Label.Text += "`r`n$hdrTag | Idle (<0.1 µs/s kernel driver ISR/DPC activity)"
        }

        $lv = $ctx.ListView
        $st = $ctx.Sorter
        if ($null -ne $lv -and -not $lv.IsDisposed) {
            $existingKernelRows = @{}
            for ($r = 0; $r -lt $lv.Items.Count; $r++) {
                $lvItem = $lv.Items[$r]
                $dev = $lvItem.Tag
                if ($null -eq $dev) { continue }
                $svcKey = if ($dev.ServiceName) { $dev.ServiceName.ToLowerInvariant() } else { "pci" }
                if ($dev.IsKernelOnly -eq $true) {
                    $existingKernelRows[$svcKey] = $lvItem
                    $kMeta = $ctx.KernelCatalog[$svcKey]
                    $kRole = if ($null -ne $kMeta -and $kMeta.Role) { $kMeta.Role } else { "System" }
                    $inheritedMask = if ($ctx.RoleMasks.ContainsKey($kRole)) { $ctx.RoleMasks[$kRole] } else { "All / C0" }
                    if ($lvItem.SubItems[6].Text -ne $inheritedMask) { $lvItem.SubItems[6].Text = $inheritedMask }
                }

                $rec = $drvLookup[$svcKey]
                if ($null -ne $rec -and ($rec.AvgUsPerSec -gt 0 -or $rec.MaxPeakUs -gt 0)) {
                    $avgText  = ("{0,6:0.0} µs/s" -f $rec.AvgUsPerSec)
                    $peakText = ("Max: {0,4:0} µs (1s: {1:0.0})" -f $rec.MaxPeakUs, $rec.UsPerSec)
                } else {
                    $avgText = "   0.0 µs/s"
                    # Indicate kernel dispatcher wrapper when PCI miniport delegates ISR/DPC to Wdf01000 / ndis / storport
                    if ($svcKey -match '^(usbxhci|usb4hostrouter|hdaudbus)$') {
                        $peakText = "Max:    0 µs (via Wdf01000)"
                    } elseif ($dev.SortRank -in @(2, 4)) {
                        $peakText = "Max:    0 µs (via ndis.sys)"
                    } elseif ($svcKey -match '^(storahci|stornvme|secnvme|iastor)') {
                        $peakText = "Max:    0 µs (via storport)"
                    } else {
                        $peakText = "Max:    0 µs (1s: 0.0)"
                    }
                }

                if ($lvItem.SubItems[3].Text -ne $avgText)  { $lvItem.SubItems[3].Text = $avgText }
                if ($lvItem.SubItems[4].Text -ne $peakText) { $lvItem.SubItems[4].Text = $peakText }

                & $ctx.StyleRow $lvItem $r $rec
            }

            if ($ctx.ChkKernel.Checked) {
                foreach ($rec in $drvSamples) {
                    if ($ctx.PciKeys.Contains($rec.ServiceKey)) { continue }
                    if ($existingKernelRows.ContainsKey($rec.ServiceKey)) { continue }
                    if ($rec.AvgUsPerSec -lt 1.0 -and $rec.MaxPeakUs -lt 15.0) { continue }

                    $meta = $ctx.KernelCatalog[$rec.ServiceKey]
                    $sysTitle  = if ($null -ne $meta) { $meta.Name } else { "[OS] $($rec.DriverName) Subsystem" }
                    $sysAdvice = if ($null -ne $meta) { $meta.Advice } else { "OS Kernel Driver (Non-PCI)" }
                    $sysRole   = if ($null -ne $meta -and $meta.Role) { $meta.Role } else { "System" }
                    $sysMask   = if ($ctx.RoleMasks.ContainsKey($sysRole)) { $ctx.RoleMasks[$sysRole] } else { "All / C0" }

                    $kItemObj = [PSCustomObject]@{
                        RawDeviceName        = $sysTitle
                        ServiceName          = $rec.ServiceKey
                        DriverTag            = $rec.DriverName
                        IsDetected           = $true
                        IsRecommendedOffload = $false
                        IsKernelOnly         = $true
                        SortRank             = 90
                    }

                    $kLv = New-Object System.Windows.Forms.ListViewItem("KERNEL")
                    [void]$kLv.SubItems.Add($sysTitle)
                    [void]$kLv.SubItems.Add($rec.DriverName)
                    [void]$kLv.SubItems.Add(("{0,6:0.0} µs/s" -f $rec.AvgUsPerSec))
                    [void]$kLv.SubItems.Add(("Max: {0,4:0} µs (1s: {1:0.0})" -f $rec.MaxPeakUs, $rec.UsPerSec))
                    [void]$kLv.SubItems.Add("System")
                    [void]$kLv.SubItems.Add($sysMask)
                    [void]$kLv.SubItems.Add($sysAdvice)
                    $kLv.Tag = $kItemObj

                    & $ctx.StyleRow $kLv $lv.Items.Count $rec
                    [void]$lv.Items.Add($kLv)
                }
            }

            if ($st.OrderOfSort -ne [System.Windows.Forms.SortOrder]::None -and
                $st.ColumnToSort -in @(3, 4, -1) -and
                [System.Windows.Forms.Control]::MouseButtons -eq [System.Windows.Forms.MouseButtons]::None) {
                $needsResort = $false
                for ($i = 0; $i -lt ($lv.Items.Count - 1); $i++) {
                    if ($st.Compare($lv.Items[$i], $lv.Items[$i + 1]) -gt 0) {
                        $needsResort = $true
                        break
                    }
                }
                if ($needsResort) {
                    $lv.BeginUpdate()
                    $lv.Sort()
                    for ($r = 0; $r -lt $lv.Items.Count; $r++) {
                        $it  = $lv.Items[$r]
                        $dev = $it.Tag
                        $svcKey = if ($null -ne $dev -and $dev.ServiceName) { $dev.ServiceName.ToLowerInvariant() } else { "pci" }
                        & $ctx.StyleRow $it $r $drvLookup[$svcKey]
                    }
                    $lv.EndUpdate()
                }
            }
        }
    })
    $dpcTimer.Start()

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
            $lvItem.Checked = ($null -ne $dev -and $dev.IsKernelOnly -ne $true -and [bool]$dev.IsRecommendedOffload)
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

    $btnForceMSI = New-UltixButton -Parent $modal -Text "Apply MSI & Policy" -X 15 -Y 708 -Width 180 -Height 38 -RGB @(150, 60, 60)
    $btnForceMSI.Anchor = 'Bottom, Left'
    $btnForceMSI.Add_Click({
        if ($listView.CheckedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No PCI devices selected. Check the devices you want to configure (or click 'Select ★ GPU/NIC').", "WinUltix - MSI & IRQ Enforcer") | Out-Null
            return
        }
        $changed = 0
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        if (-not (Test-Path -LiteralPath $bRoot)) { New-Item -Path $bRoot -Force | Out-Null }
        $prioSelection = [string]$comboPrio.SelectedItem
        $doOffload     = $chkOffloadCore0.Checked
        [byte[]]$offloadBytes = if ($doOffload) { &$getOffloadMaskBytes } else { $null }
        
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev -or $dev.IsKernelOnly -eq $true) { continue }
            $irqRoot = $dev.ActionData.IrqMgmtPath
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

            $isStorageSpread = ($dev.DeviceRole -eq "Storage" -or $dev.DevicePolicy -eq 5)

            $applyBlock = {
                Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop | Out-Null

                if ($prioSelection -ne "Keep Current") {
                    if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
                    switch ($prioSelection) {
                        "High (3)"            { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 3 -Type DWord -Force -ErrorAction Stop }
                        "Normal (2)"          { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 2 -Type DWord -Force -ErrorAction Stop }
                        "Low (1)"             { Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value 1 -Type DWord -Force -ErrorAction Stop }
                        "Undefined (Default)" { Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue }
                    }
                }

                # Protect Multi-Queue NVMe/SATA controllers from losing 'Spread' (DevicePolicy = 5)
                if ($doOffload -and $null -ne $offloadBytes) {
                    if ($isStorageSpread) {
                        Write-GUI "    [*] Preserved Multi-Queue 'Spread' policy on storage controller: $($dev.RawDeviceName)"
                    } else {
                        if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
                        Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 4 -Type DWord -Force -ErrorAction Stop
                        Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value $offloadBytes -Type Binary -Force -ErrorAction Stop
                    }
                }
            }

            try {
                try {
                    & $applyBlock
                } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
                    Grant-UltixRegistryKeyAccess -RegistryPath $irqRoot
                    Grant-UltixRegistryKeyAccess -RegistryPath $msiPath
                    if (Test-Path -LiteralPath $affPath) { Grant-UltixRegistryKeyAccess -RegistryPath $affPath }
                    & $applyBlock
                }
                Write-GUI " -> Configured IRQ/MSI policy: $($dev.RawDeviceName)"
                $changed++
            } catch {
                Write-GUI " -> [!] Failed to modify IRQ/MSI policy for $($dev.RawDeviceName): $($_.Exception.Message)"
            }
        }
        &$refreshData
        if ($changed -gt 0) { [System.Windows.Forms.MessageBox]::Show("Successfully configured MSI & IRQ policy for $changed device(s).`nOriginal states backed up.`nPlease reboot your PC.", "Reboot Required") }
    }.GetNewClosure())

    $btnRevertMSI = New-UltixButton -Parent $modal -Text "Restore Original State" -X 205 -Y 708 -Width 190 -Height 38 -RGB @(100, 100, 100)
    $btnRevertMSI.Anchor = 'Bottom, Left'
    $btnRevertMSI.Add_Click({
        if ($listView.CheckedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Check the PCI device(s) you want to restore to factory defaults.", "WinUltix - Restore MSI State") | Out-Null
            return
        }
        $bRoot = "HKCU:\Software\WinUltix\MSI_Backup"
        foreach ($lvItem in $listView.CheckedItems) {
            $dev = $lvItem.Tag
            if ($null -eq $dev -or $dev.IsKernelOnly -eq $true) { continue }
            $irqRoot = $dev.ActionData.IrqMgmtPath
            $msiPath = $dev.ActionData.Path
            $affPath = $dev.ActionData.AffinityPath
            $safeKey = &$getSafeBackupKeyName $msiPath
            $devBackupKey = "$bRoot\$safeKey"

            $revertBlock = {
                if (Test-Path -LiteralPath $devBackupKey) {
                    $bProps = Get-ItemProperty -LiteralPath $devBackupKey -ErrorAction SilentlyContinue
                    if ($null -ne $bProps.MSISupported) {
                        if ($bProps.MSISupported -eq 255 -or $bProps.MSISupported -eq -1) {
                            Remove-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Force -ErrorAction SilentlyContinue
                        } else {
                            Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value $bProps.MSISupported -Type DWord -Force -ErrorAction Stop
                        }
                    }

                    if ($bProps.AffinityKeyExisted -eq 0) {
                        if (Test-Path -LiteralPath $affPath) { Remove-Item -LiteralPath $affPath -Recurse -Force -ErrorAction Stop }
                    } elseif (Test-Path -LiteralPath $affPath) {
                        if ($bProps.InterruptPriority -eq 255 -or $null -eq $bProps.InterruptPriority) {
                            Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Force -ErrorAction SilentlyContinue
                        } else {
                            Set-ItemProperty -LiteralPath $affPath -Name "InterruptPriority" -Value $bProps.InterruptPriority -Type DWord -Force -ErrorAction Stop
                        }

                        if ($bProps.DevicePolicy -eq 255 -or $null -eq $bProps.DevicePolicy) {
                            Remove-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Force -ErrorAction SilentlyContinue
                        } else {
                            Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value $bProps.DevicePolicy -Type DWord -Force -ErrorAction Stop
                        }

                        if ($null -ne $bProps.AssignmentSetOverride) {
                            Set-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Value ([byte[]]$bProps.AssignmentSetOverride) -Type Binary -Force -ErrorAction Stop
                        } else {
                            Remove-ItemProperty -LiteralPath $affPath -Name "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                        }
                    }
                    Remove-Item -LiteralPath $devBackupKey -Recurse -Force -ErrorAction SilentlyContinue
                } elseif ($dev.DeviceRole -eq "Storage") {
                    # Factory state for modern NVMe/SATA controllers is MSI=1 + DevicePolicy=5 (Spread across all cores)
                    Set-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -Value 1 -Type DWord -Force -ErrorAction Stop
                    if (-not (Test-Path -LiteralPath $affPath)) { New-Item -Path $affPath -Force -ErrorAction Stop | Out-Null }
                    Set-ItemProperty -LiteralPath $affPath -Name "DevicePolicy" -Value 5 -Type DWord -Force -ErrorAction Stop
                    Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                } else {
                    if (Test-Path -LiteralPath $affPath) {
                        Remove-ItemProperty -LiteralPath $affPath -Name "InterruptPriority", "DevicePolicy", "AssignmentSetOverride" -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            try {
                try {
                    & $revertBlock
                } catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
                    Grant-UltixRegistryKeyAccess -RegistryPath $irqRoot
                    Grant-UltixRegistryKeyAccess -RegistryPath $msiPath
                    if (Test-Path -LiteralPath $affPath) { Grant-UltixRegistryKeyAccess -RegistryPath $affPath }
                    & $revertBlock
                }
                Write-GUI " -> Reverted IRQ/MSI state to factory defaults: $($dev.RawDeviceName)"
            } catch {
                Write-GUI " -> [!] Failed to revert IRQ/MSI state for $($dev.RawDeviceName): $($_.Exception.Message)"
            }
        }
        &$refreshData
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 405 -Y 708 -Width 120 -Height 38 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $lblIrqLegend = New-Object System.Windows.Forms.Label
    $lblIrqLegend.Text = "IRQ MASK : Default = Core 0 | 0x.. (C#) = Hex Thread Mask (e.g. 0xC = LP#2,3 -> Core 1) | Spread = All Cores`r`nKERNEL   : -> Mask = Inherited from PCI device | -> Mask* = Mixed PCI masks | All / C0 = OS Timer"
    $lblIrqLegend.Location = New-Object System.Drawing.Point(538, 708)
    $lblIrqLegend.Size = New-Object System.Drawing.Size(712, 38)
    $lblIrqLegend.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblIrqLegend.ForeColor = [System.Drawing.Color]::FromArgb(255, 175, 185, 195)
    $lblIrqLegend.Font = New-Object System.Drawing.Font("Consolas", 8.2)
    $lblIrqLegend.BorderStyle = "FixedSingle"
    $lblIrqLegend.Padding = New-Object System.Windows.Forms.Padding(6, 3, 4, 2)
    $lblIrqLegend.Anchor = 'Bottom, Left, Right'

    $modal.Controls.AddRange(@($lblDesc, $lblWarning, $lblDpcMonitor, $lblDpcLegend, $lblPrio, $comboPrio, $chkOffloadCore0, $chkShowKernel, $lblSort, $comboSort, $listView, $lblIrqLegend))
    try {
        [void]$modal.ShowDialog($global:form)
    } finally {
        $dpcTimer.Stop()
        $dpcTimer.Dispose()
        try { [WinUltix.DpcDriverProfiler]::Stop() } catch { }
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

    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(15, 60)
    $listView.Size = New-Object System.Drawing.Size(800, 330)
    $listView.BackColor = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
    $listView.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $listView.BorderStyle = "FixedSingle"
    $listView.Font = New-Object System.Drawing.Font("Consolas", 10)
    $listView.Anchor = 'Top, Bottom, Left, Right'
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.GridLines = $false
    Enable-UltixDoubleBuffer -Control $listView

    $listView.Columns.Add("Time", 170) | Out-Null
    $listView.Columns.Add("Event ID", 90) | Out-Null
    $listView.Columns.Add("APIC ID", 120) | Out-Null
    $listView.Columns.Add("Error Source / Details", 405) | Out-Null

    $btnClear = New-UltixButton -Parent $modal -Text "Wipe Logs (Prepare for Test)" -X 15 -Y 405 -Width 220 -Height 35 -RGB @(150, 60, 60)
    $btnClear.Anchor = 'Bottom, Left'

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 245 -Y 405 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Left'
    $btnClose.DialogResult = "Cancel"

    $refreshData = {
        $uiModal    = $modal
        $uiListView = $listView
        $bgEven     = [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
        $bgOdd      = [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
        $bgAlert    = [System.Drawing.Color]::FromArgb(255, 50, 26, 28)

        $uiListView.Items.Clear()
        $loadingItem = New-Object System.Windows.Forms.ListViewItem("Scanning...")
        [void]$loadingItem.SubItems.Add("---")
        [void]$loadingItem.SubItems.Add("---")
        [void]$loadingItem.SubItems.Add("Parsing System WHEA Event Log in background Runspace...")
        $loadingItem.BackColor = $bgEven
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
                $rIdx = 0
                foreach ($item in $auditData) {
                    $rowBg = if (($rIdx % 2) -eq 0) { $bgEven } else { $bgOdd }
                    $lvItem = New-Object System.Windows.Forms.ListViewItem([string]$item.Time)
                    $lvItem.BackColor = $rowBg

                    $idSub = $lvItem.SubItems.Add([string]$item.EventID)
                    $idSub.BackColor = $rowBg
                    
                    $apicSub = $lvItem.SubItems.Add([string]$item.ApicID)
                    $apicSub.BackColor = $rowBg
                    if ($item.ApicID -ne "N/A") {
                        $lvItem.UseItemStyleForSubItems = $false
                        $apicSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 255, 150, 150)
                        $apicSub.BackColor = $bgAlert
                    }
                    
                    $errSub = $lvItem.SubItems.Add([string]$item.ErrorType)
                    $errSub.BackColor = $rowBg
                    $errSub.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
                    [void]$uiListView.Items.Add($lvItem)
                    $rIdx++
                }
            } else {
                $lvItem = New-Object System.Windows.Forms.ListViewItem("---")
                [void]$lvItem.SubItems.Add("---")
                [void]$lvItem.SubItems.Add("---")
                [void]$lvItem.SubItems.Add("No WHEA errors found. Hardware is perfectly stable.")
                $lvItem.BackColor = $bgEven
                $lvItem.ForeColor = [System.Drawing.Color]::FromArgb(255, 145, 230, 165)
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

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(710, 375); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
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
	
    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(650, 200); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
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
        Remove-ItemProperty -LiteralPath $regPath -Name "GlobalTimerResolutionRequests" -ErrorAction SilentlyContinue | Out-Null
        
        $null = & bcdedit.exe /deletevalue "{current}" disabledynamictick 2>&1
        $null = & bcdedit.exe /deletevalue "{current}" useplatformclock 2>&1
        $null = & bcdedit.exe /deletevalue "{current}" useplatformtick 2>&1
        
        $hpetRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\ACPI\PNP0103"
        if (Test-Path -LiteralPath $hpetRoot) {
            foreach ($sub in (Get-ChildItem -LiteralPath $hpetRoot -ErrorAction SilentlyContinue)) {
                $hpetId = "ACPI\PNP0103\$($sub.PSChildName)"
                if ([WinUltix.PnpTree]::IsDeviceDisabled($hpetId)) {
                    $null = & pnputil.exe /enable-device "$hpetId" 2>&1
                }
            }
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

    $chkList = New-Object System.Windows.Forms.CheckedListBox; $chkList.Location = New-Object System.Drawing.Point(15, 80); $chkList.Size = New-Object System.Drawing.Size(600, 160); $chkList.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38); $chkList.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245); $chkList.BorderStyle = "FixedSingle"; $chkList.Font = New-Object System.Drawing.Font("Consolas", 10.5); $chkList.CheckOnClick = $false; $chkList.HorizontalScrollbar = $true; $chkList.Anchor = 'Top, Bottom, Left, Right'
    
    $localData = New-Object System.Collections.ArrayList

    $refreshData = {
        $modal.UseWaitCursor = $true
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            $chkList.BeginUpdate()
            $chkList.Items.Clear(); $localData.Clear()
            $auditData = Get-HardwareState_NVMe
            foreach ($item in $auditData) {
                [void]$localData.Add($item)
                if ($item.IsOptimized) { [void]$chkList.Items.Add("[ OPTIMIZED ]   " + $item.UIDisplayName, $false) } 
                else { [void]$chkList.Items.Add("[ UNOPTIMIZED ] " + $item.UIDisplayName, $true) }
            }
            $chkList.EndUpdate()
        } finally {
            $modal.UseWaitCursor = $false
            [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
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
            $modal.UseWaitCursor = $true
            [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
            try {
                Invoke-ApplyNVMeTweaks -SelectedItems $applyQueue
            } finally {
                $modal.UseWaitCursor = $false
                [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
            }
            [System.Windows.Forms.MessageBox]::Show("Selected I/O and Memory optimizations applied.`nReboot is required for PCIe/NVMe bus changes.", "Optimization Completed")
        }
        &$refreshData
    }.GetNewClosure())

    $btnRevert = New-UltixButton -Parent $modal -Text "Restore OS Defaults" -X 205 -Y 260 -Width 160 -Height 35 -RGB @(100, 100, 100)
    $btnRevert.Anchor = 'Bottom, Left'
    $btnRevert.Add_Click({
        $modal.UseWaitCursor = $true
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        try {
            Remove-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\PCI\Parameters" -Name "DisableASPM" -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device" -Name "IdlePowerMode" -Force -ErrorAction SilentlyContinue | Out-Null
            Enable-MMAgent -MemoryCompression -ErrorAction SilentlyContinue
        } finally {
            $modal.UseWaitCursor = $false
            [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        }
        
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
    if (-not (Test-Path -LiteralPath $appDataFolder)) { 
        try { New-Item -Path $appDataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null } 
        catch { [System.Windows.Forms.MessageBox]::Show("Failed to create WinUltix AppData directory.", "Error"); return }
    }
    
    $ps1Path = "$appDataFolder\PreFlight.ps1"
    $icoPath = "$appDataFolder\WinUltix.ico"

    # Ensure local WinUltix.ico cache exists across all 3 launch modes (src\, standalone .exe, and irm | iex)
    if (-not (Test-Path -LiteralPath $icoPath)) {
        if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
            $parentDir = Split-Path -Path $ScriptDir -Parent
            foreach ($cand in @((Join-Path $ScriptDir "assets\WinUltix.ico"), (Join-Path $parentDir "assets\WinUltix.ico"))) {
                if (Test-Path -LiteralPath $cand) {
                    Copy-Item -LiteralPath $cand -Destination $icoPath -Force -ErrorAction SilentlyContinue
                    break
                }
            }
        }
        # Fallback for standalone WinUltix.exe: persist embedded PE icon from memory to AppData cache
        if (-not (Test-Path -LiteralPath $icoPath)) {
            Initialize-WinUltixIcon
            if ($null -ne $global:UltixAppIcon) {
                try {
                    $fs = [System.IO.File]::Create($icoPath)
                    try { $global:UltixAppIcon.Save($fs) } finally { $fs.Dispose() }
                } catch { }
            }
        }
    }

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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
[System.Windows.Forms.Application]::EnableVisualStyles()

`$c = 'HKCU:\Software\WinUltix\AffinityLasso'
`$p = 'HKLM:\SOFTWARE\WinUltix\CPPC'
function Get-Pcfg (`$g) {
    `$out = powercfg.exe /qh SCHEME_CURRENT SUB_PROCESSOR `$g 2>`$null
    if (-not `$out) { return `$null }
    `$hexLines = @(`$out -match ':\s*(0x[0-9a-fA-F]+)\s*`$')
    if (`$hexLines.Count -ge 2 -and `$hexLines[-2] -match '(0x[0-9a-fA-F]+)\s*`$') {
        return [convert]::ToInt32(`$matches[1], 16)
    } elseif (`$hexLines.Count -eq 1 -and `$hexLines[0] -match '(0x[0-9a-fA-F]+)\s*`$') {
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
`$icoFile = "`$env:LOCALAPPDATA\WinUltix\WinUltix.ico"
if (Test-Path -LiteralPath `$icoFile) {
    try { `$frm.Icon = New-Object System.Drawing.Icon(`$icoFile, 32, 32) } catch { }
}
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
`$btnEngage.BackColor = [System.Drawing.Color]::FromArgb(255, 135, 50, 50)
`$btnEngage.FlatStyle = "Flat"
`$btnEngage.DialogResult = "Yes"

`$btnRelease = New-Object System.Windows.Forms.Button
`$btnRelease.Text = "RELEASE"
`$btnRelease.Location = New-Object System.Drawing.Point(128, 118)
`$btnRelease.Size = New-Object System.Drawing.Size(100, 32)
`$btnRelease.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
`$btnRelease.FlatStyle = "Flat"
`$btnRelease.DialogResult = "No"

`$btnCancel = New-Object System.Windows.Forms.Button
`$btnCancel.Text = "Cancel"
`$btnCancel.Location = New-Object System.Drawing.Point(236, 118)
`$btnCancel.Size = New-Object System.Drawing.Size(100, 32)
`$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
`$btnCancel.FlatStyle = "Flat"
`$btnCancel.DialogResult = "Cancel"

`$frm.Controls.AddRange(@(`$lblStatus, `$chkAff, `$chkCPPC, `$btnEngage, `$btnRelease, `$btnCancel))
`$res = `$frm.ShowDialog()
if (`$null -ne `$frm.Icon) { `$frm.Icon.Dispose() }
`$frm.Dispose()

if (`$res -eq "Yes") {
    if (`$chkAff.Checked -and (Test-Path -LiteralPath `$c)) { 
        (Get-ItemProperty -LiteralPath `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
            `$n = `$_.Name -replace '\.exe`$',''
            foreach (`$proc in @(Get-Process -Name `$n -ErrorAction SilentlyContinue)) {
                try {
                    `$proc.ProcessorAffinity = [System.IntPtr]([int64]$maskInt64)
                    `$proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
                } catch {} finally {
                    `$proc.Dispose()
                }
            }
        } 
    }
    
    if (`$chkCPPC.Checked) {
        if (-not (Test-Path -LiteralPath `$p)) { New-Item -Path `$p -Force | Out-Null }
        `$e  = Get-Pcfg '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
        `$d  = Get-Pcfg '4b92d758-5a24-4851-a470-815d78aee119'
        `$pr = Get-Pcfg '7b224883-b3cc-4d79-819f-8374152cbe7c'
        
        if (`$null -ne `$e -and -not (`$e -eq 0 -and `$d -eq 100 -and `$pr -eq 100) -and -not (`$e -eq 0 -and `$d -eq 0 -and `$pr -eq 0)) {
            Set-ItemProperty -LiteralPath `$p -Name 'EPP' -Value `$e -Type DWord -Force
            Set-ItemProperty -LiteralPath `$p -Name 'Demote' -Value `$d -Type DWord -Force
            Set-ItemProperty -LiteralPath `$p -Name 'Promote' -Value `$pr -Type DWord -Force
        }
        
        `$tsCmd = "`$bp='HKLM:\SOFTWARE\WinUltix\CPPC'; if(Test-Path -LiteralPath `$bp){ `$r=Get-ItemProperty -LiteralPath `$bp; if(`$null -ne `$r.EPP){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 36687f9e-e3a5-4dbf-b1dc-15eb381c6863 `$r.EPP}; if(`$null -ne `$r.Demote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 4b92d758-5a24-4851-a470-815d78aee119 `$r.Demote}; if(`$null -ne `$r.Promote){powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote; powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR 7b224883-b3cc-4d79-819f-8374152cbe7c `$r.Promote}; powercfg.exe /setactive SCHEME_CURRENT }; Unregister-ScheduledTask -TaskName 'WinUltix_CPPC_Failsafe' -Confirm:`$false -ErrorAction SilentlyContinue"
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
        if (Test-Path -LiteralPath `$c) { 
            (Get-ItemProperty -LiteralPath `$c).PSObject.Properties | Where-Object { `$_.Name -match '\.exe`$' } | ForEach-Object { 
                `$n = `$_.Name -replace '\.exe`$',''
                foreach (`$proc in @(Get-Process -Name `$n -ErrorAction SilentlyContinue)) {
                    try {
                        `$proc.ProcessorAffinity = `$sys
                        `$proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
                    } catch {} finally {
                        `$proc.Dispose()
                    }
                }
            } 
        } 
    }
    
    if (`$chkCPPC.Checked) {
        `$e = 50; `$d = 40; `$pr = 60
        if (Test-Path -LiteralPath `$p) { 
            `$reg = Get-ItemProperty -LiteralPath `$p -ErrorAction SilentlyContinue
            if (`$null -ne `$reg.EPP -and `$null -ne `$reg.Demote -and `$null -ne `$reg.Promote) {
                if (`$reg.EPP -eq 0 -and `$reg.Demote -eq 0 -and `$reg.Promote -eq 0) {
                    Remove-ItemProperty -LiteralPath `$p -Name 'EPP', 'Demote', 'Promote' -Force -ErrorAction SilentlyContinue
                } else {
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
        Set-Content -LiteralPath $ps1Path -Value $code -Encoding UTF8 -ErrorAction Stop
        $desktop  = [Environment]::GetFolderPath("Desktop")
        $WshShell = New-Object -ComObject WScript.Shell -ErrorAction Stop
        $Shortcut = $WshShell.CreateShortcut("$desktop\WinUltix Pre-Flight Mode.lnk")
        $Shortcut.TargetPath = "powershell.exe"
        $Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""
        $Shortcut.WindowStyle = 7
        $Shortcut.IconLocation = if (Test-Path -LiteralPath $icoPath) { "$icoPath, 0" } else { "shell32.dll, 137" }
        $Shortcut.Save()
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($WshShell)
        
        Write-GUI " -> Generated Pre-Flight shortcut on Desktop ($($topo.Label))."
        [System.Windows.Forms.MessageBox]::Show("Pre-Flight Shortcut generated on Desktop.", "Success")
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to construct COM object or write file.`n`nError: $($_.Exception.Message)", "Shortcut Generation Failed")
    }
}

# ------------------------------------------
# Z7: USB XHCI ROOT-HUB TOPOLOGY & HID POLLING MAPPER
# ------------------------------------------
function Get-UsbTopologyMap {
    param([switch]$IncludeRawHubs)

    $controllers = [System.Collections.Generic.List[PSCustomObject]]::new()
    [int64[]]$coreMasks = Get-UltixPhysicalCoreMasks
    [uint64]$core0Mask  = if ($coreMasks.Count -ge 1) { [uint64]$coreMasks[0] } else { 3 }
    [uint64]$core1Mask  = if ($coreMasks.Count -ge 2) { [uint64]$coreMasks[1] } else { 12 }

    $pciRoot = "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI"
    if (-not (Test-Path -LiteralPath $pciRoot)) { return @() }

    foreach ($venKey in (Get-ChildItem -LiteralPath $pciRoot -ErrorAction SilentlyContinue)) {
        foreach ($instKey in (Get-ChildItem -LiteralPath $venKey.PSPath -ErrorAction SilentlyContinue)) {
            $props = Get-ItemProperty -LiteralPath $instKey.PSPath -Name "Service", "FriendlyName", "DeviceDesc", "LocationInformation" -ErrorAction SilentlyContinue
            if ($null -eq $props -or $props.Service -notmatch '^(?i)(USBXHCI|USB4|usbehci)$') { continue }

            $instanceId = "PCI\$($venKey.PSChildName)\$($instKey.PSChildName)"
            if ([WinUltix.PnpTree]::GetDeviceConfigStatus($instanceId) -ne 0) { continue }
            $rawCtrlName = if ($props.FriendlyName) { $props.FriendlyName } else { $props.DeviceDesc }
            $ctrlName    = Format-UltixDeviceName -RawName $rawCtrlName

            $parents = @([WinUltix.PnpTree]::GetParentChain($instanceId))
            $pciBridgeHops = @($parents | Where-Object { $_ -like "PCI\*" }).Count

            $routingBadge = if ($venKey.PSChildName -match 'DEV_43[A-F0-9]{2}' -or $ctrlName -match '(?i)Chipset') {
                if ($pciBridgeHops -ge 3) { "[CHIPSET PCH (Daisy-Chained / $pciBridgeHops Hops)]" }
                else { "[CHIPSET PCH ($pciBridgeHops PCIe Hops)]" }
            } elseif ($pciBridgeHops -le 1) {
                "[CPU DIRECT SoC LANES (1 PCIe Hop - Lowest Latency)]"
            } else {
                "[SECONDARY BRIDGE ($pciBridgeHops PCIe Hops)]"
            }

            $msiPath = "$($instKey.PSPath)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
            $affPath = "$($instKey.PSPath)\Device Parameters\Interrupt Management\Affinity Policy"
            $msiOn   = ((Get-ItemProperty -LiteralPath $msiPath -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported -eq 1)
            $affProps = Get-ItemProperty -LiteralPath $affPath -ErrorAction SilentlyContinue
            $irqTag  = "Core 0 (Default)"
            if ($null -ne $affProps -and $affProps.DevicePolicy -eq 4 -and $null -ne $affProps.AssignmentSetOverride) {
                [uint64]$mVal = 0
                for ($b = 0; $b -lt [math]::Min(8, $affProps.AssignmentSetOverride.Length); $b++) {
                    $mVal = $mVal -bor ([uint64]$affProps.AssignmentSetOverride[$b] -shl ($b * 8))
                }
                $cHint = if ($mVal -eq $core1Mask) { " (C1 Offloaded)" } elseif (($mVal -band $core0Mask) -ne 0) { " (C0)" } else { "" }
                $irqTag = "0x$($mVal.ToString('X'))$cHint"
            }

            $descendants  = @([WinUltix.PnpTree]::GetDescendants($instanceId))
            $endpoints    = [System.Collections.Generic.List[PSCustomObject]]::new()
            $hubNames     = [System.Collections.Generic.List[string]]::new()
            $hasMouse     = $false
            $hasAudio     = $false
            $hasStorage   = $false
            $hasVr        = $false
            $mouseLabel   = ""
            $conflictList = [System.Collections.Generic.List[string]]::new()

            $rootHubInfo  = $null
            $hubSpeedMap  = @{}
            $physDevices  = [System.Collections.Generic.List[PSCustomObject]]::new()
            $currentPhys  = $null

            foreach ($entry in $descendants) {
                $parts = $entry -split '\|', 2
                $depth = [int]$parts[0]
                $devId = $parts[1]

                if ($devId -match '^USB\\ROOT_HUB') {
                    $rootHubInfo = [WinUltix.UsbProberV2]::ProbeHub($devId)
                    $hubSpeedMap[$depth] = $rootHubInfo.PortSpeeds
                    continue
                }

                # Ignore virtual Bluetooth enumerator (BTHENUM\*) and SoftwareDevice (SWD\*) child nodes
                if ($devId -match '^(?i)(BTHENUM|BTHLE|SWD|MMDEVAPI)\\') { continue }

                $regNode = "HKLM:\SYSTEM\CurrentControlSet\Enum\$devId"
                $dProps  = Get-ItemProperty -LiteralPath $regNode -Name "FriendlyName", "DeviceDesc", "Service", "Class", "Address", "LocationInformation" -ErrorAction SilentlyContinue
                if ($null -eq $dProps) { continue }

                $rawDName = if ($dProps.FriendlyName) { $dProps.FriendlyName } else { $dProps.DeviceDesc }
                $dName    = Format-UltixDeviceName -RawName $rawDName
                $dSvc     = [string]$dProps.Service
                $dCls     = [string]$dProps.Class
                $busDesc  = [WinUltix.UsbProberV2]::GetBusReportedDesc($devId)

                if ($dSvc -match '^(?i)(USBHUB3|usbhub)$') {
                    $subHub = [WinUltix.UsbProberV2]::ProbeHub($devId)
                    $hubSpeedMap[$depth] = $subHub.PortSpeeds
                }

                $parentHubDepth = $depth - 1
                $isDirectChildOfHub = $hubSpeedMap.ContainsKey($parentHubDepth)
                $isPhysicalUsbNode  = (
                    $isDirectChildOfHub -and
                    $devId -match '^USB\\(?!ROOT_HUB)[^\\]+\\[^\\]+$' -and
                    $devId -notmatch '(?i)&MI_' -and
                    (-not [string]::IsNullOrWhiteSpace($dSvc))
                )

                if ($isPhysicalUsbNode) {
                    $portNum = if ($null -ne $dProps.Address -and $dProps.Address -gt 0) {
                        [int]$dProps.Address
                    } elseif ($dProps.LocationInformation -match 'Port_#0*(\d+)') {
                        [int]$matches[1]
                    } else { 0 }

                    $negSpeed = ""
                    if ($portNum -gt 0 -and $hubSpeedMap[$parentHubDepth].ContainsKey($portNum)) {
                        $negSpeed = $hubSpeedMap[$parentHubDepth][$portNum]
                    }

                    $currentPhys = [PSCustomObject]@{
                        Depth       = $depth
                        DevId       = $devId
                        PortNumber  = $portNum
                        LinkSpeed   = $negSpeed
                        BusName     = $busDesc
                        BaseName    = $dName
                        BaseService = $dSvc
                        BaseClass   = $dCls
                        Children    = [System.Collections.Generic.List[PSCustomObject]]::new()
                    }
                    $physDevices.Add($currentPhys)
                } elseif ($null -ne $currentPhys -and $depth -gt $currentPhys.Depth) {
                    $currentPhys.Children.Add([PSCustomObject]@{
                        Depth   = $depth
                        DevId   = $devId
                        Name    = $dName
                        BusName = $busDesc
                        Service = $dSvc
                        Class   = $dCls
                    })
                }
            }

            foreach ($phys in $physDevices) {
                $deviceNodes = @([PSCustomObject]@{ DevId = $phys.DevId; Name = $phys.BaseName; BusName = $phys.BusName; Service = $phys.BaseService; Class = $phys.BaseClass }) + @($phys.Children)

                $bestName = $phys.BusName
                if ([string]::IsNullOrWhiteSpace($bestName) -or $bestName -match '^(?i)(USB Receiver|USB Composite Device|Generic|USB Input Device|HID-compliant)') {
                    foreach ($n in $deviceNodes) {
                        if (-not [string]::IsNullOrWhiteSpace($n.BusName) -and $n.BusName -notmatch '^(?i)(USB Receiver|USB Composite Device|Generic|USB Input Device)') {
                            $bestName = $n.BusName
                            break
                        }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($bestName) -or $bestName -match '^(?i)(USB Composite Device|Generic|USB Input Device|HID-compliant)') {
                    foreach ($n in $deviceNodes) {
                        if (-not [string]::IsNullOrWhiteSpace($n.Name) -and $n.Name -notmatch '^(?i)(USB Composite Device|Urządzenie kompozytowe|USB Input Device|Urządzenie wejściowe|HID Keyboard Device|Urządzenie klawiatury HID|HID-compliant|Zgodne z HID|Generic)') {
                            $bestName = $n.Name
                            break
                        }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($bestName)) { $bestName = $phys.BaseName }

                $role      = "[USB DEVICE]"
                $activeSvc = if ($phys.BaseService) { $phys.BaseService } else { $phys.BaseClass }

                $isStorage    = $false; $isCardReader = $false; $isAudio = $false; $isVr = $false; $isCam = $false; $isBt = $false; $isHub = $false
                $isOnboardMcu = ($bestName -match '(?i)(AURA\s*LED|Mystic\s*Light|RGB\s*Fusion|Polychrome|ITE\s*Device|Nuvoton)')
                $isWirelessRx = ($bestName -match '(?i)(Receiver|Lightspeed|HyperSpeed|Dongle|2\.4G|Unifying|Bolt)')
                $hasMou       = $false; $hasKbd = $false
                $mi00IsKbd    = $false; $mi00IsMou = $false

                if ($phys.BaseClass -eq "Bluetooth" -or $phys.BaseService -match '^(?i)(BTHUSB|BTHMINI|ibtusb|BtFilter|RtkBtFilter)$' -or $bestName -match '(?i)\b(BT|Bluetooth)\b') {
                    $isBt = $true
                    $activeSvc = if ($phys.BaseService) { $phys.BaseService } else { "BTHUSB" }
                }

                foreach ($n in $deviceNodes) {
                    if ($isBt) { break }
                    if ($n.Service -match '^(?i)(AmUStor|rtsuer)$' -or $bestName -match '(?i)Card\s*Reader') {
                        $isCardReader = $true
                        if ($n.Service) { $activeSvc = $n.Service }
                    }
                    elseif ($n.Service -match '^(?i)(USBSTOR|UASPStor)$' -or $n.Class -eq "DiskDrive") {
                        $isStorage = $true
                        if ($n.Service -match '^(?i)(USBSTOR|UASPStor)$') { $activeSvc = $n.Service }
                    }
                    elseif ($n.Class -eq "Bluetooth" -or $n.Service -match '^(?i)(BTHUSB|BTHMINI|ibtusb)$') {
                        $isBt = $true
                        $activeSvc = if ($phys.BaseService) { $phys.BaseService } else { "BTHUSB" }
                    }
                    elseif ($n.Class -eq "Media" -or $n.Service -match '^(?i)(usbaudio|usbaudio2|iFiUsbAudio)' -or $n.Name -match '(?i)(DAC|iFi|Audio|Headset|Microphone|Sound)') {
                        if ($n.Class -ne "AudioEndpoint" -and $n.Class -ne "SoftwareDevice") {
                            $isAudio = $true
                            if ($n.Service) { $activeSvc = $n.Service }
                        }
                    }
                    elseif ($n.Name -match '(?i)(Index|Steam Frame|VR|HMD|Watchman|Tracker|Beyond)') { $isVr = $true; if ($n.Service) { $activeSvc = $n.Service } }
                    elseif ($n.Service -eq "usbvideo" -or $n.Class -in @("Camera", "Image")) { $isCam = $true; if ($n.Service) { $activeSvc = $n.Service } }
                    elseif ($n.Service -match '^(?i)(USBHUB3|usbhub)$') { $isHub = $true; $activeSvc = $n.Service }
                    elseif ($n.Service -eq "mouhid" -or $n.Class -eq "Mouse") {
                        $hasMou = $true
                        if ($n.DevId -match '(?i)&MI_00' -or $n.DevId -notmatch '(?i)&MI_0[1-9]') { $mi00IsMou = $true }
                    }
                    elseif ($n.Service -eq "kbdhid" -or $n.Class -eq "Keyboard") {
                        $hasKbd = $true
                        if ($n.DevId -match '(?i)&MI_00' -or $n.DevId -notmatch '(?i)&MI_0[1-9]') { $mi00IsKbd = $true }
                    }
                }

                if ($isHub)             { $role = "[USB HUB]" }
                elseif ($isOnboardMcu)  { $role = "[ONBOARD MCU]"; $activeSvc = "Internal PCB RGB - Idle" }
                elseif ($isBt)          { $role = "[BLUETOOTH]" }
                elseif ($isCardReader)  { $role = "[CARD READER]" }
                elseif ($isStorage)     { $role = "[STORAGE]";     $hasStorage = $true; $conflictList.Add("Storage: $bestName") }
                elseif ($isVr)          { $role = "[VR / HMD]";    $hasVr      = $true }
                elseif ($isAudio)       { $role = "[AUDIO / DAC]"; $hasAudio   = $true; $conflictList.Add("DAC: $bestName") }
                elseif ($isCam)         { $role = "[VIDEO / CAM]"; $hasAudio   = $true; $conflictList.Add("Cam: $bestName") }
                elseif ($hasMou -and $hasKbd) {
                    if ($isWirelessRx -or $mi00IsMou -or -not $mi00IsKbd) {
                        $role       = "[MOUSE / HID]"
                        $activeSvc  = "mouhid"
                        $hasMouse   = $true
                        $mouseLabel = $bestName
                    } else {
                        $role      = "[KEYBOARD]"
                        $activeSvc = "kbdhid"
                    }
                }
                elseif ($hasMou) { $role = "[MOUSE / HID]"; $activeSvc = "mouhid"; $hasMouse = $true; $mouseLabel = $bestName }
                elseif ($hasKbd) { $role = "[KEYBOARD]";    $activeSvc = "kbdhid" }
                elseif ($phys.Children | Where-Object { $_.Class -eq "HIDClass" -or $_.Service -eq "HidUsb" }) {
                    $role      = "[HID / INPUT]"
                    $activeSvc = "HidUsb"
                }

                $portBadge = if ($phys.PortNumber -gt 0) {
                    $pPrefix = if ($phys.Depth -le 2) { "Port #$($phys.PortNumber)" } else { "Hub Port #$($phys.PortNumber)" }
                    if ($phys.LinkSpeed) { " [$pPrefix | $($phys.LinkSpeed)]" } else { " [$pPrefix]" }
                } else { "" }

                if ($isHub) {
                    $hubNames.Add($bestName)
                    if (-not $IncludeRawHubs) { continue }
                }

                $endpoints.Add([PSCustomObject]@{
                    Role       = $role
                    Name       = "$bestName$portBadge"
                    InstanceId = $phys.DevId
                    Service    = $activeSvc
                    Depth      = $phys.Depth
                })
            }

            if (-not $IncludeRawHubs -and $hubNames.Count -gt 0) {
                $uniqueHubs = @($hubNames | Select-Object -Unique) -join ", "
                $endpoints.Add([PSCustomObject]@{
                    Role       = "[ONBOARD HUBS]"
                    Name       = "$($hubNames.Count)x Passive USB 2.0/3.x Port Splitters ($uniqueHubs)"
                    InstanceId = "HUB_SUMMARY"
                    Service    = "0% DMA Load"
                    Depth      = 99
                })
            }

            $portMapSummary = if ($venKey.PSChildName -match 'DEV_15B8') {
                "1 Internal SoC Line (USB 2.0 480 Mbps - Unrouted on Desktop PCB)"
            } elseif ($null -ne $rootHubInfo -and $rootHubInfo.TotalPorts -gt 0) {
                $ssLabel = if ($ctrlName -match '(?i)(USB4|40G)' -or $venKey.PSChildName -match 'DEV_2426') {
                    "USB4 40 Gbps"
                } elseif ($rootHubInfo.SsPlusPorts -gt 0 -or $ctrlName -match '(?i)(3\.2|3\.1)') {
                    "USB 3.x SuperSpeed (5/10/20 Gbps)"
                } else {
                    "USB 3.0 SuperSpeed (5 Gbps)"
                }
                "$($rootHubInfo.TotalPorts) Logical Lines ($($rootHubInfo.Usb3Ports)x $ssLabel + $($rootHubInfo.Usb2Ports)x USB 2.0 High-Speed [480 Mbps] | Active: $($rootHubInfo.ActivePorts))"
            } else {
                "Root Hub port descriptor unavailable"
            }

            $statusAdvice = "Optimal Isolation"
            $severity     = "Green"
            if ($hasMouse -and ($hasAudio -or $hasStorage)) {
                $confTargets  = ($conflictList | Select-Object -Unique) -join ", "
                $statusAdvice = "[!] CONTENTION: Mouse ($mouseLabel) shares XHCI bus with $confTargets!"
                $severity     = "Red"
            } elseif (($hasMouse -or $hasVr) -and $routingBadge -match "CHIPSET") {
                $statusAdvice = "[*] Notice: Latency-sensitive Mouse/VR is on Chipset PCH instead of CPU Direct lanes"
                $severity     = "Yellow"
            } elseif ($endpoints.Count -eq 0) {
                if ($venKey.PSChildName -match 'DEV_15B8') {
                    $statusAdvice = "[Internal SoC USB 2.0 Node - Unrouted on Desktop PCB]"
                } else {
                    $statusAdvice = "[Idle Root Hub - Free Ports Available]"
                }
                $severity = "Gray"
            }

            $controllers.Add([PSCustomObject]@{
                ControllerName = $ctrlName
                InstanceId     = $instanceId
                RoutingBadge   = $routingBadge
                PortSummary    = $portMapSummary
                PciHops        = $pciBridgeHops
                MsiEnabled     = $msiOn
                IrqAffinity    = $irqTag
                Endpoints      = @($endpoints)
                Advice         = $statusAdvice
                Severity       = $severity
            })
        }
    }

    return @($controllers | Sort-Object PciHops, ControllerName)
}

function Show-UsbTopologyModal {
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = "WinUltix - USB XHCI Root-Hub Topology & Contention Mapper"
    $modal.Size = New-Object System.Drawing.Size(940, 680)
    $modal.MinimumSize = New-Object System.Drawing.Size(880, 580)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "Sizable"
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Maps every physical USB XHCI controller back to the PCIe Root Complex. Keep 4K/8KHz mice and VR headsets on [CPU DIRECT SoC LANES] and isolate them from USB Audio DACs or external SSDs."
    $lblDesc.Location = New-Object System.Drawing.Point(15, 12)
    $lblDesc.Size = New-Object System.Drawing.Size(895, 36)
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $lblDesc.Anchor = 'Top, Left, Right'

    $rtbMap = New-Object System.Windows.Forms.RichTextBox
    $rtbMap.Location = New-Object System.Drawing.Point(15, 52)
    $rtbMap.Size = New-Object System.Drawing.Size(895, 525)
    $rtbMap.BackColor = [System.Drawing.Color]::FromArgb(255, 18, 18, 18)
    $rtbMap.ForeColor = [System.Drawing.Color]::LightGray
    $rtbMap.BorderStyle = "FixedSingle"
    $rtbMap.ReadOnly = $true
    $rtbMap.Font = New-Object System.Drawing.Font("Consolas", 9.8)
    $rtbMap.Anchor = 'Top, Bottom, Left, Right'

    $chkShowHubs = New-Object System.Windows.Forms.CheckBox
    $chkShowHubs.Text = "Show Raw USB Hub Nodes"
    $chkShowHubs.Location = New-Object System.Drawing.Point(440, 595)
    $chkShowHubs.Size = New-Object System.Drawing.Size(210, 24)
    $chkShowHubs.ForeColor = [System.Drawing.Color]::LightGray
    $chkShowHubs.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $chkShowHubs.Anchor = 'Bottom, Left'
    $chkShowHubs.Checked = $false

    $appendColored = {
        param([string]$Text, [System.Drawing.Color]$Color)
        $rtbMap.SelectionStart  = $rtbMap.TextLength
        $rtbMap.SelectionLength = 0
        $rtbMap.SelectionColor  = $Color
        $rtbMap.AppendText($Text)
    }

    $renderTopology = {
        $rtbMap.Clear()

        # Render concise Engineering Mini-Guide at the top of the report
        & $appendColored "================================================================================`r`n" ([System.Drawing.Color]::FromArgb(255, 70, 70, 70))
        & $appendColored "QUICK WIRING GUIDE & HOW TO READ THIS TOPOLOGY MAP:`r`n" ([System.Drawing.Color]::Gold)
        & $appendColored "  1. [CPU DIRECT SoC] : Wired straight to CPU silicon (1 Hop). Best for 4K/8KHz Mice & VR.`r`n" ([System.Drawing.Color]::Cyan)
        & $appendColored "  2. [CHIPSET PCH]    : Routed via motherboard chipset. Ideal for USB Audio DACs, Keyboards & Drives.`r`n" ([System.Drawing.Color]::LightSkyBlue)
        & $appendColored "  3. XHCI Isolation   : NEVER share one controller between an 8KHz Mouse and an Audio DAC or USB Drive.`r`n" ([System.Drawing.Color]::LightGreen)
        & $appendColored "  4. Logical Lines    : Every physical USB 3.x port contains 2 logical lines (1x SuperSpeed + 1x USB 2.0).`r`n" ([System.Drawing.Color]::Silver)
        & $appendColored "  5. Onboard Hubs/MCU : Passive PCB splitters (ASM107x) & static RGB (AURA) do NOT disturb Audio DACs.`r`n" ([System.Drawing.Color]::DarkGray)

        $map = Get-UsbTopologyMap -IncludeRawHubs:($chkShowHubs.Checked)
        $idx = 0
        foreach ($ctrl in $map) {
            $idx++
            $hdrColor = if ($ctrl.RoutingBadge -match "CPU DIRECT") { [System.Drawing.Color]::Cyan } else { [System.Drawing.Color]::LightSkyBlue }
            & $appendColored "================================================================================`r`n" ([System.Drawing.Color]::FromArgb(255, 70, 70, 70))
            & $appendColored "CONTROLLER #$idx : $($ctrl.ControllerName)`r`n" $hdrColor
            & $appendColored "  PCIe Routing : $($ctrl.RoutingBadge)`r`n" $hdrColor
            & $appendColored "  PCI ID & IRQ : $($ctrl.InstanceId) | MSI: $(if($ctrl.MsiEnabled){'ON'}else{'OFF'}) | IRQ: $($ctrl.IrqAffinity)`r`n" ([System.Drawing.Color]::Silver)
            & $appendColored "  Root Hub Map : $($ctrl.PortSummary)`r`n" ([System.Drawing.Color]::LightSkyBlue)
            
            $advColor = switch ($ctrl.Severity) {
                "Red"    { [System.Drawing.Color]::OrangeRed; break }
                "Yellow" { [System.Drawing.Color]::Gold;      break }
                "Green"  { [System.Drawing.Color]::LightGreen; break }
                default  { [System.Drawing.Color]::DarkGray;  break }
            }
            & $appendColored "  Assessment   : $($ctrl.Advice)`r`n" $advColor

            if ($ctrl.Endpoints.Count -gt 0) {
                & $appendColored "  Connected Endpoints:`r`n" ([System.Drawing.Color]::White)
                foreach ($ep in $ctrl.Endpoints) {
                    $epColor = switch -Wildcard ($ep.Role) {
                        "*MOUSE*"   { [System.Drawing.Color]::LightGreen; break }
                        "*AUDIO*"   { [System.Drawing.Color]::Violet;     break }
                        "*VR*"      { [System.Drawing.Color]::Cyan;       break }
                        "*STORAGE*" { [System.Drawing.Color]::Orange;     break }
                        "*ONBOARD*" { [System.Drawing.Color]::DarkGray;   break }
                        "*HUB*"     { [System.Drawing.Color]::DarkGray;   break }
                        default     { [System.Drawing.Color]::LightGray;  break }
                    }
                    & $appendColored ("    +-- {0,-15} {1} ({2})`r`n" -f $ep.Role, $ep.Name, $ep.Service) $epColor
                }
            } else {
                & $appendColored "    +-- (No active external USB endpoints attached)`r`n" ([System.Drawing.Color]::DarkGray)
            }
            & $appendColored "`r`n" ([System.Drawing.Color]::LightGray)
        }
        $rtbMap.SelectionStart = 0
        $rtbMap.ScrollToCaret()
    }

    &$renderTopology
    $chkShowHubs.Add_CheckedChanged({ &$renderTopology }.GetNewClosure())

    $btnRefresh = New-UltixButton -Parent $modal -Text "Rescan USB Tree (Live)" -X 15 -Y 590 -Width 200 -Height 35 -RGB @(60, 100, 150)
    $btnRefresh.Anchor = 'Bottom, Left'
    $btnRefresh.Add_Click({ &$renderTopology }.GetNewClosure())

    $btnExportLog = New-UltixButton -Parent $modal -Text "Print Map to Main Log" -X 225 -Y 590 -Width 200 -Height 35 -RGB @(50, 110, 70)
    $btnExportLog.Anchor = 'Bottom, Left'
    $btnExportLog.Add_Click({
        Write-GUI "=== USB XHCI ROOT-HUB & PCIE TOPOLOGY MAP ==="
        foreach ($line in ($rtbMap.Text -split '\r?\n')) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch '^===') {
                Write-GUI "  $line"
            }
        }
        Write-GUI ""
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 790 -Y 590 -Width 120 -Height 35 -RGB @(60, 60, 60)
    $btnClose.Anchor = 'Bottom, Right'
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $rtbMap, $chkShowHubs))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

# ------------------------------------------
# Z7: QUANTUM SCHEDULER MATRIX (WIN32PRIORITYSEPARATION LIVE TUNER)
# ------------------------------------------
function Get-QuantumSchedulerInfo {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
    $rawVal  = (Get-ItemProperty -LiteralPath $regPath -Name "Win32PrioritySeparation" -ErrorAction SilentlyContinue).Win32PrioritySeparation
    if ($null -eq $rawVal) { $rawVal = 2 }

    $lenBits   = ($rawVal -shr 4) -band 3
    $varBits   = ($rawVal -shr 2) -band 3
    $boostBits = $rawVal -band 3

    $lenStr = switch ($lenBits) {
        2 { "Short Quantum (Low Input Latency)" }
        1 { "Long Quantum (High Throughput / Workstation)" }
        default { "OS Default (Short on Client SKU)" }
    }
    $varStr = switch ($varBits) {
        1 { "Variable (Foreground Boosted vs Background)" }
        2 { "Fixed (Equal Determinism Across Threads)" }
        default { "OS Default (Variable on Client SKU)" }
    }
    $boostStr = switch ($boostBits) {
        2 { "3:1 Foreground Ratio (Max Gaming Boost)" }
        1 { "2:1 Foreground Ratio (Moderate Boost)" }
        default { "1:1 Equal Slice (No Foreground Bias)" }
    }

    $binStr = [Convert]::ToString(([int]$rawVal -band 0x3F), 2).PadLeft(6, '0')
    $bitFormatted = "$($binStr.Substring(0,2))|$($binStr.Substring(2,2))|$($binStr.Substring(4,2))"

    return [PSCustomObject]@{
        DecimalValue = [int]$rawVal
        HexValue     = ("0x{0:X2}" -f [int]$rawVal)
        BitMask      = $bitFormatted
        LengthDesc   = $lenStr
        VarDesc      = $varStr
        BoostDesc    = $boostStr
    }
}

function Show-QuantumSchedulerModal {
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = "WinUltix - Quantum Scheduler Matrix (Win32PrioritySeparation)"
    $modal.Size = New-Object System.Drawing.Size(760, 520)
    $modal.MinimumSize = New-Object System.Drawing.Size(760, 520)
    $modal.StartPosition = "CenterParent"
    $modal.FormBorderStyle = "FixedDialog"
    $modal.MaximizeBox = $false
    $modal.BackColor = [System.Drawing.Color]::FromArgb(255, 30, 30, 30)
    $modal.ForeColor = [System.Drawing.Color]::White
    $modal.Add_HandleCreated({ Enable-WinUltixDarkTitleBar -Form $this })

    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Modifies HKLM\...\PriorityControl\Win32PrioritySeparation. The Windows kernel (PsChangeQuantumTable) applies changes INSTANTLY in real time without a reboot, allowing live A/B testing in games."
    $lblDesc.Location = New-Object System.Drawing.Point(15, 12)
    $lblDesc.Size = New-Object System.Drawing.Size(715, 38)
    $lblDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

    $lblTelemetry = New-Object System.Windows.Forms.Label
    $lblTelemetry.Location = New-Object System.Drawing.Point(15, 55)
    $lblTelemetry.Size = New-Object System.Drawing.Size(715, 72)
    $lblTelemetry.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblTelemetry.ForeColor = [System.Drawing.Color]::LightGreen
    $lblTelemetry.Font = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Bold)
    $lblTelemetry.BorderStyle = "FixedSingle"
    $lblTelemetry.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)

    $profiles = @(
        [PSCustomObject]@{ Value = 38; Hex = "0x26"; Name = "0x26 (38 dec) | Short | Variable | 3:1 Foreground Boost [Competitive FPS]"; Desc = "Fastest context switching + 3x CPU time slice for the active game window. Best for CS2, Valorant, Overwatch, and Apex." }
        [PSCustomObject]@{ Value = 40; Hex = "0x28"; Name = "0x28 (40 dec) | Short | Fixed    | 1:1 Equal Slice      [WinUltix Heavy Default]"; Desc = "Deterministic fixed quantum. Prevents foreground render threads from starving audio (audiodg) or worker threads in UE5/heavy titles." }
        [PSCustomObject]@{ Value = 42; Hex = "0x2A"; Name = "0x2A (42 dec) | Short | Fixed    | 3:1 Hybrid Matrix    [Enthusiast Low-Jitter]"; Desc = "Combines Fixed quantum bitmask (10) with maximum quantum table index (10). Popular among competitive latency tuners." }
        [PSCustomObject]@{ Value = 22; Hex = "0x16"; Name = "0x16 (22 dec) | Long  | Variable | 3:1 Foreground Boost [Cache-Heavy Simulators]"; Desc = "Longer execution slices reduce context-switch L1/L2 cache flushes. Useful in MSFS, Tarkov, or strategy sims." }
        [PSCustomObject]@{ Value = 2;  Hex = "0x02"; Name = "0x02 (2 dec)  | OS Default       | 3:1 Standard Client  [Windows 11 Factory]"; Desc = "Standard Windows 11 out-of-the-box scheduler behavior (6:2 quantum ticks)." }
    )

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(15, 140)
    $listBox.Size = New-Object System.Drawing.Size(715, 165)
    $listBox.BackColor = [System.Drawing.Color]::FromArgb(255, 32, 34, 38)
    $listBox.ForeColor = [System.Drawing.Color]::FromArgb(255, 235, 240, 245)
    $listBox.BorderStyle = "FixedSingle"
    $listBox.Font = New-Object System.Drawing.Font("Consolas", 10.5)
    foreach ($p in $profiles) { [void]$listBox.Items.Add($p.Name) }

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.Location = New-Object System.Drawing.Point(15, 315)
    $lblDetail.Size = New-Object System.Drawing.Size(715, 45)
    $lblDetail.ForeColor = [System.Drawing.Color]::Silver
    $lblDetail.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Italic)

    $refreshInfo = {
        $info = Get-QuantumSchedulerInfo
        $lblTelemetry.Text = "ACTIVE KERNEL STATE : $($info.HexValue) ($($info.DecimalValue) dec) | 6-Bit Mask (AA|BB|CC): [$($info.BitMask)]`r`n" +
                             "QUANTUM LENGTH      : $($info.LengthDesc)`r`n" +
                             "SCHEDULER MODE      : $($info.VarDesc) | $($info.BoostDesc)"
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            if ($profiles[$i].Value -eq $info.DecimalValue) {
                $listBox.SelectedIndex = $i
                break
            }
        }
    }

    $listBox.Add_SelectedIndexChanged({
        if ($listBox.SelectedIndex -ge 0) {
            $lblDetail.Text = "Engineering Note: " + $profiles[$listBox.SelectedIndex].Desc
        }
    }.GetNewClosure())

    &$refreshInfo
    if ($listBox.SelectedIndex -lt 0) { $listBox.SelectedIndex = 0 }

    $btnApply = New-UltixButton -Parent $modal -Text "Apply Selected Quantum (Live - Zero Reboot)" -X 15 -Y 425 -Width 330 -Height 38 -RGB @(150, 60, 60)
    $btnApply.Add_Click({
        if ($listBox.SelectedIndex -lt 0) { return }
        $sel = $profiles[$listBox.SelectedIndex]
        Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value $sel.Value -Type DWord -Force
        Write-GUI " -> [LIVE QUANTUM] Enforced Win32PrioritySeparation = $($sel.Hex) ($($sel.Value) dec) [$($sel.Name)]"
        &$refreshInfo
    }.GetNewClosure())

    $btnReset = New-UltixButton -Parent $modal -Text "Restore Factory (0x02)" -X 355 -Y 425 -Width 200 -Height 38 -RGB @(60, 100, 150)
    $btnReset.Add_Click({
        Set-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -Type DWord -Force
        Write-GUI " -> [LIVE QUANTUM] Restored factory Win32PrioritySeparation = 0x02 (2 dec)."
        &$refreshInfo
    }.GetNewClosure())

    $btnClose = New-UltixButton -Parent $modal -Text "Close" -X 610 -Y 425 -Width 120 -Height 38 -RGB @(60, 60, 60)
    $btnClose.DialogResult = "Cancel"

    $modal.Controls.AddRange(@($lblDesc, $lblTelemetry, $listBox, $lblDetail))
    try { [void]$modal.ShowDialog($global:form) } finally { $modal.Dispose() }
}

# ------------------------------------------
# Z7: UI INITIALIZATION (PRE-FLIGHT HEADER + 2-COLUMN HARDWARE COCKPIT)
# ------------------------------------------
function Initialize-Z7UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = "Hardware"
    $tab.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $topo = Get-CPUTopologyProfile

    # --- SECTION 1: PRE-FLIGHT CPU TOPOLOGY & P-STATE CONTROL ---
    $lblPreFlight = New-Object System.Windows.Forms.Label
    $lblPreFlight.Text = "Pre-Flight CPU Affinity & CPPC P-State Control"
    $lblPreFlight.Location = New-Object System.Drawing.Point(15, 14)
    $lblPreFlight.Size = New-Object System.Drawing.Size(370, 18)
    $lblPreFlight.ForeColor = [System.Drawing.Color]::DarkGray
    $lblPreFlight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    if ($topo.IsSupported) {
        [void](New-UltixButton -Parent $tab -X 15 -Y 36 -Width 240 -Height 40 -RGB @(135, 50, 50) `
            -Text "Affinity Lasso (CPU Core Lock)" `
            -Description "Lock background apps to specific cores ($($topo.CoreDesc)) to free up prime gaming cores." `
            -OnClick ({ Show-AffinityModal "Affinity Lasso - $($topo.Label)" "Lock background processes to $($topo.CoreDesc) with BelowNormal priority." }.GetNewClosure()))
    } else {
        $btnAffinity = New-UltixButton -Parent $tab -X 15 -Y 36 -Width 240 -Height 40 -RGB @(45, 45, 48) `
            -ForeColor ([System.Drawing.Color]::DarkGray) `
            -Text "Affinity Lasso (Requires 6+ Cores)" `
            -Description "Affinity Lasso is disabled on 2-Core and 4-Core CPUs because locking background threads leaves too few cores for games."
        $btnAffinity.Enabled = $false
    }

    [void](New-UltixButton -Parent $tab -X 15 -Y 86 -Width 240 -Height 40 -RGB @(55, 58, 64) `
        -Text "CPPC P-State Unhider" `
        -Description "Unhide and manage advanced AMD/Intel CPPC power states with an automatic SYSTEM Dead Man's Switch." `
        -OnClick { Show-CPPCModal "CPPC Management" "Unhide advanced power plan settings (EPP, Demote, Promote)." })

    [void](New-UltixButton -Parent $tab -X 265 -Y 36 -Width 120 -Height 90 -RGB @(45, 85, 125) `
        -Text "Generate Pre-Flight Shortcut" `
        -Description "Create a desktop shortcut to instantly toggle CPU Affinity Lasso and Max CPPC rules right before launching a game." `
        -OnClick { New-PreFlightShortcut })

    # --- SECTION 2: 2-COLUMN LOW-LATENCY HARDWARE & BUS TUNING ---
    $lblColLeft = New-Object System.Windows.Forms.Label
    $lblColLeft.Text = "Scheduler, Timer & Bus"
    $lblColLeft.Location = New-Object System.Drawing.Point(15, 138)
    $lblColLeft.Size = New-Object System.Drawing.Size(180, 18)
    $lblColLeft.ForeColor = [System.Drawing.Color]::DarkGray
    $lblColLeft.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    $lblColRight = New-Object System.Windows.Forms.Label
    $lblColRight.Text = "IRQ, USB & OC Diagnostics"
    $lblColRight.Location = New-Object System.Drawing.Point(205, 138)
    $lblColRight.Size = New-Object System.Drawing.Size(180, 18)
    $lblColRight.ForeColor = [System.Drawing.Color]::DarkGray
    $lblColRight.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

    # Row 1 (Y = 160)
    [void](New-UltixButton -Parent $tab -X 15 -Y 160 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "Quantum Scheduler Matrix" `
        -Description "Live Win32PrioritySeparation quantum tuner (0x26, 0x28, 0x2A, 0x16, 0x02). Changes apply in real time without rebooting." `
        -OnClick { Show-QuantumSchedulerModal })

    [void](New-UltixButton -Parent $tab -X 205 -Y 160 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "MSI & IRQ Affinity Enforcer" `
        -Description "Force Message Signaled Interrupts (MSI), set Interrupt Priority, offload IRQs from Core 0, and monitor live kernel DPCs." `
        -OnClick { Show-MsiModal "MSI & IRQ Affinity Enforcer" "Force PCI devices into MSI mode, adjust interrupt priority, and offload high-DPC drivers (GPU/NIC) from Core 0." })

    # Row 2 (Y = 210)
    [void](New-UltixButton -Parent $tab -X 15 -Y 210 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "System Timer & TSC (0.5ms)" `
        -Description "Fix Windows 11 API to allow global 0.5ms High Resolution Timers and force CPU TSC." `
        -OnClick { Show-TimerModal "Timer Resolution Subsystem" "Enable legacy 0.5ms requests globally and stabilize DPC latency." })

    [void](New-UltixButton -Parent $tab -X 205 -Y 210 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "USB XHCI Topology Map" `
        -Description "Maps physical USB XHCI controllers to CPU Direct PCIe lanes vs Chipset PCH bridges, and spots Mouse/DAC/VR bus contention." `
        -OnClick { Show-UsbTopologyModal })

    # Row 3 (Y = 260)
    [void](New-UltixButton -Parent $tab -X 15 -Y 260 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "I/O & Memory Optimizer" `
        -Description "Disable NVMe APST, PCIe ASPM, and System Memory Compression to reduce CPU overhead and micro-stuttering." `
        -OnClick { Show-NVMeModal "I/O & Memory Optimizer" "Prevent NVMe and PCIe bus from entering low-power states (D3hot/L1.2) and disable RAM compression." })

    [void](New-UltixButton -Parent $tab -X 205 -Y 260 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Network NDIS & TCP Tuner" `
        -Description "Configure low-latency NDIS parameters, TCP properties, and offloads with full symmetric revert." `
        -OnClick { Show-NetworkModal "Network Optimizer" "Disable flow control, power saving, interrupt moderation, and enforce TCPNoDelay." })

    # Row 4 (Y = 310 - Full Width)
    [void](New-UltixButton -Parent $tab -X 15 -Y 310 -Width 370 -Height 40 -RGB @(45, 85, 125) `
        -Text "WHEA Hardware Error Logger & OC Decoder" `
        -Description "Scan system logs for hardware instability (Curve Optimizer / FCLK / DDR5 timings) and decode APIC IDs to physical CPU cores." `
        -OnClick { Show-WHEAModal "WHEA Logger" "Analyze hardware errors to find unstable CPU cores or RAM." })

    # --- SECTION 3: LIVE KERNEL INTERRUPT / DPC TELEMETRY PANEL (Y = 365) ---
    $lblDpcHeader = New-Object System.Windows.Forms.Label
    $lblDpcHeader.Text = "Live Kernel Interrupt / DPC Distribution Monitor (ntdll.dll)"
    $lblDpcHeader.Location = New-Object System.Drawing.Point(15, 365)
    $lblDpcHeader.Size = New-Object System.Drawing.Size(370, 20)
    $lblDpcHeader.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDpcHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblTabDpc = New-Object System.Windows.Forms.Label
    $lblTabDpc.Location = New-Object System.Drawing.Point(15, 387)
    $lblTabDpc.Size = New-Object System.Drawing.Size(370, 68)
    $lblTabDpc.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 20, 20)
    $lblTabDpc.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $lblTabDpc.Font = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)
    $lblTabDpc.TextAlign = "TopLeft"
    $lblTabDpc.BorderStyle = "FixedSingle"
    $lblTabDpc.Padding = New-Object System.Windows.Forms.Padding(5, 5, 5, 4)

    $lblTabLegend = New-Object System.Windows.Forms.Label
    $lblTabLegend.Text = "C0..Cn = Physical Cores (SMT: 2 LP#/Core) | LP# = Logical Thread`r`nColor = Core 0 Load: Green (<30%) | Yellow (30-54%) | Red (>=55%)"
    $lblTabLegend.Location = New-Object System.Drawing.Point(15, 459)
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

    $btnToggleDpc = New-UltixButton -Parent $tab -X 15 -Y 495 -Width 320 -Height 36 -RGB @(45, 85, 125) `
        -Text "Start Live DPC Monitor (1Hz Stream)" `
        -Description "Toggles real-time 1Hz polling of ntdll!NtQuerySystemInformation (SystemInterruptInformation). Automatically pauses if you switch tabs."

    $btnHelpDpc = New-UltixButton -Parent $tab -X 345 -Y 495 -Width 40 -Height 36 -RGB @(72, 76, 82) `
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
            $this.BackColor   = [System.Drawing.Color]::FromArgb(255, 45, 95, 60)
            Update-UltixDpcMonitorUI -TargetLabel $lbl -State $state -CompactMode
            $timer.Start()
            Write-GUI " -> Live Kernel DPC Monitor started (1Hz polling)."
        } else {
            $timer.Stop()
            $state.IsRunning = $false
            $this.Text       = "Start Live DPC Monitor (1Hz Stream)"
            $this.BackColor  = [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
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

    $tab.Controls.AddRange(@($lblPreFlight, $lblColLeft, $lblColRight, $lblDpcHeader, $lblTabDpc, $lblTabLegend))
    $TabControl.Controls.Add($tab)
}