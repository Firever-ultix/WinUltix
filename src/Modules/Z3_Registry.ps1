# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z3_REGISTRY.PS1 - REGISTRY ENGINE MODULE
# Z3_Registry: Main registry engine (Invoke-ApplyRegistry). Modulates UI (classic taskbar, Start menu), disables telemetry and data collection, optimizes background services (Edge, Defender), applies gaming tweaks (MMCSS, disabling VBS/HVCI, GameDVR), and disables mouse acceleration.
# ==========================================

# ------------------------------------------
# Z3: REGISTRY AUDIT HELPER
# ------------------------------------------
function Invoke-RegistryAudit {
    param([array]$Rules)
    
    $results = @()
    foreach ($rule in $Rules) {
        $isDetected = $true
        $keyExists  = Test-Path -Path $rule.Path
        $currentValue = $null
        $valueExists  = $false

        if ($keyExists) {
            if ($rule.Name -eq "" -or $rule.Name -eq "(Default)") {
                $regKey = Get-Item -Path $rule.Path -ErrorAction SilentlyContinue
                if ($null -ne $regKey -and $null -ne $regKey.GetValue($null, $null)) {
                    $currentValue = $regKey.GetValue("")
                    $valueExists  = $true
                }
            } else {
                $prop = Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue
                if ($null -ne $prop -and $prop.PSObject.Properties.Match($rule.Name).Count -gt 0) {
                    $currentValue = $prop.$($rule.Name)
                    $valueExists  = $true
                }
            }
        }
        
        if ($rule.ContainsKey("ValidValues")) {
            if ($valueExists -and ($rule.ValidValues -contains $currentValue)) { 
                $isDetected = $false 
            }
        } else {
            if ($valueExists -and ([string]$currentValue -eq [string]$rule.Expected)) { 
                $isDetected = $false 
            }
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

# ------------------------------------------
# Z3: REGISTRY AUDITS
# ------------------------------------------
function Get-RegState_Taskbar {
    $rules = @(
        @{ UIDisplayName = "Taskbar: Align to Left (Disables Windows 11 center alignment)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Show Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Search Box (Saves space)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Expected = 0; Default = 2; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Disable Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; Expected = 3; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Enable 'End Task' on right-click (Dev feature)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Enforce Classic Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Web Search (Forces local-only, faster search)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Hide Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Search Highlights (Bing bloat)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableSearchBoxSearchHighlights"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Tailored Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowTailoredSearch"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Toast Notifications"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "ToastEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable Focus Assist (Global)"; Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings"; Name = "NOC_GLOBAL_SETTING_TOASTS_ENABLED"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "UI: Disable App Push Notifications (Policy)"; Path = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"; Name = "NoToastApplicationNotification"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Bing Web Results (Keeps local queries private)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Expected = 1; Default = 0; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Connected Cloud Search Services"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "ConnectedSearchUseWeb"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Location Tracking in Search"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowSearchToUseLocation"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Force Local-Only UI (Disable Bing Search UI)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Expected = 0; Default = 1; Type = "DWord" }
        @{ UIDisplayName = "Search: Disable Search Highlights (Dynamic Web Content)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "EnableDynamicContentInWSB"; Expected = 0; Default = 1; Type = "DWord" }
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
    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Default = 1; Type = "DWord" }
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
# Z3: SRP (SOFTWARE RESTRICTION POLICIES) ENGINE
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
        @{ UIDisplayName = "SRP+IFEO Lock: Windows Widgets (Widgets.exe)"; TargetPath = "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.WebExperience*\Dashboard\Widgets.exe"; ExeName = "Widgets.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Compatibility Telemetry (CompatTelRunner.exe)"; TargetPath = "$env:windir\System32\CompatTelRunner.exe"; ExeName = "CompatTelRunner.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Hardware Telemetry (DeviceCensus.exe)"; TargetPath = "$env:windir\System32\DeviceCensus.exe"; ExeName = "DeviceCensus.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: GameBar Telemetry (GameBarPresenceWriter.exe)"; TargetPath = "$env:windir\System32\GameBarPresenceWriter.exe"; ExeName = "GameBarPresenceWriter.exe" }
        @{ UIDisplayName = "SRP+IFEO Lock: Edge Background Updater (MicrosoftEdgeUpdate.exe)"; TargetPath = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"; ExeName = "MicrosoftEdgeUpdate.exe" }
    )
    
    $customKey = "HKLM:\SOFTWARE\WinUltix\SRP"
    if (Test-Path $customKey) {
        $customEntries = Get-Item -Path $customKey -ErrorAction SilentlyContinue
        if ($customEntries) {
            foreach ($prop in $customEntries.Property) {
                $customPath = (Get-ItemProperty -Path $customKey -Name $prop -ErrorAction SilentlyContinue).$prop
                if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                    $exeLeaf = [System.IO.Path]::GetFileName($customPath)
                    $targets += @{ UIDisplayName = "SRP+IFEO Lock (Custom): $prop"; TargetPath = $customPath; ExeName = $exeLeaf }
                }
            }
        }
    }

    $results = @()
    $srpBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers\0\Paths"
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    
    foreach ($target in $targets) {
        $guid = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $srpRuleExists = Test-Path -Path "$srpBase\$guid"
        
        $ifeoKey = "$ifeoBase\$($target.ExeName)"
        $ifeoDebugger = (Get-ItemProperty -Path $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
        $ifeoLocked = ($null -ne $ifeoDebugger -and $ifeoDebugger -match "systray\.exe")

        # Marked as detected (needs optimization) if either SRP or IFEO lock is missing
        $isDetected = -not ($srpRuleExists -and $ifeoLocked)
        
        $results += [PSCustomObject]@{
            UIDisplayName = $target.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $target
        }
    }
    return $results
}

# ------------------------------------------
# Z3: SRP (SOFTWARE RESTRICTION POLICIES) ENGINE
# ------------------------------------------
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
        if (-not (Test-Path $srpRoot)) { New-Item -Path $srpRoot -Force | Out-Null }
        
        $srpSettings = @{
            "AuthenticodeEnabled" = 0
            "DefaultLevel"        = 262144
            "TransparentEnabled"  = 1
            "PolicyScope"         = 0
        }
        foreach ($kvp in $srpSettings.GetEnumerator()) {
            Set-ItemProperty -Path $srpRoot -Name $kvp.Key -Value $kvp.Value -Type DWord -Force
        }
        
        $exeTypes = [string[]]@("BAT","CMD","COM","EXE","HTA","LNK","MSI","OCX","PIF","REG","SCR","VBS","WSF")
        Set-ItemProperty -Path $srpRoot -Name "ExecutableTypes" -Value $exeTypes -Type MultiString -Force
        
        if (-not (Test-Path "$srpRoot\0")) { New-Item -Path "$srpRoot\0" -Force | Out-Null }
        if (-not (Test-Path "$srpRoot\262144")) { New-Item -Path "$srpRoot\262144" -Force | Out-Null }
        if (-not (Test-Path $srpPaths)) { New-Item -Path $srpPaths -Force | Out-Null }
    }

    $actionVerb = if ($Operation -eq 'Apply') { "Enforcing" } else { "Removing" }
    $policyChanged = $false

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> $($actionVerb) Execution Lock: $($item.UIDisplayName)"
        
        $target   = $item.ActionData
        $guid     = Get-DeterministicSrpGuid -InputString $target.TargetPath
        $ruleKey  = "$srpPaths\$guid"
        $ifeoKey  = "$ifeoBase\$($target.ExeName)"
        
        try {
            if ($Operation -eq 'Apply') {
                if (Test-Path $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -Path $srpPaths -ErrorAction SilentlyContinue)) {
                        $existingData = (Get-ItemProperty -Path $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($existingData -eq $target.TargetPath -and $subKey.PSChildName -ne $guid) {
                            Remove-Item -Path $subKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                New-Item -Path $ruleKey -Force | Out-Null
                Set-ItemProperty -Path $ruleKey -Name "Description" -Value "WinUltix Pro SRP Lockdown" -Type String -Force
                Set-ItemProperty -Path $ruleKey -Name "ItemData" -Value $target.TargetPath -Type String -Force
                Set-ItemProperty -Path $ruleKey -Name "SaferFlags" -Value 0 -Type DWord -Force

                if (-not (Test-Path $ifeoKey)) { New-Item -Path $ifeoKey -Force | Out-Null }
                Set-ItemProperty -Path $ifeoKey -Name "Debugger" -Value $nullStub -Type String -Force
                Set-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -Value 1 -Type DWord -Force
                
                $procName = [System.IO.Path]::GetFileNameWithoutExtension($target.ExeName)
                $activeProc = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($activeProc) { 
                    $activeProc | Stop-Process -Force -ErrorAction SilentlyContinue
                    Write-GUI "    [OK] Flushed active process ($procName) from memory."
                }
                $policyChanged = $true
            } else {
                if (Test-Path $srpPaths) {
                    foreach ($subKey in (Get-ChildItem -Path $srpPaths -ErrorAction SilentlyContinue)) {
                        $itemData = (Get-ItemProperty -Path $subKey.PSPath -Name "ItemData" -ErrorAction SilentlyContinue).ItemData
                        if ($subKey.PSChildName -eq $guid -or $itemData -eq $target.TargetPath) {
                            Remove-Item -Path $subKey.PSPath -Force -Recurse -ErrorAction Stop
                            $policyChanged = $true
                        }
                    }
                }

                if (Test-Path $ifeoKey) {
                    $isManaged = (Get-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -ErrorAction SilentlyContinue).WinUltixManaged
                    $dbgVal    = (Get-ItemProperty -Path $ifeoKey -Name "Debugger" -ErrorAction SilentlyContinue).Debugger
                    if ($isManaged -eq 1 -or $dbgVal -match "systray\.exe") {
                        Remove-ItemProperty -Path $ifeoKey -Name "Debugger" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -Path $ifeoKey -Name "WinUltixManaged" -Force -ErrorAction SilentlyContinue
                        $remainingProps = (Get-Item -Path $ifeoKey -ErrorAction SilentlyContinue).Property
                        if (-not $remainingProps -or $remainingProps.Count -eq 0) {
                            Remove-Item -Path $ifeoKey -Force -ErrorAction SilentlyContinue
                        }
                        $policyChanged = $true
                    }
                }
                Write-GUI "    [OK] SRP & IFEO restriction rules purged from registry."
            }
        } catch { Write-GUI "    [!] Failed to modify execution lock: $($_.Exception.Message)" }
    }
    
    if ($policyChanged) {
        Write-GUI " -> Refreshing Safer API policy tokens (gpupdate in background)..."
        Update-Progress 85

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
            $gpProc = Start-Process -FilePath "gpupdate.exe" -ArgumentList "/force" -WindowStyle Hidden -PassThru
            $gpProc.WaitForExit()
            $gpProc.Dispose()
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI "    [OK] Kernel IFEO and AuthZ policy tokens updated.`n"
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
                if (Test-Path $reg.Path) { 
                    Remove-Item -Path $reg.Path -Recurse -Force -ErrorAction Stop | Out-Null 
                    $parentKey = Split-Path -Path $reg.Path -Parent
                    if ($parentKey -match "\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2\}$" -and (Test-Path $parentKey)) {
                        Remove-Item -Path $parentKey -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                }
                continue
            }
            if ($targetValue -eq 'DELETE_VALUE') {
                if (Test-Path $reg.Path) { Remove-ItemProperty -Path $reg.Path -Name $reg.Name -Force -ErrorAction Stop | Out-Null }
                continue
            }

            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force -ErrorAction Stop | Out-Null }
            
            if ($reg.Name -eq "" -or $reg.Name -eq "(Default)") {
                Set-Item -Path $reg.Path -Value $targetValue -Force -ErrorAction Stop | Out-Null
            } 
            else { 
                Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $targetValue -Type $reg.Type -Force -ErrorAction Stop | Out-Null 
            }
        } catch { Write-GUI "    [!] Failed to modify key (Permissions/Lock): $($reg.Name)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $CategoryName registry modifications completed ($Operation)."
}

function Initialize-Z3UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabReg = New-Object System.Windows.Forms.TabPage
    $tabReg.Text = "Registry"
    $tabReg.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # Taskbar & Start Menu
    $btnRegTaskbar = New-Object System.Windows.Forms.Button
    $btnRegTaskbar.Text = "Taskbar and Start Menu"
    $btnRegTaskbar.Location = New-Object System.Drawing.Point(15, 20)
    $btnRegTaskbar.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegTaskbar.ForeColor = [System.Drawing.Color]::White
    $btnRegTaskbar.FlatStyle = "Flat"
    $btnRegTaskbar.Add_MouseEnter({ Show-Description "Aligns the taskbar to the left, kills Bing assistants, and hides widgets." })
    $btnRegTaskbar.Add_Click({ 
        $auditData = Get-RegState_Taskbar
        $modalOutput = Show-ActionModal -Title "WinUltix - Taskbar Tweaks" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Taskbar" -Operation $modalOutput.Action
            Stop-Process -Name "SearchHost" -Force -ErrorAction SilentlyContinue
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Write-GUI "" 
        } 
    })
    
    $btnAudTaskbar = New-Object System.Windows.Forms.Button
    $btnAudTaskbar.Text = "?"
    $btnAudTaskbar.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudTaskbar.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudTaskbar.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudTaskbar.ForeColor = [System.Drawing.Color]::White
    $btnAudTaskbar.FlatStyle = "Flat"
    $btnAudTaskbar.Add_MouseEnter({ Show-Description "AUDIT: Verifies taskbar alignment policy, Start Menu layouts, and Bing locks." })
    $btnAudTaskbar.Add_Click({ Write-GUI "--- AUDIT: Taskbar & Start Menu ---"; $state = Get-RegState_Taskbar; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # File Explorer
    $btnRegExplorer = New-Object System.Windows.Forms.Button
    $btnRegExplorer.Text = "File Explorer and Context Menu"
    $btnRegExplorer.Location = New-Object System.Drawing.Point(15, 70)
    $btnRegExplorer.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegExplorer.ForeColor = [System.Drawing.Color]::White
    $btnRegExplorer.FlatStyle = "Flat"
    $btnRegExplorer.Add_MouseEnter({ Show-Description "Restores the full context menu, launches folder processes in isolation." })
    $btnRegExplorer.Add_Click({ 
        $auditData = Get-RegState_Explorer
        $modalOutput = Show-ActionModal -Title "WinUltix - Explorer Tweaks" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Explorer" -Operation $modalOutput.Action
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Write-GUI "" 
        } 
    })

    $btnAudExplorer = New-Object System.Windows.Forms.Button
    $btnAudExplorer.Text = "?"
    $btnAudExplorer.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudExplorer.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudExplorer.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudExplorer.ForeColor = [System.Drawing.Color]::White
    $btnAudExplorer.FlatStyle = "Flat"
    $btnAudExplorer.Add_MouseEnter({ Show-Description "AUDIT: Verifies the presence of classic context menu and Explorer performance flags." })
    $btnAudExplorer.Add_Click({ Write-GUI "--- AUDIT: File Explorer ---"; $state = Get-RegState_Explorer; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # OS Annoyances
    $btnRegAnnoyances = New-Object System.Windows.Forms.Button
    $btnRegAnnoyances.Text = "OS Annoyances (AutoRun / Sticky Keys)"
    $btnRegAnnoyances.Location = New-Object System.Drawing.Point(15, 120)
    $btnRegAnnoyances.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegAnnoyances.ForeColor = [System.Drawing.Color]::White
    $btnRegAnnoyances.FlatStyle = "Flat"
    $btnRegAnnoyances.Add_MouseEnter({ Show-Description "Deactivates AutoPlay and Accessibility shortcuts (Sticky Keys)." })
    $btnRegAnnoyances.Add_Click({ 
        $auditData = Get-RegState_Annoyances
        $modalOutput = Show-ActionModal -Title "WinUltix - OS Annoyances" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Annoyances" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudAnnoyances = New-Object System.Windows.Forms.Button
    $btnAudAnnoyances.Text = "?"
    $btnAudAnnoyances.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudAnnoyances.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudAnnoyances.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudAnnoyances.ForeColor = [System.Drawing.Color]::White
    $btnAudAnnoyances.FlatStyle = "Flat"
    $btnAudAnnoyances.Add_MouseEnter({ Show-Description "AUDIT: Verifies AutoPlay and Sticky Keys blockade." })
    $btnAudAnnoyances.Add_Click({ Write-GUI "--- AUDIT: OS Annoyances ---"; $state = Get-RegState_Annoyances; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Privacy
    $btnRegPrivacy = New-Object System.Windows.Forms.Button
    $btnRegPrivacy.Text = "Privacy and Background Apps (AppPrivacy)"
    $btnRegPrivacy.Location = New-Object System.Drawing.Point(15, 170)
    $btnRegPrivacy.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegPrivacy.ForeColor = [System.Drawing.Color]::White
    $btnRegPrivacy.FlatStyle = "Flat"
    $btnRegPrivacy.Add_MouseEnter({ Show-Description "Blocks telemetry, background UWP apps execution, and limits Edge processes." })
    $btnRegPrivacy.Add_Click({ 
        $auditData = Get-RegState_Privacy
        $modalOutput = Show-ActionModal -Title "WinUltix - Privacy Policies" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Privacy" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudPrivacy = New-Object System.Windows.Forms.Button
    $btnAudPrivacy.Text = "?"
    $btnAudPrivacy.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudPrivacy.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudPrivacy.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudPrivacy.ForeColor = [System.Drawing.Color]::White
    $btnAudPrivacy.FlatStyle = "Flat"
    $btnAudPrivacy.Add_MouseEnter({ Show-Description "AUDIT: Checks the registry for telemetry, Edge, and background execution blocks." })
    $btnAudPrivacy.Add_Click({ Write-GUI "--- AUDIT: Privacy Policies ---"; $state = Get-RegState_Privacy; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Boot & Security
    $btnRegSystemBoot = New-Object System.Windows.Forms.Button
    $btnRegSystemBoot.Text = "Boot and WPBT (BIOS/UEFI Block)"
    $btnRegSystemBoot.Location = New-Object System.Drawing.Point(15, 220)
    $btnRegSystemBoot.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegSystemBoot.ForeColor = [System.Drawing.Color]::White
    $btnRegSystemBoot.FlatStyle = "Flat"
    $btnRegSystemBoot.Add_MouseEnter({ Show-Description "Disables Fast Boot, OneDrive, RDP, and blocks software injections from BIOS/UEFI (WPBT)." })
    $btnRegSystemBoot.Add_Click({ 
        $auditData = Get-RegState_SystemBoot
        $modalOutput = Show-ActionModal -Title "WinUltix - Boot & Security" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "SystemBoot" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudSystemBoot = New-Object System.Windows.Forms.Button
    $btnAudSystemBoot.Text = "?"
    $btnAudSystemBoot.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudSystemBoot.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSystemBoot.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSystemBoot.ForeColor = [System.Drawing.Color]::White
    $btnAudSystemBoot.FlatStyle = "Flat"
    $btnAudSystemBoot.Add_MouseEnter({ Show-Description "AUDIT: Verifies kernel hibernation logic (Fast Boot), WPBT, and RDP." })
    $btnAudSystemBoot.Add_Click({ Write-GUI "--- AUDIT: Boot & Security ---"; $state = Get-RegState_SystemBoot; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Mouse
    $btnRegMouse = New-Object System.Windows.Forms.Button
    $btnRegMouse.Text = "Hard Mouse Acceleration Disable (Raw Input)"
    $btnRegMouse.Location = New-Object System.Drawing.Point(15, 270)
    $btnRegMouse.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnRegMouse.ForeColor = [System.Drawing.Color]::White
    $btnRegMouse.FlatStyle = "Flat"
    $btnRegMouse.Add_MouseEnter({ Show-Description "Pure 1:1 input. Hard-disables 'Enhance pointer precision' to eliminate system smoothing." })
    $btnRegMouse.Add_Click({ 
        $auditData = Get-RegState_Mouse
        $modalOutput = Show-ActionModal -Title "WinUltix - Raw Input Enforcer" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Mouse" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudMouse = New-Object System.Windows.Forms.Button
    $btnAudMouse.Text = "?"
    $btnAudMouse.Location = New-Object System.Drawing.Point(345, 270)
    $btnAudMouse.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudMouse.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnAudMouse.ForeColor = [System.Drawing.Color]::White
    $btnAudMouse.FlatStyle = "Flat"
    $btnAudMouse.Add_MouseEnter({ Show-Description "AUDIT: Scans registry keys for system pointer acceleration." })
    $btnAudMouse.Add_Click({ Write-GUI "--- AUDIT: Mouse Acceleration ---"; $state = Get-RegState_Mouse; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # Gaming
    $btnRegGaming = New-Object System.Windows.Forms.Button
    $btnRegGaming.Text = "Hardware and Gaming (Extreme)"
    $btnRegGaming.Location = New-Object System.Drawing.Point(15, 320)
    $btnRegGaming.Size = New-Object System.Drawing.Size(320, 40)
    $btnRegGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnRegGaming.ForeColor = [System.Drawing.Color]::White
    $btnRegGaming.FlatStyle = "Flat"
    $btnRegGaming.Add_MouseEnter({ Show-Description "Enforces MMCSS priorities, disables GameDVR, enabling maximum hardware performance." })
    $btnRegGaming.Add_Click({ 
        $auditData = Get-RegState_Gaming
        $modalOutput = Show-ActionModal -Title "WinUltix - Extreme Gaming Profile" -Description "Select tweaks to apply or revert." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput) { 
            Invoke-ApplyRegistry -SelectedItems $modalOutput.Items -CategoryName "Gaming" -Operation $modalOutput.Action
            Write-GUI "" 
        } 
    })

    $btnAudGaming = New-Object System.Windows.Forms.Button
    $btnAudGaming.Text = "?"
    $btnAudGaming.Location = New-Object System.Drawing.Point(345, 320)
    $btnAudGaming.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGaming.BackColor = [System.Drawing.Color]::FromArgb(255, 150, 60, 60)
    $btnAudGaming.ForeColor = [System.Drawing.Color]::White
    $btnAudGaming.FlatStyle = "Flat"
    $btnAudGaming.Add_MouseEnter({ Show-Description "AUDIT: Verifies MMCSS limits, CPU priority, and HAGS acceleration." })
    $btnAudGaming.Add_Click({ Write-GUI "--- AUDIT: Hardware & Gaming ---"; $state = Get-RegState_Gaming; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] To Optimize: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Optimized." }; Write-GUI "" })

    # SRP Execution Locks (Main Button)
    $btnRegSRP = New-Object System.Windows.Forms.Button
    $btnRegSRP.Text = "Execution Blocks (SRP/Legacy Pro)"
    $btnRegSRP.Location = New-Object System.Drawing.Point(15, 420)
    $btnRegSRP.Size = New-Object System.Drawing.Size(240, 40)
    $btnRegSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnRegSRP.ForeColor = [System.Drawing.Color]::White
    $btnRegSRP.FlatStyle = "Flat"
    $btnRegSRP.Add_MouseEnter({ Show-Description "NATIVE KERNEL LOCK (Pro/Enterprise Only): Generates legacy Software Restriction Policies to block execution. May not work on Home editions or future OS builds." })


    # SRP: Add Custom Target [+]
    $btnAddSRP = New-Object System.Windows.Forms.Button
    $btnAddSRP.Text = "+"
    $btnAddSRP.Location = New-Object System.Drawing.Point(260, 420)
    $btnAddSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnAddSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 60)
    $btnAddSRP.ForeColor = [System.Drawing.Color]::White
    $btnAddSRP.FlatStyle = "Flat"
    $btnAddSRP.Add_MouseEnter({ Show-Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP block list." })
    $btnAddSRP.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Executables (*.exe)|*.exe"
        $dlg.Title = "Select Executable to Block (SRP)"
        $dlg.InitialDirectory = "$env:ProgramFiles"
        
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            if (-not (Test-Path $regKey)) { New-Item -Path $regKey -Force | Out-Null }
            $exeName = [System.IO.Path]::GetFileName($dlg.FileName)
            Set-ItemProperty -Path $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
            Write-GUI " -> Added custom SRP target: $exeName"
        }
    })

    # SRP: Clear Custom Roster [-]
    $btnClrSRP = New-Object System.Windows.Forms.Button
    $btnClrSRP.Text = "-"
    $btnClrSRP.Location = New-Object System.Drawing.Point(305, 420)
    $btnClrSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnClrSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 60)
    $btnClrSRP.ForeColor = [System.Drawing.Color]::White
    $btnClrSRP.FlatStyle = "Flat"
    $btnClrSRP.Add_MouseEnter({ Show-Description "CLEAR CUSTOM TARGETS: Removes all custom executables from the WinUltix tracking list (does not unlock them if currently applied)." })
    $btnClrSRP.Add_Click({
        $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
        if (Test-Path $regKey) {
            Remove-Item -Path $regKey -Force -Recurse | Out-Null
            Write-GUI " -> Custom SRP tracking database purged."
        } else {
            Write-GUI " -> Custom SRP roster is already empty."
        }
    })

    # SRP Audit Button [?]
    $btnAudSRP = New-Object System.Windows.Forms.Button
    $btnAudSRP.Text = "?"
    $btnAudSRP.Location = New-Object System.Drawing.Point(350, 420)
    $btnAudSRP.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudSRP.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudSRP.ForeColor = [System.Drawing.Color]::White
    $btnAudSRP.FlatStyle = "Flat"
    $btnAudSRP.Add_MouseEnter({ Show-Description "AUDIT: Verifies active Software Restriction Policies." })
    $btnAudSRP.Add_Click({ 
        Write-GUI "--- AUDIT: Software Restriction Policies ---"
        $state = Get-RegState_SRP
        $detected = @($state | Where-Object { $_.IsDetected })
        
        if ($detected.Count -gt 0) { 
            foreach ($d in $detected) { Write-GUI "  [!] To Block: $($d.UIDisplayName)" } 
        } else { 
            Write-GUI "  [OK] Optimized." 
        }
        Write-GUI "" 
    })

    $btnRegSRP.Add_Click({ 
        $auditData = Get-RegState_SRP
        $modalOutput = Show-ActionModal -Title "WinUltix - SRP & IFEO Lockdown" -Description "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." -AuditResults $auditData -EnableRevert
        
        if ($null -ne $modalOutput -and $null -ne $modalOutput.Items -and $modalOutput.Items.Count -gt 0) { 
            Invoke-ApplySRP -SelectedItems $modalOutput.Items -Operation $modalOutput.Action -ControlsToDisable @($btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP)
        } 
    }.GetNewClosure())
    
    $tabReg.Controls.AddRange(@($btnRegTaskbar, $btnAudTaskbar, $btnRegExplorer, $btnAudExplorer, $btnRegAnnoyances, $btnAudAnnoyances, $btnRegPrivacy, $btnAudPrivacy, $btnRegSystemBoot, $btnAudSystemBoot, $btnRegMouse, $btnAudMouse, $btnRegGaming, $btnAudGaming, $btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP))
    $TabControl.Controls.Add($tabReg)
}