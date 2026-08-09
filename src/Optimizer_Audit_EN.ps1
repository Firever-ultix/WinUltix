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

function Invoke-ServicesAudit {
    param([array]$Rules)
    
    $results = @()
    foreach ($rule in $Rules) {
        $currentStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($rule.Name)" -Name "Start" -ErrorAction SilentlyContinue).Start
        
        $isDetected = $true
        if ($null -eq $currentStart -or $currentStart -eq $rule.ExpectedStart) {
            $isDetected = $false
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $rule.UIDisplayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

function Invoke-RegistryAudit {
    param([array]$Rules)
    
    $results = @()
    foreach ($rule in $Rules) {
        $isDetected = $true
        
        if ($rule.Name -eq "" -or $rule.Name -eq "(Default)") {
            $regKey = Get-Item -Path $rule.Path -ErrorAction SilentlyContinue
            if ($null -ne $regKey) { $currentValue = $regKey.GetValue("") } else { $currentValue = $null }
        } else {
            $currentValue = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
        }
        
        if ($rule.ContainsKey("ValidValues")) {
            if ($rule.ValidValues -contains $currentValue) { 
                $isDetected = $false 
            }
        } else {
            if ($null -ne $currentValue -and [string]$currentValue -eq [string]$rule.Expected) { 
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
# Z1: CLEANUP AUDITS
# ------------------------------------------
function Get-CleanupState {
    param([string]$Category)
    $rules = @()

    if ($Category -eq "WU") {
        $rules += @{ UIDisplayName = "Windows Update Download Cache"; Path = "$env:windir\SoftwareDistribution\Download"; Type = "Files" }
    }
    if ($Category -eq "Temp") {
        $rules += @{ UIDisplayName = "Windows System Temp"; Path = "$env:windir\Temp"; Type = "Files" }
        $rules += @{ UIDisplayName = "Global User Temp"; Path = "$env:TEMP"; Type = "Files" }
        $rules += @{ UIDisplayName = "Windows Prefetch"; Path = "$env:windir\Prefetch"; Type = "Files" }
        Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(Public|Default.*|All Users)$' } | ForEach-Object {
            $rules += @{ UIDisplayName = "User Temp ($($_.Name))"; Path = "$($_.FullName)\AppData\Local\Temp"; Type = "Files" }
        }
    }
    if ($Category -eq "EventLogs") {
        $rules += @{ UIDisplayName = "Windows Event Logs"; Path = "$env:windir\System32\winevt\Logs"; Type = "EventLogs" }
    }
    if ($Category -eq "ThirdParty") {
        $appCaches = @(
            @{ Name = "Edge"; Path = "AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data" }
            @{ Name = "Chrome"; Path = "AppData\Local\Google\Chrome\User Data\Default\Cache\Cache_Data" }
            @{ Name = "Discord"; Path = "AppData\Local\Discord\Cache" }
            @{ Name = "NVIDIA DXCache"; Path = "AppData\Local\NVIDIA\DXCache" }
            @{ Name = "AMD DxCache"; Path = "AppData\Local\AMD\DxCache" }
        )
        Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(Public|Default.*|All Users)$' } | ForEach-Object {
            $usr = $_.Name
            $base = $_.FullName
            foreach ($app in $appCaches) {
                $rules += @{ UIDisplayName = "$($app.Name) Cache ($usr)"; Path = "$base\$($app.Path)"; Type = "Files" }
            }
        }
    }
    if ($Category -eq "RecycleBin") {
        foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) {
            $rules += @{ UIDisplayName = "Recycle Bin ($($drive.Name):)"; Path = "$($drive.Root)`$Recycle.Bin"; Type = "RecycleBin" }
        }
    }

    $results = @()
    foreach ($rule in $rules) {
        $isDetected = $false
        $sizeMB = 0

        if (Test-Path $rule.Path -ErrorAction SilentlyContinue) {
            $files = @(Get-ChildItem -Path $rule.Path -Recurse -File -Force -ErrorAction SilentlyContinue)
            
            if ($files.Count -gt 0) {
                $bytes = ($files | Measure-Object -Property Length -Sum).Sum
                $sizeMB = [math]::Round(($bytes / 1MB), 2)
            }
        }

        if ($sizeMB -ge 1) {
            $isDetected = $true
            $displayName = "$($rule.UIDisplayName) [ $sizeMB MB ]"
        } else {
            $displayName = "$($rule.UIDisplayName) [ Clean ]"
        }

        $results += [PSCustomObject]@{
            UIDisplayName = $displayName
            IsDetected    = $isDetected
            ActionData    = $rule
        }
    }
    return $results
}

# ------------------------------------------
# Z2: BLOATWARE AUDITS
# ------------------------------------------
function Audit-OneDrive { Write-GUI "--- AUDIT: OneDrive ---"; if ((Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") -or (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup")) { Write-GUI "[!] OneDrive traces found." } else { Write-GUI "[OK] OneDrive eradicated." } }

function Get-CapabilitiesState {
    $capsWildcards = @("*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*", "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*", "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*", "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*", "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*")
    
    $installedCaps = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object State -eq 'Installed'
    
    $results = @()
    foreach ($capName in $capsWildcards) {
        $found = $installedCaps | Where-Object Name -like $capName
        $isDetected = ($found.Count -gt 0)
        $cleanName = $capName.Replace("*", "") 

        $results += [PSCustomObject]@{
            UIDisplayName = "FOD: $cleanName"
            IsDetected    = $isDetected
            ActionData    = $found
        }
    }
    return $results
}

function Get-GarbageCollectorState {
    $allPackages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $standardApps = $allPackages | Where-Object { $_.IsFramework -eq $false }
    
    $activeDependencies = @()
    foreach ($app in $standardApps) { 
        if ($app.Dependencies) { foreach ($dep in $app.Dependencies) { $activeDependencies += $dep.PackageFullName } } 
    }
    $activeDependencies = $activeDependencies | Select-Object -Unique
    
    $critical = "Microsoft.VCLibs|Microsoft.NET.Native|Microsoft.UI.Xaml|Microsoft.WinJS|Microsoft.Services.Store|Microsoft.WindowsAppRuntime|Microsoft.AIFabric|Microsoft.Windows.AugLoop"
    $frameworks = $allPackages | Where-Object { $_.IsFramework -eq $true -and $_.Name -notmatch $critical }
    
    $results = @()
    foreach ($fw in $frameworks) { 
        if ($fw.PackageFullName -notin $activeDependencies) { 
            $results += [PSCustomObject]@{
                UIDisplayName = "Orphaned Framework: $($fw.Name)"
                IsDetected    = $true
                ActionData    = @{ Type = "Framework"; Target = $fw.PackageFullName }
            }
        } 
    }
    
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($prov in $provisioned) { 
        if (-not ($allPackages | Where-Object { $_.Name -eq $prov.DisplayName })) { 
            $results += [PSCustomObject]@{
                UIDisplayName = "Orphaned Base: $($prov.DisplayName)"
                IsDetected    = $true
                ActionData    = @{ Type = "Provisioned"; Target = $prov.PackageName }
            }
        } 
    } 
    return $results
}

function Get-BloatwareState {
    $appList = @(
        "*3DBuilder*", "*3DViewer*", "*Bing*", "*BingNews*", "*BingWeather*", "*Clipchamp*", 
        "*DevHome*", "*PowerAutomateDesktop*", "*Copilot*", "*Store.Engagement*", "*Edge.GameAssist*", 
        "*Family*", "*FeedbackHub*", "*GetHelp*", "*windowscommunicationsapps*", "*WindowsMaps*", 
        "*MixedReality*", "*ZuneVideo*", "*ZuneMusic*", "*Gaming*", "*MicrosoftOfficeHub*", 
        "*OneDriveSync*", "*OneNote*", "*OutlookForWindows*", "*People*", "*Photos*", "*QuickAssist*", 
        "*SkypeApp*", "*SolitaireCollection*", "*MSTeams*", "*MicrosoftTeams*", "*Getstarted*", 
        "*Todos*", "*XboxApp*", "*XboxGamingOverlay*", "*XboxSpeechToTextOverlay*", "*YourPhone*", 
        "*Cortana*", "*WindowsAlarms*", "*SoundRecorder*", "*Client.WebExperience*", "*CrossDevice*", "*StickyNotes*",
        "*CandyCrush*", "*BubbleWitch*", "*FarmHeroes*", "*MarchofEmpires*", "*Homescapes*", "*Township*",
        "*TikTok*", "*Instagram*", "*Facebook*", "*Twitter*", "*LinkedIn*", "*Netflix*", "*Spotify*", 
        "*Disney*", "*Amazon*", "*McAfee*", "*Norton*", "*Lenovo*", "*Dell*", "*HP*"
    )
    
    $installedAppx = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider" }
    $provAppx = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider" }

    $results = @()
    foreach ($app in $appList) {
        $foundInstalled = $installedAppx | Where-Object { $_.Name -like $app }
        $foundProv = $provAppx | Where-Object { $_.DisplayName -like $app }

        $isDetected = ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)
        $cleanName = $app.Replace("*", "") 

        $results += [PSCustomObject]@{
            UIDisplayName = $cleanName
            IsDetected    = $isDetected
            ActionData    = @{ Installed = $foundInstalled; Provisioned = $foundProv }
        }
    }
    return $results
}

# ------------------------------------------
# Z3: REGISTRY AUDITS
# ------------------------------------------
function Get-RegState_Taskbar {
    $rules = @(
        @{ UIDisplayName = "Taskbar: Align to Left (Disables Windows 11 center alignment)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Show Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Search Box (Saves space)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Disable Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Hide Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; Expected = 3; Type = "DWord" }
        @{ UIDisplayName = "Taskbar: Enable 'End Task' on right-click (Dev feature)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Enforce Classic Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Web Search (Forces local-only, faster search)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Hide Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Start Menu: Disable Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Widgets: Disable News & Interests (Saves RAM/Network)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Bloat: Disable Consumer Features (Stops auto-installing apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Expected = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Explorer {
    $rules = @(
        @{ UIDisplayName = "Explorer: Open to 'This PC' instead of Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show hidden files and folders"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Show known file extensions (Security)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Run folder windows in a separate process (Stability)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "SeparateProcess"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Expand navigation pane to current folder"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "NavPaneExpandToCurrentFolder"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Explorer: Hide Cloud Files in Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = "ShowCloudFilesInQuickAccess"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Context Menu: Restore Classic Win10 Style"; Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"; Name = ""; Expected = ""; Type = "String" }
        @{ UIDisplayName = "Desktop: Hide 'Control Panel' Icon"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Desktop: Hide 'Control Panel' Icon (Classic)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (64-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Nav Pane: Unpin OneDrive (32-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "UI: Reduce Menu Show Delay from 400ms to 50ms"; Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; Expected = "50"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Annoyances {
    $rules = @(
        @{ UIDisplayName = "Security: Disable AutoPlay for all drives"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; Expected = 255; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Autoplay Handlers"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"; Name = "DisableAutoplay"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Accessibility: Disable Sticky Keys prompt (Shift x5)"; Path = "HKCU:\Control Panel\Accessibility\StickyKeys"; Name = "Flags"; Expected = "506"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Filter Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"; Name = "Flags"; Expected = "122"; Type = "String" }
        @{ UIDisplayName = "Accessibility: Disable Toggle Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\ToggleKeys"; Name = "Flags"; Expected = "58"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Privacy {
    $rules = @()
    $rules += @{ UIDisplayName = "Privacy: Block OS Telemetry & Data Collection"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable App Advertising ID"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Timeline & Activity History tracking"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Tailored Experiences"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Disable Cloud Speech Recognition"; Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Privacy: Restrict Implicit Ink/Text Collection"; Path = "HKCU:\Software\Microsoft\InputPersonalization"; Name = "RestrictImplicitInkCollection"; Expected = 1; Type = "DWord" }
    $rules += @{ UIDisplayName = "Background Apps: Block UWP apps from running globally"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; Expected = 1; Type = "DWord" }
    
    $uwpBlocks = @("LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo")
    foreach ($app in $uwpBlocks) { $rules += @{ UIDisplayName = "UWP Permissions: Block $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; Expected = 2; Type = "DWord" } }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessCamera"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessCamera"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "UWP Permissions: Block LetAppsAccessMicrophone"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = "LetAppsAccessMicrophone"; Expected = 0; Type = "DWord" }
    
    $rules += @{ UIDisplayName = "Edge: Disable Startup Boost (Background Process)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Edge: Disable Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; Expected = 0; Type = "DWord" }
    $rules += @{ UIDisplayName = "Defender: Prevent automatic sample submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; Expected = 2; Type = "DWord" }
    
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rules += @{ UIDisplayName = "Junk Blocker: Disable Content Delivery ($k)"; Path = $cdm; Name = $k; Expected = 0; Type = "DWord" } }

    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_SystemBoot {
    $rules = @(
        @{ UIDisplayName = "Boot: Disable Fast Startup (Prevents kernel hibernation bugs)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Security: Block BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "System: Block OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable Remote Desktop (RDP) access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "System: Disable Insider Preview Builds"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"; Name = "AllowBuildPreview"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Boot: Enable Verbose Status Messages"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "verbosestatus"; Expected = 1; Type = "DWord" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Mouse {
    $rules = @(
        @{ UIDisplayName = "Mouse: Disable 'Enhance pointer precision' (Raw Input)"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseSpeed"; Expected = "0"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 1"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold1"; Expected = "0"; Type = "String" }
        @{ UIDisplayName = "Mouse: Disable Acceleration Threshold 2"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold2"; Expected = "0"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

function Get-RegState_Gaming {
    $rules = @(
        @{ UIDisplayName = "Gaming: Disable Xbox GameDVR (Reduces stuttering)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Disable GameDVR Store Config"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Optimize FullScreen Exclusive Behavior"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; Expected = 2; Type = "DWord" }
        @{ UIDisplayName = "Gaming: Enable Hardware Accelerated GPU Scheduling (HAGS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; Expected = 2; ValidValues = @(2, $null); Type = "DWord" }
        @{ UIDisplayName = "Kernel: Disable Paging Executive (Keeps core system in RAM)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "Security: Disable VBS / Hypervisor Code Integrity (Massive FPS boost)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "Network: Remove MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; Expected = 4294967295; Type = "DWord" }
        @{ UIDisplayName = "MMCSS: System Responsiveness (Allocate 100% CPU to Games)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; Expected = 0; Type = "DWord" }
        @{ UIDisplayName = "CPU: Optimize Priority Separation (Focus CPU on foreground)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; Expected = 40; Type = "DWord" }
        @{ UIDisplayName = "Power: Disable Windows Power Throttling globally"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; Expected = 1; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: GPU Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; Expected = 8; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Priority (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; Expected = 6; Type = "DWord" }
        @{ UIDisplayName = "MMCSS Profile: Scheduling Category (High)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; Expected = "High"; Type = "String" }
    )
    return Invoke-RegistryAudit -Rules $rules
}

# ------------------------------------------
# Z4: SERVICES & TASKS AUDITS
# ------------------------------------------
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
    } else { Write-GUI "[OK] All targeted telemetry tasks are disabled." } 
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

function Audit-Power { 
    Write-GUI "--- AUDIT: Power Profile ---"; $err = 0
    $hiber = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue
    if ($hiber -and $hiber.HibernateEnabled -eq 0) { Write-GUI "  [OK] Hibernation (Disabled)" } else { Write-GUI "  [!] Hibernation (Likely active)"; $err++ }
    $err += Assert-Power "SUB_SLEEP" "STANDBYIDLE" 999999 "System Sleep"
    $err += Assert-Power "SUB_VIDEO" "VIDEOIDLE" 3600 "Display Turn Off"
    Write-GUI "-> STATUS: $err issues with power profile." 
}

function Audit-Network { Write-GUI "--- AUDIT: Nagle's Algorithm ---"; $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}; $err=0; foreach ($a in $adapters) { $p = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($a.SettingID)"; $val = (Get-ItemProperty -Path $p -Name "TCPNoDelay" -ErrorAction SilentlyContinue).TCPNoDelay; if ($val -eq 1) { Write-GUI "  [OK] $($a.Description)" } else { Write-GUI "  [!] $($a.Description) (Missing TCPNoDelay)"; $err++ } }; Write-GUI "-> STATUS: $err network adapters without optimization." }

function Get-ServicesState_Light {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (wuqisvc)"; Name = "wuqisvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Windows Health Service (whesvc)"; Name = "whesvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4 }
        @{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

function Get-ServicesState_Heavy {
    $rules = @(
        @{ UIDisplayName = "Telemetry: Connected User Experiences (DiagTrack)"; Name = "DiagTrack"; ExpectedStart = 4 }
        @{ UIDisplayName = "Updates: Windows Update Medic Service (wuqisvc)"; Name = "wuqisvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Windows Health Service (whesvc)"; Name = "whesvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Maps: Downloaded Maps Manager (MapsBroker)"; Name = "MapsBroker"; ExpectedStart = 4 }
        @{ UIDisplayName = "Retail: Retail Demo Service (RetailDemo)"; Name = "RetailDemo"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Program Compatibility Assistant (PcaSvc)"; Name = "PcaSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Edge: Edge Update Service (edgeupdate)"; Name = "edgeupdate"; ExpectedStart = 4 }
        @{ UIDisplayName = "Edge: Edge Update Service M (edgeupdatem)"; Name = "edgeupdatem"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Device Inventory Service (InventorySvc)"; Name = "InventorySvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Networking: Connected Devices Platform (CDPSvc)"; Name = "CDPSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Location: Geolocation Service (lfsvc)"; Name = "lfsvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Performance: SysMain / Superfetch - Disables RAM caching (SysMain)"; Name = "SysMain"; ExpectedStart = 4 }
        @{ UIDisplayName = "Virtualization: Windows Subsystem for Linux (WSLService)"; Name = "WSLService"; ExpectedStart = 4 }
        @{ UIDisplayName = "AI: Windows AI Fabric Service (WSAIFabricSvc)"; Name = "WSAIFabricSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Printers: Print Spooler - Disables all printing (Spooler)"; Name = "Spooler"; ExpectedStart = 4 }
        @{ UIDisplayName = "Printers: Print Notify Service (PrintNotify)"; Name = "PrintNotify"; ExpectedStart = 4 }
        @{ UIDisplayName = "Printers: Fax Service (Fax)"; Name = "Fax"; ExpectedStart = 4 }
        @{ UIDisplayName = "Remote: Remote Desktop Services (TermService)"; Name = "TermService"; ExpectedStart = 4 }
        @{ UIDisplayName = "Remote: Remote Registry (RemoteRegistry)"; Name = "RemoteRegistry"; ExpectedStart = 4 }
        @{ UIDisplayName = "Biometrics: Windows Biometric Service (WbioSrvc)"; Name = "WbioSrvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Sensors: Sensor Data Service (SensorDataService)"; Name = "SensorDataService"; ExpectedStart = 4 }
        @{ UIDisplayName = "Sensors: Sensor Service (SensorService)"; Name = "SensorService"; ExpectedStart = 4 }
        @{ UIDisplayName = "Sensors: Sensor Monitoring Service (SensrSvc)"; Name = "SensrSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Mobile: Phone Service (PhoneSvc)"; Name = "PhoneSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Network: Windows Mobile Hotspot Service (icssvc)"; Name = "icssvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Network: WWAN AutoConfig (WwanSvc)"; Name = "WwanSvc"; ExpectedStart = 4 }
        @{ UIDisplayName = "Search: Windows Search - Disables file indexing (WSearch)"; Name = "WSearch"; ExpectedStart = 4 }
        @{ UIDisplayName = "Networking: Offline Files (CscService)"; Name = "CscService"; ExpectedStart = 4 }
        @{ UIDisplayName = "Network: Internet Connection Sharing (SharedAccess)"; Name = "SharedAccess"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: WAP Push Message Routing (dmwappushservice)"; Name = "dmwappushservice"; ExpectedStart = 4 }
        @{ UIDisplayName = "Telemetry: Windows Error Reporting (wermgr)"; Name = "wermgr"; ExpectedStart = 4 }
        
        @{ UIDisplayName = "Xbox: Xbox Live Auth Manager [Manual] (XblAuthManager)"; Name = "XblAuthManager"; ExpectedStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Game Save [Manual] (XblGameSave)"; Name = "XblGameSave"; ExpectedStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Live Networking Service [Manual] (XboxNetApiSvc)"; Name = "XboxNetApiSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Xbox: Xbox Accessory Management [Manual] (XboxGipSvc)"; Name = "XboxGipSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server [Manual] (FrameServer)"; Name = "FrameServer"; ExpectedStart = 3 }
        @{ UIDisplayName = "Camera: Windows Camera Frame Server Monitor [Manual] (FrameServerMonitor)"; Name = "FrameServerMonitor"; ExpectedStart = 3 }
    )
    return Invoke-ServicesAudit -Rules $rules
}

# ------------------------------------------
# GLOBAL: RESCUE AUDITS
# ------------------------------------------
function Get-RescueState_Registry {
    $rescueRules = @()
    $rescueRules += @{ UIDisplayName = "Restore: Centered Taskbar Alignment"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "TaskbarAl"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Hide Seconds in Clock"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowSecondsInSystemClock"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Show Taskbar Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Dynamic Search Box"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name = "IsDynamicSearchBoxEnabled"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Task View Button"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideTaskViewButton"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Teams Chat Icon"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"; Name = "ChatIcon"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Remove 'End Task' from Taskbar"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name = "TaskbarEndTask"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Default Start Menu Layout"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Start_Layout"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Start Menu Web Search Suggestions"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "DisableSearchBoxSuggestions"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Start Menu Recommended Section"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Recent Docs History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "NoRecentDocsHistory"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: News & Interests Widgets"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Windows Consumer Features (Sponsored Apps)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Explorer opens to Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "LaunchTo"; DefaultValue = 2; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Hide hidden files and folders"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"; DefaultValue = 2; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Hide known file extensions"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Default Explorer Process Mode"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "SeparateProcess"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Do not expand navigation pane"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "NavPaneExpandToCurrentFolder"; DefaultValue = 0; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Show Cloud Files in Quick Access"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"; Name = "ShowCloudFilesInQuickAccess"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Windows 11 Default Context Menu"; Path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"; Name = "DeleteEntireKey"; DefaultValue = $null; Type = "DeleteKey" }
    $rescueRules += @{ UIDisplayName = "Restore: Desktop 'Control Panel' Icon (New)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Desktop 'Control Panel' Icon (Classic)"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu"; Name = "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: OneDrive Pin (64-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: OneDrive Pin (32-bit shell)"; Path = "Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"; Name = "System.IsPinnedToNameSpaceTree"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Default Menu Show Delay (400ms)"; Path = "HKCU:\Control Panel\Desktop"; Name = "MenuShowDelay"; DefaultValue = "400"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: AutoPlay for all drives"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "NoDriveTypeAutoRun"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Autoplay Handlers"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers"; Name = "DisableAutoplay"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Sticky Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\StickyKeys"; Name = "Flags"; DefaultValue = "510"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: Filter Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\Keyboard Response"; Name = "Flags"; DefaultValue = "126"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: Toggle Keys prompt"; Path = "HKCU:\Control Panel\Accessibility\ToggleKeys"; Name = "Flags"; DefaultValue = "63"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: OS Telemetry & Data Collection (AllowTelemetry)"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: App Advertising ID"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Timeline & Activity History"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name = "PublishUserActivities"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Tailored Experiences"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Cloud Speech Recognition"; Path = "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"; Name = "HasAccepted"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Implicit Ink/Text Collection"; Path = "HKCU:\Software\Microsoft\InputPersonalization"; Name = "RestrictImplicitInkCollection"; DefaultValue = 0; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Background Apps Global Execution"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"; Name = "GlobalUserDisabled"; DefaultValue = 0; Type = "DWord" }
    
    $uwpBlocks = @("LetAppsActivateWithVoice", "LetAppsAccessNotifications", "LetAppsAccessCallHistory", "LetAppsAccessPhone", "LetAppsAccessMessaging", "LetAppsAccessEmail", "LetAppsAccessContacts", "LetAppsAccessDocuments", "LetAppsAccessDownloads", "LetAppsAccessMusic", "LetAppsAccessPictures", "LetAppsAccessVideos", "LetAppsAccessFileSystem", "LetAppsAccessLocation", "LetAppsAccessMotion", "LetAppsAccessRadios", "LetAppsAccessTrustedDevices", "LetAppsSyncWithDevices", "LetAppsAccessDiagnostics", "LetAppsAccessTasks", "LetAppsAccessCalendar", "LetAppsAccessAccountInfo", "LetAppsAccessCamera", "LetAppsAccessMicrophone")
    foreach ($app in $uwpBlocks) { $rescueRules += @{ UIDisplayName = "Restore UWP Permission: $app"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy"; Name = $app; DefaultValue = $null; Type = "Delete" } }
    
    $rescueRules += @{ UIDisplayName = "Restore: Edge Startup Boost"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "StartupBoostEnabled"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Edge Background Mode"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name = "BackgroundModeEnabled"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Defender Automatic Sample Submission"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet"; Name = "SubmitSamplesConsent"; DefaultValue = 1; Type = "DWord" }
    
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { $rescueRules += @{ UIDisplayName = "Restore Content Delivery: $k"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = $k; DefaultValue = $null; Type = "Delete" } }

    $rescueRules += @{ UIDisplayName = "Restore: Fast Startup / Hibernation"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name = "HiberbootEnabled"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: BIOS/UEFI Software Injections (WPBT)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"; Name = "DisableWpbtExecution"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: OneDrive File Sync Integration"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"; Name = "DisableFileSyncNGSC"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Remote Desktop (RDP) Access"; Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = "fDenyTSConnections"; DefaultValue = 0; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Insider Preview Builds"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds"; Name = "AllowBuildPreview"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Default Boot Status Messages"; Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "verbosestatus"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: 'Enhance pointer precision' (Mouse Acceleration)"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseSpeed"; DefaultValue = "1"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: Mouse Acceleration Threshold 1"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold1"; DefaultValue = "6"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: Mouse Acceleration Threshold 2"; Path = "HKCU:\Control Panel\Mouse"; Name = "MouseThreshold2"; DefaultValue = "10"; Type = "String" }
    $rescueRules += @{ UIDisplayName = "Restore: Xbox GameDVR"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: GameDVR Store Config"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; DefaultValue = 1; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: FullScreen Exclusive Behavior"; Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_FSEBehavior"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Hardware Accelerated GPU Scheduling (HAGS)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; Name = "HwSchMode"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: Paging Executive (Default Memory Management)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"; Name = "DisablePagingExecutive"; DefaultValue = 0; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: VBS / Hypervisor Code Integrity"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"; Name = "Enabled"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: MMCSS Network Throttling Index"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "NetworkThrottlingIndex"; DefaultValue = 10; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: System Responsiveness (20%)"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; Name = "SystemResponsiveness"; DefaultValue = 20; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: CPU Priority Separation (Windows Default)"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"; Name = "Win32PrioritySeparation"; DefaultValue = 2; Type = "DWord" }
    $rescueRules += @{ UIDisplayName = "Restore: Windows Power Throttling"; Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"; Name = "PowerThrottlingOff"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: MMCSS Profile GPU Priority"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "GPU Priority"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: MMCSS Profile Priority"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Priority"; DefaultValue = $null; Type = "Delete" }
    $rescueRules += @{ UIDisplayName = "Restore: MMCSS Profile Scheduling Category"; Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"; Name = "Scheduling Category"; DefaultValue = $null; Type = "Delete" }

    $results = @()
    foreach ($rule in $rescueRules) {
        $isDetected = $false
        
        if ($rule.Type -eq "DeleteKey") {
            if (Test-Path $rule.Path) { $isDetected = $true }
        } elseif ($rule.Type -eq "Delete") {
            $currentValue = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
            if ($null -ne $currentValue) { $isDetected = $true }
        } else {
            $currentValue = (Get-ItemProperty -Path $rule.Path -Name $rule.Name -ErrorAction SilentlyContinue).$($rule.Name)
            if ($null -ne $currentValue -and [string]$currentValue -ne [string]$rule.DefaultValue) { 
                $isDetected = $true 
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

function Get-RescueState_Services {
    $rules = @(
        @{ UIDisplayName = "Restore Service: SysMain / Superfetch [Automatic]"; Name = "SysMain"; ExpectedStart = 2 }
        @{ UIDisplayName = "Restore Service: Print Spooler [Automatic]"; Name = "Spooler"; ExpectedStart = 2 }
        @{ UIDisplayName = "Restore Service: Windows Search [Automatic]"; Name = "WSearch"; ExpectedStart = 2 }
        @{ UIDisplayName = "Restore Service: Connected User Experiences [Automatic]"; Name = "DiagTrack"; ExpectedStart = 2 }
        @{ UIDisplayName = "Restore Service: Program Compatibility Assistant [Automatic]"; Name = "PcaSvc"; ExpectedStart = 2 }
        @{ UIDisplayName = "Restore Service: Downloaded Maps Manager [Manual]"; Name = "MapsBroker"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Retail Demo Service [Manual]"; Name = "RetailDemo"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Edge Update Service [Manual]"; Name = "edgeupdate"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Edge Update Service M [Manual]"; Name = "edgeupdatem"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Device Inventory Service [Manual]"; Name = "InventorySvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Connected Devices Platform [Manual]"; Name = "CDPSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Geolocation Service [Manual]"; Name = "lfsvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows Subsystem for Linux [Manual]"; Name = "WSLService"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows AI Fabric Service [Manual]"; Name = "WSAIFabricSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Print Notify Service [Manual]"; Name = "PrintNotify"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Fax Service [Manual]"; Name = "Fax"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Remote Desktop Services [Manual]"; Name = "TermService"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Remote Registry [Manual]"; Name = "RemoteRegistry"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows Biometric Service [Manual]"; Name = "WbioSrvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Xbox Live Auth Manager [Manual]"; Name = "XblAuthManager"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Xbox Live Game Save [Manual]"; Name = "XblGameSave"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Xbox Live Networking [Manual]"; Name = "XboxNetApiSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Xbox Accessory Management [Manual]"; Name = "XboxGipSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Sensor Data Service [Manual]"; Name = "SensorDataService"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Sensor Service [Manual]"; Name = "SensorService"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Sensor Monitoring Service [Manual]"; Name = "SensrSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Phone Service [Manual]"; Name = "PhoneSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows Mobile Hotspot [Manual]"; Name = "icssvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: WWAN AutoConfig [Manual]"; Name = "WwanSvc"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows Camera Frame Server [Manual]"; Name = "FrameServer"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Camera Frame Server Monitor [Manual]"; Name = "FrameServerMonitor"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Offline Files [Manual]"; Name = "CscService"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Internet Connection Sharing [Manual]"; Name = "SharedAccess"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: WAP Push Message Routing [Manual]"; Name = "dmwappushservice"; ExpectedStart = 3 }
        @{ UIDisplayName = "Restore Service: Windows Error Reporting [Manual]"; Name = "wermgr"; ExpectedStart = 3 }
    )
    return Invoke-ServicesAudit -Rules $rules
}