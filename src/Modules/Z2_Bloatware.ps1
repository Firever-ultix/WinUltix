# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE (v3.0.0)
# Z2_Bloatware: Aggressive debloatifier. Uses Core_Helpers profile/hive discovery (Get-UltixUserProfiles), fast .NET directory sizing (Get-UltixFastSize), and asynchronous Runspace workers ($UltixSync) to amputate OneDrive, remove FOD Capabilities, clean orphaned Appx frameworks, lock down Windows Recall/AI, and purge UWP bloatware.
# ==========================================

# ------------------------------------------
# Z2: BLOATWARE AUDITS (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-OneDriveState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $userProfiles = @(Get-UltixUserProfiles)
    $loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded })

    # Fallback to HKCU if no loaded SID hives were returned
    if ($loadedHives.Count -eq 0) {
        $loadedHives = @(
            [PSCustomObject]@{
                SID          = "CurrentUser"
                UserName     = $env:USERNAME
                LocalPath    = $env:USERPROFILE
                HiveRoot     = "HKCU:"
                IsHiveLoaded = $true
            }
        )
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 30 }

    # 1. Core Executables & Multi-Profile Run Keys (SystemRoot stubs are left dormant for SFC/DISM integrity)
    $localExe  = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    $liveProc  = Get-Process -Name "OneDrive", "OneDriveSetup" -ErrorAction SilentlyContinue
    $hasRunKey = $false

    foreach ($hive in $loadedHives) {
        $runPath = "$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path -Path $runPath) {
            $runProps = Get-ItemProperty -Path $runPath -ErrorAction SilentlyContinue
            if ($null -ne $runProps -and ($runProps.PSObject.Properties.Match("OneDriveSetup").Count -gt 0 -or $runProps.PSObject.Properties.Match("OneDrive").Count -gt 0)) {
                $hasRunKey = $true
                break
            }
        }
    }

    foreach ($prof in $userProfiles) {
        if ($hasRunKey) { break }
        if (Test-Path -Path (Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive\OneDrive.exe")) {
            $hasRunKey = $true
            break
        }
    }

    $isCoreDetected = ((Test-Path -Path $localExe) -or $hasRunKey -or ($null -ne $liveProc))

    $results.Add([PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup and Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }

    # 2. Multi-Profile Zombie Registry Keys (Inspected across all loaded HKEY_USERS\<SID> hives)
    $zombieSubKeys = @("SyncEngine", "Client_Policy", "Accounts")
    foreach ($hive in $loadedHives) {
        foreach ($subKey in $zombieSubKeys) {
            $fullRegPath = "$($hive.HiveRoot)\Software\Microsoft\OneDrive\$subKey"
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Registry ($($hive.UserName)): $subKey"
                IsDetected    = (Test-Path -Path $fullRegPath)
                ActionData    = @{ Type = "Registry"; Path = $fullRegPath }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }

    # 3. System Data Folders
    $staticFolders = @("$env:PROGRAMDATA\Microsoft OneDrive", "$env:SystemDrive\OneDriveTemp")
    foreach ($folder in $staticFolders) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Folder: $folder"
            IsDetected    = (Test-Path -Path $folder)
            ActionData    = @{ Type = "Folder"; Path = $folder }
        })
    }

    # 4. Dynamic User Profiles Data Folders (Zero hardcoded C:\Users)
    foreach ($prof in $userProfiles) {
        $userPath = Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
        $results.Add([PSCustomObject]@{
            UIDisplayName = "User Data: $($prof.UserName)"
            IsDetected    = (Test-Path -Path $userPath)
            ActionData    = @{ Type = "Folder"; Path = $userPath }
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-CapabilitiesState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 15 }
    $capsWildcards = @(
        "*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*",
        "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*",
        "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*",
        "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*",
        "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*"
    )

    $installedCaps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Installed' })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 65 }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $total   = $capsWildcards.Count
    $idx     = 0

    foreach ($capName in $capsWildcards) {
        $idx++
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 65 + [int](($idx / $total) * 35)
        }
        $found      = @($installedCaps | Where-Object { $_.Name -like $capName })
        $isDetected = ($found.Count -gt 0)
        $cleanName  = $capName.Replace("*", "")

        $results.Add([PSCustomObject]@{
            UIDisplayName = "FOD: $cleanName"
            IsDetected    = $isDetected
            ActionData    = $found
        })
    }
    return $results
}

function Get-GarbageCollectorState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if ($null -ne $UltixSync) { $UltixSync.Progress = 35 }

    # Complete protected framework & shared system UI whitelist (Win11 24H2/25H2/26H2 + Gaming Identity)
    $critical = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|MicrosoftWindows\.Client|MicrosoftWindows\.CrossDevice|Windows\.CBSPreview|Windows\.PrintDialog|Microsoft\.AsyncTextService|Microsoft\.AccountsControl|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.BioEnrollment|ApplicationCompatibilityEnhancements|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension"

    # 1. Seed active dependencies from all non-framework packages (including NonRemovable SystemApps and ResourcePackages)
    $rootPackages       = @($allPackages | Where-Object { $_.IsFramework -eq $false -or $_.IsResourcePackage -eq $true -or $_.NonRemovable -eq $true -or $_.Name -match $critical })
    $activeDependencies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installedNames     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pkg in $allPackages) {
        if (-not [string]::IsNullOrWhiteSpace($pkg.Name)) {
            [void]$installedNames.Add($pkg.Name)
        }
    }

    foreach ($app in $rootPackages) {
        if ($app.Dependencies) {
            foreach ($dep in $app.Dependencies) {
                if (-not [string]::IsNullOrWhiteSpace($dep.PackageFullName)) {
                    [void]$activeDependencies.Add($dep.PackageFullName)
                }
            }
        }
    }

    # 2. Compute transitive closure for Framework -> Framework dependency chains
    $allFrameworks = @($allPackages | Where-Object { $_.IsFramework -eq $true })
    $addedNew = $true
    while ($addedNew) {
        $addedNew = $false
        foreach ($fw in $allFrameworks) {
            if ($activeDependencies.Contains($fw.PackageFullName) -and $fw.Dependencies) {
                foreach ($nestedDep in $fw.Dependencies) {
                    if (-not [string]::IsNullOrWhiteSpace($nestedDep.PackageFullName)) {
                        if ($activeDependencies.Add($nestedDep.PackageFullName)) {
                            $addedNew = $true
                        }
                    }
                }
            }
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 65 }

    # 3. Filter candidate frameworks strictly excluding protected runtimes, non-removable packages, and resource packs
    $candidateFrameworks = @($allFrameworks | Where-Object {
        $_.NonRemovable -eq $false -and
        $_.IsResourcePackage -eq $false -and
        $_.Name -notmatch $critical
    })

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($fw in $candidateFrameworks) {
        if (-not $activeDependencies.Contains($fw.PackageFullName)) {
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Framework: $($fw.Name) ($($fw.Version))"
                IsDetected    = $true
                ActionData    = @{ Type = "Framework"; Target = $fw.PackageFullName }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 85 }

    # 4. Inspect Provisioned packages (shielded by $critical regex)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($prov in $provisioned) {
        if ($prov.DisplayName -match $critical) { continue }
        if (-not $installedNames.Contains($prov.DisplayName)) {
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Base: $($prov.DisplayName)"
                IsDetected    = $true
                ActionData    = @{ Type = "Provisioned"; Target = $prov.PackageName }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-BloatwareState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }

    # Ordered, non-overlapping definitions matching Windows 11 24H2/25H2/26H2 packages
    $appCatalog = @(
        @{ Label = "Windows Recall & AI Snapshots (24H2/25H2/26H2)"; Pattern = "*Recall*|*AIDataAnalysis*"; IsRecall = $true }
        @{ Label = "Windows Copilot & AI Assistant";              Pattern = "*Copilot*" }
        @{ Label = "Microsoft Bing Search (BingSearch)";          Pattern = "*BingSearch*" }
        @{ Label = "Microsoft News (BingNews)";                   Pattern = "*BingNews*" }
        @{ Label = "Microsoft Weather (BingWeather)";             Pattern = "*BingWeather*" }
        @{ Label = "Microsoft Finance / Sports / Food (Bing)";    Pattern = "Microsoft.BingFinance|Microsoft.BingSports|Microsoft.BingFoodAndDrink|Microsoft.BingTravel|Microsoft.BingHealthAndFitness|Microsoft.BingTranslator" }
        @{ Label = "Microsoft To Do (Todos)";                     Pattern = "*Todos*" }
        @{ Label = "Microsoft Sticky Notes (StickyNotes)";        Pattern = "*StickyNotes*" }
        @{ Label = "Microsoft Teams Personal / Work (MSTeams)";   Pattern = "*MSTeams*|*MicrosoftTeams*" }
        @{ Label = "New Outlook for Windows (OutlookForWindows)"; Pattern = "*OutlookForWindows*" }
        @{ Label = "Mail & Calendar (CommunicationsApps)";        Pattern = "*windowscommunicationsapps*" }
        @{ Label = "Microsoft 365 / Office Hub";                  Pattern = "*MicrosoftOfficeHub*" }
        @{ Label = "Microsoft OneNote (UWP)";                     Pattern = "*OneNote*" }
        @{ Label = "Microsoft Family Safety";                     Pattern = "*MicrosoftFamily*|*Family*" }
        @{ Label = "Microsoft Clipchamp Video Editor";            Pattern = "*Clipchamp*" }
        @{ Label = "Windows Dev Home (DevHome)";                  Pattern = "*DevHome*" }
        @{ Label = "Power Automate Desktop";                      Pattern = "*PowerAutomateDesktop*" }
        @{ Label = "Microsoft Edge Game Assist";                  Pattern = "*Edge.GameAssist*" }
        @{ Label = "Windows Widgets (Client.WebExperience)";      Pattern = "*Client.WebExperience*" }
        @{ Label = "Widgets Platform Runtime";                    Pattern = "*WidgetsPlatformRuntime*" }
        @{ Label = "Cross Device Experience Host";                Pattern = "*CrossDevice*" }
        @{ Label = "Phone Link (YourPhone)";                      Pattern = "*YourPhone*" }
        @{ Label = "Quick Assist (Remote Help)";                  Pattern = "*QuickAssist*" }
        @{ Label = "Windows Feedback Hub";                        Pattern = "*FeedbackHub*" }
        @{ Label = "Get Help (Contact Support)";                  Pattern = "*GetHelp*" }
        @{ Label = "Windows Tips (GetStarted)";                   Pattern = "*Getstarted*" }
        @{ Label = "Windows Maps";                                Pattern = "*WindowsMaps*" }
        @{ Label = "Windows Alarms & Clock";                      Pattern = "*WindowsAlarms*" }
        @{ Label = "Windows Voice Recorder (SoundRecorder)";      Pattern = "*SoundRecorder*" }
        @{ Label = "Windows Camera";                              Pattern = "*WindowsCamera*" }
        @{ Label = "Windows Photos";                              Pattern = "*Windows.Photos*" }
        @{ Label = "Media Player / Groove Music (ZuneMusic)";     Pattern = "*ZuneMusic*" }
        @{ Label = "Movies & TV (ZuneVideo)";                     Pattern = "*ZuneVideo*" }
        @{ Label = "Microsoft Solitaire Collection";              Pattern = "*SolitaireCollection*" }
        @{ Label = "Xbox App (GamingApp)";                        Pattern = "*GamingApp*|*XboxApp*" }
        @{ Label = "Xbox Game Bar (XboxGamingOverlay)";           Pattern = "*XboxGamingOverlay*" }
        @{ Label = "Xbox Speech To Text Overlay";                 Pattern = "*XboxSpeechToTextOverlay*" }
        @{ Label = "Xbox TCUI (Live In-Game Experience)";         Pattern = "*Xbox.TCUI*" }
        @{ Label = "Microsoft People";                            Pattern = "*Microsoft.People*" }
        @{ Label = "Skype UWP";                                   Pattern = "*SkypeApp*" }
        @{ Label = "Cortana";                                     Pattern = "*Cortana*" }
        @{ Label = "Mixed Reality Portal";                        Pattern = "*MixedReality*" }
        @{ Label = "3D Builder & 3D Viewer";                      Pattern = "*3DBuilder*|*3DViewer*" }
        @{ Label = "OneDrive UWP Sync Client";                    Pattern = "*OneDriveSync*" }

        # Third-Party Casual Games (Granular)
        @{ Label = "King: Candy Crush Saga";                      Pattern = "*CandyCrush*" }
        @{ Label = "King: Bubble Witch Saga";                     Pattern = "*BubbleWitch*" }
        @{ Label = "King: Farm Heroes Saga";                      Pattern = "*FarmHeroes*" }
        @{ Label = "Gameloft: March of Empires";                  Pattern = "*MarchofEmpires*" }
        @{ Label = "Playrix: Homescapes";                         Pattern = "*Homescapes*" }
        @{ Label = "Playrix: Township";                           Pattern = "*Township*" }
        @{ Label = "Disney Interactive (Magic Kingdoms / Games)"; Pattern = "*Disney*" }

        # Third-Party Social & Streaming Media (Granular)
        @{ Label = "TikTok";                                      Pattern = "*TikTok*" }
        @{ Label = "Meta: Instagram";                             Pattern = "*Instagram*" }
        @{ Label = "Meta: Facebook";                              Pattern = "*Facebook*" }
        @{ Label = "Twitter / X";                                 Pattern = "*Twitter*" }
        @{ Label = "LinkedIn";                                    Pattern = "*LinkedIn*" }
        @{ Label = "Netflix";                                     Pattern = "*Netflix*" }
        @{ Label = "Spotify Music";                               Pattern = "*Spotify*" }
        @{ Label = "Amazon (Prime Video / Shopping)";             Pattern = "*Amazon*" }

        # OEM Software & Trialware Suites (Granular)
        @{ Label = "McAfee Security Suite";                       Pattern = "*McAfee*" }
        @{ Label = "Norton Security Suite";                       Pattern = "*Norton*" }
        @{ Label = "Lenovo OEM Bloatware & Vantage Stubs";        Pattern = "*Lenovo*" }
        @{ Label = "Dell SupportAssist & OEM Stubs";              Pattern = "*Dell*" }
        @{ Label = "HP Support Assistant & OEM Stubs";            Pattern = "*HP*" }
    )

    # Ironclad whitelist protecting Xbox/Steam identity, core system applets, and AI Fabric/AugLoop runtimes
    $protectedRegex = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|WindowsStore|StorePurchaseApp|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|ApplicationCompatibilityEnhancements|MicrosoftEdge\.Stable"

    $installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }

    $provAppx = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }

    # Query Recall Optional Feature and AI Data Analysis Policy state
    $recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
    $isRecallFeatEnabled = ($null -ne $recallFeature -and ($recallFeature.State -eq 'Enabled' -or $recallFeature.State -eq 'EnablePending'))

    $aiPolPathLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    $aiPolPathCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
    $aiPolValLM  = (Get-ItemProperty -Path $aiPolPathLM -Name "DisableAIDataAnalysis" -ErrorAction SilentlyContinue).DisableAIDataAnalysis
    $aiPolValCU  = (Get-ItemProperty -Path $aiPolPathCU -Name "DisableAIDataAnalysis" -ErrorAction SilentlyContinue).DisableAIDataAnalysis
    $isRecallPolicyLocked = ($aiPolValLM -eq 1 -and $aiPolValCU -eq 1)

    $seenInstalled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenProv      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results       = [System.Collections.Generic.List[PSCustomObject]]::new()

    $totalEntries = $appCatalog.Count
    $entryIdx     = 0

    foreach ($entry in $appCatalog) {
        $entryIdx++
        if ($null -ne $UltixSync) {
            $UltixSync.Progress = 40 + [int](($entryIdx / $totalEntries) * 60)
        }

        $patterns = $entry.Pattern -split '\|'

        $foundInstalled = [System.Collections.Generic.List[object]]::new()
        foreach ($pkg in $installedAppx) {
            if ($seenInstalled.Contains($pkg.PackageFullName)) { continue }
            foreach ($pat in $patterns) {
                if ($pkg.Name -like $pat) {
                    $foundInstalled.Add($pkg)
                    [void]$seenInstalled.Add($pkg.PackageFullName)
                    break
                }
            }
        }

        $foundProv = [System.Collections.Generic.List[object]]::new()
        foreach ($prov in $provAppx) {
            if ($seenProv.Contains($prov.PackageName)) { continue }
            foreach ($pat in $patterns) {
                if ($prov.DisplayName -like $pat) {
                    $foundProv.Add($prov)
                    [void]$seenProv.Add($prov.PackageName)
                    break
                }
            }
        }

        $installLocations = @($foundInstalled | ForEach-Object { $_.InstallLocation } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $totalBytes       = if ($installLocations.Count -gt 0) { Get-UltixFastSize -TargetPaths $installLocations } else { 0 }
        $totalSizeMB      = if ($totalBytes -gt 0) { $totalBytes / 1MB } else { 0 }

        if ($entry.IsRecall) {
            $isDetected = $isRecallFeatEnabled -or (-not $isRecallPolicyLocked) -or ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)
            $sizeLabel  = ""
            if ($isDetected) {
                if ($isRecallFeatEnabled) {
                    $sizeLabel = " [ OptionalFeature: Enabled ]"
                } elseif (-not $isRecallPolicyLocked) {
                    $sizeLabel = " [ AI Policy: Unlocked ]"
                } elseif ($totalSizeMB -ge 0.5) {
                    $sizeLabel = " [ $([math]::Round($totalSizeMB, 1)) MB ]"
                } else {
                    $sizeLabel = " [ Active Trace ]"
                }
            }

            $results.Add([PSCustomObject]@{
                UIDisplayName = "$($entry.Label)$sizeLabel"
                IsDetected    = $isDetected
                ActionData    = @{
                    IsRecall      = $true
                    RecallFeature = $isRecallFeatEnabled
                    Installed     = @($foundInstalled)
                    Provisioned   = @($foundProv)
                }
            })
            continue
        }

        $isDetected = ($foundInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)

        $sizeLabel = ""
        if ($isDetected) {
            if ($totalSizeMB -ge 0.5) {
                $sizeLabel = " [ $([math]::Round($totalSizeMB, 1)) MB ]"
            } elseif ($foundInstalled.Count -gt 0) {
                $sizeLabel = " [ Installed Stub ]"
            } elseif ($foundProv.Count -gt 0) {
                $sizeLabel = " [ Provisioned Image ]"
            }
        }

        $results.Add([PSCustomObject]@{
            UIDisplayName = "$($entry.Label)$sizeLabel"
            IsDetected    = $isDetected
            ActionData    = @{
                IsRecall    = $false
                Installed   = @($foundInstalled)
                Provisioned = @($foundProv)
            }
        })
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

function Get-CapabilityStubState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 20 }
    $cbsStubs = @(Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match "(?i)stub" -and $_.PackageState -eq "Installed" })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 80 }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($stub in $cbsStubs) {
        $cleanName = ($stub.PackageName -split '~')[0]
        $results.Add([PSCustomObject]@{
            UIDisplayName = "CBS Stub: $cleanName"
            IsDetected    = $true
            ActionData    = $stub.PackageName
        })
    }
    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return $results
}

# ------------------------------------------
# Z2: BLOATWARE & APPS ENGINE (ASYNC RUNSPACE EXECUTORS)
# ------------------------------------------
function Invoke-RemoveOneDrive {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No OneDrive components selected. Aborting."; return }

    Write-GUI " -> Engaging asynchronous OneDrive amputation engine (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        # Pre-kill all OneDrive and companion processes holding file/registry handles
        Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            $data = $item.ActionData
            try {
                if ($data.Type -eq "Core") {
                    $setupX64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                    $setupX86 = "$env:SystemRoot\System32\OneDriveSetup.exe"

                    if (Test-Path -Path $setupX64) {
                        Start-Process -FilePath $setupX64 -ArgumentList "/uninstall" -NoNewWindow -Wait
                    } elseif (Test-Path -Path $setupX86) {
                        Start-Process -FilePath $setupX86 -ArgumentList "/uninstall" -NoNewWindow -Wait
                    }

                    Start-Sleep -Seconds 2
                    Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue

                    # Neutralize Run keys across HKCU, HKLM, and all loaded HKEY_USERS\<SID> hives while keeping SystemRoot stub for SFC/DISM
                    $runTargets = [System.Collections.Generic.List[string]]::new()
                    $runTargets.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")

                    foreach ($prof in (Get-UltixUserProfiles)) {
                        if ($prof.IsHiveLoaded) {
                            $sidRun = "$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run"
                            if (Test-Path -Path $sidRun) { $runTargets.Add($sidRun) }
                        }
                    }

                    foreach ($rPath in ($runTargets | Select-Object -Unique)) {
                        if (Test-Path -Path $rPath) {
                            Remove-ItemProperty -Path $rPath -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue
                            Remove-ItemProperty -Path $rPath -Name "OneDrive" -Force -ErrorAction SilentlyContinue
                        }
                    }

                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [+] Core installation payloads purged. Multi-profile Run hooks neutralized (SystemRoot stub preserved for SFC).")
                    }
                }
                elseif ($data.Type -eq "Registry") {
                    if (Test-Path -Path $data.Path) {
                        Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Registry key removed: $($data.Path)") }
                    }
                }
                elseif ($data.Type -eq "Folder") {
                    $targetDir = $data.Path
                    if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
                        & takeown.exe /F "$targetDir" /R /A /D Y 2>$null | Out-Null
                        & icacls.exe "$targetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null

                        # Evacuate memory-mapped shell extensions (e.g., FileSyncShell64.dll locked by explorer.exe)
                        $dllFiles = @(Get-ChildItem -LiteralPath $targetDir -Filter "*.dll" -Recurse -File -Force -ErrorAction SilentlyContinue)
                        foreach ($dll in $dllFiles) {
                            $dllPath = $dll.FullName
                            $dllName = $dll.Name
                            if ([string]::IsNullOrWhiteSpace($dllPath)) { continue }

                            try {
                                $dll.Attributes = 'Normal'
                                Remove-Item -LiteralPath $dllPath -Force -ErrorAction Stop
                            } catch {
                                $trashPath = Join-Path -Path $env:TEMP -ChildPath "WinUltix_Locked_${dllName}_$([guid]::NewGuid().ToString('N')).tmp"
                                Move-Item -LiteralPath $dllPath -Destination $trashPath -Force -ErrorAction SilentlyContinue
                            }
                        }

                        # Strip ReadOnly/Hidden/System attributes from remaining items and wipe directory
                        Get-ChildItem -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Attributes = 'Normal' } catch {}
                        }
                        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue

                        # Final fallback: if directory still exists due to an open directory handle in Explorer, cycle explorer.exe
                        if (Test-Path -LiteralPath $targetDir) {
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [*] Releasing Shell Extension lock via Explorer refresh...") }
                            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 600
                            Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
                            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                                Start-Process "explorer.exe"
                            }
                        }
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Folder eradicated: $targetDir") }
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Selected OneDrive components eliminated.`n"
    }
}

function Invoke-RemoveCapabilities {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }

    Write-GUI " -> Removing selected Windows Capabilities (CBS Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing Capability: $($item.UIDisplayName)")
            }
            foreach ($cap in $item.ActionData) {
                try {
                    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Removed FOD: $($cap.Name)") }
                } catch {
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)") }
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> System features (FOD) removal completed.`n"
    }
}

function Invoke-GarbageCollector {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> System clean or operation aborted."; return }

    Write-GUI " -> Running Appx Garbage Collector (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Cleaning: $($item.UIDisplayName)")
            }
            try {
                if ($item.ActionData.Type -eq "Framework") {
                    Remove-AppxPackage -Package $item.ActionData.Target -AllUsers -ErrorAction Stop
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Removed orphaned framework: $($item.ActionData.Target)") }
                } elseif ($item.ActionData.Type -eq "Provisioned") {
                    Remove-AppxProvisionedPackage -Online -PackageName $item.ActionData.Target -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Deprovisioned orphaned base: $($item.ActionData.Target)") }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Error removing $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Appx Garbage Collector finished its run.`n"
    }
}

function Invoke-RemoveBloatware {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }

    Write-GUI " -> Engaging Aggressive Bloatware & AI Removal (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk", "aixhost" -Force -ErrorAction SilentlyContinue
        Stop-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            # Handle Windows Recall & AI Data Analysis (24H2/25H2/26H2)
            if ($item.ActionData.IsRecall -eq $true -or $item.UIDisplayName -match "(?i)Recall") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Enforcing DisableAIDataAnalysis & TurnOffSavingSnapshots GPO locks...")
                }
                $aiPolicies = @(
                    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI",
                    "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
                )
                foreach ($pol in $aiPolicies) {
                    if (-not (Test-Path -Path $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $pol -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $pol -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }

                if ($item.ActionData.RecallFeature -eq $true) {
                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [*] Stripping Windows Recall Optional Feature payload via CBS...")
                    }
                    try {
                        Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -Remove -NoRestart -ErrorAction Stop | Out-Null
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Windows Recall feature disabled and payload removed.") }
                    } catch {
                        try {
                            Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Windows Recall feature disabled.") }
                        } catch {
                            if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] CBS Recall feature modification skipped: $($_.Exception.Message)") }
                        }
                    }
                }
            }

            # Handle Copilot GPO constraints
            if ($item.UIDisplayName -match "(?i)Copilot") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Applying local policy constraints for Windows Copilot...")
                }
                $policies = @(
                    "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
                    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                )
                foreach ($pol in $policies) {
                    if (-not (Test-Path -Path $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -Path $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }

            # 1. Process Installed Packages (AllUsers + CurrentUser fallback)
            foreach ($pkg in $item.ActionData.Installed) {
                $pfn = $pkg.PackageFamilyName

                try {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    } catch {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    }

                    # Register in Deprovisioned store to prevent Windows Update from reinstalling it
                    if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                        if (-not (Test-Path -Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Removed Appx: $($pkg.Name)") }
                } catch {
                    if ($pkg.Name -match "(?i)Copilot|Recall") {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] API uninstallation blocked for $($pkg.Name). Relying on GPO lockdown.") }
                    } else {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [-] Error removing $($pkg.Name): $($_.Exception.Message)") }
                    }
                }
            }

            # 2. Process Provisioned Packages (Only if still present after Remove-AppxPackage -AllUsers)
            $remainingProv = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
            foreach ($prov in $item.ActionData.Provisioned) {
                $stillProvisioned = $remainingProv | Where-Object { $_.PackageName -eq $prov.PackageName }
                if ($null -eq $stillProvisioned) { continue }

                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Deprovisioned base image: $($prov.DisplayName)") }
                } catch {
                    if ($_.Exception.Message -notmatch "(?i)nie można odnaleźć|cannot find|0x80070002|0x80070003") {
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [-] Error deprovisioning $($prov.DisplayName): $($_.Exception.Message)") }
                    }
                }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> Aggressive Bloatware Removal completed.`n"
    }
}

function Invoke-RemoveCapabilityStubs {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { Write-GUI " -> No stubs selected. Operation aborted."; return }

    Write-GUI " -> Purging selected CBS Stubs (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$SelectedItems) -ScriptBlock {
        param([array]$Items)
        $total   = $Items.Count
        $current = 0

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging CBS Stub: $($item.UIDisplayName)")
            }
            try {
                Remove-WindowsPackage -Online -PackageName $item.ActionData -NoRestart -ErrorAction Stop | Out-Null
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Eradicated stub package: $($item.ActionData)") }
            } catch {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [!] Error purging stub: $($_.Exception.Message)") }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> CBS capability stubs successfully eradicated.`n"
    }
}

# ------------------------------------------
# Z2: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloatware"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. OneDrive
    $rowOneDrive = New-UltixActionRow -Parent $tabApps -Y 20 `
        -Text "Uninstall and Deprovision OneDrive" `
        -MainRGB @(60, 60, 100) `
        -Description "Completely uninstalls OneDrive, burns its keys across all loaded HKEY_USERS hives, and physically deletes folders across all user profiles." `
        -AuditDescription "AUDIT: Scans for active OneDrive installers, multi-profile HKEY_USERS startup keys, and residual folders." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 2. Capabilities (FOD)
    $rowCaps = New-UltixActionRow -Parent $tabApps -Y 70 `
        -Text "Remove System Features (FOD)" `
        -Description "Interactive removal of optional built-in Features on Demand (FOD) in a background CBS thread." `
        -AuditDescription "AUDIT: Verifies installed unnecessary Capabilities (FOD)." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 3. Aggressive Bloatware (Appx)
    $rowBloat = New-UltixActionRow -Parent $tabApps -Y 120 `
        -Text "Aggressive Bloatware Removal (Appx)" `
        -Description "Aggressive, interactive removal of 64 UWP bloatware targets and Windows Recall/AI telemetry from the system." `
        -AuditDescription "AUDIT: Scans the system for target Appx Bloatware, Recall payloads, and prints a detailed footprint report." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 4. Appx Garbage Collector
    $rowGC = New-UltixActionRow -Parent $tabApps -Y 170 `
        -Text "Run Appx Garbage Collector" `
        -MainRGB @(100, 80, 40) `
        -Description "Resolves transitive Appx dependency graphs and removes orphaned frameworks in a background thread." `
        -AuditDescription "AUDIT: Scans and lists all orphaned frameworks and base packages that can be safely removed." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 5. CBS Capability Stubs
    $rowStubs = New-UltixActionRow -Parent $tabApps -Y 220 `
        -Text "Purge Capability Stubs (CBS)" `
        -MainRGB @(100, 60, 100) `
        -Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." `
        -AuditDescription "AUDIT: Queries CBS registry/payload directly for active stubs." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    foreach ($row in @($rowOneDrive, $rowCaps, $rowBloat, $rowGC, $rowStubs)) {
        $allTabButtons.AddRange($row.Controls)
    }

    $TabControl.Controls.Add($tabApps)
}