# ==========================================
# OPTIMIZER_RESTORE_EN.PS1 - RESCUE MODULE
# ==========================================

function Remove-RegVal { 
    param($Path, $Name)
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue | Out-Null } 
}

function Restore-ServicesLight {
    Write-GUI "--- RESCUE: Restoring Windows Services ---"
    $svcsAuto = @("SysMain", "Spooler", "WSearch", "DiagTrack", "PcaSvc")
    $svcsManual = @("MapsBroker", "RetailDemo", "edgeupdate", "edgeupdatem", "InventorySvc", "CDPSvc", "lfsvc", "WSLService", "WSAIFabricSvc", "PrintNotify", "Fax", "TermService", "RemoteRegistry", "WbioSrvc", "XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc", "SensorDataService", "SensorService", "SensrSvc", "PhoneSvc", "icssvc", "WwanSvc", "FrameServer", "FrameServerMonitor", "CscService", "SharedAccess", "dmwappushservice", "wermgr")
    
    foreach ($svc in $svcsAuto) { 
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
        if (Test-Path $regPath) { Set-ItemProperty -Path $regPath -Name "Start" -Value 2 -Type DWord -ErrorAction SilentlyContinue; Write-GUI "  -> $svc [Automatic]" } 
    }
    foreach ($svc in $svcsManual) { 
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
        if (Test-Path $regPath) { Set-ItemProperty -Path $regPath -Name "Start" -Value 3 -Type DWord -ErrorAction SilentlyContinue; Write-GUI "  -> $svc [Manual]" } 
    }
}

function Restore-Registry {
    Write-GUI "--- RESCUE: Reverting all Registry changes ---"
    
    # 1. Taskbar and Start Menu
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures"
    Set-RegKey "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 1
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_Layout"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "SearchboxTaskbarMode"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" "IsDynamicSearchBoxEnabled"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideTaskViewButton"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" "HideRecommendedSection"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon"
    Write-GUI "  -> [OK] Taskbar and Start Menu restored."

    # 2. File Explorer
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" "{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "SeparateProcess"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "NavPaneExpandToCurrentFolder"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowCloudFilesInQuickAccess"
    Set-RegKey "Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" "System.IsPinnedToNameSpaceTree" 1
    Set-RegKey "HKCU:\Control Panel\Desktop" "MenuShowDelay" "400" "String"
    $contextKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    if (Test-Path $contextKey) { Remove-Item -Path $contextKey -Recurse -Force -ErrorAction SilentlyContinue }
    Write-GUI "  -> [OK] File Explorer and default Windows 11 context menu."

    # 3. OS Annoyances
    Remove-RegVal "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoDriveTypeAutoRun"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay"
    Set-RegKey "HKCU:\Control Panel\Accessibility\StickyKeys" "Flags" "510" "String"
    Set-RegKey "HKCU:\Control Panel\Accessibility\Keyboard Response" "Flags" "126" "String"
    Set-RegKey "HKCU:\Control Panel\Accessibility\ToggleKeys" "Flags" "63" "String"
    Write-GUI "  -> [OK] AutoPlay and Sticky Keys."

    # 4. Privacy, Telemetry, Edge and ContentDeliveryManager
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled"
    Remove-RegVal "HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" "HasAccepted"
    Remove-RegVal "HKCU:\Software\Microsoft\Input\TIPC" "Enabled"
    Remove-RegVal "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection"
    Remove-RegVal "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection"
    Remove-RegVal "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts"
    Remove-RegVal "HKCU:\Software\Microsoft\Personalization\Settings" "AcceptedPrivacyPolicy"
    Remove-RegVal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities"
    Remove-RegVal "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod"
    
    # Reverting ContentDeliveryManager and background installations
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    $cdmKeys = @("OemPreInstalledAppsEnabled", "PreInstalledAppsEnabled", "SilentInstalledAppsEnabled", "ContentDeliveryAllowed", "FeatureManagementEnabled", "PreInstalledAppsEverEnabled", "SoftLandingEnabled", "SubscribedContentEnabled", "SystemPaneSuggestionsEnabled", "SubscribedContent-310093Enabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")
    foreach ($k in $cdmKeys) { Remove-RegVal $cdm $k }
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\PushToInstall" "DisablePushToInstall"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\MRT" "DontOfferThroughWUAU"

    # Reverting Defender and PowerShell blocks
    Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', $null, 'Machine')
    
    $edgeKeys = @("StartupBoostEnabled", "BackgroundModeEnabled", "CreateDesktopShortcutDefault", "PersonalizationReportingEnabled", "ShowRecommendationsEnabled", "UserFeedbackAllowed", "AlternateErrorPagesEnabled", "EdgeCollectionsEnabled", "EdgeShoppingAssistantEnabled", "MicrosoftEdgeInsiderPromotionEnabled", "ShowMicrosoftRewards", "WebWidgetAllowed", "DiagnosticData", "EdgeAssetDeliveryServiceEnabled", "WalletDonationEnabled", "DefaultBrowserSettingsCampaignEnabled", "HideFirstRunExperience", "ConfigureDoNotTrack")
    foreach ($k in $edgeKeys) { Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Edge" $k }
    
    Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Recurse -ErrorAction SilentlyContinue
    Write-GUI "  -> [OK] Telemetry, Profiling, Edge, and Junk Blockers."

    # 5. Boot and WPBT
    Remove-RegVal "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" "DisableWpbtExecution"
    Set-RegKey "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 1
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PreviewBuilds" "AllowBuildPreview"
    Remove-RegVal "HKLM:\System\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections"
    Remove-RegVal "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "verbosestatus"
    Write-GUI "  -> [OK] Fast Boot, BIOS WPBT, and RDP settings."

    # 6. Mouse
    Set-RegKey "HKCU:\Control Panel\Mouse" "MouseSpeed" "1" "String"
    Set-RegKey "HKCU:\Control Panel\Mouse" "MouseThreshold1" "6" "String"
    Set-RegKey "HKCU:\Control Panel\Mouse" "MouseThreshold2" "10" "String"
    Write-GUI "  -> [OK] 'Enhance pointer precision' restored."

    # 7. Hardware and Gaming
    Remove-RegVal "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\ApplicationManagement\AllowGameDVR" "value"
    Remove-RegVal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR"
    Set-RegKey "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 1
    Remove-RegVal "HKCU:\System\GameConfigStore" "GameDVR_FSEBehavior"
    Remove-RegVal "HKCU:\System\GameConfigStore" "GameDVR_FSEBehaviorMode"
    Remove-RegVal "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode"
    Set-RegKey "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 0
    Remove-RegVal "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled"
    Remove-RegVal "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex"
    Set-RegKey "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" 20
    Set-RegKey "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 2
    Remove-RegVal "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff"
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" -Recurse -ErrorAction SilentlyContinue
    Write-GUI "  -> [OK] MMCSS priorities, HAGS, GameDVR."
    
    Write-GUI "-> Changes successfully reverted. System restart recommended."
}