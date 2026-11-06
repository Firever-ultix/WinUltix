# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z1_CLEANUP.PS1 - CLEANUP MODULE (v3.14)
# Z1_Cleanup: Deep disk & orphan hygiene (WU/CBS cache, Temp/Dumps, 3rd-party/GPU shader caches, Event Logs, DriverStore OEM INF Sweeper, Windows Installer MSI/MSP Sweeper, Surgical Registry Orphan Sweeper, Ghost Services, and NTFS Recycle Bin).
# ==========================================

# ------------------------------------------
# Z1: CLEANUP AUDITS (PURE RUNSPACE WORKER)
# ------------------------------------------
function Get-CleanupState {
    param([string]$Category)
    
    $rules   = [System.Collections.Generic.List[hashtable]]::new()
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    if ($Category -eq "WU") {
        $rules.Add(@{
            UIDisplayName = "Windows Update Download Cache"
            Path          = "$env:windir\SoftwareDistribution\Download"
            Paths         = @("$env:windir\SoftwareDistribution\Download")
            Type          = "Files"
            ServiceGroup  = "WU"
        })
        $rules.Add(@{
            UIDisplayName = "Delivery Optimization Cache"
            Path          = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
            Paths         = @(
                "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache",
                "$env:windir\SoftwareDistribution\DeliveryOptimization"
            )
            Type          = "Files"
            ServiceGroup  = "WU"
        })
        $rules.Add(@{
            UIDisplayName = "Windows Update ETW Logs"
            Path          = "$env:windir\Logs\WindowsUpdate"
            Paths         = @("$env:windir\Logs\WindowsUpdate")
            Type          = "Files"
            ServiceGroup  = "None"
        })
        $rules.Add(@{
            UIDisplayName = "CBS Servicing Logs (Logs\CBS)"
            Path          = "$env:windir\Logs\CBS"
            Paths         = @("$env:windir\Logs\CBS")
            Type          = "Files"
            ServiceGroup  = "CBS"
        })
    }

    if ($Category -eq "Temp") {
        $rules.Add(@{ UIDisplayName = "Windows System Temp"; Path = "$env:windir\Temp"; Paths = @("$env:windir\Temp"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Paths = @("$env:windir\Prefetch"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Archive (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Queue (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Type = "Files" })

        if ([System.IO.File]::Exists("$env:windir\MEMORY.DMP")) {
            $rules.Add(@{ UIDisplayName = "System Memory Dump"; Path = "$env:windir\MEMORY.DMP"; Paths = @("$env:windir\MEMORY.DMP"); Type = "Files" })
        }
        if ([System.IO.Directory]::Exists("$env:windir\Minidump")) {
            $rules.Add(@{ UIDisplayName = "Minidump Files"; Path = "$env:windir\Minidump"; Paths = @("$env:windir\Minidump"); Type = "Files" })
        }

        $userProfiles    = @(Get-UltixUserProfiles)
        $profileTempDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($prof in $userProfiles) {
            $userName = $prof.UserName
            $base     = $prof.LocalPath
            $uTemp    = "$base\AppData\Local\Temp"

            try {
                [void]$profileTempDirs.Add([System.IO.Path]::GetFullPath($uTemp).TrimEnd('\'))
            } catch {
                [void]$profileTempDirs.Add($uTemp.TrimEnd('\'))
            }

            $rules.Add(@{ UIDisplayName = "User Temp ($userName)"; Path = $uTemp; Paths = @($uTemp); Type = "Files" })
            
            $userWerPaths = @(
                "$base\AppData\Local\Microsoft\Windows\WER\ReportArchive",
                "$base\AppData\Local\Microsoft\Windows\WER\ReportQueue"
            )
            if ([System.IO.Directory]::Exists($userWerPaths[0]) -or [System.IO.Directory]::Exists($userWerPaths[1])) {
                $rules.Add(@{ UIDisplayName = "User WER Reports ($userName)"; Path = $userWerPaths[0]; Paths = $userWerPaths; Type = "Files" })
            }
        }

        # Only add $env:TEMP if it points to a custom non-profile path (e.g., RAMDisk or dedicated scratch volume)
        if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
            $envTempNorm = try { [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') } catch { $env:TEMP.TrimEnd('\') }
            if (-not $profileTempDirs.Contains($envTempNorm) -and [System.IO.Directory]::Exists($envTempNorm)) {
                $rules.Add(@{ UIDisplayName = "Custom Environment Temp ($envTempNorm)"; Path = $envTempNorm; Paths = @($envTempNorm); Type = "Files" })
            }
        }
    }

    if ($Category -eq "EventLogs") {
        $rules.Add(@{ UIDisplayName = "Windows Event Logs"; Path = "$env:windir\System32\winevt\Logs"; Paths = @("$env:windir\System32\winevt\Logs"); Type = "EventLogs" })
    }

    if ($Category -eq "ThirdParty") {
        # Chromium browsers supporting multi-profile (Default + Profile *)
        $chromiumBrowsers = @(
            @{ Name = "Chrome";  RelUserData = "AppData\Local\Google\Chrome\User Data" }
            @{ Name = "Edge";    RelUserData = "AppData\Local\Microsoft\Edge\User Data" }
            @{ Name = "Brave";   RelUserData = "AppData\Local\BraveSoftware\Brave-Browser\User Data" }
            @{ Name = "Vivaldi"; RelUserData = "AppData\Local\Vivaldi\User Data" }
        )

        # Consolidated per-user app & GPU shader caches (only added if DetectDir or any cache path exists)
        $userCaches = @(
            @{
                Name      = "Opera Cache"
                DetectDir = "AppData\Local\Opera Software\Opera Stable"
                RelPaths  = @(
                    "AppData\Local\Opera Software\Opera Stable\Cache",
                    "AppData\Local\Opera Software\Opera Stable\Cache\Cache_Data",
                    "AppData\Local\Opera Software\Opera Stable\Network\Cache",
                    "AppData\Local\Opera Software\Opera Stable\Code Cache",
                    "AppData\Local\Opera Software\Opera Stable\GPUCache"
                )
            }
            @{
                Name      = "Opera GX Cache"
                DetectDir = "AppData\Local\Opera Software\Opera GX Stable"
                RelPaths  = @(
                    "AppData\Local\Opera Software\Opera GX Stable\Cache",
                    "AppData\Local\Opera Software\Opera GX Stable\Cache\Cache_Data",
                    "AppData\Local\Opera Software\Opera GX Stable\Network\Cache",
                    "AppData\Local\Opera Software\Opera GX Stable\Code Cache",
                    "AppData\Local\Opera Software\Opera GX Stable\GPUCache"
                )
            }
            @{
                Name      = "Discord Cache"
                DetectDir = "AppData\Roaming\discord"
                RelPaths  = @(
                    "AppData\Roaming\discord\Cache",
                    "AppData\Roaming\discord\Cache\Cache_Data",
                    "AppData\Roaming\discord\Code Cache",
                    "AppData\Roaming\discord\GPUCache"
                )
            }
            @{
                Name      = "Steam HTML Cache"
                DetectDir = "AppData\Local\Steam"
                RelPaths  = @("AppData\Local\Steam\htmlcache")
            }
            @{
                Name      = "Epic Games Cache"
                DetectDir = "AppData\Local\EpicGamesLauncher"
                RelPaths  = @(
                    "AppData\Local\EpicGamesLauncher\Saved\webcache",
                    "AppData\Local\EpicGamesLauncher\Saved\webcache_4430",
                    "AppData\Local\EpicGamesLauncher\Saved\HttpCache"
                )
            }
            @{
                Name      = "Spotify Cache"
                DetectDir = "AppData\Local\Spotify"
                RelPaths  = @(
                    "AppData\Local\Spotify\Data",
                    "AppData\Local\Spotify\Browser\Cache"
                )
            }
            @{
                Name      = "Deezer Cache"
                DetectDir = "AppData\Roaming\deezer-desktop"
                RelPaths  = @("AppData\Roaming\deezer-desktop\Cache")
            }
            @{
                Name      = "VLC Art Cache"
                DetectDir = "AppData\Roaming\vlc"
                RelPaths  = @("AppData\Roaming\vlc\art")
            }
            @{
                Name      = "DirectX D3DSCache"
                DetectDir = "AppData\Local\D3DSCache"
                RelPaths  = @("AppData\Local\D3DSCache")
            }
            @{
                Name      = "NVIDIA DX & GL Shader Cache"
                DetectDir = "AppData\Local\NVIDIA"
                RelPaths  = @(
                    "AppData\Local\NVIDIA\DXCache",
                    "AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache",
                    "AppData\Local\NVIDIA\GLCache",
                    "AppData\Roaming\NVIDIA\ComputeCache"
                )
            }
            @{
                Name      = "AMD DX & Vulkan Shader Cache"
                DetectDir = "AppData\Local\AMD"
                RelPaths  = @(
                    "AppData\Local\AMD\DxCache",
                    "AppData\Local\AMD\DxcCache",
                    "AppData\Local\AMD\VkCache",
                    "AppData\Local\AMD\GLCache"
                )
            }
        )

        $globalCaches = @(
            @{ Name = "Battle.net"; DetectDir = "$env:ProgramData\Battle.net";     Path = "$env:ProgramData\Battle.net\Cache" }
            @{ Name = "GOG Galaxy"; DetectDir = "$env:ProgramData\GOG.com\Galaxy"; Path = "$env:ProgramData\GOG.com\Galaxy\webcache" }
        )

        # Dynamic profile resolution via Core_Helpers Get-UltixUserProfiles (Zero hardcoded C:\Users)
        foreach ($prof in (Get-UltixUserProfiles)) {
            $usr  = $prof.UserName
            $base = $prof.LocalPath

            # 1. Multi-profile Chromium enumeration (only when browser User Data exists)
            foreach ($browser in $chromiumBrowsers) {
                $userDataDir = Join-Path -Path $base -ChildPath $browser.RelUserData
                if (-not [System.IO.Directory]::Exists($userDataDir)) { continue }

                $profDirs = @(Get-ChildItem -LiteralPath $userDataDir -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" })

                if ($profDirs.Count -gt 0) {
                    $isFirstProf = $true
                    foreach ($profDir in $profDirs) {
                        $pName = $profDir.Name
                        $pFull = $profDir.FullName
                        $cPaths = [System.Collections.Generic.List[string]]::new()
                        foreach ($relSub in @("Cache", "Network\Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage", "Service Worker\ScriptCache")) {
                            $cPaths.Add("$pFull\$relSub")
                        }
                        if ($isFirstProf) {
                            $cPaths.Add("$userDataDir\ShaderCache")
                            $cPaths.Add("$userDataDir\GrShaderCache")
                            $isFirstProf = $false
                        }
                        $rules.Add(@{
                            UIDisplayName = "$($browser.Name) Cache ($usr - $pName)"
                            Path          = "$pFull\Cache"
                            Paths         = @($cPaths)
                            Type          = "Files"
                        })
                    }
                }
            }

            # 2. Consolidated per-user app & GPU shader caches (filtered by installation presence)
            foreach ($app in $userCaches) {
                $detectFull = Join-Path -Path $base -ChildPath $app.DetectDir
                $fullPaths  = @($app.RelPaths | ForEach-Object { Join-Path -Path $base -ChildPath $_ })

                $isInstalled = [System.IO.Directory]::Exists($detectFull)
                if (-not $isInstalled) {
                    foreach ($fp in $fullPaths) {
                        if ([System.IO.Directory]::Exists($fp)) { $isInstalled = $true; break }
                    }
                }

                if ($isInstalled) {
                    $rules.Add(@{
                        UIDisplayName = "$($app.Name) ($usr)"
                        Path          = $fullPaths[0]
                        Paths         = $fullPaths
                        Type          = "Files"
                    })
                }
            }
            
            # 3. Firefox multi-profile enumeration (consolidated per profile)
            $ffProfilesPath = "$base\AppData\Local\Mozilla\Firefox\Profiles"
            if ([System.IO.Directory]::Exists($ffProfilesPath)) {
                $ffFolders = @(Get-ChildItem -LiteralPath $ffProfilesPath -Directory -Force -ErrorAction SilentlyContinue)
                foreach ($ff in $ffFolders) {
                    $ffPaths = @(
                        "$($ff.FullName)\cache2",
                        "$($ff.FullName)\startupCache",
                        "$($ff.FullName)\jumpListCache"
                    )
                    $rules.Add(@{
                        UIDisplayName = "Firefox Cache ($usr - $($ff.Name))"
                        Path          = $ffPaths[0]
                        Paths         = $ffPaths
                        Type          = "Files"
                    })
                }
            }
        }

        foreach ($app in $globalCaches) {
            if ([System.IO.Directory]::Exists($app.DetectDir) -or [System.IO.Directory]::Exists($app.Path)) {
                $rules.Add(@{ UIDisplayName = "$($app.Name) Cache (Global)"; Path = $app.Path; Paths = @($app.Path); Type = "Files" })
            }
        }
    }

    if ($Category -eq "RecycleBin") {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
            $binPath = "$($drive.Root)`$Recycle.Bin"
            $rules.Add(@{ UIDisplayName = "Recycle Bin ($($drive.Name):)"; Path = $binPath; Paths = @($binPath); Type = "RecycleBin" })
        }
    }

    $totalRules = $rules.Count
    $currentIdx = 0

    foreach ($rule in $rules) {
        $currentIdx++
        if ($null -ne $UltixSync -and $totalRules -gt 0) {
            $UltixSync.Progress = [int](($currentIdx / $totalRules) * 100)
        }

        $isDetected = $false
        $sizeMB = 0

        $targetList = if ($rule.ContainsKey("Paths") -and $null -ne $rule.Paths) { [string[]]$rule.Paths } else { [string[]]@($rule.Path) }
        $bytes = Get-UltixFastSize -TargetPaths $targetList

        if ($bytes -gt 0) {
            $sizeMB = [math]::Round(($bytes / 1MB), 2)
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
# Z1: ASYNCHRONOUS CLEANING ENGINE ($UltixSync)
# ------------------------------------------
function Invoke-InteractiveCleanup {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    if ($SelectedItems.Count -eq 0) { return }

    Write-GUI " -> Dispatching cleanup worker to background Runspace..."
    Update-Progress 5

    # Wrap $SelectedItems as a single-element array @(,$SelectedItems) so Invoke-AsyncTask passes it as one parameter
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)

        $total = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
            }

            $rule = $item.ActionData
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue(" -> Purging: $($rule.UIDisplayName)...")
            }

            try {
                if ($rule.Type -eq "EventLogs") {
                    $channels = @(wevtutil.exe el 2>$null)
                    $totalCh  = $channels.Count
                    $chIdx    = 0

                    foreach ($ch in $channels) {
                        $chIdx++
                        if ($null -ne $UltixSync -and $totalCh -gt 0 -and ($chIdx % 20 -eq 0)) {
                            $UltixSync.Progress = [int](($chIdx / $totalCh) * 100)
                        }
                        & wevtutil.exe cl "$ch" 2>$null
                    }
                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [OK] Cleared $totalCh Event Viewer channel(s).")
                    }
                }
                elseif ($rule.Type -eq "RecycleBin") {
                    $path = $rule.Path
                    if (Test-Path -LiteralPath $path) {
                        & takeown.exe /F "$path\*" /R /A /D Y 2>$null | Out-Null
                        # Use well-known Administrators SID (*S-1-5-32-544) for locale independence
                        & icacls.exe "$path\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                elseif ($rule.Type -eq "Files") {
                    $targetPaths = if ($rule.ContainsKey("Paths") -and $null -ne $rule.Paths) { $rule.Paths } else { @($rule.Path) }
                    $svcGroup    = if ($rule.ContainsKey("ServiceGroup")) { $rule.ServiceGroup } else { "None" }

                    $servicesToManage = switch ($svcGroup) {
                        "WU"  { @("dosvc", "bits", "wuauserv") }
                        "CBS" { @("TrustedInstaller") }
                        default {
                            if ($rule.UIDisplayName -match "Windows Update|Delivery Optimization") {
                                @("dosvc", "bits", "wuauserv")
                            } else {
                                @()
                            }
                        }
                    }

                    $runningServices = [System.Collections.Generic.List[string]]::new()

                    try {
                        # Capture initial service states and stop running instances
                        foreach ($svcName in $servicesToManage) {
                            $svcObj = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                            if ($null -ne $svcObj -and $svcObj.Status -eq 'Running') {
                                $runningServices.Add($svcName)
                                Stop-Service -Name $svcName -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                            }
                        }

                        # Release CBS.log file handle held by background TiWorker.exe process
                        if ($svcGroup -eq "CBS") {
                            Stop-Process -Name "TiWorker" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 300
                        }

                        foreach ($tPath in $targetPaths) {
                            if ([string]::IsNullOrWhiteSpace($tPath) -or -not (Test-Path -LiteralPath $tPath)) { continue }

                            if (Test-Path -LiteralPath $tPath -PathType Leaf) {
                                Remove-Item -LiteralPath $tPath -Force -ErrorAction SilentlyContinue
                            } else {
                                Get-ChildItem -LiteralPath $tPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    } finally {
                        # Symmetrically restore only services that were running prior to cleanup (excluding TrustedInstaller demand service)
                        foreach ($svcName in $runningServices) {
                            if ($svcName -ne "TrustedInstaller") {
                                Start-Service -Name $svcName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Partial lock on $($rule.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Cleanup operation completed.`n"
    }
}

# ------------------------------------------
# Z1: DRIVERSTORE ORPHAN SWEEPER (PNPUTIL & KERNEL DRIVERDATABASE)
# ------------------------------------------
function Get-DriverStoreOrphans_Worker {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }

    $activeOemInfs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # 1. Authoritative CfgMgr32 device-to-driver dump (catches Base INFs, Extension INFs, Audio KS, and Root devices)
    $devDrvOut = (pnputil.exe /enum-devices /drivers 2>$null) -join "`n"
    if (-not [string]::IsNullOrWhiteSpace($devDrvOut)) {
        foreach ($m in [regex]::Matches($devDrvOut, '(?i)\b(oem\d+\.inf)\b')) {
            [void]$activeOemInfs.Add($m.Groups[1].Value.ToLowerInvariant())
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }

    # 2. Fast native Win32 Registry traversal across HKLM\SYSTEM\CurrentControlSet\Enum (ROOT, SWD, USB, PCI, HID)
    $boundDeviceIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $enumRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Enum", $false)
    if ($null -ne $enumRoot) {
        try {
            foreach ($busName in $enumRoot.GetSubKeyNames()) {
                $busKey = $enumRoot.OpenSubKey($busName, $false)
                if ($null -eq $busKey) { continue }
                try {
                    foreach ($devName in $busKey.GetSubKeyNames()) {
                        $devKey = $busKey.OpenSubKey($devName, $false)
                        if ($null -eq $devKey) { continue }
                        try {
                            foreach ($instName in $devKey.GetSubKeyNames()) {
                                $instKey = $devKey.OpenSubKey($instName, $false)
                                if ($null -eq $instKey) { continue }
                                try {
                                    $drvLink = [string]$instKey.GetValue("Driver", "")
                                    if (-not [string]::IsNullOrWhiteSpace($drvLink)) {
                                        [void]$boundDeviceIds.Add($drvLink)
                                    }
                                } finally {
                                    $instKey.Dispose()
                                }
                            }
                        } finally {
                            $devKey.Dispose()
                        }
                    }
                } finally {
                    $busKey.Dispose()
                }
            }
        } finally {
            $enumRoot.Dispose()
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 45 }

    # 3. Inspect Control\Class bindings + unconditionally lock active Extension & SoftwareComponent classes
    $alwaysLockClasses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$alwaysLockClasses.Add("{e2f84ce7-8efa-411c-aa69-97454ca4cb57}") # Extension INF Class
    [void]$alwaysLockClasses.Add("{5c4c3332-344d-483c-8739-259e934c9cc8}") # SoftwareComponent Class

    $classRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Control\Class", $false)
    if ($null -ne $classRoot) {
        try {
            foreach ($clsGuid in $classRoot.GetSubKeyNames()) {
                $clsKey = $classRoot.OpenSubKey($clsGuid, $false)
                if ($null -eq $clsKey) { continue }
                try {
                    $isAlwaysLockedClass = $alwaysLockClasses.Contains($clsGuid)
                    foreach ($subName in $clsKey.GetSubKeyNames()) {
                        if ($subName -notmatch '^\d{4}$') { continue }
                        $subKey = $clsKey.OpenSubKey($subName, $false)
                        if ($null -eq $subKey) { continue }
                        try {
                            $infPath = [string]$subKey.GetValue("InfPath", "")
                            if ($infPath -match '^(?i)(oem\d+\.inf)$') {
                                $relDrv = "$clsGuid\$subName"
                                if ($isAlwaysLockedClass -or $boundDeviceIds.Contains($relDrv)) {
                                    [void]$activeOemInfs.Add($matches[1].ToLowerInvariant())
                                }
                            }
                        } finally {
                            $subKey.Dispose()
                        }
                    }
                } finally {
                    $clsKey.Dispose()
                }
            }
        } finally {
            $classRoot.Dispose()
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 60 }

    # 4. Map oemXX.inf -> FileRepository folder paths via HKLM\SYSTEM\DriverDatabase\DriverPackages + directory fallback
    $repoBase  = "$env:SystemRoot\System32\DriverStore\FileRepository"
    $oemToRepo = @{}
    $drvDbRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\DriverDatabase\DriverPackages", $false)
    if ($null -ne $drvDbRoot) {
        try {
            foreach ($pkgName in $drvDbRoot.GetSubKeyNames()) {
                $pkgKey = $drvDbRoot.OpenSubKey($pkgName, $false)
                if ($null -eq $pkgKey) { continue }
                try {
                    $oemVal = [string]$pkgKey.GetValue("", "")
                    if ($oemVal -match '^(?i)(oem\d+\.inf)$') {
                        $oemToRepo[$matches[1].ToLowerInvariant()] = Join-Path $repoBase $pkgName
                    }
                } catch {
                } finally {
                    $pkgKey.Dispose()
                }
            }
        } finally {
            $drvDbRoot.Dispose()
        }
    }

    # 5. Parse pnputil.exe /enum-drivers in a 100% locale-independent manner (supports MM/dd/yyyy, dd.MM.yyyy, yyyy-MM-dd)
    $rawPnp = (pnputil.exe /enum-drivers 2>$null) -join "`n"
    $blocks = $rawPnp -split "(?:\r?\n){2,}"
    $parsedDrivers = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($blk in $blocks) {
        if ($blk -notmatch '(?im)^\s*[^:]+:\s*(oem\d+\.inf)\s*$') { continue }
        $oemInf = $matches[1].ToLowerInvariant()

        $lines = @($blk -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match ':' })
        $origInf   = "Unknown.inf"
        $provider  = ""
        $className = ""
        $verDate   = "N/A"

        foreach ($ln in $lines) {
            $val = ($ln -split ':\s*', 2)[1].Trim()
            if ([string]::IsNullOrWhiteSpace($val) -or $val -eq $oemInf) { continue }
            elseif ($val -match '^\{[0-9a-fA-F\-]{36}\}$') { continue }
            elseif ($origInf -eq "Unknown.inf" -and $val -match '(?i)^[a-z0-9_\-\.]+\.inf$') { $origInf = $val }
            elseif ($val -match '^\d{1,4}[/\.\-]\d{1,2}[/\.\-]\d{1,4}\s+[\d\.]+$') { $verDate = $val }
            elseif ([string]::IsNullOrEmpty($provider))  { $provider  = $val }
            elseif ([string]::IsNullOrEmpty($className)) { $className = $val }
        }

        if ([string]::IsNullOrEmpty($provider))  { $provider  = "Unknown" }
        if ([string]::IsNullOrEmpty($className)) { $className = "System" }

        $repoDir = $oemToRepo[$oemInf]
        if ([string]::IsNullOrWhiteSpace($repoDir) -and $origInf -ne "Unknown.inf") {
            $cand = Get-ChildItem -LiteralPath $repoBase -Filter "$($origInf)_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $cand) { $repoDir = $cand.FullName }
        }

        $bytes  = if (-not [string]::IsNullOrWhiteSpace($repoDir) -and [System.IO.Directory]::Exists($repoDir)) { Get-UltixFastSize -TargetPaths @($repoDir) } else { 0 }
        $sizeMB = [math]::Round($bytes / 1MB, 2)

        $isActive  = $activeOemInfs.Contains($oemInf)
        $statusStr = if ($isActive) { "[ACTIVE - LOCKED]" } else { "[ORPHAN / OLD]" }

        $parsedDrivers.Add([PSCustomObject]@{
            OemInf        = $oemInf
            OriginalInf   = $origInf
            Provider      = $provider
            DriverClass   = $className
            VersionDate   = $verDate
            SizeMB        = $sizeMB
            SizeDisplay = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $sizeMB)
            Status        = $statusStr
            IsLocked      = $isActive
            IsDetected    = (-not $isActive)
            UIDisplayName = "$oemInf ($origInf | $provider | $verDate) [ $sizeMB MB ]"
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($parsedDrivers | Sort-Object IsLocked, @{Expression="SizeMB"; Descending=$true}, OriginalInf)
}

function Show-DriverStoreSweeper {
    param(
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [switch]$AuditOnly
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: DriverStore FileRepository (Background Thread) ---"
    } else {
        Write-GUI " -> Scanning DriverStore FileRepository & PnP bindings (Background Thread)..."
    }
    Update-Progress 10

    $sb = (Get-Command -Name Get-DriverStoreOrphans_Worker).ScriptBlock
    $isAudit = $AuditOnly.IsPresent

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$allDrv = @($output | Where-Object { $null -ne $_ })
        $orphans = @($allDrv | Where-Object { -not $_.IsLocked })
        $totalOrphanMB = [math]::Round((($orphans | Measure-Object -Property SizeMB -Sum).Sum), 2)

        if ($isAudit) {
            if ($orphans.Count -gt 0) {
                foreach ($o in $orphans) {
                    Write-GUI "  [!] Orphaned Package: $($o.UIDisplayName)"
                }
                Write-GUI "-> STATUS: $($orphans.Count) orphaned/superseded driver package(s) found (Reclaimable: $totalOrphanMB MB).`n"
            } else {
                Write-GUI "  [OK] DriverStore is completely clean. Zero orphaned driver packages found.`n"
            }
            return
        }

        if ($allDrv.Count -eq 0) {
            Write-GUI "  [OK] No third-party OEM driver packages found in DriverStore.`n"
            return
        }

        $cols = @(
            @{ Header = "OEM INF";      Property = "OemInf";      Width = 95  }
            @{ Header = "Status";       Property = "Status";      Width = 140 }
            @{ Header = "Size";         Property = "SizeDisplay"; Width = 95  }
            @{ Header = "Original INF"; Property = "OriginalInf"; Width = 145 }
            @{ Header = "Provider";     Property = "Provider";    Width = 150 }
            @{ Header = "Class";        Property = "DriverClass"; Width = 120 }
            @{ Header = "Date & Ver";   Property = "VersionDate"; Width = 165 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - DriverStore Orphan Sweeper (Reclaimable: $totalOrphanMB MB)" `
            -Description "Active drivers bound to hardware are locked in RED. Select orphaned/superseded OEM packages to purge from FileRepository." `
            -Data $allDrv -Columns $cols -PrimaryButtonText "Delete Selected Orphans (pnputil)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> DriverStore cleanup cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $cur   = 0
            [double]$freedMB = 0

            foreach ($drv in $Selected) {
                $cur++
                if ($null -ne $UltixSync) { $UltixSync.Progress = [int](($cur / $total) * 100) }
                if ($drv.IsLocked) { continue }

                $UltixSync.Logs.Enqueue(" -> Deleting DriverStore package: $($drv.OemInf) ($($drv.OriginalInf) - $($drv.SizeDisplay.Trim()))...")
                $null = pnputil.exe /delete-driver $drv.OemInf 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $freedMB += $drv.SizeMB
                    $UltixSync.Logs.Enqueue("    [OK] Purged $($drv.OemInf) from DriverStore.")
                } else {
                    $UltixSync.Logs.Enqueue("    [!] OS protected $($drv.OemInf) (Still referenced by a device node). Skipped.")
                }
            }
            return [math]::Round($freedMB, 2)
        } -OnComplete ({
            param($reclaimed)
            Update-Progress 0
            Write-GUI " -> DriverStore sweep completed. Reclaimed: $reclaimed MB.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

# ------------------------------------------
# Z1: WINDOWS INSTALLER (MSI / MSP / PATCHCACHE) ORPHAN SWEEPER
# ------------------------------------------
function Get-InstallerOrphans_Worker {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }
    $installerDir = "$env:windir\Installer"
    if (-not [System.IO.Directory]::Exists($installerDir)) { return @() }

    # 1. Build map of all active .msi / .msp LocalPackage paths via native Win32 Registry API
    $activePackages = @{}
    $patchLookup    = @{}
    $activePatchIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $userDataRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData", $false)
    if ($null -ne $userDataRoot) {
        try {
            foreach ($sidName in $userDataRoot.GetSubKeyNames()) {
                $sidKey = $userDataRoot.OpenSubKey($sidName, $false)
                if ($null -eq $sidKey) { continue }
                try {
                    # Collect registered patches metadata first
                    $patchesKey = $sidKey.OpenSubKey("Patches", $false)
                    if ($null -ne $patchesKey) {
                        try {
                            foreach ($patchId in $patchesKey.GetSubKeyNames()) {
                                $pKey = $patchesKey.OpenSubKey($patchId, $false)
                                if ($null -eq $pKey) { continue }
                                try {
                                    $lp = [string]$pKey.GetValue("LocalPackage", "")
                                    if (-not [string]::IsNullOrWhiteSpace($lp)) {
                                        $dn = [string]$pKey.GetValue("DisplayName", "")
                                        $patchLookup[$patchId] = [PSCustomObject]@{
                                            Path = $lp.Trim()
                                            Name = if (-not [string]::IsNullOrWhiteSpace($dn)) { $dn } else { "Registered OS/App Patch" }
                                        }
                                    }
                                } finally {
                                    $pKey.Dispose()
                                }
                            }
                        } finally {
                            $patchesKey.Dispose()
                        }
                    }

                    # Collect installed products and their active patch bindings
                    $prodsKey = $sidKey.OpenSubKey("Products", $false)
                    if ($null -ne $prodsKey) {
                        try {
                            foreach ($prodGuid in $prodsKey.GetSubKeyNames()) {
                                $prodKey = $prodsKey.OpenSubKey($prodGuid, $false)
                                if ($null -eq $prodKey) { continue }
                                try {
                                    $instPropKey = $prodKey.OpenSubKey("InstallProperties", $false)
                                    if ($null -ne $instPropKey) {
                                        try {
                                            $lp = [string]$instPropKey.GetValue("LocalPackage", "")
                                            if (-not [string]::IsNullOrWhiteSpace($lp)) {
                                                $dn   = [string]$instPropKey.GetValue("DisplayName", "")
                                                $pub  = [string]$instPropKey.GetValue("Publisher", "")
                                                $leaf = [System.IO.Path]::GetFileName($lp.Trim()).ToLowerInvariant()
                                                $activePackages[$leaf] = [PSCustomObject]@{
                                                    ProductName = if (-not [string]::IsNullOrWhiteSpace($dn))  { $dn }  else { "Installed MSI Product" }
                                                    Publisher   = if (-not [string]::IsNullOrWhiteSpace($pub)) { $pub } else { "Microsoft / OEM" }
                                                }
                                            }
                                        } finally {
                                            $instPropKey.Dispose()
                                        }
                                    }

                                    $prodPatchesKey = $prodKey.OpenSubKey("Patches", $false)
                                    if ($null -ne $prodPatchesKey) {
                                        try {
                                            foreach ($boundPatchId in $prodPatchesKey.GetSubKeyNames()) {
                                                [void]$activePatchIds.Add($boundPatchId)
                                            }
                                        } finally {
                                            $prodPatchesKey.Dispose()
                                        }
                                    }
                                } finally {
                                    $prodKey.Dispose()
                                }
                            }
                        } finally {
                            $prodsKey.Dispose()
                        }
                    }
                } finally {
                    $sidKey.Dispose()
                }
            }
        } finally {
            $userDataRoot.Dispose()
        }
    }

    foreach ($patchId in $activePatchIds) {
        if ($patchLookup.ContainsKey($patchId)) {
            $pInfo = $patchLookup[$patchId]
            $leaf  = [System.IO.Path]::GetFileName($pInfo.Path).ToLowerInvariant()
            if (-not $activePackages.ContainsKey($leaf)) {
                $activePackages[$leaf] = [PSCustomObject]@{
                    ProductName = $pInfo.Name
                    Publisher   = "Active MSP Patch"
                }
            }
        }
    }

    # Cross-check standard Uninstall keys (x64 & WOW6432Node) via native Registry API
    foreach ($uninstSubPath in @("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall")) {
        $uninstRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($uninstSubPath, $false)
        if ($null -eq $uninstRoot) { continue }
        try {
            foreach ($uName in $uninstRoot.GetSubKeyNames()) {
                $uKey = $uninstRoot.OpenSubKey($uName, $false)
                if ($null -eq $uKey) { continue }
                try {
                    $lp = [string]$uKey.GetValue("LocalPackage", "")
                    if (-not [string]::IsNullOrWhiteSpace($lp)) {
                        $leaf = [System.IO.Path]::GetFileName($lp.Trim()).ToLowerInvariant()
                        if (-not $activePackages.ContainsKey($leaf)) {
                            $dn  = [string]$uKey.GetValue("DisplayName", "")
                            $pub = [string]$uKey.GetValue("Publisher", "")
                            $activePackages[$leaf] = [PSCustomObject]@{
                                ProductName = if (-not [string]::IsNullOrWhiteSpace($dn))  { $dn }  else { $uName }
                                Publisher   = if (-not [string]::IsNullOrWhiteSpace($pub)) { $pub } else { "Installed App" }
                            }
                        }
                    }
                } finally {
                    $uKey.Dispose()
                }
            }
        } finally {
            $uninstRoot.Dispose()
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }

    # 2. Enumerate C:\Windows\Installer (*.msi, *.msp) and inspect orphaned metadata via COM SummaryInformation
    $files = @(Get-ChildItem -LiteralPath $installerDir -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -match '^\.(?i)(msi|msp)$' })

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $wiCom = $null
    try { $wiCom = New-Object -ComObject WindowsInstaller.Installer -ErrorAction SilentlyContinue } catch { }

    $totalFiles = [math]::Max(1, $files.Count)
    $idx = 0

    foreach ($file in $files) {
        $idx++
        if ($null -ne $UltixSync -and ($idx % 15 -eq 0 -or $idx -eq $totalFiles)) {
            $UltixSync.Progress = 40 + [int](($idx / $totalFiles) * 55)
        }

        $leafLower = $file.Name.ToLowerInvariant()
        $sizeMB    = [math]::Round($file.Length / 1MB, 2)
        if ($sizeMB -lt 0.05) { continue }

        $isActive = $activePackages.ContainsKey($leafLower)
        $prodName = "Orphaned Installer Package"
        $pubName  = "Unknown Vendor"

        if ($isActive) {
            $prodName = $activePackages[$leafLower].ProductName
            $pubName  = $activePackages[$leafLower].Publisher
        } elseif ($null -ne $wiCom) {
            $sumInfo = $null
            try {
                $sumInfo = $wiCom.SummaryInformation($file.FullName, 0)
                $subj = [string]$sumInfo.Property(3)
                $auth = [string]$sumInfo.Property(4)
                if (-not [string]::IsNullOrWhiteSpace($subj)) { $prodName = $subj.Trim() }
                if (-not [string]::IsNullOrWhiteSpace($auth)) { $pubName  = $auth.Trim() }
            } catch {
            } finally {
                if ($null -ne $sumInfo) {
                    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sumInfo)
                }
            }
        }

        $statusTag = if ($isActive) { "[ACTIVE - LOCKED]" } else { "[ORPHAN / SAFE]" }

        $results.Add([PSCustomObject]@{
            FileName      = $file.Name
            Status        = $statusTag
            SizeMB        = $sizeMB
            SizeDisplay = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $sizeMB)
            ProductName   = $prodName
            Publisher     = $pubName
            FullPath      = $file.FullName
            IsDirectory   = $false
            IsLocked      = $isActive
            IsDetected    = (-not $isActive)
            UIDisplayName = "$($file.Name) ($prodName | $pubName) [ $sizeMB MB ]"
        })
    }

    if ($null -ne $wiCom) {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wiCom)
    }

    # 3. Check $PatchCache$\Managed baseline cache folder
    $patchCacheDir = "$installerDir\`$PatchCache`$\Managed"
    if ([System.IO.Directory]::Exists($patchCacheDir)) {
        $pcBytes = Get-UltixFastSize -TargetPaths @($patchCacheDir)
        $pcMB    = [math]::Round($pcBytes / 1MB, 2)
        if ($pcMB -ge 1.0) {
            $results.Add([PSCustomObject]@{
                FileName      = "`$PatchCache`$"
                Status        = "[ORPHAN / CACHE]"
                SizeMB        = $pcMB
                SizeDisplay   = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0,7:0.00} MB", $pcMB)
                ProductName   = "Windows Installer Baseline RTM Patch Cache (Safe to empty)"
                Publisher     = "Microsoft Corporation"
                FullPath      = $patchCacheDir
                IsDirectory   = $true
                IsLocked      = $false
                IsDetected    = $true
                UIDisplayName = "`$PatchCache`$\Managed (Baseline RTM Cache) [ $pcMB MB ]"
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results | Sort-Object IsLocked, @{Expression="SizeMB"; Descending=$true}, ProductName)
}

function Show-InstallerSweeper {
    param(
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [switch]$AuditOnly
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: Windows Installer (C:\Windows\Installer) Orphans ---"
    } else {
        Write-GUI " -> Auditing C:\Windows\Installer packages & UserData bindings (Background Thread)..."
    }
    Update-Progress 10

    $sb = (Get-Command -Name Get-InstallerOrphans_Worker).ScriptBlock
    $isAudit = $AuditOnly.IsPresent

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$allItems = @($output | Where-Object { $null -ne $_ })
        $orphans = @($allItems | Where-Object { -not $_.IsLocked })
        $totalOrphanMB = [math]::Round((($orphans | Measure-Object -Property SizeMB -Sum).Sum), 2)

        if ($isAudit) {
            if ($orphans.Count -gt 0) {
                foreach ($o in $orphans) {
                    Write-GUI "  [!] Orphaned MSI/MSP: $($o.UIDisplayName)"
                }
                Write-GUI "-> STATUS: $($orphans.Count) orphaned installer package(s) found (Reclaimable: $totalOrphanMB MB).`n"
            } else {
                Write-GUI "  [OK] C:\Windows\Installer has zero orphaned packages.`n"
            }
            return
        }

        if ($allItems.Count -eq 0) {
            Write-GUI "  [OK] No MSI/MSP packages found in C:\Windows\Installer.`n"
            return
        }

        $cols = @(
            @{ Header = "Package";      Property = "FileName";    Width = 110 }
            @{ Header = "Status";       Property = "Status";      Width = 140 }
            @{ Header = "Size";         Property = "SizeDisplay"; Width = 95  }
            @{ Header = "Product Name"; Property = "ProductName"; Width = 335 }
            @{ Header = "Publisher";    Property = "Publisher";   Width = 175 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Installer (MSI/MSP) Orphan Sweeper (Reclaimable: $totalOrphanMB MB)" `
            -Description "Active MSI/MSP packages required for app uninstallation are locked in RED. Select orphaned packages to permanently delete." `
            -Data $allItems -Columns $cols -PrimaryButtonText "Purge Selected Orphans"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Windows Installer cleanup cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $cur   = 0
            [double]$freedMB = 0

            foreach ($pkg in $Selected) {
                $cur++
                if ($null -ne $UltixSync) { $UltixSync.Progress = [int](($cur / $total) * 100) }
                if ($pkg.IsLocked) { continue }

                try {
                    if ($pkg.IsDirectory) {
                        Get-ChildItem -LiteralPath $pkg.FullPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        $freedMB += $pkg.SizeMB
                        $UltixSync.Logs.Enqueue("    [OK] Purged Windows Installer `$PatchCache`$ ($($pkg.SizeDisplay.Trim())).")
                    } elseif (Test-Path -LiteralPath $pkg.FullPath -PathType Leaf) {
                        $fItem = Get-Item -LiteralPath $pkg.FullPath -Force -ErrorAction SilentlyContinue
                        if ($null -ne $fItem) { $fItem.Attributes = 'Normal' }
                        Remove-Item -LiteralPath $pkg.FullPath -Force -ErrorAction Stop
                        $freedMB += $pkg.SizeMB
                        $UltixSync.Logs.Enqueue("    [OK] Deleted orphaned $($pkg.FileName) ($($pkg.ProductName) - $($pkg.SizeDisplay.Trim())).")
                    }
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Locked/Skipped $($pkg.FileName): $($_.Exception.Message)")
                }
            }
            return [math]::Round($freedMB, 2)
        } -OnComplete ({
            param($reclaimed)
            Update-Progress 0
            Write-GUI " -> Windows Installer sweep completed. Reclaimed: $reclaimed MB.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

# ------------------------------------------
# Z1: SURGICAL REGISTRY ORPHAN SWEEPER
# ------------------------------------------
function Get-RegistryOrphans_Worker {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }
    $orphans = [System.Collections.Generic.List[PSCustomObject]]::new()

    $readyDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($drv in ([System.IO.DriveInfo]::GetDrives())) {
        if ($drv.IsReady) { [void]$readyDrives.Add($drv.Name.Substring(0, 1)) }
    }

    function Test-IsOrphanedDiskPath {
        param([string]$RawPath, [switch]$IsDirectory)
        if ([string]::IsNullOrWhiteSpace($RawPath)) { return $false }
        $clean = [System.Environment]::ExpandEnvironmentVariables($RawPath.Trim().Trim('"')).Trim()
        if ($clean -notmatch '^([a-zA-Z]):\\') { return $false }

        $driveLetter = $matches[1]
        if (-not $readyDrives.Contains($driveLetter)) { return $false }
        if ($clean -match '(?i)^[a-z]:\\Windows(\\|$)' -or $clean -match '(?i)\\WindowsApps\\') { return $false }

        if ($IsDirectory) {
            return (-not [System.IO.Directory]::Exists($clean))
        } else {
            return (-not [System.IO.File]::Exists($clean))
        }
    }

    # 1. Orphaned Windows Firewall Application Rules
    $fwPath = "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
    if (Test-Path -LiteralPath $fwPath) {
        $fwKey = Get-Item -LiteralPath $fwPath -ErrorAction SilentlyContinue
        if ($null -ne $fwKey) {
            try {
                foreach ($valName in $fwKey.Property) {
                    $ruleStr = [string]$fwKey.GetValue($valName)
                    if ($ruleStr -match '\|App=([^|]+)\|') {
                        $appPath = $matches[1]
                        if (Test-IsOrphanedDiskPath -RawPath $appPath) {
                            $ruleTitle = if ($ruleStr -match '\|Name=([^|]+)\|') { $matches[1] } else { $valName }
                            $orphans.Add([PSCustomObject]@{
                                Category      = "[Firewall Rule]"
                                TargetName    = $ruleTitle
                                MissingPath   = $appPath
                                RegPath       = $fwPath
                                ValueName     = $valName
                                RawValueData  = $ruleStr
                                ValueKind     = "String"
                                EntryType     = "Value"
                                IsDetected    = $true
                                UIDisplayName = "[Firewall Rule] $ruleTitle -> $appPath"
                            })
                        }
                    }
                }
            } finally { $fwKey.Dispose() }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }

    # 2. Orphaned AppCompat Flags (Compatibility Assistant Store & Layers)
    $compatKeys = @(
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store",
        "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers",
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    )
    foreach ($cPath in $compatKeys) {
        if (-not (Test-Path -LiteralPath $cPath)) { continue }
        $cKey = Get-Item -LiteralPath $cPath -ErrorAction SilentlyContinue
        if ($null -ne $cKey) {
            try {
                foreach ($valName in $cKey.Property) {
                    if (Test-IsOrphanedDiskPath -RawPath $valName) {
                        $leaf   = [System.IO.Path]::GetFileName($valName)
                        $rawObj = $cKey.GetValue($valName)
                        $vKind  = if ($rawObj -is [byte[]]) { "Binary" } else { "String" }
                        $vData  = if ($rawObj -is [byte[]]) { [Convert]::ToBase64String($rawObj) } else { [string]$rawObj }
                        $orphans.Add([PSCustomObject]@{
                            Category      = "[AppCompat Cache]"
                            TargetName    = $leaf
                            MissingPath   = $valName
                            RegPath       = $cPath
                            ValueName     = $valName
                            RawValueData  = $vData
                            ValueKind     = $vKind
                            EntryType     = "Value"
                            IsDetected    = $true
                            UIDisplayName = "[AppCompat Cache] $leaf -> $valName"
                        })
                    }
                }
            } finally { $cKey.Dispose() }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }

    # 3. Orphaned DirectX Per-App GPU Preferences
    $dxPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (Test-Path -LiteralPath $dxPath) {
        $dxKey = Get-Item -LiteralPath $dxPath -ErrorAction SilentlyContinue
        if ($null -ne $dxKey) {
            try {
                foreach ($valName in $dxKey.Property) {
                    if ($valName -eq "DirectXUserGlobalSettings") { continue }
                    if (Test-IsOrphanedDiskPath -RawPath $valName) {
                        $leaf = [System.IO.Path]::GetFileName($valName)
                        $orphans.Add([PSCustomObject]@{
                            Category      = "[GPU Preference]"
                            TargetName    = $leaf
                            MissingPath   = $valName
                            RegPath       = $dxPath
                            ValueName     = $valName
                            RawValueData  = [string]$dxKey.GetValue($valName)
                            ValueKind     = "String"
                            EntryType     = "Value"
                            IsDetected    = $true
                            UIDisplayName = "[GPU Preference] $leaf -> $valName"
                        })
                    }
                }
            } finally { $dxKey.Dispose() }
        }
    }

    # 4. Orphaned SharedDLLs Reference Counters
    $sharedDllPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\SharedDlls"
    if (Test-Path -LiteralPath $sharedDllPath) {
        $sdKey = Get-Item -LiteralPath $sharedDllPath -ErrorAction SilentlyContinue
        if ($null -ne $sdKey) {
            try {
                foreach ($valName in $sdKey.Property) {
                    if (Test-IsOrphanedDiskPath -RawPath $valName) {
                        $leaf = [System.IO.Path]::GetFileName($valName)
                        $orphans.Add([PSCustomObject]@{
                            Category      = "[SharedDLLs]"
                            TargetName    = $leaf
                            MissingPath   = $valName
                            RegPath       = $sharedDllPath
                            ValueName     = $valName
                            RawValueData  = [string]$sdKey.GetValue($valName)
                            ValueKind     = "DWord"
                            EntryType     = "Value"
                            IsDetected    = $true
                            UIDisplayName = "[SharedDLLs] $leaf -> $valName"
                        })
                    }
                }
            } finally { $sdKey.Dispose() }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 80 }

    # 5. Orphaned Windows Installer Folder References
    $msiFoldersPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders"
    if (Test-Path -LiteralPath $msiFoldersPath) {
        $mfKey = Get-Item -LiteralPath $msiFoldersPath -ErrorAction SilentlyContinue
        if ($null -ne $mfKey) {
            try {
                foreach ($valName in $mfKey.Property) {
                    if ($valName -match '(?i)\\Microsoft\\|\\Common Files\\|\\Windows\\') { continue }
                    if (Test-IsOrphanedDiskPath -RawPath $valName -IsDirectory) {
                        $dirName = [System.IO.Path]::GetFileName($valName.TrimEnd('\'))
                        $orphans.Add([PSCustomObject]@{
                            Category      = "[MSI Folder Ref]"
                            TargetName    = $dirName
                            MissingPath   = $valName
                            RegPath       = $msiFoldersPath
                            ValueName     = $valName
                            RawValueData  = [string]$mfKey.GetValue($valName)
                            ValueKind     = "String"
                            EntryType     = "Value"
                            IsDetected    = $true
                            UIDisplayName = "[MSI Folder Ref] $dirName -> $valName"
                        })
                    }
                }
            } finally { $mfKey.Dispose() }
        }
    }

    # 6. Orphaned App Paths Subkeys
    foreach ($apRoot in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths", "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths")) {
        if (-not (Test-Path -LiteralPath $apRoot)) { continue }
        foreach ($sub in (Get-ChildItem -LiteralPath $apRoot -ErrorAction SilentlyContinue)) {
            try {
                $defVal = [string]$sub.GetValue("")
                if ([string]::IsNullOrWhiteSpace($defVal)) { continue }

                $exePath = [System.Environment]::ExpandEnvironmentVariables($defVal.Trim()).Trim()
                if ($exePath -match '^"([^"]+)"') {
                    $exePath = $matches[1]
                } elseif ($exePath -match '(?i)^(.+?\.(?:exe|com|bat|cmd|msc))(?:$|\s)') {
                    $exePath = $matches[1]
                } else {
                    $exePath = $exePath.Trim('"')
                }

                if (Test-IsOrphanedDiskPath -RawPath $exePath) {
                    $orphans.Add([PSCustomObject]@{
                        Category      = "[App Paths]"
                        TargetName    = $sub.PSChildName
                        MissingPath   = $exePath
                        RegPath       = $sub.PSPath
                        ValueName     = "(Default)"
                        RawValueData  = $defVal
                        ValueKind     = "String"
                        EntryType     = "SubKey"
                        IsDetected    = $true
                        UIDisplayName = "[App Paths] $($sub.PSChildName) -> $exePath"
                    })
                }
            } catch {
            } finally {
                $sub.Dispose()
            }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($orphans | Sort-Object Category, TargetName)
}

function Show-RegistryOrphanSweeper {
    param(
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [switch]$AuditOnly
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: Surgical Registry Orphan Sweeper (Background Thread) ---"
    } else {
        Write-GUI " -> Scanning Firewall, AppCompat, DirectX GPU, SharedDLLs & AppPaths for dead file paths..."
    }
    Update-Progress 10

    $sb = (Get-Command -Name Get-RegistryOrphans_Worker).ScriptBlock
    $isAudit = $AuditOnly.IsPresent

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$orphans = @($output | Where-Object { $null -ne $_ })

        if ($isAudit) {
            if ($orphans.Count -gt 0) {
                $grouped = $orphans | Group-Object Category
                foreach ($g in $grouped) {
                    Write-GUI "  [!] $($g.Name): $($g.Count) orphaned registry reference(s)"
                }
                Write-GUI "-> STATUS: $($orphans.Count) total orphaned registry path reference(s) detected.`n"
            } else {
                Write-GUI "  [OK] Zero orphaned path references found in registry.`n"
            }
            return
        }

        $cols = @(
            @{ Header = "Category";            Property = "Category";    Width = 145 }
            @{ Header = "Application / Entry"; Property = "TargetName";  Width = 210 }
            @{ Header = "Missing Disk Path";   Property = "MissingPath"; Width = 500 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Surgical Registry Orphan Sweeper ($($orphans.Count) Orphans)" `
            -Description "100% path-verified registry orphans left behind by uninstalled apps/games. You will choose where to save the JSON backup before purging, or click 'Restore Backup (JSON)...' to import an existing backup." `
            -Data $orphans -Columns $cols -PrimaryButtonText "Purge Selected Orphans..." -SecondaryButtonText "Restore Backup (JSON)..." -SecondaryAlwaysEnabled

        if ($null -eq $res) {
            Write-GUI " -> Registry orphan sweep cancelled.`n"
            return
        }

        if ($res.Action -eq "Secondary") {
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = "WinUltix Registry Backup (*.json)|*.json"
            $ofd.Title = "Select Registry Orphans JSON Backup to Restore"
            $ofd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

            $selectedBackup = $null
            try {
                if ($ofd.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
                    $selectedBackup = $ofd.FileName
                }
            } finally {
                $ofd.Dispose()
            }

            if ([string]::IsNullOrWhiteSpace($selectedBackup) -or -not (Test-Path -LiteralPath $selectedBackup)) {
                Write-GUI " -> Registry backup restore cancelled.`n"
                return
            }

            try {
                $restored = 0
                $bData = @(Get-Content -LiteralPath $selectedBackup -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
                foreach ($entry in $bData) {
                    if ($null -eq $entry -or [string]::IsNullOrWhiteSpace($entry.RegPath)) { continue }
                    if ($entry.EntryType -eq "SubKey") {
                        if (-not (Test-Path -LiteralPath $entry.RegPath)) { New-Item -Path $entry.RegPath -Force | Out-Null }
                        Set-Item -LiteralPath $entry.RegPath -Value ([string]$entry.RawValueData) -Force -ErrorAction SilentlyContinue
                        $restored++
                    } else {
                        if (-not (Test-Path -LiteralPath $entry.RegPath)) { New-Item -Path $entry.RegPath -Force | Out-Null }
                        $kind = if ($entry.PSObject.Properties.Match("ValueKind").Count -gt 0 -and $entry.ValueKind) { [string]$entry.ValueKind } else { "String" }
                        $regItem = Get-Item -LiteralPath $entry.RegPath -ErrorAction SilentlyContinue
                        if ($null -ne $regItem) {
                            $wKey = $regItem.OpenSubKey("", $true)
                            $regItem.Dispose()
                            if ($null -ne $wKey) {
                                try {
                                    if ($kind -eq "Binary" -and -not [string]::IsNullOrWhiteSpace($entry.RawValueData)) {
                                        [byte[]]$bytes = [Convert]::FromBase64String([string]$entry.RawValueData)
                                        $wKey.SetValue([string]$entry.ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
                                    } elseif ($kind -eq "DWord") {
                                        $dw = if ($entry.RawValueData -match '^\d+$') { [int]$entry.RawValueData } else { 1 }
                                        $wKey.SetValue([string]$entry.ValueName, $dw, [Microsoft.Win32.RegistryValueKind]::DWord)
                                    } else {
                                        $wKey.SetValue([string]$entry.ValueName, [string]$entry.RawValueData, [Microsoft.Win32.RegistryValueKind]::String)
                                    }
                                    $restored++
                                } finally {
                                    $wKey.Dispose()
                                }
                            }
                        }
                    }
                }
                Write-GUI " -> [OK] Restored $restored registry entry(s) from: $selectedBackup`n"
            } catch {
                Write-GUI " -> [!] Failed to restore registry backup: $($_.Exception.Message)`n"
            }
            return
        }

        if ($res.Items.Count -eq 0) { return }

        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "WinUltix Registry Backup (*.json)|*.json"
        $sfd.Title = "Save Registry Orphans Backup Before Purging"
        $sfd.FileName = "WinUltix_RegOrphans_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $sfd.InitialDirectory = [Environment]::GetFolderPath("Desktop")

        $targetBackupFile = $null
        try {
            if ($sfd.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
                $targetBackupFile = $sfd.FileName
            }
        } finally {
            $sfd.Dispose()
        }

        if ([string]::IsNullOrWhiteSpace($targetBackupFile)) {
            Write-GUI " -> Registry orphan purge cancelled (No backup file selected).`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $targetBackupFile) -ScriptBlock {
            param([array]$Selected, [string]$BackupPath)
            $parentDir = Split-Path -Path $BackupPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }

            $jsonPayload = @($Selected) | ConvertTo-Json -Depth 4
            $jsonPayload | Set-Content -LiteralPath $BackupPath -Encoding UTF8 -Force -ErrorAction Stop

            # Maintain shadow copy in AppData\Local\WinUltix as emergency fallback
            $shadowDir = "$env:LOCALAPPDATA\WinUltix"
            if (-not (Test-Path -LiteralPath $shadowDir)) { New-Item -Path $shadowDir -ItemType Directory -Force | Out-Null }
            $jsonPayload | Set-Content -LiteralPath "$shadowDir\RegOrphans_LastBackup.json" -Encoding UTF8 -Force -ErrorAction SilentlyContinue

            $total   = $Selected.Count
            $cur     = 0
            $removed = 0

            foreach ($item in $Selected) {
                $cur++
                if ($null -ne $UltixSync -and ($cur % 10 -eq 0 -or $cur -eq $total)) {
                    $UltixSync.Progress = [int](($cur / $total) * 100)
                }
                try {
                    if ($item.EntryType -eq "SubKey") {
                        if (Test-Path -LiteralPath $item.RegPath) {
                            Remove-Item -LiteralPath $item.RegPath -Recurse -Force -ErrorAction Stop
                            $removed++
                        }
                    } else {
                        $regItem = Get-Item -LiteralPath $item.RegPath -ErrorAction Stop
                        if ($null -ne $regItem) {
                            $wKey = $regItem.OpenSubKey("", $true)
                            $regItem.Dispose()
                            if ($null -ne $wKey) {
                                try {
                                    $wKey.DeleteValue([string]$item.ValueName, $true)
                                    $removed++
                                } finally {
                                    $wKey.Dispose()
                                }
                            }
                        }
                    }
                } catch { }
            }
            return [PSCustomObject]@{
                RemovedCount = $removed
                SavedPath    = $BackupPath
            }
        } -OnComplete ({
            param($resObj)
            Update-Progress 0
            if ($null -ne $resObj) {
                Write-GUI " -> [OK] Purged $($resObj.RemovedCount) orphaned registry reference(s). Backup saved to: $($resObj.SavedPath)`n"
            }
        }.GetNewClosure())
    }.GetNewClosure())
}

# ------------------------------------------
# Z1: GHOST SERVICES & DRIVERS SWEEPER (MOVED FROM Z4)
# ------------------------------------------
function Get-GhostServicesState {
    $ghosts = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $readyDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($drv in ([System.IO.DriveInfo]::GetDrives())) {
        if ($drv.IsReady) { [void]$readyDrives.Add($drv.Name.Substring(0, 1)) }
    }

    $runningNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [System.ServiceProcess.ServiceController]::GetServices() | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.ServiceName) }
    [System.ServiceProcess.ServiceController]::GetDevices()  | Where-Object { $_.Status -eq 'Running' } | ForEach-Object { [void]$runningNames.Add($_.ServiceName) }

    $svcRoot = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services", $false)
    if ($null -eq $svcRoot) { return $ghosts }

    try {
        $svcNames = $svcRoot.GetSubKeyNames()
        $total    = $svcNames.Count
        $current  = 0

        foreach ($svcName in $svcNames) {
            $current++
            if ($null -ne $UltixSync -and ($current % 25 -eq 0 -or $current -eq $total)) {
                $UltixSync.Progress = [int](($current / $total) * 100)
            }

            if ($runningNames.Contains($svcName)) { continue }

            # Open with writable=true to automatically skip TrustedInstaller-protected inbox OS services/drivers
            $svcKey = $null
            try {
                $svcKey = $svcRoot.OpenSubKey($svcName, $true)
            } catch {
                continue
            }
            if ($null -eq $svcKey) { continue }

            try {
                # Skip Per-User service templates and dynamic session instances (SERVICE_USER_SERVICE bit 0x40)
                $svcType = $svcKey.GetValue("Type", $null)
                if ($null -ne $svcType -and (([int]$svcType -band 0x40) -ne 0)) { continue }

                $imagePath = [string]$svcKey.GetValue("ImagePath", "")
            } finally {
                $svcKey.Dispose()
            }

            if ([string]::IsNullOrWhiteSpace($imagePath)) { continue }
            if ($imagePath -match '(?i)^\\(?:Driver|FileSystem|KernelObjects)\\') { continue }
            
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
                
                if ([System.IO.File]::Exists($candidateWinDir))    { $rawPath = $candidateWinDir }
                elseif ([System.IO.File]::Exists($candidateSys32)) { $rawPath = $candidateSys32 }
                elseif ([System.IO.File]::Exists($candidateDrv))   { $rawPath = $candidateDrv }
                else { $rawPath = $candidateWinDir }
            }

            # Shield services/drivers installed on currently unplugged external drives
            if ($rawPath -match '^([a-zA-Z]):\\') {
                if (-not $readyDrives.Contains($matches[1])) { continue }
            }
            
            if (-not [System.IO.File]::Exists($rawPath)) {
                $ghosts.Add([PSCustomObject]@{
                    Name          = $svcName
                    Path          = $rawPath
                    UIDisplayName = "Ghost: $svcName (Missing: $rawPath)"
                    IsDetected    = $true
                })
            }
        }
    } finally {
        $svcRoot.Dispose()
    }

    return $ghosts
}

function Remove-GhostServices {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing Ghost Service: $($item.Name)")
            }
            Remove-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($item.Name)" -Recurse -Force -ErrorAction SilentlyContinue
        }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Ghost services purged from system registry.`n"
    }.GetNewClosure())
}

# ------------------------------------------
# Z1: UI INITIALIZATION (CLEANUP & ORPHAN SWEEPERS)
# ------------------------------------------
function Initialize-Z1UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabClean = New-Object System.Windows.Forms.TabPage
    $tabClean.Text = "Cleanup"
    $tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    $invokeCategory = ({
        param([string]$Cat, [switch]$Audit)
        Invoke-UltixAuditFlow `
            -ScannerFunction "Get-CleanupState" `
            -ScannerArguments @($Cat) `
            -AuditLabel $Cat `
            -ModalTitle "WinUltix - $Cat Purge" `
            -ModalDescription "Select items to empty." `
            -ExecutorFunction "Invoke-InteractiveCleanup" `
            -ControlsToDisable $allTabButtons.ToArray() `
            -AuditOnly:$Audit.IsPresent
    }.GetNewClosure())

    # 1. Windows Update & CBS Cache
    $rowWU = New-UltixActionRow -Parent $tabClean -Y 20 -MainRGB @(55, 58, 64) `
        -Text "Clean Windows Update & CBS Cache" `
        -Description "Analyzes and interactively purges Windows Update (SoftwareDistribution), Delivery Optimization, and CBS Servicing logs safely." `
        -AuditDescription "AUDIT: Calculates the exact megabyte footprint of Windows Update, Delivery Optimization, and CBS log files." `
        -OnClick ({ & $invokeCategory "WU" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "WU" -Audit }.GetNewClosure())

    # 2. Temp, Prefetch & Crash Dumps
    $rowTemp = New-UltixActionRow -Parent $tabClean -Y 70 -MainRGB @(55, 58, 64) `
        -Text "Clean Temp, Prefetch & Dumps" `
        -Description "Scans and weighs System Temp, Prefetch, Windows Error Reporting (WER), Crash Dumps, and local Temp directories across all user profiles." `
        -AuditDescription "AUDIT: Weighs orphaned temporary files, WER reports, crash dumps, and prefetch data globally." `
        -OnClick ({ & $invokeCategory "Temp" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "Temp" -Audit }.GetNewClosure())

    # 3. Third-Party App & GPU Shader Cache
    $rowThirdParty = New-UltixActionRow -Parent $tabClean -Y 120 -MainRGB @(55, 58, 64) `
        -Text "Clean 3rd-Party & Shader Cache" `
        -Description "Locates bloated application and shader caches (Multi-profile Chrome/Edge/Brave/Vivaldi/Firefox, Discord, D3DSCache, NVIDIA/AMD DxCache) across all user profiles." `
        -AuditDescription "AUDIT: Aggregates the storage space wasted by third-party browser, launcher, and GPU shader caches." `
        -OnClick ({ & $invokeCategory "ThirdParty" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "ThirdParty" -Audit }.GetNewClosure())

    # 4. Event Viewer Logs
    $rowLogs = New-UltixActionRow -Parent $tabClean -Y 170 -MainRGB @(55, 58, 64) `
        -Text "Clear Event Viewer Logs (wevtutil)" `
        -Description "Calculates the size of Event Logs (.evtx) and asynchronously clears diagnostic history using the native wevtutil engine." `
        -AuditDescription "AUDIT: Checks the current disk space consumed by Windows Event Logs." `
        -OnClick ({ & $invokeCategory "EventLogs" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "EventLogs" -Audit }.GetNewClosure())

    # 5. DriverStore Orphan Sweeper (pnputil FileRepository)
    $rowDrvStore = New-UltixActionRow -Parent $tabClean -Y 220 -MainRGB @(45, 85, 125) `
        -Text "DriverStore Orphan Sweeper (OEM INF)" `
        -Description "Scans C:\Windows\System32\DriverStore\FileRepository for superseded/orphaned OEM driver packages (NVIDIA, AMD, Intel, Realtek) while locking active hardware drivers." `
        -AuditDescription "AUDIT: Calculates total gigabytes/megabytes wasted by old, superseded driver packages in DriverStore." `
        -OnClick ({ Show-DriverStoreSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Show-DriverStoreSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())

    # 6. Windows Installer (C:\Windows\Installer) Orphan Sweeper
    $rowMsiStore = New-UltixActionRow -Parent $tabClean -Y 270 -MainRGB @(45, 85, 125) `
        -Text "Windows Installer Orphan Sweeper (MSI)" `
        -Description "Cross-references C:\Windows\Installer (.msi / .msp / `$PatchCache`$) against active UserData registrations. Locks active uninstallers and purges orphaned packages." `
        -AuditDescription "AUDIT: Calculates disk space wasted by orphaned .msi/.msp packages in C:\Windows\Installer." `
        -OnClick ({ Show-InstallerSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Show-InstallerSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())

    # 7. Surgical Registry Orphan Sweeper
    $rowRegOrphans = New-UltixActionRow -Parent $tabClean -Y 320 -MainRGB @(45, 85, 125) `
        -Text "Surgical Registry Orphan Sweeper" `
        -Description "Scans Firewall Rules, AppCompat Store/Layers, DirectX GPU Preferences, SharedDLLs, MSI Folders, and App Paths for dead file paths with JSON backup." `
        -AuditDescription "AUDIT: Counts dead file/folder references left behind in the registry by uninstalled applications and games." `
        -OnClick ({ Show-RegistryOrphanSweeper -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Show-RegistryOrphanSweeper -ControlsToDisable $allTabButtons.ToArray() -AuditOnly }.GetNewClosure())

    # 8. Ghost Services & Drivers Cleanup
    $rowGhostSvc = New-UltixActionRow -Parent $tabClean -Y 370 -MainRGB @(55, 58, 64) `
        -Text "Cleanup Ghost Services & Drivers" `
        -Description "Scans HKLM\...\Services for orphaned service and driver keys pointing to non-existent binaries (.exe/.sys) and removes them." `
        -AuditDescription "AUDIT: Detects orphaned service and kernel driver registrations pointing to missing disk files." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ModalTitle "WinUltix - Ghost Services Cleanup" -ModalDescription "Select orphaned service/driver keys to remove." -ExecutorFunction "Remove-GhostServices" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GhostServicesState" -AuditLabel "Ghost Services & Drivers" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Found"
        }.GetNewClosure())

    # 9. Hard Empty Recycle Bin (NTFS)
    $rowRecycle = New-UltixActionRow -Parent $tabClean -Y 420 -MainRGB @(135, 50, 50) `
        -Text "Hard Empty Recycle Bin (NTFS)" `
        -Description "Scans all logical partitions for Recycle Bin contents and forcefully purges them in a background thread, bypassing standard file locks." `
        -AuditDescription "AUDIT: Reports the total size of deleted files waiting in the Recycle Bins across all partitions." `
        -OnClick ({ & $invokeCategory "RecycleBin" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "RecycleBin" -Audit }.GetNewClosure())

    foreach ($row in @($rowWU, $rowTemp, $rowThirdParty, $rowLogs, $rowDrvStore, $rowMsiStore, $rowRegOrphans, $rowGhostSvc, $rowRecycle)) {
        $allTabButtons.AddRange($row.Controls)
    }
    $TabControl.Controls.Add($tabClean)
}