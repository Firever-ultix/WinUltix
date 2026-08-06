# ==========================================
# OPTIMIZER_AUDIT_EN.PS1 - DIAGNOSTIC MODULE
# ==========================================

function Assert-Reg { 
    param($Path, $Name, $Expected)
    $actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -ne $actual -and [string]$actual -eq [string]$Expected) { Write-GUI "  [OK] $Name"; return 0 } 
    else { Write-GUI "  [!] $Name (Current: $actual | Expected: $Expected)"; return 1 } 
}

function Assert-Service { 
    param($Name)
    $regStart = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name "Start" -ErrorAction SilentlyContinue).Start
    if ($null -eq $regStart) { Write-GUI "  [OK] $Name (Removed from system)"; return 0 }
    if ($regStart -eq 4) { Write-GUI "  [OK] $Name (Disabled)"; return 0 } 
    else { Write-GUI "  [!] $Name (Invalid start value: $regStart)"; return 1 } 
}

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

function Audit-TempFiles { 
    Write-GUI "--- AUDIT: Temporary Files ---"
    $tempPaths = @("$env:TEMP\*", "$env:windir\Temp\*", "$env:windir\Prefetch\*")
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object { $tempPaths += "$($_.FullName)\AppData\Local\Temp\*" }
    
    $totalSize = 0
    foreach ($p in $tempPaths) { 
        $size = (Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
    }
    if ($totalSize -gt 0) { Write-GUI "  [!] Found: $([math]::Round($totalSize / 1MB, 2)) MB of temporary files." } 
    else { Write-GUI "  [OK] Buffers clean." }
}

function Audit-WindowsUpdate {
    Write-GUI "--- AUDIT: Windows Update Cache ---"
    $path = "$env:windir\SoftwareDistribution\Download"
    Write-GUI "  Target path: $path"
    if (Test-Path $path) {
        $size = (Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($size -gt 0) { Write-GUI "  [!] Found: $([math]::Round($size / 1MB, 2)) MB of temporary update files." }
        else { Write-GUI "  [OK] Update cache is empty." }
    } else { Write-GUI "  [OK] Update cache folder missing or empty." }
}

function Audit-EventLogs {
    Write-GUI "--- AUDIT: Event Viewer Logs ---"
    $logs = (wevtutil el).Count
    Write-GUI "  [INFO] System maintains $logs event log categories (channels)."
    Write-GUI "  -> Clearing them will safely flush all stored records and reset old error history."
}

function Audit-ThirdPartyCache {
    Write-GUI "--- AUDIT: Third-Party App Cache ---"
    Write-GUI "  Targets: Edge, Chrome, Discord, NVIDIA & AMD Shaders"
    $appCachePaths = @("AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data", "AppData\Local\Google\Chrome\User Data\Default\Cache\Cache_Data", "AppData\Local\Discord\Cache", "AppData\Local\NVIDIA\DXCache", "AppData\Local\AMD\DxCache")
    $totalSize = 0
    Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object { 
        $userDir = $_.FullName
        foreach ($partialPath in $appCachePaths) { 
            $fullPath = "$userDir\$partialPath"
            if (Test-Path $fullPath) { 
                $size = (Get-ChildItem -Path "$fullPath\*" -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $totalSize += $size
            } 
        } 
    }
    if ($totalSize -gt 0) { Write-GUI "  [!] Found: $([math]::Round($totalSize / 1MB, 2)) MB of temporary app data." } 
    else { Write-GUI "  [OK] Targeted app caches are clean." }
}

function Audit-RecycleBin {
    Write-GUI "--- AUDIT: Recycle Bin ---"
    $totalSize = 0
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) { 
        $recyclePath = "$($drive.Root)`$Recycle.Bin"
        if (Test-Path $recyclePath) { 
            $size = (Get-ChildItem -Path "$recyclePath\*" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $totalSize += $size
        } 
    }
    if ($totalSize -gt 0) { Write-GUI "  [!] Found: $([math]::Round($totalSize / 1MB, 2)) MB of trashed files across all drives." } 
    else { Write-GUI "  [OK] All Recycle Bins are empty." }
}

function Audit-OneDrive { Write-GUI "--- AUDIT: OneDrive ---"; if ((Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") -or (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup")) { Write-GUI "[!] OneDrive traces found." } else { Write-GUI "[OK] OneDrive eradicated." } }

function Audit-Capabilities { 
    Write-GUI "--- AUDIT: Built-in FOD Features ---"
    $capsList = @("*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*", "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*", "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*", "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*", "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*")
    Write-GUI "Target packages list: $($capsList -join ', ')"
    $found = @()
    foreach ($cap in $capsList) { 
        $installed = Get-WindowsCapability -Online | Where-Object { $_.Name -like $cap -and $_.State -eq 'Installed' }
        if ($installed) { 
            foreach ($c in $installed) { 
                if ($c.Name -notin $found) { $found += $c.Name; Write-GUI "  [!] Found: $($c.Name)" } 
            } 
        } 
    }
    if ($found.Count -eq 0) { Write-GUI "[OK] Base image clean. Target features not detected." } 
}

function Audit-Bloatware { 
    Write-GUI "--- AUDIT: Bloatware (Appx) ---"
    $appList = @("*3DBuilder*", "*3DViewer*", "*Bing*", "*BingNews*", "*BingWeather*", "*Clipchamp*", "*DevHome*", "*PowerAutomateDesktop*", "*Copilot*", "*Store.Engagement*", "*Edge.GameAssist*", "*Family*", "*FeedbackHub*", "*GetHelp*", "*windowscommunicationsapps*", "*WindowsMaps*", "*MixedReality*", "*ZuneVideo*", "*ZuneMusic*", "*Gaming*", "*MicrosoftOfficeHub*", "*OneDriveSync*", "*OneNote*", "*OutlookForWindows*", "*People*", "*Photos*", "*QuickAssist*", "*SkypeApp*", "*SolitaireCollection*", "*MSTeams*", "*MicrosoftTeams*", "*Getstarted*", "*Todos*", "*XboxApp*", "*XboxGamingOverlay*", "*XboxSpeechToTextOverlay*", "*YourPhone*", "*Cortana*", "*WindowsAlarms*", "*SoundRecorder*", "*Client.WebExperience*", "*CrossDevice*", "*TikTok*", "*Instagram*", "*Facebook*", "*Twitter*", "*Netflix*", "*Spotify*", "*Disney*", "*McAfee*", "*Norton*", "*Lenovo*", "*Dell*", "*HP*", "*StickyNotes*")
    Write-GUI "Scanned applications: $($appList -join ', ')"
    $found = @()
    foreach ($app in $appList) { 
        $packages = Get-AppxPackage -Name $app -AllUsers | Where-Object { $_.Name -notmatch "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider" }
        if ($packages) { 
            foreach ($p in $packages) { 
                if ($p.Name -notin $found) { $found += $p.Name; Write-GUI "  [!] Found: $($p.Name)" } 
            } 
        } 
    }
    if ($found.Count -eq 0) { Write-GUI "[OK] No Appx bloatware. System free of target applications." } 
}

function Audit-TelemetryTasks { 
    Write-GUI "--- AUDIT: Task Scheduler ---"
    $tasksToCheck = @("\Microsoft\Windows\Customer Experience Improvement Program\*", "\Microsoft\Windows\Feedback\*", "\Microsoft\Windows\PerformanceTrace\*", "\Microsoft\Windows\Windows Error Reporting\*", "\Microsoft\XblGameSave\*")
    Write-GUI "Scanned telemetry areas: $($tasksToCheck -join ', ')"
    $foundActive = @()
    foreach ($t in $tasksToCheck) { 
        $active = Get-ScheduledTask | Where-Object { $_.TaskPath -like $t -and ($_.State -eq 'Ready' -or $_.State -eq 'Running') }
        foreach ($a in $active) { $foundActive += "$($a.TaskPath)$($a.TaskName)" }
    }
    if ($foundActive.Count -gt 0) { 
        Write-GUI "[!] Active telemetry tasks:"
        foreach ($task in $foundActive) { Write-GUI "  -> $task" } 
    } 
    else { Write-GUI "[OK] All targeted telemetry tasks are disabled." } 
}

function Audit-Power { 
    Write-GUI "--- AUDIT: Power Profile ---"; $err = 0
    $hiber = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue
    if ($hiber -and $hiber.HibernateEnabled -eq 0) { Write-GUI "  [OK] Hibernation (Disabled)" } else { Write-GUI "  [!] Hibernation (Likely active)"; $err++ }
    $err += Assert-Power "SUB_SLEEP" "STANDBYIDLE" 999999 "System Sleep"
    $err += Assert-Power "SUB_VIDEO" "VIDEOIDLE" 3600 "Display Turn Off"
    Write-GUI "-> STATUS: $err issues with power profile." 
}

function Audit-Network { Write-GUI "--- AUDIT: Nagle's Algorithm ---"; $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}; $err=0; foreach ($a in $adapters) { $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.SettingID)"; $val = (Get-ItemProperty -Path $p -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay; if ($val -eq 1) { Write-GUI "  [OK] $($a.Description)" } else { Write-GUI "  [!] $($a.Description) (Missing TCPNoDelay)"; $err++ } }; Write-GUI "-> STATUS: $err network adapters without optimization." }

function Audit-ServicesLight { 
    Write-GUI "--- AUDIT: Services (Office Profile) ---"
    $svcs = @("wuqisvc", "whesvc", "MapsBroker", "RetailDemo", "PcaSvc", "DiagTrack", "edgeupdate", "edgeupdatem")
    $err=0; foreach ($s in $svcs) { $err += Assert-Service $s }; Write-GUI "-> STATUS: $err active services." 
}

function Audit-ServicesHeavy { 
    Write-GUI "--- AUDIT: Gaming Profile Services ---"
    $servicesToDisable = @("wuqisvc", "whesvc", "MapsBroker", "RetailDemo", "PcaSvc", "DiagTrack", "edgeupdate", "edgeupdatem", "InventorySvc", "CDPSvc", "lfsvc", "SysMain", "WSLService", "WSAIFabricSvc", "Spooler", "PrintNotify", "Fax", "TermService", "RemoteRegistry", "WbioSrvc", "SensorDataService", "SensorService", "SensrSvc", "PhoneSvc", "icssvc", "WwanSvc", "WSearch", "CscService", "SharedAccess", "dmwappushservice", "wermgr")
    $servicesToManual = @("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc", "FrameServer", "FrameServerMonitor")
    
    $mismatch = 0
    foreach ($svc in $servicesToDisable) { 
        $val = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($val -ne $null -and $val -ne 4) { Write-GUI "  [!] To Disable: $svc is currently set to $val"; $mismatch++ }
    }
    foreach ($svc in $servicesToManual) { 
        $val = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -ErrorAction SilentlyContinue).Start
        if ($val -ne $null -and $val -ne 3 -and $val -ne 4) { Write-GUI "  [!] To Manual (Safe): $svc is currently set to $val"; $mismatch++ }
    }
    
    if ($mismatch -eq 0) { Write-GUI "  [OK] Gaming Profile correctly enforced (bloat disabled, essential gaming/camera services set to manual)." } 
    else { Write-GUI "  -> STATUS: $mismatch services require configuration." }
}

function Audit-RegTaskbar { 
    Write-GUI "--- AUDIT: Taskbar and Start Menu ---"; $err = 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_Layout" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" "IsDynamicSearchBoxEnabled" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideTaskViewButton" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon" 3
    Write-GUI "-> STATUS: $err missing keys." 
}

function Audit-RegExplorer { 
    Write-GUI "--- AUDIT: File Explorer ---"; $err = 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "SeparateProcess" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "NavPaneExpandToCurrentFolder" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowCloudFilesInQuickAccess" 0
    $err += Assert-Reg "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 0
    $err += Assert-Reg "HKCU:\Control Panel\Desktop" "MenuShowDelay" "50"
    if (Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32") { Write-GUI "  [OK] Classic Context Menu" } else { Write-GUI "  [!] Classic Context Menu"; $err++ }
    Write-GUI "-> STATUS: $err missing keys." 
}

function Audit-RegAnnoyances { 
    Write-GUI "--- AUDIT: OS Annoyances ---"; $err = 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun" 255
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay" 1
    $err += Assert-Reg "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "506"
    $err += Assert-Reg "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "122"
    $err += Assert-Reg "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "58"
    Write-GUI "-> STATUS: $err missing keys." 
}

function Audit-RegPrivacy { 
    Write-GUI "--- AUDIT: Full Privacy, Background Apps & Edge ---"; $err = 0
    Write-GUI "  [ Telemetry and Profiling ]"
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" "HasAccepted" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Input\TIPC" "Enabled" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" 1
    $err += Assert-Reg "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Personalization\Settings" "AcceptedPrivacyPolicy" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0
    $err += Assert-Reg "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    
    Write-GUI "  [ Junk Blockers - ContentDeliveryManager ]"
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $err += Assert-Reg $cdm $k 0 }
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall" "DisablePushToInstall" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\MRT" "DontOfferThroughWUAU" 1

    Write-GUI "  [ Microsoft Edge Blockers ]"
    $edgeKeys = @("StartupBoostEnabled", "BackgroundModeEnabled", "CreateDesktopShortcutDefault", "PersonalizationReportingEnabled", "ShowRecommendationsEnabled", "UserFeedbackAllowed", "AlternateErrorPagesEnabled", "EdgeCollectionsEnabled", "EdgeShoppingAssistantEnabled", "MicrosoftEdgeInsiderPromotionEnabled", "ShowMicrosoftRewards", "WebWidgetAllowed", "DiagnosticData", "EdgeAssetDeliveryServiceEnabled", "WalletDonationEnabled", "DefaultBrowserSettingsCampaignEnabled", "HideFirstRunExperience", "ConfigureDoNotTrack")
    foreach ($k in $edgeKeys) { 
        $expected = if ($k -in @("HideFirstRunExperience", "ConfigureDoNotTrack")) { 1 } else { 0 }
        $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Edge" $k $expected 
    }
    
    Write-GUI "  [ Hard UWP App Permissions ]"
    $privacyKeys = @("LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo")
    foreach ($key in $privacyKeys) { $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" $key 2 }
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsAccessCamera" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsAccessMicrophone" 0

    Write-GUI "  [ Defender & PowerShell Telemetry ]"
    $psTel = [Environment]::GetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'Machine')
    if ($psTel -eq '1') { Write-GUI "  [OK] PowerShell Telemetry (Blocked)" } else { Write-GUI "  [!] PowerShell Telemetry (Active)"; $err++ }
    $mp = (Get-MpPreference -ErrorAction SilentlyContinue).SubmitSamplesConsent
    if ($mp -eq 2) { Write-GUI "  [OK] Defender Samples (Blocked)" } else { Write-GUI "  [!] Defender Samples (Enabled)"; $err++ }

    Write-GUI "-> STATUS: $err missing/invalid entries in privacy zone." 
}

function Audit-RegSystemBoot { 
    Write-GUI "--- AUDIT: Boot, WPBT & Logon ---"; $err = 0
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution" 1
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" "AllowBuildPreview" 0
    $err += Assert-Reg "HKLM:\System\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch" "Start" 4
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "verbosestatus" 1
    Write-GUI "-> STATUS: $err issues in boot zone." 
}

function Audit-RegMouse { 
    Write-GUI "--- AUDIT: Mouse Acceleration ---"; $err = 0
    $err += Assert-Reg "HKCU:\Control Panel\Mouse" "MouseSpeed" "0"
    $err += Assert-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold1" "0"
    $err += Assert-Reg "HKCU:\Control Panel\Mouse" "MouseThreshold2" "0"
    Write-GUI "-> STATUS: $err issues in mouse profile." 
}

function Audit-RegGaming { 
    Write-GUI "--- AUDIT: Hardware & Gaming ---"; $err = 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" "value" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" 0
    $err += Assert-Reg "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0
    $err += Assert-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior" 2
    $err += Assert-Reg "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode" 2
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 4294967295
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 0
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 40
    $err += Assert-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" 1
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" 8
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" 6
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" "High"
    $err += Assert-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" "High"
    Write-GUI "-> STATUS: $err deviations in gaming zone." 
}
function Audit-GarbageCollector { 
    Write-GUI "--- AUDIT: Orphaned Frameworks (Garbage Collector) ---"
    $allPackages = Get-AppxPackage -AllUsers
    $standardApps = $allPackages | Where-Object { $_.IsFramework -eq $false }
    
    $activeDependencies = @()
    foreach ($app in $standardApps) { 
        if ($app.Dependencies) { 
            foreach ($dep in $app.Dependencies) { $activeDependencies += $dep.PackageFullName }
        } 
    }
    $activeDependencies = $activeDependencies | Select-Object -Unique
    
    $critical = "Microsoft.VCLibs|Microsoft.NET.Native|Microsoft.UI.Xaml|Microsoft.WinJS|Microsoft.Services.Store|Microsoft.WindowsAppRuntime|Microsoft.AIFabric|Microsoft.Windows.AugLoop"
    $frameworks = $allPackages | Where-Object { $_.IsFramework -eq $true -and $_.Name -notmatch $critical }
    
    $foundCount = 0
    foreach ($fw in $frameworks) { 
        if ($fw.PackageFullName -notin $activeDependencies) { 
            Write-GUI "  [!] Orphaned framework detected: $($fw.Name)"
            $foundCount++
        } 
    }
    
    $provisioned = Get-AppxProvisionedPackage -Online
    foreach ($prov in $provisioned) { 
        if (-not ($allPackages | Where-Object { $_.Name -eq $prov.DisplayName })) { 
            Write-GUI "  [!] Orphaned provisioned base detected: $($prov.DisplayName)"
            $foundCount++
        } 
    } 
    
    if ($foundCount -eq 0) { Write-GUI "[OK] System clean. No orphaned frameworks to remove." }
    else { Write-GUI "-> STATUS: $foundCount obsolete packages ready for cleanup." }
}

function Audit-StartMenu {
    Write-GUI "--- AUDIT: Start Menu Pins Database ---"
    $smPath = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin"
    if (Test-Path $smPath) {
        $sz = (Get-Item $smPath).Length
        Write-GUI "  [!] Menu layout database found ($([math]::Round($sz / 1KB, 2)) KB)."
        Write-GUI "  -> Action will wipe this database to unpin all items and provide a clean slate."
    } else {
        Write-GUI "  [OK] Start Menu database is fresh/empty."
    }
}