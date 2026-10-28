# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z3_REGISTRY.PS1 - REGISTRY ENGINE MODULE (v3.0.0)
# Z3_Registry: Main registry engine (Invoke-ApplyRegistry). Modulates UI (classic taskbar, Start menu), disables telemetry and data collection, optimizes background services (Edge, Defender), applies gaming tweaks (MMCSS, MPO, Flip Model, disabling VBS/HVCI, GameDVR), enforces Dual-Layer SRP+IFEO execution locks, and disables mouse acceleration.
# ==========================================

# ------------------------------------------
# Z3: REGISTRY AUDIT ENGINE (HANDLE-CACHED)
# ------------------------------------------
function Invoke-RegistryAudit {
    param([array]$Rules)
    
    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $keyCache = @{}

    try {
        foreach ($rule in $Rules) {
            $isDetected   = $true
            $currentValue = $null
            $valueExists  = $false
            $regPath      = $rule.Path

            if (-not $keyCache.ContainsKey($regPath)) {
                $keyCache[$regPath] = if (Test-Path -LiteralPath $regPath) {
                    Get-Item -LiteralPath $regPath -ErrorAction SilentlyContinue
                } else {
                    $null
                }
            }

            $regKey = $keyCache[$regPath]
            if ($null -ne $regKey) {
                $lookupName = if ($rule.Name -eq "" -or $rule.Name -eq "(Default)") { "" } else { $rule.Name }
                $rawVal = $regKey.GetValue($lookupName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                
                # Distinguishes (value not set) [$null] from an initialized empty string [""]
                if ($null -ne $rawVal) {
                    $currentValue = $rawVal
                    $valueExists  = $true
                }
            }
            
            if ($rule.ContainsKey("ValidValues")) {
                if ($valueExists -and ($rule.ValidValues -contains $currentValue)) { 
                    $isDetected = $false 
                }
            } elseif ($rule.ContainsKey("MatchRegex")) {
                if ($valueExists -and ([string]$currentValue -match $rule.MatchRegex)) {
                    $isDetected = $false
                }
            } else {
                if ($valueExists -and ([string]$currentValue -eq [string]$rule.Expected)) { 
                    $isDetected = $false 
                }
            }

            $results.Add([PSCustomObject]@{
                UIDisplayName = $rule.UIDisplayName
                IsDetected    = $isDetected
                ActionData    = $rule
            })
        }
    } finally {
        foreach ($k in $keyCache.Values) {
            if ($null -ne $k -and $k -is [System.IDisposable]) { $k.Dispose() }
        }
    }

    return @($results)
}

# ------------------------------------------
# Z3: REGISTRY AUDITS
# ------------------------------------------
function Get-RegState_Taskbar {
    $rules = @(
        @{ UIDisplayName = "Taskbar: Align to Left (Disables Windows 11 center alignment)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Show Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Search Box (Saves space)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Expected = 0; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Disable Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Taskbar: Hide Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; Expected = 1; Default = 0; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Taskbar: Hide Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; Expected = 3; Default = 1; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Taskbar: Enable 'End Task' on right-click (Dev feature)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Enforce Classic Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Web Search (Forces local-only, faster search)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Expected = 1; Default = 0; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Start Menu: Hide Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Expected = 1; Default = 0; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Start Menu: Disable Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Search Highlights (Bing bloat)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableSearchBoxSearchHighlights"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Start Menu: Disable Tailored Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowTailoredSearch"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Default = 1; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Toast Notifications (Flyouts)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "ToastEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Focus Assist (Global)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"; Name = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Push Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoCloudApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Toast Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoToastApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Bing Web Results (Keeps local queries private)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Expected = 1; Default = 0; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Connected Cloud Search Services"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Location Tracking in Search"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchToUseLocation"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Force Local-Only UI (Disable Bing Search UI)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Search: Disable Search Highlights (Dynamic Web Content)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableDynamicContentInWSB"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Explorer {
    $rules = @(
        @{ UIDisplayName = "Explorer: Open to 'This PC' instead of Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show hidden files and folders"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; Expected = 1; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show known file extensions (Security)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Run folder windows in a separate process (Stability)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "SeparateProcess"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Expand navigation pane to current folder"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "NavPaneExpandToCurrentFolder"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Hide Cloud Files in Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = "ShowCloudFilesInQuickAccess"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Context Menu: Restore Classic Win10 Style"; Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ""; Expected = ""; Default = "DELETE_KEY"; Type = "String" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon on Desktop"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Desktop: Show 'This PC' Icon (Classic Start)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (64-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (32-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Reduce Menu Show Delay from 400ms to 50ms"; Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; Expected = "50"; Default = "400"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Annoyances {
    $rules = @(
        @{ UIDisplayName = "Power: Disable Modern Standby S0 (Force Hardware S3 Sleep)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"; Name = "PlatformAoAcOverride"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable AutoPlay for all drives"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255; Default = 91; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Autoplay Handlers"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"; Name = "DisableAutoplay"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Accessibility: Disable Sticky Keys prompt (Shift x5)"; Path = "HKCU:\Control Panel\Accessibility\StickyKeys"; Name = "Flags"; Expected = "506"; Default = "510"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Filter Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"; Name = "Flags"; Expected = "122"; Default = "126"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Toggle Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\ToggleKeys"; Name = "Flags"; Expected = "58"; Default = "62"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Privacy {
    $rules = @()
    $rules += @{ UIDisplayName = "Privacy: Suppress UX Experience Reporting (Telemetry)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\ExperienceReporting"; Name = "SuppressExperienceReporting"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Block OS Telemetry & Data Collection"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Expected = 0; Default = 3; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable App Advertising ID"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Timeline & Activity History tracking"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Tailored Experiences"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Cloud Speech Recognition"; Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Restrict Implicit Ink/Text Collection"; Path = "HKCU:\Software\Microsoft\InputPersonalization"; Name = "RestrictImplicitInkCollection"; Expected = 1; Default = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Background Apps: Block UWP apps from running globally"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Expected = 1; Default = 0; Type = "DWord" }
    
    $uwpBlocks = @("LetAppsRunInBackground", "LetAppsAccessSync", "LetAppsAccessIdentity", "LetAppsAccessBluetooth", "LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo")
    foreach ($app in $uwpBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" } }
    
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessCamera"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessCamera"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessMicrophone"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessMicrophone"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" }
    
    $rules += @{ UIDisplayName = "Edge: Disable Startup Boost (Background Process)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Edge: Disable Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Defender: Prevent automatic sample submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; Expected = 2; Default = 1; Type = "DWord" }
    
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rules += @{ UIDisplayName = "Junk Blocker: Disable Content Delivery ($k)"; Path = $cdm; Name = $k; Expected = 0; Default = 1; Type = "DWord" } }
    
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_SystemBoot {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -Property TotalPhysicalMemory -ErrorAction SilentlyContinue
    $ramKB = if ($null -ne $cs -and $cs.TotalPhysicalMemory -gt 0) {
        [int][math]::Min([int]::MaxValue, [math]::Round($cs.TotalPhysicalMemory / 1KB))
    } else {
        16777216
    }

    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Disable Explorer Startup Delay (Instant Desktop Load)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name = "StartupDelayInMSec"; Expected = 0; Default = "DELETE_KEY"; Type = "DWord" }
        @{ UIDisplayName = "Kernel: Consolidate SvcHost Processes (Dynamic RAM Threshold)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control"; Name = "SvcHostSplitThresholdInKB"; Expected = $ramKB; Default = 3670016; ValidValues = @($ramKB, ($ramKB + 1048576)); Type = "DWord" }
        @{ UIDisplayName = "Security: Block BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive Network Traffic Pre-Sign-In"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "PreventNetworkTrafficPreUserSignIn"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Remote Desktop (RDP) access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Disable Insider Preview Builds"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"; Name = "AllowBuildPreview"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Enable Verbose Status Messages"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "verbosestatus"; Expected = 1; Default = 0; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Mouse {
    $rules = @(
        @{ UIDisplayName = "Mouse: Disable 'Enhance pointer precision' (Raw Input)"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseSpeed"; Expected = "0"; Default = "1"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 1"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold1"; Expected = "0"; Default = "6"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 2"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold2"; Expected = "0"; Default = "10"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Gaming {
    $rules = @(
        @{ UIDisplayName = "Gaming: Disable Xbox GameDVR (Reduces stuttering)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Store Config"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Frame Rate Cap (VSync bypass)"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_CapFrameRate"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Optimize FullScreen Exclusive Behavior"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; Expected = 2; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Hardware Accelerated GPU Scheduling (HAGS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Expected = 2; Default = 1; ValidValues = @(2); Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable Multiplane Overlay (MPO - Fixes VRR/Flicker)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\Dwm"; Name = "OverlayTestMode"; Expected = 5; Default = "DELETE_VALUE"; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Windowed Game Optimizations (Flip Model)"; Path = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"; Name = "DirectXUserGlobalSettings"; Expected = "SwapEffectUpgradeEnable=1;"; Default = "DELETE_VALUE"; MatchRegex = "SwapEffectUpgradeEnable=1"; Type = "String" }
        @{ UIDisplayName = "Kernel: Disable Paging Executive (Keeps core system in RAM)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS: System Responsiveness (Allocate 100% CPU to Games)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; Expected = 0; Default = 20; Type = "DWord" }
        @{ UIDisplayName = "Network: Remove MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Expected = 4294967295; Default = 10; Type = "DWord" }
        @{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Default = "Medium"; Type = "String" }
        @{ UIDisplayName = "Security: Disable Virtualization Based Security (VBS)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Hypervisor-protected Code Integrity (HVCI)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

# ------------------------------------------
# Z3: SRP & IFEO (DUAL-LAYER EXECUTION LOCKS)
# ------------------------------------------
function Get-DeterministicSrpGuid {
    param([Parameter(Mandatory=$true)][string]$InputString)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($InputString.ToLowerInvariant()))
    $md5.Dispose()
    return "{" + ([guid]::new($hashBytes)).ToString().ToUpper() + "}"
}

function Get-RegState_SRP {
    $targets = @(
        @{ UIDisplayName = "SRP+IFEO Lock: Windows Widgets (Widgets.exe)"; TargetPath = "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.WebExperience*\Dashboard\Widgets.exe"; ExeName = "Widgets.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Compatibility Telemetry (CompatTelRunner.exe)"; TargetPath = "$env:windir\System32\CompatTelRunner.exe"; ExeName = "CompatTelRunner.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Hardware Telemetry (DeviceCensus.exe)"; TargetPath = "$env:windir\System32\DeviceCensus.exe"; ExeName = "DeviceCensus.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: GameBar Telemetry (GameBarPresenceWriter.exe)"; TargetPath = "$env:windir\System32\GameBarPresenceWriter.exe"; ExeName = "GameBarPresenceWriter.exe"; IsCustom = $false }
        @{ UIDisplayName = "SRP+IFEO Lock: Edge Background Updater (MicrosoftEdgeUpdate.exe)"; TargetPath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"; ExeName = "MicrosoftEdgeUpdate.exe"; IsCustom = $false }
    )
    
    $customKey = "HKLM:\SOFTWARE\WinUltix\SRP"
    if (Test-Path -LiteralPath $customKey) {
        $customEntries = Get-Item -LiteralPath $customKey -ErrorAction SilentlyContinue
        if ($customEntries) {
            foreach ($prop in $customEntries.Property) {
                $customPath = $customEntries.GetValue($prop, $null)
                if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                    $exeLeaf = [System.IO.Path]::GetFileName($customPath)
                    $targets += @{ UIDisplayName = "SRP+IFEO Lock (Custom): $prop"; TargetPath = $customPath; ExeName = $exeLeaf; IsCustom = $true }
                }
            }
            $customEntries.Dispose()
        }
    }

    $results  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    $srpBase  = "$srpRoot\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    $srpRootProps = Get-ItemProperty -LiteralPath $srpRoot -Name "DefaultLevel", "TransparentEnabled" -ErrorAction SilentlyContinue
    $saferMasterActive = ($null -ne $srpRootProps -and $srpRootProps.DefaultLevel -eq 262144 -and $srpRootProps.TransparentEnabled -eq 1)

    foreach ($target in $targets) {
        $guid = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey = "$srpBase\$guid"
        
        $srpRuleProps = Get-ItemProperty -LiteralPath $ruleKey -Name "SaferFlags", "ItemData" -ErrorAction SilentlyContinue
        $srpLocked = ($saferMasterActive -and $null -ne $srpRuleProps -and $srpRuleProps.SaferFlags -eq 0)

        $ifeoKey = "$ifeoBase\$($target.ExeName)"
        $ifeoLocked = $false

        if (Test-Path -LiteralPath $ifeoKey) {
            $ifeoProps = Get-ItemProperty -LiteralPath $ifeoKey -Name "Debugger", "UseFilter" -ErrorAction SilentlyContinue
            if ($target.IsCustom -and $target.TargetPath -notmatch '[\*\?]') {
                $filterSubKey = "$ifeoKey\$guid"
                $subProps = Get-ItemProperty -LiteralPath $filterSubKey -Name "Debugger", "FilterFullPath" -ErrorAction SilentlyContinue
                $ifeoLocked = (
                    ($null -ne $ifeoProps -and $ifeoProps.UseFilter -eq 1 -and $null -ne $subProps -and $subProps.Debugger -match "systray\.exe" -and $subProps.FilterFullPath -eq $target.TargetPath) -or
                    ($null -ne $ifeoProps -and $ifeoProps.Debugger -match "systray\.exe")
                )
            } else {
                $ifeoLocked = ($null -ne $ifeoProps -and $ifeoProps.Debugger -match "systray\.exe")
            }
        }

        $isDetected = -not ($srpLocked -and $ifeoLocked)
        
        $results.Add([PSCustomObject]@{
            UIDisplayName = $target.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $target
        })
    }
    return @($results)
}

function Invoke-ApplySRP {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No execution locks selected."; return }
    $current = 0

    $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
    $srpPaths = "$srpRoot\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $nullStub = "$env:SystemRoot\System32\systray.exe"
    
    if ($Operation -eq 'Apply') {
        if (-not (Test-Path -LiteralPath $srpRoot)) { New-Item -Path $srpRoot -Force | Out-Null }
        
        $srpSettings = @{
            "AuthenticodeEnabled" = 0
            "DefaultLevel"        = 262144
            "TransparentEnabled"  = 1
            "PolicyScope"         = 0
        }
        foreach ($kvp in $srpSettings.GetEnumerator()) {
            Set-ItemProperty -LiteralPath $srpRoot -Name $kvp.Key -Value $kvp.Value -Type DWord -Force
        }
        
        $exeTypes = [string[]]@("BAT","CMD","COM","EXE","HTA","LNK","MSI","OCX","PIF","REG","SCR","VBS","WSF")
        Set-ItemProperty -LiteralPath $srpRoot -Name "ExecutableTypes" -Value $exeTypes -Type MultiString -Force
        
        if (-not (Test-Path -LiteralPath "$srpRoot\0"))      { New-Item -Path "$srpRoot\0" -Force | Out-Null }
        if (-not (Test-Path -LiteralPath "$srpRoot\262144")) { New-Item -Path "$srpRoot\262144" -Force | Out-Null }
        if (-not (Test-Path -LiteralPath $srpPaths))         { New-Item -Path $srpPaths -Force | Out-Null }
    }

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Removing" }
    $policyChanged = $false

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 75)) }
        Write-GUI " -> $($actionVerb) Execution Lock: $($item.UIDisplayName)"
        
        $target       = $item.ActionData
        $guid         = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey      = "$srpPaths\$guid"
        $ifeoKey      = "$ifeoBase\$($target.ExeName)"
        $filterSubKey = "$ifeoKey\$guid"
        
        try {
            if ($Operation -eq 'Apply') {
                if (Test-Path -LiteralPath $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)) {
                        $existingData = (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($existingData -eq $target.TargetPath -and $subKey.PSChildName -ne $guid) {
                            Remove-Item -LiteralPath $subKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                New-Item -Path $ruleKey -Force | Out-Null
                Set-ItemProperty -LiteralPath $ruleKey -Name "Description" -Value "WinUltix SRP Lockdown" -Type String -Force
                Set-ItemProperty -LiteralPath $ruleKey -Name "ItemData" -Value $target.TargetPath -Type String -Force
                Set-ItemProperty -LiteralPath $ruleKey -Name "SaferFlags" -Value 0 -Type DWord -Force

                if (-not (Test-Path -LiteralPath $ifeoKey)) { New-Item -Path $ifeoKey -Force | Out-Null }

                if ($target.IsCustom -and $target.TargetPath -notmatch '[\*\?]') {
                    # Scoped kernel filter (FilterFullPath) so custom .exe blocks do not collide with other apps sharing the same filename
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Value 1 -Type DWord -Force
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                    if (-not (Test-Path -LiteralPath $filterSubKey)) { New-Item -Path $filterSubKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "FilterFullPath" -Value $target.TargetPath -Type String -Force
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "Debugger" -Value $nullStub -Type String -Force
                    Set-ItemProperty -LiteralPath $filterSubKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                } else {
                    # Global kernel image lock (intercepts wildcard paths such as WindowsApps\...\Widgets.exe across updates)
                    Remove-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -Value $nullStub -Type String -Force
                    Set-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                }
                
                $procName = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName)
                $activeProc = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($activeProc) { 
                    $activeProc | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-GUI "    [OK] Flushed active process ($procName) from memory."
                }
                $policyChanged = $true
            } else {
                if (Test-Path -LiteralPath $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)) {
                        $itemData = (Get-ItemProperty -LiteralPath $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($subKey.PSChildName -eq $guid -or $itemData -eq $target.TargetPath) {
                            Remove-Item -LiteralPath $subKey.PSPath -Force -Recurse -ErrorAction Stop
                            $policyChanged = $true
                        }
                    }
                }

                if (Test-Path -LiteralPath $ifeoKey) {
                    if (Test-Path -LiteralPath $filterSubKey) {
                        Remove-Item -LiteralPath $filterSubKey -Recurse -Force -ErrorAction SilentlyContinue
                        $policyChanged = $true
                    }

                    $isManaged = (Get-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -ErrorAction SilentlyContinue).WinUltixManaged
                    $dbgVal    = (Get-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
                    if ($isManaged -eq 1 -or $dbgVal -match "systray\.exe") {
                        if (-not $target.IsCustom -or $dbgVal -match "systray\.exe") {
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "Debugger" -Force -ErrorAction SilentlyContinue
                        }
                        $remainingSubKeys = @(Get-ChildItem -LiteralPath $ifeoKey -ErrorAction SilentlyContinue)
                        if ($remainingSubKeys.Count -eq 0) {
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "UseFilter" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -LiteralPath $ifeoKey -Name "WinUltixManaged" -Force -ErrorAction SilentlyContinue
                        }
                        $remainingProps = (Get-Item -LiteralPath $ifeoKey -ErrorAction SilentlyContinue).Property
                        if ($remainingSubKeys.Count -eq 0 -and (-not $remainingProps -or $remainingProps.Count -eq 0)) {
                            Remove-Item -LiteralPath $ifeoKey -Force -ErrorAction SilentlyContinue
                        }
                        $policyChanged = $true
                    }
                }
                Write-GUI "    [OK] SRP & IFEO restriction rules purged from registry."
            }
        } catch { Write-GUI "    [!] Failed to modify execution lock: $($_.Exception.Message)" }
    }

    if ($Operation -eq 'Revert' -and (Test-Path -LiteralPath $srpPaths)) {
        $remainingSrp = @(Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)
        if ($remainingSrp.Count -eq 0) {
            Remove-Item -LiteralPath $srpRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    if ($policyChanged) {
        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
            $UltixSync.Logs.Enqueue(" -> Refreshing Safer API policy tokens (gpupdate.exe /force in background)...")
            $UltixSync.Progress = 85

            $gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
            $gpProc.WaitForExit()
            $exitCode = $gpProc.ExitCode
            $gpProc.Dispose()

            $UltixSync.Progress = 100
            return $exitCode
        } -OnComplete {
            param($exitCode)
            Update-Progress 0
            Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated (ExitCode: $exitCode).`n"
        }
    } else {
        Update-Progress 0
        Write-GUI " -> Execution lock operation completed ($Operation).`n"
    }
}

# ------------------------------------------
# Z3: REGISTRY ENGINE
# ------------------------------------------
function Invoke-ApplyRegistry {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply'
    )
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No tweaks selected."; return }
    $current = 0

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Reverting" }

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
        $reg = $item.ActionData
        
        $targetValue = if ($Operation -eq 'Apply') { $reg.Expected } else { $reg.Default }

        if ($null -eq $targetValue -and $Operation -eq 'Revert') {
            Write-GUI "    [!] Missing 'Default' property in array definition. Skipping."
            continue
        }

        try {
            if ($targetValue -eq 'DELETE_KEY') {
                if (Test-Path -LiteralPath $reg.Path) { 
                    Remove-Item -LiteralPath $reg.Path -Recurse -Force -ErrorAction Stop | Out-Null 
                    $parentKey = Split-Path -Path $reg.Path -Parent
                    if ($parentKey -match "\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2\}$" -and (Test-Path -LiteralPath $parentKey)) {
                        Remove-Item -LiteralPath $parentKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                continue
            }

            if ($targetValue -eq 'DELETE_VALUE') {
                if (Test-Path -LiteralPath $reg.Path) {
                    if ($reg.Name -eq "DirectXUserGlobalSettings") {
                        $existingDx = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
                        $cleanedDx  = ($existingDx -replace "SwapEffectUpgradeEnable=\d+;?", "").Trim()
                        if ([string]::IsNullOrWhiteSpace($cleanedDx)) {
                            Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Force -ErrorAction SilentlyContinue | Out-Null
                        } else {
                            Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $cleanedDx -Type String -Force -ErrorAction Stop | Out-Null
                        }
                    } else {
                        Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Force -ErrorAction Stop | Out-Null
                    }
                }
                continue
            }

            if (-not (Test-Path -LiteralPath $reg.Path)) { New-Item -Path $reg.Path -Force -ErrorAction Stop | Out-Null }
            
            if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
                # Explicitly write empty or target string into unnamed (Default) value
                Set-Item -LiteralPath $reg.Path -Value ([string]$targetValue) -Force -ErrorAction Stop | Out-Null
            } elseif ($reg.Name -eq "DirectXUserGlobalSettings" -and $Operation -eq 'Apply') {
                $existingDx = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
                if ([string]::IsNullOrWhiteSpace($existingDx)) {
                    $newDx = "SwapEffectUpgradeEnable=1;"
                } elseif ($existingDx -match "SwapEffectUpgradeEnable=\d+") {
                    $newDx = $existingDx -replace "SwapEffectUpgradeEnable=\d+", "SwapEffectUpgradeEnable=1"
                } else {
                    $sep   = if ($existingDx.EndsWith(";")) { "" } else { ";" }
                    $newDx = "$existingDx${sep}SwapEffectUpgradeEnable=1;"
                }
                Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $newDx -Type String -Force -ErrorAction Stop | Out-Null
            } else { 
                Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $targetValue -Type $reg.Type -Force -ErrorAction Stop | Out-Null 
            }
        } catch { Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
}

# ------------------------------------------
# Z3: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z3UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabReg = New-Object System.Windows.Forms.TabPage
    $tabReg.Text = "Registry"
    $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $invokeRegCategory = {
        param(
            [string]$ScannerFn,
            [string]$CategoryName,
            [string]$ModalTitle,
            [string]$AuditHeader,
            [switch]$RefreshShell,
            [switch]$AuditOnly
        )
        $auditData = & $ScannerFn
        if ($AuditOnly) {
            Write-GUI "--- AUDIT: $AuditHeader ---"
            $detected = @($auditData | Where-Object { $_.IsDetected })
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] Optimized."
            }
            Write-GUI ""
            return
        }

        $modalOutput = Show-ActionModal -Title $ModalTitle -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) {
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName $CategoryName -Operation $modalOutput.Action
            if ($RefreshShell) {
                Update-ShellEnvironment -ModifiedItems $modalOutput.Items
            }
            Write-GUI ""
        }
    }.GetNewClosure()

    # 1. Taskbar & Start Menu
    [void](New-UltixActionRow -Parent $tabReg -Y 20 `
        -Text "Taskbar and Start Menu" `
        -Description "Aligns the taskbar to the left, kills Bing assistants, and hides widgets." `
        -AuditDescription "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, and Bing locks." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -AuditOnly }.GetNewClosure()))

    # 2. File Explorer
    [void](New-UltixActionRow -Parent $tabReg -Y 70 `
        -Text "File Explorer and Context Menu" `
        -Description "Restores the full context menu, launches folder processes in isolation." `
        -AuditDescription "AUDIT: Verifies the presence of classic context menu and Explorer performance flags." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -AuditOnly }.GetNewClosure()))

    # 3. OS Annoyances
    [void](New-UltixActionRow -Parent $tabReg -Y 120 `
        -Text "OS Annoyances (AutoRun / Sticky Keys)" `
        -Description "Deactivates AutoPlay and Accessibility shortcuts (Sticky Keys)." `
        -AuditDescription "AUDIT: Verifies AutoPlay and Sticky Keys blockade." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" -AuditOnly }.GetNewClosure()))

    # 4. Privacy
    [void](New-UltixActionRow -Parent $tabReg -Y 170 `
        -Text "Privacy and Background Apps (AppPrivacy)" `
        -Description "Blocks telemetry, background UWP apps execution, and limits Edge processes." `
        -AuditDescription "AUDIT: Checks the registry for telemetry, Edge, and background execution blocks." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy Policies" "Privacy Policies" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy Policies" "Privacy Policies" -AuditOnly }.GetNewClosure()))

    # 5. Boot & Security
    [void](New-UltixActionRow -Parent $tabReg -Y 220 `
        -Text "Boot and WPBT (BIOS/UEFI Block)" `
        -Description "Disables Fast Boot, OneDrive, RDP, and blocks software injections from BIOS/UEFI (WPBT)." `
        -AuditDescription "AUDIT: Verifies kernel hibernation logic (Fast Boot), WPBT, and RDP." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Security" "Boot & Security" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Security" "Boot & Security" -AuditOnly }.GetNewClosure()))

    # 6. Mouse
    [void](New-UltixActionRow -Parent $tabReg -Y 270 `
        -Text "Hard Mouse Acceleration Disable (Raw Input)" `
        -MainRGB @(60, 100, 150) -AuditRGB @(60, 100, 150) `
        -Description "Pure 1:1 input. Hard-disables 'Enhance pointer precision' to eliminate system smoothing." `
        -AuditDescription "AUDIT: Scans registry keys for system pointer acceleration." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" -AuditOnly }.GetNewClosure()))

    # 7. Gaming
    [void](New-UltixActionRow -Parent $tabReg -Y 320 `
        -Text "Hardware and Gaming (Extreme)" `
        -MainRGB @(150, 60, 60) -AuditRGB @(150, 60, 60) `
        -Description "Enforces MMCSS priorities, disables GameDVR, enabling maximum hardware performance." `
        -AuditDescription "AUDIT: Verifies MMCSS limits, CPU priority, and HAGS acceleration." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" -AuditOnly }.GetNewClosure()))

    # 8. SRP Execution Locks (Main + [+], [-], [?])
    $btnRegSRP = New-UltixButton -Parent $tabReg -X 15 -Y 420 -Width 240 -Height 40 -RGB @(60, 60, 60) `
        -Text "Execution Blocks (SRP/Legacy Pro)" `
        -Description "NATIVE KERNEL LOCK (Pro/Enterprise Only): Generates legacy Software Restriction Policies to block execution. May not work on Home editions or future OS builds."

    $btnAddSRP = New-UltixButton -Parent $tabReg -X 260 -Y 420 -Width 40 -Height 40 -RGB @(60, 100, 60) `
        -Text "+" `
        -Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP block list." `
        -OnClick {
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = "Executables (*.exe)|*.exe"
            $dlg.Title = "Select Executable to Block (SRP)"
            $dlg.InitialDirectory = "$env:ProgramFiles"
            try {
                if ($dlg.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
                    $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
                    if (-not (Test-Path -LiteralPath $regKey)) { New-Item -Path $regKey -Force | Out-Null }
                    $exeName = [System.IO.Path]::GetFileName($dlg.FileName)
                    Set-ItemProperty -LiteralPath $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
                    Write-GUI " -> Added custom SRP target: $exeName"
                }
            } finally {
                $dlg.Dispose()
            }
        }

    $btnClrSRP = New-UltixButton -Parent $tabReg -X 305 -Y 420 -Width 40 -Height 40 -RGB @(100, 60, 60) `
        -Text "-" `
        -Description "CLEAR CUSTOM TARGETS: Removes all custom executables from the WinUltix tracking list (does not unlock them if currently applied)." `
        -OnClick {
            $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            if (Test-Path -LiteralPath $regKey) {
                Remove-Item -LiteralPath $regKey -Force -Recurse | Out-Null
                Write-GUI " -> Custom SRP tracking database purged."
            } else {
                Write-GUI " -> Custom SRP roster is already empty."
            }
        }

    $btnAudSRP = New-UltixButton -Parent $tabReg -X 350 -Y 420 -Width 40 -Height 40 -RGB @(80, 80, 80) `
        -Text "?" `
        -Description "AUDIT: Verifies active Software Restriction Policies." `
        -OnClick {
            Write-GUI "--- AUDIT: Software Restriction Policies ---"
            $state = Get-RegState_SRP
            $detected = @($state | Where-Object { $_.IsDetected })
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] To Block: $($d.UIDisplayName)" }
            } else {
                Write-GUI "  [OK] Optimized."
            }
            Write-GUI ""
        }

    $btnRegSRP.Add_Click({
        $auditData = Get-RegState_SRP
        $modalOutput = Show-ActionModal -Title "WinUltix - SRP & IFEO Lockdown" -Description "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." -AuditResults $auditData -EnableRevert
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) {
            Invoke-ApplySRP -SelectedItems $modalOutput.Items -Operation $modalOutput.Action -ControlsToDisable @($btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP)
        }
    }.GetNewClosure())

    $TabControl.Controls.Add($tabReg)
}