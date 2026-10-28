# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z1_CLEANUP.PS1 - CLEANUP MODULE (v3.0.0)
# Z1_Cleanup: Manages deep system cleaning. Uses Core_Helpers high-speed .NET directory enumeration (Get-UltixFastSize) and asynchronous Runspace workers ($UltixSync) to weigh and purge Windows Update/CBS/DeliveryOptimization caches, Temp/WER/Dump buffers, Event Viewer logs (wevtutil), and multi-profile 3rd-party app/shader caches.
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
        $rules.Add(@{ UIDisplayName = "Global User Temp"; Path = "$env:TEMP"; Paths = @("$env:TEMP"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Paths = @("$env:windir\Prefetch"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Archive (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive"); Type = "Files" })
        $rules.Add(@{ UIDisplayName = "WER Report Queue (Global)"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Paths = @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue"); Type = "Files" })

        if ([System.IO.File]::Exists("$env:windir\MEMORY.DMP")) {
            $rules.Add(@{ UIDisplayName = "System Memory Dump"; Path = "$env:windir\MEMORY.DMP"; Paths = @("$env:windir\MEMORY.DMP"); Type = "Files" })
        }
        if ([System.IO.Directory]::Exists("$env:windir\Minidump")) {
            $rules.Add(@{ UIDisplayName = "Minidump Files"; Path = "$env:windir\Minidump"; Paths = @("$env:windir\Minidump"); Type = "Files" })
        }

        foreach ($prof in (Get-UltixUserProfiles)) {
            $userName = $prof.UserName
            $base     = $prof.LocalPath
            $rules.Add(@{ UIDisplayName = "User Temp ($userName)"; Path = "$base\AppData\Local\Temp"; Paths = @("$base\AppData\Local\Temp"); Type = "Files" })
            
            $userWerPaths = @(
                "$base\AppData\Local\Microsoft\Windows\WER\ReportArchive",
                "$base\AppData\Local\Microsoft\Windows\WER\ReportQueue"
            )
            if ([System.IO.Directory]::Exists($userWerPaths[0]) -or [System.IO.Directory]::Exists($userWerPaths[1])) {
                $rules.Add(@{ UIDisplayName = "User WER Reports ($userName)"; Path = $userWerPaths[0]; Paths = $userWerPaths; Type = "Files" })
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

        # Static single-path per-user caches
        $userCaches = @(
            @{ Name = "Opera Cache";       Path = "AppData\Local\Opera Software\Opera Stable\Cache" }
            @{ Name = "Opera Code";        Path = "AppData\Local\Opera Software\Opera Stable\Code Cache" }
            @{ Name = "Opera GPU";         Path = "AppData\Local\Opera Software\Opera Stable\GPUCache" }
            @{ Name = "Opera GX Cache";    Path = "AppData\Local\Opera Software\Opera GX Stable\Cache" }
            @{ Name = "Opera GX Code";     Path = "AppData\Local\Opera Software\Opera GX Stable\Code Cache" }
            @{ Name = "Opera GX GPU";      Path = "AppData\Local\Opera Software\Opera GX Stable\GPUCache" }
            @{ Name = "Discord Cache";     Path = "AppData\Roaming\discord\Cache" }
            @{ Name = "Discord Code";      Path = "AppData\Roaming\discord\Code Cache" }
            @{ Name = "Discord GPU";       Path = "AppData\Roaming\discord\GPUCache" }
            @{ Name = "Steam HTML";        Path = "AppData\Local\Steam\htmlcache" }
            @{ Name = "Epic Games Web";    Path = "AppData\Local\EpicGamesLauncher\Saved\webcache" }
            @{ Name = "Epic Games Http";   Path = "AppData\Local\EpicGamesLauncher\Saved\HttpCache" }
            @{ Name = "Spotify Data";      Path = "AppData\Local\Spotify\Data" }
            @{ Name = "Spotify Browser";   Path = "AppData\Local\Spotify\Browser\Cache" }
            @{ Name = "Deezer";            Path = "AppData\Roaming\deezer-desktop\Cache" }
            @{ Name = "VLC Art";           Path = "AppData\Roaming\vlc\art" }
            @{ Name = "DirectX D3DSCache"; Path = "AppData\Local\D3DSCache" }
            @{ Name = "NVIDIA DXCache";    Path = "AppData\Local\NVIDIA\DXCache" }
            @{ Name = "NVIDIA GLCache";    Path = "AppData\Local\NVIDIA\GLCache" }
            @{ Name = "AMD DxCache";       Path = "AppData\Local\AMD\DxCache" }
        )

        $globalCaches = @(
            @{ Name = "Battle.net"; Path = "$env:ProgramData\Battle.net\Cache" }
            @{ Name = "GOG Galaxy"; Path = "$env:ProgramData\GOG.com\Galaxy\webcache" }
        )

        # Dynamic profile resolution via Core_Helpers Get-UltixUserProfiles (Zero hardcoded C:\Users)
        foreach ($prof in (Get-UltixUserProfiles)) {
            $usr  = $prof.UserName
            $base = $prof.LocalPath

            # 1. Multi-profile Chromium enumeration (Default + Profile *)
            foreach ($browser in $chromiumBrowsers) {
                $userDataDir = Join-Path -Path $base -ChildPath $browser.RelUserData
                if ([System.IO.Directory]::Exists($userDataDir)) {
                    $profDirs = @(Get-ChildItem -LiteralPath $userDataDir -Directory -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -eq "Default" -or $_.Name -like "Profile *" })

                    if ($profDirs.Count -gt 0) {
                        foreach ($profDir in $profDirs) {
                            $pName = $profDir.Name
                            $pFull = $profDir.FullName
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr - $pName)";      Path = "$pFull\Cache";      Paths = @("$pFull\Cache");      Type = "Files" })
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) Code Cache ($usr - $pName)"; Path = "$pFull\Code Cache"; Paths = @("$pFull\Code Cache"); Type = "Files" })
                            $rules.Add(@{ UIDisplayName = "$($browser.Name) GPUCache ($usr - $pName)";   Path = "$pFull\GPUCache";   Paths = @("$pFull\GPUCache");   Type = "Files" })
                        }
                    } else {
                        $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr)"; Path = "$userDataDir\Default\Cache"; Paths = @("$userDataDir\Default\Cache"); Type = "Files" })
                    }
                } else {
                    $rules.Add(@{ UIDisplayName = "$($browser.Name) Cache ($usr)"; Path = "$userDataDir\Default\Cache"; Paths = @("$userDataDir\Default\Cache"); Type = "Files" })
                }
            }

            # 2. Standard per-user app & shader caches
            foreach ($app in $userCaches) {
                $fullAppPath = "$base\$($app.Path)"
                $rules.Add(@{ UIDisplayName = "$($app.Name) ($usr)"; Path = $fullAppPath; Paths = @($fullAppPath); Type = "Files" })
            }
            
            # 3. Firefox multi-profile enumeration
            $ffProfilesPath = "$base\AppData\Local\Mozilla\Firefox\Profiles"
            if ([System.IO.Directory]::Exists($ffProfilesPath)) {
                $ffFolders = Get-ChildItem -LiteralPath $ffProfilesPath -Directory -Force -ErrorAction SilentlyContinue
                foreach ($ff in $ffFolders) {
                    $rules.Add(@{ UIDisplayName = "Firefox Cache ($usr - $($ff.Name))";   Path = "$($ff.FullName)\cache2";       Paths = @("$($ff.FullName)\cache2");       Type = "Files" })
                    $rules.Add(@{ UIDisplayName = "Firefox Startup ($usr - $($ff.Name))"; Path = "$($ff.FullName)\startupCache"; Paths = @("$($ff.FullName)\startupCache"); Type = "Files" })
                }
            }
        }

        foreach ($app in $globalCaches) {
            $rules.Add(@{ UIDisplayName = "$($app.Name) Cache (Global)"; Path = $app.Path; Paths = @($app.Path); Type = "Files" })
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

                        foreach ($tPath in $targetPaths) {
                            if ([string]::IsNullOrWhiteSpace($tPath) -or -not (Test-Path -LiteralPath $tPath)) { continue }

                            if ($servicesToManage.Count -gt 0) {
                                & takeown.exe /F "$tPath\*" /R /A /D Y 2>$null | Out-Null
                                & icacls.exe "$tPath\*" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null
                            }

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
# Z1: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z1UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabClean = New-Object System.Windows.Forms.TabPage
    $tabClean.Text = "Cleanup"
    $tabClean.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    $invokeCategory = {
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
    }.GetNewClosure()

    # 1. Windows Update Cache
    $rowWU = New-UltixActionRow -Parent $tabClean -Y 20 `
        -Text "Clean Windows Update Cache" `
        -Description "Analyzes and interactively purges Windows Update (SoftwareDistribution), Delivery Optimization, and CBS Servicing logs safely." `
        -AuditDescription "AUDIT: Calculates the exact megabyte footprint of Windows Update, Delivery Optimization, and CBS log files." `
        -OnClick ({ & $invokeCategory "WU" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "WU" -Audit }.GetNewClosure())

    # 2. Temp & Prefetch Buffers
    $rowTemp = New-UltixActionRow -Parent $tabClean -Y 70 `
        -Text "Clean Temp and Prefetch Buffers" `
        -Description "Scans and weighs System Temp, Prefetch, Windows Error Reporting (WER), Crash Dumps, and local Temp directories across all user profiles." `
        -AuditDescription "AUDIT: Weighs orphaned temporary files, WER reports, crash dumps, and prefetch data globally." `
        -OnClick ({ & $invokeCategory "Temp" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "Temp" -Audit }.GetNewClosure())

    # 3. Event Viewer Logs
    $rowLogs = New-UltixActionRow -Parent $tabClean -Y 120 `
        -Text "Clear Event Viewer Logs" `
        -Description "Calculates the size of Event Logs (.evtx) and asynchronously clears diagnostic history using the native wevtutil engine." `
        -AuditDescription "AUDIT: Checks the current disk space consumed by Windows Event Logs." `
        -OnClick ({ & $invokeCategory "EventLogs" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "EventLogs" -Audit }.GetNewClosure())

    # 4. Third-Party App Cache
    $rowThirdParty = New-UltixActionRow -Parent $tabClean -Y 170 `
        -Text "Clean Third-Party App Cache" `
        -Description "Locates bloated application and shader caches (Multi-profile Chrome/Edge/Brave/Vivaldi/Firefox, Discord, D3DSCache, NVIDIA/AMD DxCache) across all user profiles." `
        -AuditDescription "AUDIT: Aggregates the storage space wasted by third-party browser, launcher, and GPU shader caches." `
        -OnClick ({ & $invokeCategory "ThirdParty" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "ThirdParty" -Audit }.GetNewClosure())

    # 5. Recycle Bin
    $rowRecycle = New-UltixActionRow -Parent $tabClean -Y 220 `
        -Text "Hard Empty Recycle Bin (NTFS)" `
        -MainRGB @(100, 40, 40) -AuditRGB @(100, 40, 40) `
        -Description "Scans all logical partitions for Recycle Bin contents and forcefully purges them in a background thread, bypassing standard file locks." `
        -AuditDescription "AUDIT: Reports the total size of deleted files waiting in the Recycle Bins across all partitions." `
        -OnClick ({ & $invokeCategory "RecycleBin" }.GetNewClosure()) `
        -OnAudit ({ & $invokeCategory "RecycleBin" -Audit }.GetNewClosure())

    foreach ($row in @($rowWU, $rowTemp, $rowLogs, $rowThirdParty, $rowRecycle)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabClean)
}