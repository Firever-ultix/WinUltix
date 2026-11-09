# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z3_REGISTRY.PS1 - REGISTRY ENGINE MODULE (v3.14)
# Z3_Registry: OS Tweaks, Taskbar (with UCPD.sys bypass), native 3-icon Start Menu compiler (with 26H2 Classic List view), File Explorer, Modern Standby S0, 7-Point Power & Display Optimizer, 1:1 Raw Mouse Input, and Extreme Gaming Registry.
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
                    # Convert negative signed Int32 REG_DWORD reads (e.g. -1 for 0xFFFFFFFF) to unsigned UInt32
                    if ($rule.Type -eq "DWord" -and $rawVal -is [int] -and $rawVal -lt 0) {
                        $currentValue = [BitConverter]::ToUInt32([BitConverter]::GetBytes($rawVal), 0)
                    } else {
                        $currentValue = $rawVal
                    }
                    $valueExists = $true
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

            # Fallback check for UCPD-protected keys (e.g., DisableWidgetsBoard on Win11 25H2/26H2)
            if ($isDetected -and $rule.ContainsKey("AltName") -and $null -ne $regKey) {
                $altRaw = $regKey.GetValue($rule.AltName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($null -ne $altRaw -and ([string]$altRaw -eq [string]$rule.AltExpected)) {
                    $isDetected = $false
                }
            }

            $results.Add([PSCustomObject]@{
                UIDisplayName = $rule.UIDisplayName
                IsDetected    = $isDetected
                OptIn         = [bool]$rule.OptIn
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
        @{ UIDisplayName = "Start Menu: Force Classic Alphabetical List (Disables 26H2 Category Tiles)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"; Name = "AllAppsViewMode"; Expected = 2; Default = 0; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Start Menu: Hide Recently Opened Files & Jump Lists"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_TrackDocs"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Hide Recently Added & Most Used Apps"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_TrackProgs"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Search Highlights (Bing bloat)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableSearchBoxSearchHighlights"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Start Menu: Disable Tailored Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowTailoredSearch"; Expected = 0; Default = 1; Type = "DWord"; RestartSearch = $true }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Default = 1; AltName = "DisableWidgetsBoard"; AltExpected = 1; Type = "DWord"; RestartShell = $true }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Toast Notifications (Flyouts)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "ToastEnabled"; Expected = 0; Default = 1; Type = "DWord"; OptIn = $true }
        @{ UIDisplayName = "UI: Disable Focus Assist (Global)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"; Name = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"; Expected = 0; Default = 1; Type = "DWord"; OptIn = $true }
        @{ UIDisplayName = "UI: Disable App Push Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoCloudApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord"; OptIn = $true }
        @{ UIDisplayName = "UI: Disable App Toast Notifications (Policy)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoToastApplicationNotification"; Expected = 1; Default = "DELETE_VALUE"; Type = "DWord"; OptIn = $true }
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
        @{ UIDisplayName = "Power: Disable Modern Standby S0 (Force Hardware S3 Sleep - Desktop/Supported BIOS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"; Name = "PlatformAoAcOverride"; Expected = 0; Default = 1; Type = "DWord"; OptIn = $true }
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
    $rules += @{ UIDisplayName = "Background Apps: Block UWP apps from running globally (Optional)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Expected = 1; Default = 0; Type = "DWord"; OptIn = $true }
    
    $uwpBlocks = @("LetAppsRunInBackground", "LetAppsAccessSync", "LetAppsActivateWithVoice", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar")
    foreach ($app in $uwpBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord" } }

    $uwpOptInBlocks = @("LetAppsAccessIdentity", "LetAppsAccessAccountInfo", "LetAppsAccessBluetooth", "LetAppsAccessRadios", "LetAppsAccessNotifications")
    foreach ($optApp in $uwpOptInBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $optApp (Optional - May affect Xbox/BT apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $optApp; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord"; OptIn = $true } }

    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessCamera (Warning: Blocks Webcams globally)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessCamera"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord"; OptIn = $true }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessMicrophone (Warning: Blocks Mics globally)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessMicrophone"; Expected = 2; Default = "DELETE_VALUE"; Type = "DWord"; OptIn = $true }

    $rules += @{ UIDisplayName = "Edge: Disable Startup Boost (Background Process)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Edge: Disable Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Expected = 0; Default = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Defender: Prevent automatic sample submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; Expected = 2; Default = 1; Type = "DWord" }
    
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rules += @{ UIDisplayName = "Junk Blocker: Disable Content Delivery ($k)"; Path = $cdm; Name = $k; Expected = 0; Default = 1; Type = "DWord" } }
    
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_SystemBoot {
    $ramKB = [WinUltix.NativeMethods]::GetTotalPhysicalMemoryKB()

    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Boot: Disable Explorer Startup Delay (Instant Desktop Load)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name = "StartupDelayInMSec"; Expected = 0; Default = "DELETE_KEY"; Type = "DWord" }
        @{ UIDisplayName = "Kernel: Consolidate SvcHost Processes (Dynamic RAM Threshold)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control"; Name = "SvcHostSplitThresholdInKB"; Expected = $ramKB; Default = 3670016; ValidValues = @($ramKB, ($ramKB + 1048576)); Type = "DWord" }
        @{ UIDisplayName = "Security: Block BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive Network Traffic Pre-Sign-In"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "PreventNetworkTrafficPreUserSignIn"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Remote Desktop (RDP) access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; Expected = 1; Default = 0; Type = "DWord"; OptIn = $true }
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
        @{ UIDisplayName = "Network: Remove MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Expected = 4294967295; Default = 10; ValidValues = @(4294967295, -1); Type = "DWord" }
        @{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Default = 2; ValidValues = @(38, 40, 42, 22, 24); Type = "DWord" }
        @{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Default = "Medium"; Type = "String" }
        @{ UIDisplayName = "Security: Disable Virtualization Based Security (VBS)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"; Name = "EnableVirtualizationBasedSecurity"; Expected = 0; Default = 1; Type = "DWord"; OptIn = $true }
        @{ UIDisplayName = "Security: Disable Hypervisor-protected Code Integrity (HVCI)(Warning: Lowers memory latency but removes kernel-mode malware protection)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Default = 1; Type = "DWord"; OptIn = $true }
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
        @{ UIDisplayName = "SRP+IFEO Lock: Edge Background Updater - Blocks WinGet Edge/WebView2 updates (MicrosoftEdgeUpdate.exe)"; TargetPath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"; ExeName = "MicrosoftEdgeUpdate.exe"; IsCustom = $false; OptIn = $true }
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
            OptIn         = [bool]$target.OptIn
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
    
    if ($SelectedItems.Count -eq 0) {
        Write-GUI " -> No execution locks selected."
        return
    }

    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)

        $total   = $Items.Count
        $current = 0

        $srpRoot  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
        $srpPaths = "$srpRoot\0\Paths"
        $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
        $nullStub = "$env:SystemRoot\System32\systray.exe"
        
        if ($Op -eq 'Apply') {
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

        $actionVerb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Removing" }
        $policyChanged = $false

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 75)
                $UltixSync.Logs.Enqueue(" -> $($actionVerb) Execution Lock: $($item.UIDisplayName)")
            }
            
            $target       = $item.ActionData
            $guid         = Get-DeterministicSrpGuid -InputString $target.TargetPath
            $ruleKey      = "$srpPaths\$guid"
            $ifeoKey      = "$ifeoBase\$($target.ExeName)"
            $filterSubKey = "$ifeoKey\$guid"
            
            try {
                if ($Op -eq 'Apply') {
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
                        if ($null -ne $UltixSync) {
                            $UltixSync.Logs.Enqueue("    [OK] Flushed active process ($procName) from memory.")
                        }
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

                            $remainingProps = @()
                            $ifeoItem = Get-Item -LiteralPath $ifeoKey -ErrorAction SilentlyContinue
                            if ($null -ne $ifeoItem) {
                                try { $remainingProps = @($ifeoItem.Property) } finally { $ifeoItem.Dispose() }
                            }
                            if ($remainingSubKeys.Count -eq 0 -and $remainingProps.Count -eq 0) {
                                Remove-Item -LiteralPath $ifeoKey -Force -ErrorAction SilentlyContinue
                            }
                            $policyChanged = $true
                        }
                    }
                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [OK] SRP & IFEO restriction rules purged from registry.")
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Failed to modify execution lock: $($_.Exception.Message)")
                }
            }
        }

        if ($Op -eq 'Revert' -and (Test-Path -LiteralPath $srpPaths)) {
            $remainingSrp = @(Get-ChildItem -LiteralPath $srpPaths -ErrorAction SilentlyContinue)
            if ($remainingSrp.Count -eq 0) {
                Remove-Item -LiteralPath $srpRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $exitCode = $null
        if ($policyChanged) {
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue(" -> Refreshing Safer API policy tokens (gpupdate.exe /force in background)...")
                $UltixSync.Progress = 85
            }
            $gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
            $gpProc.WaitForExit()
            $exitCode = $gpProc.ExitCode
            $gpProc.Dispose()
        }

        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
        return [PSCustomObject]@{
            PolicyChanged = $policyChanged
            ExitCode      = $exitCode
            Operation     = $Op
        }
    } -OnComplete ({
        param($res)
        Update-Progress 0
        if ($null -ne $res -and $res.PolicyChanged) {
            Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated (ExitCode: $($res.ExitCode)).`n"
        } else {
            Write-GUI " -> Execution lock operation completed ($Operation).`n"
        }
    }.GetNewClosure())
}

# ------------------------------------------
# Z3: REGISTRY ENGINE (ASYNC RUNSPACE + RE-ENTRANCY SAFE)
# ------------------------------------------
function Invoke-ApplyRegistry {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$CategoryName,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @(),
        [switch]$RefreshShell
    )

    if ($SelectedItems.Count -eq 0) {
        Write-GUI " -> No tweaks selected."
        return
    }

    $doShellRefresh = $RefreshShell.IsPresent

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $CategoryName, $Operation) -ScriptBlock {
        param([array]$Items, [string]$CatName, [string]$Op)

        $total        = $Items.Count
        $current      = 0
        $touchedMouse = $false
        $actionVerb   = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> $($actionVerb): $($item.UIDisplayName)")
            } else {
                Update-Progress ([int](($current / $total) * 100))
                Write-GUI " -> $($actionVerb): $($item.UIDisplayName)"
            }

            $reg = $item.ActionData
            if ($reg.Path -eq "HKCU:\Control Panel\Mouse") {
                $touchedMouse = $true
            }

            $targetValue = if ($Op -eq 'Apply') { $reg.Expected } else { $reg.Default }
            if ($null -eq $targetValue -and $Op -eq 'Revert') {
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

                # Preserve custom optimized values (e.g., Z7 Quantum Scheduler presets in Win32PrioritySeparation)
                if ($Op -eq 'Apply' -and $reg.ContainsKey("ValidValues")) {
                    $curRaw = (Get-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -ErrorAction SilentlyContinue).$($reg.Name)
                    if ($null -ne $curRaw) {
                        $curNorm = if ($reg.Type -eq "DWord" -and $curRaw -is [int] -and $curRaw -lt 0) {
                            [BitConverter]::ToUInt32([BitConverter]::GetBytes($curRaw), 0)
                        } else {
                            $curRaw
                        }
                        if ($reg.ValidValues -contains $curNorm -or $reg.ValidValues -contains $curRaw) {
                            if ($reg.Name -eq "Win32PrioritySeparation" -and $curNorm -ne $reg.Expected) {
                                Write-GUI ("    [OK] Preserved active Quantum Scheduler preset (0x{0:X2} / {0} dec)." -f [int]$curNorm)
                            }
                            continue
                        }
                    }
                }

                # Sync 25H2/26H2 DisableWidgetsBoard policy alongside AllowNewsAndInterests
                if ($reg.ContainsKey("AltName")) {
                    if ($Op -eq 'Apply') {
                        Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                        Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
                        Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }

                if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
                    Set-Item -LiteralPath $reg.Path -Value ([string]$targetValue) -Force -ErrorAction Stop | Out-Null
                } elseif ($reg.Name -eq "DirectXUserGlobalSettings" -and $Op -eq 'Apply') {
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
                    $writeVal = $targetValue
                    if ($reg.Type -eq "DWord" -and $writeVal -is [long] -and $writeVal -gt [int]::MaxValue) {
                        $writeVal = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$writeVal), 0)
                    }
                    Set-ItemProperty -LiteralPath $reg.Path -Name $reg.Name -Value $writeVal -Type $reg.Type -Force -ErrorAction Stop | Out-Null
                }
            } catch {
                # Symmetric UCPD.sys kernel filter bypass for both Apply and Revert on Windows 11 24H2/25H2/26H2
                if ($reg.ContainsKey("AltName")) {
                    try {
                        if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UCPD") {
                            Set-ProtectedServiceStart -ServiceName "UCPD" -StartValue 4
                            Disable-ScheduledTask -TaskPath "\Microsoft\Windows\AppxDeploymentClient\" -TaskName "UCPD velocity" -ErrorAction SilentlyContinue | Out-Null
                        }

                        if ($Op -eq 'Apply') {
                            Set-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Value $reg.AltExpected -Type DWord -Force -ErrorAction Stop | Out-Null
                            Set-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue | Out-Null
                            Write-GUI "    [+] Bypassed UCPD.sys filter via $($reg.AltName)=1 & disarmed UCPD driver."
                        } else {
                            Remove-ItemProperty -LiteralPath $reg.Path -Name $reg.AltName -Force -ErrorAction SilentlyContinue | Out-Null
                            Remove-ItemProperty -LiteralPath $reg.Path -Name "DisableWidgetsOnLockScreen" -Force -ErrorAction SilentlyContinue | Out-Null
                            Write-GUI "    [+] Reverted $($reg.AltName) policy & disarmed UCPD filter (Reboot unlocks $($reg.Name))."
                        }
                    } catch {
                        Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
                    }
                } else {
                    Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)"
                }
            }
        }

        # Live win32kfull.sys mouse acceleration reload via user32!SystemParametersInfoW (SPI_SETMOUSE)
        if ($touchedMouse) {
            try {
                $mProps = Get-ItemProperty -LiteralPath "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1", "MouseThreshold2", "MouseSpeed" -ErrorAction SilentlyContinue
                $t1 = if ($null -ne $mProps -and $mProps.MouseThreshold1 -match '^\d+$') { [int]$mProps.MouseThreshold1 } else { 0 }
                $t2 = if ($null -ne $mProps -and $mProps.MouseThreshold2 -match '^\d+$') { [int]$mProps.MouseThreshold2 } else { 0 }
                $sp = if ($null -ne $mProps -and $mProps.MouseSpeed -match '^\d+$')      { [int]$mProps.MouseSpeed }      else { 0 }
                if ([WinUltix.NativeMethods]::ApplyLiveMouseParams($t1, $t2, $sp)) {
                    Write-GUI "    [OK] Live-reloaded win32kfull.sys pointer acceleration table (SPI_SETMOUSE: $t1/$t2/$sp)."
                }
            } catch { }
        }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
        if ($doShellRefresh) {
            Update-ShellEnvironment -ModifiedItems $SelectedItems
        }
        if ($null -eq $UltixSync) {
            Write-GUI ""
        }
    }.GetNewClosure())
}

# ------------------------------------------
# Z3: START MENU NATIVE COMPILATION & POWER/DISPLAY TUNER
# ------------------------------------------
function Get-StartMenuState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }
    $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    $isCleanActive = $false
    $sizeTag       = ""

    if ($null -ne $pkgDir) {
        $binFile   = Get-Item -Path (Join-Path $pkgDir.FullName "LocalState\start2.bin") -Force -ErrorAction SilentlyContinue
        $clearedSz = (Get-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -ErrorAction SilentlyContinue).StartMenuClearedSize
        $viewMode  = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "AllAppsViewMode" -ErrorAction SilentlyContinue).AllAppsViewMode
        if ($null -ne $binFile) {
            $szKB = [math]::Round($binFile.Length / 1KB, 1)
            $sizeTag = " [Current: $szKB KB]"
            if ($null -ne $clearedSz -and [math]::Abs($binFile.Length - $clearedSz) -le 512 -and $viewMode -eq 2) {
                $isCleanActive = $true
            }
        }
    }

    $bakExists = Test-Path -LiteralPath "$env:LOCALAPPDATA\WinUltix\start2_backup.bin"
    $bakTag    = if ($bakExists) { " | Backup: Ready" } else { "" }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @([PSCustomObject]@{
        UIDisplayName = "Start Menu: Compile Clean 3-Icon Layout (Edge, Settings, Explorer) + Classic List$sizeTag$bakTag"
        IsDetected    = (-not $isCleanActive)
        ActionData    = @{ Type = "StartMenuReset" }
    })
}

function Invoke-StartMenuAudit {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI "--- AUDIT: Start Menu Pins & Layout Mode (Background Thread) ---"
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $UltixSync.Progress = 35
        $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1

        if ($null -eq $pkgDir) {
            $UltixSync.Logs.Enqueue("  [OK] StartMenuExperienceHost package not found in current user profile.")
            $UltixSync.Progress = 100
            return
        }

        $localState = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
        $binFile    = Get-Item -Path (Join-Path $localState "start2.bin") -Force -ErrorAction SilentlyContinue
        $clearedSz  = (Get-ItemProperty -Path "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -ErrorAction SilentlyContinue).StartMenuClearedSize

        if ($null -ne $binFile) {
            $szKB = [math]::Round($binFile.Length / 1KB, 2)
            if ($null -ne $clearedSz -and [math]::Abs($binFile.Length - $clearedSz) -le 512) {
                $UltixSync.Logs.Enqueue("  [OK] Clean minimal layout active: start2.bin ($szKB KB - Edge, Settings, Explorer).")
            } else {
                $UltixSync.Logs.Enqueue("  [!] Active layout database detected: $($binFile.Name) ($szKB KB).")
            }
        } else {
            $UltixSync.Logs.Enqueue("  [OK] Start Menu binary database is not present.")
        }

        $UltixSync.Progress = 70
        $viewMode  = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "AllAppsViewMode" -ErrorAction SilentlyContinue).AllAppsViewMode
        $trackDocs = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -ErrorAction SilentlyContinue).Start_TrackDocs
        if ($viewMode -eq 2 -and $trackDocs -eq 0) {
            $UltixSync.Logs.Enqueue("  [OK] All Apps View: Classic Alphabetical List (AllAppsViewMode=2) & Recent Files hidden.")
        } else {
            $UltixSync.Logs.Enqueue("  [!] All Apps View / Recent Files not yet locked to Classic List (Current ViewMode: $(if($null -ne $viewMode){$viewMode}else{'0 - Category Tiles'})).")
        }

        $provGuid   = "B5292708-1619-419B-9923-E5D9F3925E71"
        $policyPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
        $mdmLock    = (Get-ItemProperty -LiteralPath $policyPath -Name "ConfigureStartPins_ProviderSet" -ErrorAction SilentlyContinue).ConfigureStartPins_ProviderSet
        $hasProvKey = (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") -or
                      (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Enrollments\$provGuid")

        if ($mdmLock -eq 1 -or $hasProvKey) {
            $UltixSync.Logs.Enqueue("  [!] Residual MDM Start Menu provider/lock detected in PolicyManager ($provGuid).")
        } else {
            $UltixSync.Logs.Enqueue("  [OK] No residual MDM Start Menu locks or orphaned provider keys found.")
        }
        $UltixSync.Progress = 100
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }.GetNewClosure())
}

function Clear-StartMenu {
    param(
        [array]$SelectedItems = @(),
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    if ($Operation -eq 'Revert') {
        Write-GUI " -> Restoring original Start Menu layout from backup (start2_backup.bin)..."
        Update-Progress 15

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
            $pkgDir = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -eq $pkgDir) {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] StartMenuExperienceHost package directory not found.") }
                return
            }

            $startStatePath = Join-Path -Path $pkgDir.FullName -ChildPath "LocalState"
            $origBin        = Join-Path $startStatePath "start2.bin"
            $bakBin         = "$env:LOCALAPPDATA\WinUltix\start2_backup.bin"

            $UltixSync.Progress = 40
            Stop-Process -Name "StartMenuExperienceHost", "ShellExperienceHost", "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 350

            if (Test-Path -LiteralPath $bakBin) {
                Copy-Item -LiteralPath $bakBin -Destination $origBin -Force -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue("    [OK] Restored original start2.bin from $bakBin.")
            } else {
                $UltixSync.Logs.Enqueue("    [*] No start2_backup.bin found in %LOCALAPPDATA%\WinUltix; reverting registry view flags only.")
            }

            Remove-ItemProperty -LiteralPath "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "AllAppsViewMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "ShowRecentList", "ShowFrequentList" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_IrisRecommendations", "Start_AccountNotifications" -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "HideRecommendedSection" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "NoRecentDocsHistory" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            $defaultJsonPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.json"
            if (Test-Path -LiteralPath $defaultJsonPath) {
                Remove-Item -LiteralPath $defaultJsonPath -Force -ErrorAction SilentlyContinue
            }

            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
            $UltixSync.Progress = 100
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Start Menu layout and view settings restored.`n"
        }.GetNewClosure())
        return
    }

    Write-GUI " -> Initializing deterministic Start Menu reset (3-Icon + Classic List + No Recent Files)..."
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
        $policyUserPath   = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PolicyManager\current\user\Start"

        # Minimal 3-icon layout: Microsoft Edge, Windows Settings, File Explorer
        $cleanPinsJson = '{"pinnedList":[{"desktopAppId":"MSEdge"},{"packagedAppId":"windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel"},{"desktopAppId":"Microsoft.Windows.Explorer"}]}'

        $createdEnrollment = $false

        try {
            # Stage 1: ContentDeliveryManager lockdown + Disable Recent Files & Force Classic List View
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 15
                $UltixSync.Logs.Enqueue(" -> [1/7] Disabling ContentDeliveryManager, Recent Files & forcing Classic Alphabetical List...")
            }
            $cdmPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            if (Test-Path -LiteralPath $cdmPath) {
                foreach ($cdmName in @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "SubscribedContentEnabled")) {
                    Set-ItemProperty -LiteralPath $cdmPath -Name $cdmName -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                }
                if (Test-Path -LiteralPath "$cdmPath\SuggestedApps") {
                    Remove-Item -LiteralPath "$cdmPath\SuggestedApps" -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $advPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            if (Test-Path -LiteralPath $advPath) {
                Set-ItemProperty -LiteralPath $advPath -Name "Start_TrackDocs" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $advPath -Name "Start_TrackProgs" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $advPath -Name "Start_IrisRecommendations" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $advPath -Name "Start_AccountNotifications" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -LiteralPath $advPath -Name "Start_Layout" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }

            $expPolPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
            if (-not (Test-Path -LiteralPath $expPolPath)) { New-Item -Path $expPolPath -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -LiteralPath $expPolPath -Name "HideRecommendedSection" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath $expPolPath -Name "NoRecentDocsHistory" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

            # Purge Recent JumpList AutomaticDestinations & Recent shortcuts
            $recentDir = "$env:APPDATA\Microsoft\Windows\Recent"
            if (Test-Path -LiteralPath $recentDir) {
                Get-ChildItem -LiteralPath $recentDir -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath "$recentDir\AutomaticDestinations") {
                    Get-ChildItem -LiteralPath "$recentDir\AutomaticDestinations" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                }
            }

            # Stage 2: Temporary MDM Provider Registration
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 30
                $UltixSync.Logs.Enqueue(" -> [2/7] Injecting temporary MDM PolicyManager provider context...")
            }
            if (-not (Test-Path -LiteralPath $enrollmentPath)) {
                New-Item -Path $enrollmentPath -Force -ErrorAction Stop | Out-Null
                $createdEnrollment = $true
            }
            Set-ItemProperty -LiteralPath $enrollmentPath -Name "EnrollmentState" -Value 1 -Type DWord -Force
            Set-ItemProperty -LiteralPath $enrollmentPath -Name "EnrollmentType" -Value 6 -Type DWord -Force
            Set-ItemProperty -LiteralPath $enrollmentPath -Name "IsFederated" -Value 0 -Type DWord -Force
            Set-ItemProperty -LiteralPath $enrollmentPath -Name "ProviderID" -Value "MS DM Server" -Type String -Force

            if (-not (Test-Path -LiteralPath $providerPath)) {
                New-Item -Path $providerPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -LiteralPath $providerPath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -LiteralPath $providerPath -Name "ConfigureStartPins_LastWrite" -Value 1 -Type DWord -Force

            if (-not (Test-Path -LiteralPath $policyDevicePath)) {
                New-Item -Path $policyDevicePath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins" -Value $cleanPinsJson -Type String -Force
            Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins_ProviderSet" -Value 1 -Type DWord -Force
            Set-ItemProperty -LiteralPath $policyDevicePath -Name "ConfigureStartPins_WinningProvider" -Value $provGuid -Type String -Force

            # Stage 3: Purge CloudStore caches & lock AllAppsViewMode = 2 (Classic Alphabetical List)
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 45
                $UltixSync.Logs.Enqueue(" -> [3/7] Purging CloudStore tile grid and enforcing AllAppsViewMode=2 (List View)...")
            }
            $cloudStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current"
            if (Test-Path -LiteralPath $cloudStoreRoot) {
                Get-ChildItem -LiteralPath $cloudStoreRoot -ErrorAction SilentlyContinue | Where-Object {
                    $_.PSChildName -match "start\.tilegrid|unifiedtile|start\.allapps|start\.properties"
                } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            $startRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start"
            if (Test-Path -LiteralPath $startRegPath) {
                Remove-Item -LiteralPath $startRegPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -Path $startRegPath -Force -ErrorAction SilentlyContinue | Out-Null
            # 2 = Classic Alphabetical List View (replaces Windows 11 25H2/26H2 Category Tiles = 0)
            Set-ItemProperty -LiteralPath $startRegPath -Name "AllAppsViewMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath $startRegPath -Name "ShowRecentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -LiteralPath $startRegPath -Name "ShowFrequentList" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

            # Stage 4: Backup original start2.bin once, then stop shell processes and wipe start*.bin
            $origBin = Join-Path $startStatePath "start2.bin"
            $bakDir  = "$env:LOCALAPPDATA\WinUltix"
            $bakBin  = "$bakDir\start2_backup.bin"
            if ((Test-Path -LiteralPath $origBin) -and -not (Test-Path -LiteralPath $bakBin)) {
                if (-not (Test-Path -LiteralPath $bakDir)) { New-Item -Path $bakDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
                Copy-Item -LiteralPath $origBin -Destination $bakBin -Force -ErrorAction SilentlyContinue
            }

            # Stage 5: Stop shell processes and wipe start*.bin (with attribute reset & locked-handle evacuation)
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 60
                $UltixSync.Logs.Enqueue(" -> [4/7] Recycling Explorer & wiping locked start2.bin database...")
            }
            Stop-Process -Name "StartMenuExperienceHost", "ShellExperienceHost", "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300

            for ($attempt = 1; $attempt -le 6; $attempt++) {
                Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $startStatePath -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $binFull = $_.FullName
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $binFull -Force -ErrorAction Stop
                    } catch {
                        $trashBin = Join-Path -Path $env:TEMP -ChildPath "WinUltix_StartBin_$([guid]::NewGuid().ToString('N')).tmp"
                        Move-Item -LiteralPath $binFull -Destination $trashBin -Force -ErrorAction SilentlyContinue
                    }
                }
                if (-not (Test-Path -LiteralPath (Join-Path $startStatePath "start2.bin"))) { break }
                Start-Sleep -Milliseconds 60
            }

            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
                Start-Sleep -Milliseconds 800
            }

            # Stage 6: Trigger native compilation via Core_Helpers [WinUltix.AppActivator] COM interop
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 75
                $UltixSync.Logs.Enqueue(" -> [5/7] Invoking COM IApplicationActivationManager to compile clean start2.bin...")
            }
            $appActivator = $null
            try {
                $appActivator = New-Object WinUltix.AppActivator
                [uint32]$activatedPid = 0
                [void]$appActivator.ActivateApplication("Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App", $null, 0, [ref]$activatedPid)
            } catch {
            } finally {
                if ($null -ne $appActivator -and [System.Runtime.InteropServices.Marshal]::IsComObject($appActivator)) {
                    [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($appActivator)
                }
            }

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
                if (-not (Test-Path -LiteralPath "HKCU:\Software\WinUltix")) { New-Item -Path "HKCU:\Software\WinUltix" -Force | Out-Null }
                Set-ItemProperty -LiteralPath "HKCU:\Software\WinUltix" -Name "StartMenuClearedSize" -Value $newBinSize -Type DWord -Force
            }

            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [OK] Native start2.bin compiled (3-Icon + Classic Alphabetical List + No Recent Files).")
            }
        } catch {
            if ($null -ne $UltixSync) {
                $UltixSync.Logs.Enqueue("    [!] Error during Start Menu native compilation: $($_.Exception.Message)")
            }
        } finally {
            # Stage 7: Deterministic MDM cleanup so pins remain unlocked
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 90
                $UltixSync.Logs.Enqueue(" -> [6/7] Stripping temporary MDM PolicyManager locks...")
            }
            foreach ($polPath in @($policyDevicePath, $policyLegacyPath, $policyUserPath, "HKCU:\Software\Microsoft\PolicyManager\current\user\Start")) {
                if (Test-Path -LiteralPath $polPath) {
                    Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins_ProviderSet" -Force -ErrorAction SilentlyContinue
                    Remove-ItemProperty -LiteralPath $polPath -Name "ConfigureStartPins_WinningProvider" -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid") {
                Remove-Item -LiteralPath "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$provGuid" -Recurse -Force -ErrorAction SilentlyContinue
            }
            if ($createdEnrollment -and (Test-Path -LiteralPath $enrollmentPath)) {
                Remove-Item -LiteralPath $enrollmentPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
        }

        # Stage 8: Default User provisioning
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [7/7] Provisioning Default User profile LayoutModification.json...")
        }
        $defaultShellPath = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
        if (-not (Test-Path -LiteralPath $defaultShellPath)) {
            New-Item -Path $defaultShellPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $defaultJsonPath = Join-Path -Path $defaultShellPath -ChildPath "LayoutModification.json"
        Set-Content -LiteralPath $defaultJsonPath -Value $cleanPinsJson -Encoding UTF8 -Force -ErrorAction SilentlyContinue

        $defaultPkgPath = "$env:SystemDrive\Users\Default\AppData\Local\Packages"
        if (Test-Path -LiteralPath $defaultPkgPath) {
            Get-ChildItem -Path $defaultPkgPath -Filter "Microsoft.Windows.StartMenuExperienceHost_*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem -Path (Join-Path $_.FullName "LocalState") -Filter "start*.bin*" -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue("    [OK] Default User LayoutModification.json provisioned.")
        }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }.GetNewClosure())
}

function Get-PowerDisplayState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    # 1. System Hibernation (hiberfil.sys)
    $hiberVal = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled
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

    # 7. Display Content Adaptive Brightness Control (CABC / Adaptive Dimming = 0)
    $cabcVal = Get-UltixPowerAcIndex -SubGroupGuid "7516b95f-f776-4464-8c53-06167f40cc99" -SettingGuid "aded5e82-b909-4619-9949-f5d71dac0bcb" -IncludeHidden
    $cabcReg = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "DisableCABC" -ErrorAction SilentlyContinue).DisableCABC
    $isCabcOpt = (($null -eq $cabcVal -or $cabcVal -eq 0) -and $cabcReg -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Display: Disable Content Adaptive Brightness (CABC / OLED Auto-Dimming)"
        IsDetected    = (-not $isCabcOpt)
        ActionData    = @{ Type = "CABC"; Sub = "7516b95f-f776-4464-8c53-06167f40cc99"; Guid = "aded5e82-b909-4619-9949-f5d71dac0bcb"; OptAC = 0; OptDC = 0; DefAC = 1; DefDC = 1 }
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
                        powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.OptAC 2>$null
                        powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.OptDC 2>$null
                        if (-not (Test-Path -LiteralPath $gfxKey)) { New-Item -Path $gfxKey -Force -ErrorAction SilentlyContinue | Out-Null }
                        Set-ItemProperty -LiteralPath $gfxKey -Name "DisableCABC" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    } else {
                        powercfg.exe /setacvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.DefAC 2>$null
                        powercfg.exe /setdcvalueindex SCHEME_CURRENT $d.Sub $d.Guid $d.DefDC 2>$null
                        Remove-ItemProperty -LiteralPath $gfxKey -Name "DisableCABC" -Force -ErrorAction SilentlyContinue
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
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Power & Display subsystem configuration completed ($Operation).`n"
    }.GetNewClosure())
}

# ------------------------------------------
# Z3: UI INITIALIZATION (TWEAKS, SHELL, POWER & GAMING)
# ------------------------------------------
function Initialize-Z3UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabReg = New-Object System.Windows.Forms.TabPage
    $tabReg.Text = "Tweaks"
    $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    $invokeRegCategory = ({
        param(
            [string]$ScannerFn,
            [string]$CategoryName,
            [string]$ModalTitle,
            [string]$AuditHeader,
            [switch]$RefreshShell,
            [switch]$AuditOnly
        )
        Invoke-UltixAuditFlow `
            -ScannerFunction $ScannerFn `
            -AuditLabel $AuditHeader `
            -ModalTitle $ModalTitle `
            -ModalDescription "Select tweaks to apply or revert." `
            -ExecutorFunction "Invoke-ApplyRegistry" `
            -ExecutorExtraParams @{
                CategoryName = $CategoryName
                RefreshShell = $RefreshShell.IsPresent
            } `
            -ControlsToDisable $allTabButtons.ToArray() `
            -AuditOnly:$AuditOnly.IsPresent `
            -AuditPrefix "To Optimize" `
            -EnableRevert
    }.GetNewClosure())

    # 1. Taskbar & Start Menu
    $rowTaskbar = New-UltixActionRow -Parent $tabReg -Y 20 -MainRGB @(55, 58, 64) `
        -Text "Taskbar & Start Menu Tweaks" `
        -Description "Aligns the taskbar to the left, kills Bing search assistants, disables notifications bloat, and hides Widgets (with UCPD.sys bypass)." `
        -AuditDescription "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, Widgets state, and Bing locks." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Taskbar" "Taskbar" "WinUltix - Taskbar Tweaks" "Taskbar & Start Menu" -AuditOnly }.GetNewClosure())

    # 2. Reset Start Menu Layout (3-Icon Clean + Backup Restore)
    $rowStartMenu = New-UltixActionRow -Parent $tabReg -Y 70 -MainRGB @(55, 58, 64) `
        -Text "Reset Start Menu Layout (Clean 3-Icon)" `
        -Description "Backs up your current start2.bin database, wipes promotional tiles, and compiles a clean 3-icon layout (Edge, Settings, Explorer) with full Revert support." `
        -AuditDescription "AUDIT: Scans the size of the current Start Menu layout database (start2.bin), backup state, and checks for residual MDM locks." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-StartMenuState" -AuditLabel "Start Menu Layout" -ModalTitle "WinUltix - Clean Start Menu Compiler" -ModalDescription "Click 'Execute Selected' to compile a clean 3-icon Start Menu (backs up start2.bin), or 'Revert Selected' to restore your original start2_backup.bin." -ExecutorFunction "Clear-StartMenu" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({ Invoke-StartMenuAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 3. File Explorer & Context Menu
    $rowExplorer = New-UltixActionRow -Parent $tabReg -Y 120 -MainRGB @(55, 58, 64) `
        -Text "File Explorer & Context Menu" `
        -Description "Restores the classic Windows 10 right-click context menu, shows file extensions, unpins OneDrive, and runs folder windows in a separate process." `
        -AuditDescription "AUDIT: Verifies classic context menu CLSID registration and File Explorer performance flags." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -RefreshShell }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Explorer" "Explorer" "WinUltix - Explorer Tweaks" "File Explorer" -AuditOnly }.GetNewClosure())

    # 4. OS Annoyances (Modern Standby S0 / Sticky Keys / AutoPlay)
    $rowAnnoy = New-UltixActionRow -Parent $tabReg -Y 170 -MainRGB @(55, 58, 64) `
        -Text "OS Annoyances (Modern Standby / Keys)" `
        -Description "Disables Modern Standby S0 (forces hardware S3 sleep), blocks AutoPlay across all drives, and disables Sticky/Filter/Toggle Keys popups." `
        -AuditDescription "AUDIT: Verifies Modern Standby S0 override, AutoPlay policy, and Sticky Keys blockade." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Annoyances" "Annoyances" "WinUltix - OS Annoyances" "OS Annoyances" -AuditOnly }.GetNewClosure())

    # 5. Optimize Power & Display (7-Point)
    $rowPower = New-UltixActionRow -Parent $tabReg -Y 220 -MainRGB @(55, 58, 64) `
        -Text "Optimize Power & Display (7-Point)" `
        -Description "7-Point Power & Display tuner: Disables Hibernation (hiberfil.sys), Sleep/SATA spin-down, USB Selective Suspend (protects DACs/8K mice), PCIe ASPM, and OLED CABC dimming." `
        -AuditDescription "AUDIT: Verifies active Power Plan timeouts, USB Selective Suspend, PCIe ASPM, CABC, and Hibernation state." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ModalTitle "WinUltix - Power & Display Optimizer" -ModalDescription "Select power and display parameters to enforce or revert to Windows defaults." -ExecutorFunction "Invoke-ApplyPowerDisplay" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-PowerDisplayState" -AuditLabel "Power & Display Subsystem" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unoptimized"
        }.GetNewClosure())

    # 6. Hard Mouse Acceleration Disable (1:1 Raw Input)
    $rowMouse = New-UltixActionRow -Parent $tabReg -Y 270 -MainRGB @(45, 85, 125) `
        -Text "Hard Mouse Acceleration Disable (1:1)" `
        -Description "Enforces pure 1:1 raw pointer input by disabling 'Enhance pointer precision' and zeroing acceleration thresholds." `
        -AuditDescription "AUDIT: Scans HKCU\Control Panel\Mouse for pointer acceleration thresholds." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Mouse" "Mouse" "WinUltix - Raw Input Enforcer" "Mouse Acceleration" -AuditOnly }.GetNewClosure())

    # 7. Hardware and Gaming (Extreme)
    $rowGaming = New-UltixActionRow -Parent $tabReg -Y 320 -MainRGB @(135, 50, 50) `
        -Text "Hardware & Gaming Registry (Extreme)" `
        -Description "Enforces MMCSS gaming thread priorities, disables GameDVR, disables Multiplane Overlay (MPO - fixes VRR/OLED flicker), enables Flip Model, and tunes VBS/HVCI." `
        -AuditDescription "AUDIT: Verifies MMCSS limits, MPO state, GameDVR, HAGS, and VBS/HVCI flags." `
        -OnClick ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" }.GetNewClosure()) `
        -OnAudit ({ & $invokeRegCategory "Get-RegState_Gaming" "Gaming" "WinUltix - Extreme Gaming Profile" "Hardware & Gaming" -AuditOnly }.GetNewClosure())

    foreach ($row in @($rowTaskbar, $rowStartMenu, $rowExplorer, $rowAnnoy, $rowPower, $rowMouse, $rowGaming)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabReg)
}