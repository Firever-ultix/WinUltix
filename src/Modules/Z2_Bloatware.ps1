# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE (v3.14)
# Z2_Bloatware: Multi-profile OneDrive amputation, 64-target UWP Bloatware & Windows Recall/Copilot AI removal, FOD Preset, Appx Framework Garbage Collector, CBS Stubs, and 4 manual package/feature inspector grids.
# ==========================================

# ------------------------------------------
# Z2: SHARED PROTECTED APPX WHITELIST (AUTO-HYDRATED INTO RUNSPACES)
# ------------------------------------------
function Get-UltixProtectedAppxRegex {
    # Ironclad whitelist: Core Shell/OS UI (Win10 & Win11 24H2/25H2/26H2), Defender/SecHealth, Gaming/Store Identity, Shared Runtimes, and Hardware Media Codecs
    return "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|ShellExperienceHost|StartMenuExperienceHost|immersivecontrolpanel|SecHealthUI|WindowsDefender|WindowsStore|StorePurchaseApp|DesktopAppInstaller|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|MicrosoftEdge\.Stable|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|MicrosoftWindows\.Client\.(?!WebExperience)|Windows\.CBSPreview|Windows\.PrintDialog|Microsoft\.AsyncTextService|Microsoft\.AccountsControl|Microsoft\.CredDialogHost|Microsoft\.ECApp|Microsoft\.LockApp|Microsoft\.BioEnrollment|ApplicationCompatibilityEnhancements|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|MPEG2VideoExtension"
}

# ------------------------------------------
# Z2: BLOATWARE AUDITS (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-OneDriveState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 10 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $userProfiles = @(Get-UltixUserProfiles)
    $loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })

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

    # 1. Core Executables, Scheduled Tasks & Multi-Profile Run Keys (SystemRoot stubs are left dormant for SFC/DISM integrity)
    $exeCandidates = @(
        "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
        "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
    )
    foreach ($prof in $userProfiles) {
        if (-not [string]::IsNullOrWhiteSpace($prof.LocalPath)) {
            $exeCandidates += (Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive\OneDrive.exe")
        }
    }

    $hasBinary = $false
    foreach ($exePath in ($exeCandidates | Select-Object -Unique)) {
        if ([System.IO.File]::Exists($exePath)) {
            $hasBinary = $true
            break
        }
    }

    $liveProc  = Get-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -ErrorAction SilentlyContinue
    $odTasks   = @(Get-ScheduledTask -TaskName "*OneDrive*" -ErrorAction SilentlyContinue)
    $hasRunKey = $false

    $runRoots = [System.Collections.Generic.List[string]]::new()
    $runRoots.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
    $runRoots.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
    foreach ($hive in $loadedHives) {
        $runRoots.Add("$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run")
        $runRoots.Add("$($hive.HiveRoot)\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
    }

    foreach ($runPath in ($runRoots | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $runPath) {
            $runProps = Get-ItemProperty -LiteralPath $runPath -ErrorAction SilentlyContinue
            if ($null -ne $runProps -and ($runProps.PSObject.Properties.Match("OneDrive*").Count -gt 0)) {
                $hasRunKey = $true
                break
            }
        }
    }

    $isCoreDetected = ($hasBinary -or $hasRunKey -or ($null -ne $liveProc) -or ($odTasks.Count -gt 0))

    $results.Add([PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup and Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 55 }

    # 2. Multi-Profile Zombie Registry Keys & Explorer\Desktop\NameSpace CLSIDs (Inspected across all loaded HKEY_USERS\<SID> hives)
    $zombieSubKeys = @("SyncEngine", "Client_Policy", "Accounts")
    $knownNsGuids  = @("{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "{04271989-C4D2-430F-9D0E-2A48B44B1A5C}")

    foreach ($hive in $loadedHives) {
        foreach ($subKey in $zombieSubKeys) {
            $fullRegPath = "$($hive.HiveRoot)\Software\Microsoft\OneDrive\$subKey"
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Registry ($($hive.UserName)): $subKey"
                IsDetected    = (Test-Path -LiteralPath $fullRegPath)
                ActionData    = @{ Type = "Registry"; Path = $fullRegPath }
            })
        }

        # Inspect Explorer\Desktop\NameSpace for residual OneDrive shell folders
        $nsRoot = "$($hive.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace"
        $foundNsKeys = [System.Collections.Generic.List[string]]::new()

        if (Test-Path -LiteralPath $nsRoot) {
            foreach ($nsSub in (Get-ChildItem -LiteralPath $nsRoot -ErrorAction SilentlyContinue)) {
                try {
                    $childName = $nsSub.PSChildName
                    $defVal    = [string]$nsSub.GetValue("", "")
                    if ($childName -in $knownNsGuids -or $defVal -match '(?i)OneDrive') {
                        $foundNsKeys.Add($childName)
                    }
                } catch {
                } finally {
                    $nsSub.Dispose()
                }
            }
        }

        if ($foundNsKeys.Count -gt 0) {
            foreach ($nsGuid in $foundNsKeys) {
                $results.Add([PSCustomObject]@{
                    UIDisplayName = "Shell NameSpace ($($hive.UserName)): $nsGuid"
                    IsDetected    = $true
                    ActionData    = @{ Type = "Registry"; Path = "$nsRoot\$nsGuid" }
                })
            }
        } else {
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Shell NameSpace ($($hive.UserName)): {018D5C66-4533-4307-9B53-224DE2ED1FE6}"
                IsDetected    = $false
                ActionData    = @{ Type = "Registry"; Path = "$nsRoot\{018D5C66-4533-4307-9B53-224DE2ED1FE6}" }
            })
        }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 75 }

    # 3. System Data & Per-Machine Installation Folders
    $staticFolders = @(
        "$env:ProgramFiles\Microsoft OneDrive",
        "${env:ProgramFiles(x86)}\Microsoft OneDrive",
        "$env:PROGRAMDATA\Microsoft OneDrive",
        "$env:SystemDrive\OneDriveTemp"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($folder in $staticFolders) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Folder: $folder"
            IsDetected    = (Test-Path -LiteralPath $folder)
            ActionData    = @{ Type = "Folder"; Path = $folder }
        })
    }

    # 4. Dynamic User Profiles Data Folders (Zero hardcoded C:\Users)
    foreach ($prof in $userProfiles) {
        $userPath = Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
        $results.Add([PSCustomObject]@{
            UIDisplayName = "User Data: $($prof.UserName)"
            IsDetected    = (Test-Path -LiteralPath $userPath)
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

    $critical = Get-UltixProtectedAppxRegex

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

    # 4. Inspect Provisioned packages (shielded by unified $critical regex)
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

    $protectedRegex = Get-UltixProtectedAppxRegex

    $installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 25 }

    $provAppx = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })
    if ($null -ne $UltixSync) { $UltixSync.Progress = 40 }

    # Query Recall Optional Feature and AI Data Analysis Policy state
    $recallFeature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
    $isRecallFeatEnabled = ($null -ne $recallFeature -and ($recallFeature.State -eq 'Enabled' -or $recallFeature.State -eq 'EnablePending'))

    $aiPolPathLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
    $aiPolPathCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
    $aiPropsLM   = Get-ItemProperty -LiteralPath $aiPolPathLM -Name "DisableAIDataAnalysis", "TurnOffSavingSnapshots" -ErrorAction SilentlyContinue
    $aiPropsCU   = Get-ItemProperty -LiteralPath $aiPolPathCU -Name "DisableAIDataAnalysis", "TurnOffSavingSnapshots" -ErrorAction SilentlyContinue
    $isRecallPolicyLocked = (
        $null -ne $aiPropsLM -and $aiPropsLM.DisableAIDataAnalysis -eq 1 -and $aiPropsLM.TurnOffSavingSnapshots -eq 1 -and
        $null -ne $aiPropsCU -and $aiPropsCU.DisableAIDataAnalysis -eq 1 -and $aiPropsCU.TurnOffSavingSnapshots -eq 1
    )

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

        function Remove-UltixOneDriveDirectory {
            param([string]$TargetDir)
            if ([string]::IsNullOrWhiteSpace($TargetDir) -or -not (Test-Path -LiteralPath $TargetDir)) { return }

            & takeown.exe /F "$TargetDir" /R /A /D Y 2>$null | Out-Null
            & icacls.exe "$TargetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null

            # Evacuate memory-mapped shell extensions & binaries (e.g., FileSyncShell64.dll locked by explorer.exe)
            $binFiles = @(Get-ChildItem -LiteralPath $TargetDir -Include "*.dll", "*.exe" -Recurse -File -Force -ErrorAction SilentlyContinue)
            foreach ($bin in $binFiles) {
                $binPath = $bin.FullName
                $binName = $bin.Name
                if ([string]::IsNullOrWhiteSpace($binPath)) { continue }
                try {
                    $bin.Attributes = 'Normal'
                    Remove-Item -LiteralPath $binPath -Force -ErrorAction Stop
                } catch {
                    $trashPath = Join-Path -Path $env:TEMP -ChildPath "WinUltix_Locked_${binName}_$([guid]::NewGuid().ToString('N')).tmp"
                    Move-Item -LiteralPath $binPath -Destination $trashPath -Force -ErrorAction SilentlyContinue
                }
            }

            Get-ChildItem -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { $_.Attributes = 'Normal' } catch {}
            }
            Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue

            if (Test-Path -LiteralPath $TargetDir) {
                if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [*] Releasing Shell Extension lock via Explorer refresh...") }
                Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 600
                Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                    Start-Process "explorer.exe"
                }
            }
        }

        # Pre-kill all OneDrive and companion processes holding file/registry handles
        Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 600

        $userProfiles = @(Get-UltixUserProfiles)
        $loadedHives  = @($userProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })
        if ($loadedHives.Count -eq 0) {
            $loadedHives = @([PSCustomObject]@{ SID = "CurrentUser"; UserName = $env:USERNAME; LocalPath = $env:USERPROFILE; HiveRoot = "HKCU:"; IsHiveLoaded = $true })
        }

        $registryTargetsToVerify = [System.Collections.Generic.List[string]]::new()

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 90)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            $data = $item.ActionData
            try {
                if ($data.Type -eq "Core") {
                    # 1. Unregister all OneDrive scheduled tasks so they cannot respawn OneDriveSetup/Updater
                    Get-ScheduledTask -TaskName "*OneDrive*" -ErrorAction SilentlyContinue | ForEach-Object {
                        Stop-ScheduledTask -InputObject $_ -ErrorAction SilentlyContinue | Out-Null
                        Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue
                    }

                    # 2. Check if any actual OneDrive installation binary exists before invoking OneDriveSetup.exe
                    # (Running OneDriveSetup.exe when already uninstalled needlessly recreates HKCU\...\OneDrive\Accounts!)
                    $installDirs = [System.Collections.Generic.List[string]]::new()
                    foreach ($d in @("$env:ProgramFiles\Microsoft OneDrive", "${env:ProgramFiles(x86)}\Microsoft OneDrive", "$env:LOCALAPPDATA\Microsoft\OneDrive")) {
                        if (-not [string]::IsNullOrWhiteSpace($d)) { $installDirs.Add($d) }
                    }
                    foreach ($prof in $userProfiles) {
                        if (-not [string]::IsNullOrWhiteSpace($prof.LocalPath)) {
                            $installDirs.Add((Join-Path -Path $prof.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"))
                        }
                    }

                    $activeExeFound = $false
                    foreach ($dir in ($installDirs | Select-Object -Unique)) {
                        if ([System.IO.File]::Exists((Join-Path $dir "OneDrive.exe"))) {
                            $activeExeFound = $true
                            break
                        }
                    }

                    if ($activeExeFound) {
                        $setupCandidates = [System.Collections.Generic.List[string]]::new()
                        foreach ($dir in ($installDirs | Select-Object -Unique)) {
                            if ([System.IO.Directory]::Exists($dir)) {
                                Get-ChildItem -LiteralPath $dir -Filter "OneDriveSetup.exe" -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                                    $setupCandidates.Add($_.FullName)
                                }
                            }
                        }
                        $setupCandidates.Add("$env:SystemRoot\SysWOW64\OneDriveSetup.exe")
                        $setupCandidates.Add("$env:SystemRoot\System32\OneDriveSetup.exe")

                        foreach ($setupExe in ($setupCandidates | Select-Object -Unique)) {
                            if ([System.IO.File]::Exists($setupExe)) {
                                Start-Process -FilePath $setupExe -ArgumentList "/uninstall" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                                Start-Process -FilePath $setupExe -ArgumentList "/uninstall /allusers" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                                break
                            }
                        }

                        # Wait for any detached child OneDriveSetup.exe processes to finish writing teardown keys, then kill
                        $childProcs = @(Get-Process -Name "OneDriveSetup", "OneDrive", "OneDriveStandaloneUpdater", "FileCoAuth" -ErrorAction SilentlyContinue)
                        if ($childProcs.Count -gt 0) {
                            $childProcs | Wait-Process -Timeout 8 -ErrorAction SilentlyContinue
                            Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
                        }
                        Start-Sleep -Milliseconds 500
                    }

                    # 3. Physically eradicate remaining OneDrive.exe binaries across Program Files & user profiles
                    foreach ($dir in ($installDirs | Select-Object -Unique)) {
                        if ($dir -like "$env:ProgramFiles*" -or $dir -like "${env:ProgramFiles(x86)}*") {
                            if (Test-Path -LiteralPath $dir) {
                                Remove-UltixOneDriveDirectory -TargetDir $dir
                            }
                        } elseif ([System.IO.File]::Exists((Join-Path $dir "OneDrive.exe"))) {
                            Remove-UltixOneDriveDirectory -TargetDir $dir
                        }
                    }

                    # 4. Neutralize Run keys across HKCU, HKLM, and all loaded HKEY_USERS\<SID> hives (including WOW6432Node)
                    $runTargets = [System.Collections.Generic.List[string]]::new()
                    $runTargets.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
                    $runTargets.Add("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")

                    $nsRoots = [System.Collections.Generic.List[string]]::new()
                    $nsRoots.Add("HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")

                    foreach ($prof in $loadedHives) {
                        $runTargets.Add("$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Run")
                        $runTargets.Add("$($prof.HiveRoot)\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run")
                        $nsRoots.Add("$($prof.HiveRoot)\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")
                    }

                    foreach ($rPath in ($runTargets | Select-Object -Unique)) {
                        if (Test-Path -LiteralPath $rPath) {
                            $rKey = Get-Item -LiteralPath $rPath -ErrorAction SilentlyContinue
                            if ($null -ne $rKey) {
                                try {
                                    foreach ($valName in $rKey.Property) {
                                        if ($valName -like "OneDrive*") {
                                            Remove-ItemProperty -LiteralPath $rPath -Name $valName -Force -ErrorAction SilentlyContinue
                                        }
                                    }
                                } finally {
                                    $rKey.Dispose()
                                }
                            }
                        }
                    }

                    # 5. Sweep residual Explorer\Desktop\NameSpace OneDrive CLSIDs across all loaded hives
                    $knownNsGuids = @("{018D5C66-4533-4307-9B53-224DE2ED1FE6}", "{04271989-C4D2-430F-9D0E-2A48B44B1A5C}")
                    foreach ($nsPath in ($nsRoots | Select-Object -Unique)) {
                        if (Test-Path -LiteralPath $nsPath) {
                            foreach ($sub in (Get-ChildItem -LiteralPath $nsPath -ErrorAction SilentlyContinue)) {
                                $shouldRemove = $false
                                $cName = ""
                                try {
                                    $cName  = $sub.PSChildName
                                    $defVal = [string]$sub.GetValue("", "")
                                    if ($cName -in $knownNsGuids -or $defVal -match '(?i)OneDrive') {
                                        $shouldRemove = $true
                                    }
                                } catch {
                                } finally {
                                    $sub.Dispose()
                                }
                                if ($shouldRemove -and -not [string]::IsNullOrWhiteSpace($cName)) {
                                    Remove-Item -LiteralPath "$nsPath\$cName" -Recurse -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }

                    if ($null -ne $UltixSync) {
                        $UltixSync.Logs.Enqueue("    [+] Core installation payloads, tasks & multi-profile Run/NameSpace hooks neutralized (SystemRoot stub preserved for SFC).")
                    }
                }
                elseif ($data.Type -eq "Registry") {
                    $registryTargetsToVerify.Add([string]$data.Path)
                    if (Test-Path -LiteralPath $data.Path) {
                        Remove-Item -LiteralPath $data.Path -Recurse -Force -ErrorAction Stop
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Registry key removed: $($data.Path)") }
                    }
                }
                elseif ($data.Type -eq "Folder") {
                    $targetDir = $data.Path
                    if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
                        Remove-UltixOneDriveDirectory -TargetDir $targetDir
                        if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [OK] Folder eradicated: $targetDir") }
                    }
                }
            } catch {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)")
                }
            }
        }

        # Final post-kill sweep: ensure any OneDriveSetup teardown thread that exited late cannot leave recreated Accounts keys
        Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
        foreach ($regPath in ($registryTargetsToVerify | Select-Object -Unique)) {
            if (-not [string]::IsNullOrWhiteSpace($regPath) -and (Test-Path -LiteralPath $regPath)) {
                Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
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

        Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk", "aixhost", "GameBar" -Force -ErrorAction SilentlyContinue

        # Query online DISM image ONCE before the loop and track provisioned state via HashSet
        $provisionedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace($p.PackageName)) {
                [void]$provisionedSet.Add($p.PackageName)
            }
        }

        $loadedHives = @(Get-UltixUserProfiles | Where-Object { $_.IsHiveLoaded -and -not [string]::IsNullOrWhiteSpace($_.HiveRoot) })

        foreach ($item in $Items) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Purging: $($item.UIDisplayName)")
            }

            # Handle Windows Recall & AI Data Analysis (24H2/25H2/26H2) across HKLM, HKCU, and loaded user hives
            if ($item.ActionData.IsRecall -eq $true -or $item.UIDisplayName -match "(?i)Recall") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Enforcing DisableAIDataAnalysis & TurnOffSavingSnapshots GPO locks...")
                }
                $aiPolicies = [System.Collections.Generic.List[string]]::new()
                $aiPolicies.Add("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI")
                $aiPolicies.Add("HKCU:\Software\Policies\Microsoft\Windows\WindowsAI")
                foreach ($h in $loadedHives) {
                    $aiPolicies.Add("$($h.HiveRoot)\Software\Policies\Microsoft\Windows\WindowsAI")
                }

                foreach ($pol in ($aiPolicies | Select-Object -Unique)) {
                    if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -LiteralPath $pol -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -LiteralPath $pol -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
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

            # Handle Copilot GPO constraints across HKLM, HKCU, and loaded user hives
            if ($item.UIDisplayName -match "(?i)Copilot") {
                if ($null -ne $UltixSync) {
                    $UltixSync.Logs.Enqueue("    [*] Applying local policy constraints for Windows Copilot...")
                }
                $policies = [System.Collections.Generic.List[string]]::new()
                $policies.Add("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")
                $policies.Add("HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")
                foreach ($h in $loadedHives) {
                    $policies.Add("$($h.HiveRoot)\Software\Policies\Microsoft\Windows\WindowsCopilot")
                }

                foreach ($pol in ($policies | Select-Object -Unique)) {
                    if (-not (Test-Path -LiteralPath $pol)) { New-Item -Path $pol -Force -ErrorAction SilentlyContinue | Out-Null }
                    Set-ItemProperty -LiteralPath $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                }
            }

            # 1. Process Installed Packages (AllUsers + CurrentUser fallback)
            foreach ($pkg in $item.ActionData.Installed) {
                $pfn = $pkg.PackageFamilyName

                try {
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                        [void]$provisionedSet.Remove($pkg.PackageFullName)
                    } catch {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                    }

                    # Register in Deprovisioned store to prevent Windows Update from reinstalling it
                    if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                        if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
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

            # 2. Process Provisioned Packages (O(1) HashSet lookup, zero repeated DISM enumeration)
            foreach ($prov in $item.ActionData.Provisioned) {
                if (-not $provisionedSet.Contains($prov.PackageName)) { continue }

                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    [void]$provisionedSet.Remove($prov.PackageName)

                    # Lock Deprovisioned registry key even for provisioned-only packages
                    $pkgParts = $prov.PackageName -split '_'
                    if ($pkgParts.Count -ge 5 -and -not [string]::IsNullOrWhiteSpace($pkgParts[0]) -and -not [string]::IsNullOrWhiteSpace($pkgParts[4])) {
                        $provPfn = "$($pkgParts[0])_$($pkgParts[4])"
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$provPfn"
                        if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }

                    if ($null -ne $UltixSync) { $UltixSync.Logs.Enqueue("    [+] Deprovisioned base image: $($prov.DisplayName)") }
                } catch {
                    [void]$provisionedSet.Remove($prov.PackageName)
                    if ($_.Exception.HResult -notin @(-2147024894, -2147024893) -and $_.Exception.Message -notmatch "(?i)0x80070002|0x80070003") {
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
# Z2: MANUAL INTERACTIVE INSPECTOR GRIDS (MOVED FROM Z5)
# ------------------------------------------
function Show-AppxGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning installed Appx packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = Get-UltixProtectedAppxRegex
        
        $pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } |
            Select-Object Name, PackageFullName, PackageFamilyName, IsFramework, Status |
            Sort-Object Name)
        return $pkgs
    } -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$pkgs = @($output | Where-Object { $null -ne $_ })
        if ($pkgs.Count -eq 0) {
            Write-GUI " -> No removable Appx packages found.`n"
            return
        }

        $cols = @(
            @{ Header = "Package Name";    Property = "Name";            Width = 310 }
            @{ Header = "Framework";       Property = "IsFramework";     Width = 90  }
            @{ Header = "Status";          Property = "Status";          Width = 95  }
            @{ Header = "PackageFullName"; Property = "PackageFullName"; Width = 350 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Installed Appx Packages" `
            -Description "Select Appx packages to remove across all accounts. Protected gaming/system runtimes are hidden." `
            -Data $pkgs -Columns $cols -PrimaryButtonText "Remove Selected Appx"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Appx removal cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($app in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Removing Appx: $($app.Name)")
                try {
                    try {
                        Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                    } catch {
                        Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop
                    }
                    if (-not [string]::IsNullOrWhiteSpace($app.PackageFamilyName)) {
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$($app.PackageFamilyName)"
                        if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    $UltixSync.Logs.Enqueue("    [OK] $($app.Name) removed and deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error removing $($app.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Appx removal routine finished.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

function Show-AppxProvGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning Provisioned Appx image packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = Get-UltixProtectedAppxRegex
        
        $pkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -notmatch $protectedPattern } |
            Select-Object DisplayName, Version, PackageName |
            Sort-Object DisplayName)
        return $pkgs
    } -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$pkgs = @($output | Where-Object { $null -ne $_ })
        if ($pkgs.Count -eq 0) {
            Write-GUI " -> No provisioned packages found in system image.`n"
            return
        }

        $cols = @(
            @{ Header = "Display Name"; Property = "DisplayName"; Width = 340 }
            @{ Header = "Version";      Property = "Version";     Width = 140 }
            @{ Header = "Package Name"; Property = "PackageName"; Width = 365 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Provisioned Appx Image Packages" `
            -Description "Select base-image packages to deprovision so they never install for new users." `
            -Data $pkgs -Columns $cols -PrimaryButtonText "Deprovision Selected"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Deprovisioning cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($app in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Deprovisioning: $($app.DisplayName)")
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction Stop | Out-Null
                    $pkgParts = $app.PackageName -split '_'
                    if ($pkgParts.Count -ge 5 -and -not [string]::IsNullOrWhiteSpace($pkgParts[0]) -and -not [string]::IsNullOrWhiteSpace($pkgParts[4])) {
                        $provPfn = "$($pkgParts[0])_$($pkgParts[4])"
                        $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$provPfn"
                        if (-not (Test-Path -LiteralPath $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    $UltixSync.Logs.Enqueue("    [OK] $($app.DisplayName) deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)")
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Provisioned packages removed from image.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

function Show-CapsGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Querying installed Windows Capabilities / FOD (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        # Lock critical DirectX database, Ethernet NDIS client drivers, and Defender Sense core
        $criticalFodRegex = '^(?i)(DirectX\.Configuration\.Database|Microsoft\.Windows\.Ethernet\.Client|Microsoft\.Windows\.Sense\.Client)'

        $caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Installed' } |
            ForEach-Object {
                $isCrit = ($_.Name -match $criticalFodRegex)
                $stateDisp = if ($isCrit) { "Installed [CRITICAL - LOCKED]" } else { [string]$_.State }
                [PSCustomObject]@{
                    Name     = $_.Name
                    State    = $stateDisp
                    IsLocked = $isCrit
                }
            } | Sort-Object IsLocked, Name)
        return $caps
    } -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$caps = @($output | Where-Object { $null -ne $_ })
        if ($caps.Count -eq 0) {
            Write-GUI " -> No installed Capabilities returned.`n"
            return
        }

        $cols = @(
            @{ Header = "Capability Name (FOD)"; Property = "Name";  Width = 650 }
            @{ Header = "State";                 Property = "State"; Width = 190 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Capabilities (FOD)" `
            -Description "Select installed Features on Demand (FOD) to uninstall. Critical DirectX, Ethernet LAN, and Defender FODs (Red) are locked." `
            -Data $caps -Columns $cols -PrimaryButtonText "Uninstall Selected FODs"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Capability removal cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($cap in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                if ($cap.IsLocked) { continue }

                $UltixSync.Logs.Enqueue(" -> Removing capability: $($cap.Name)")
                try {
                    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($cap.Name) removed.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Capability removal finished.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

function Show-OptFeaturesGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Querying enabled Windows Optional Features (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $feats = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Enabled' } |
            Select-Object FeatureName, State |
            Sort-Object FeatureName)
        return $feats
    } -OnComplete ({
        param($output)
        Update-Progress 0
        [array]$feats = @($output | Where-Object { $null -ne $_ })
        if ($feats.Count -eq 0) {
            Write-GUI " -> No enabled Optional Features found.`n"
            return
        }

        $cols = @(
            @{ Header = "Optional Feature Name"; Property = "FeatureName"; Width = 680 }
            @{ Header = "State";                 Property = "State";       Width = 160 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Optional Features" `
            -Description "Select enabled Optional Features to disable (e.g., Legacy Components, SMB1, Hypervisor modules)." `
            -Data $feats -Columns $cols -PrimaryButtonText "Disable Selected Features"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Optional feature configuration cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @(,$res.Items) -ScriptBlock {
            param([array]$Selected)
            $total = $Selected.Count
            $current = 0
            foreach ($feat in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> Disabling feature: $($feat.FeatureName)")
                try {
                    Disable-WindowsOptionalFeature -Online -FeatureName $feat.FeatureName -NoRestart -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($feat.FeatureName) disabled (Reboot may be required).")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Failed to disable $($feat.FeatureName): $($_.Exception.Message)")
                }
            }
        } -OnComplete ({
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Optional Features processing completed.`n"
        }.GetNewClosure())
    }.GetNewClosure())
}

# ------------------------------------------
# Z2: UI INITIALIZATION (DEBLOAT & PACKAGE INSPECTORS)
# ------------------------------------------
function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Debloat"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. OneDrive Amputation
    $rowOneDrive = New-UltixActionRow -Parent $tabApps -Y 20 -MainRGB @(55, 58, 64) `
        -Text "Uninstall and Deprovision OneDrive" `
        -Description "Completely uninstalls OneDrive, burns its keys across all loaded HKEY_USERS hives, and physically deletes folders across all user profiles." `
        -AuditDescription "AUDIT: Scans for active OneDrive installers, multi-profile HKEY_USERS startup keys, and residual folders." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 2. Aggressive Bloatware & AI Removal (64 Appx + Recall/Copilot)
    $rowBloat = New-UltixActionRow -Parent $tabApps -Y 70 -MainRGB @(135, 50, 50) `
        -Text "Aggressive Bloatware & AI Removal" `
        -Description "Aggressive, interactive removal of 64 UWP bloatware targets and Windows Recall/Copilot AI telemetry from the system." `
        -AuditDescription "AUDIT: Scans the system for target Appx Bloatware, Recall payloads, and prints a detailed footprint report." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware & AI Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 3. Capabilities (FOD Preset)
    $rowCaps = New-UltixActionRow -Parent $tabApps -Y 120 -MainRGB @(55, 58, 64) `
        -Text "Remove System Features (FOD Preset)" `
        -Description "Interactive removal of 14 unnecessary built-in Features on Demand (Steps Recorder, Quick Assist, WordPad, Fax, Hello Face) in a background CBS thread." `
        -AuditDescription "AUDIT: Verifies installed unnecessary Capabilities (FOD)." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 4. Appx Garbage Collector
    $rowGC = New-UltixActionRow -Parent $tabApps -Y 170 -MainRGB @(55, 58, 64) `
        -Text "Run Appx Framework Garbage Collector" `
        -Description "Resolves transitive Appx dependency graphs and removes orphaned UWP frameworks in a background thread." `
        -AuditDescription "AUDIT: Scans and lists all orphaned frameworks and base packages that can be safely removed." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 5. CBS Capability Stubs
    $rowStubs = New-UltixActionRow -Parent $tabApps -Y 220 -MainRGB @(55, 58, 64) `
        -Text "Purge Capability Stubs (CBS)" `
        -Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." `
        -AuditDescription "AUDIT: Queries CBS registry/payload directly for active stubs." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable $allTabButtons.ToArray() -SkipModalIfClean
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly
        }.GetNewClosure())

    # 6. Manual Package & Feature Inspectors (Sortable Grids)
    $lblInspect = New-Object System.Windows.Forms.Label
    $lblInspect.Text = "Manual Package & Feature Inspectors (Sortable Grids)"
    $lblInspect.Location = New-Object System.Drawing.Point(15, 272)
    $lblInspect.Size = New-Object System.Drawing.Size(370, 18)
    $lblInspect.ForeColor = [System.Drawing.Color]::DarkGray
    $lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $lblWarnInspect = New-Object System.Windows.Forms.Label
    $lblWarnInspect.Text = "[!] MANUAL INSPECTORS ONLY — DO NOT SELECT ALL!`r`nFor targeted inspection of what remains after presets."
    $lblWarnInspect.Location = New-Object System.Drawing.Point(15, 293)
    $lblWarnInspect.Size = New-Object System.Drawing.Size(370, 40)
    $lblWarnInspect.BackColor = [System.Drawing.Color]::FromArgb(255, 58, 35, 20)
    $lblWarnInspect.ForeColor = [System.Drawing.Color]::Gold
    $lblWarnInspect.BorderStyle = "FixedSingle"
    $lblWarnInspect.TextAlign = "MiddleCenter"
    $lblWarnInspect.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $tabApps.Controls.AddRange(@($lblInspect, $lblWarnInspect))

    $btnAppxUser = New-UltixButton -Parent $tabApps -X 15 -Y 342 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "Appx (User Accounts)" `
        -Description "MANUAL INSPECTOR: Opens a table of all remaining installed Appx packages. Do NOT blindly delete all!" `
        -OnClick ({ Show-AppxGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $btnAppxImg = New-UltixButton -Parent $tabApps -X 205 -Y 342 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "Appx (Base Image)" `
        -Description "MANUAL INSPECTOR: Opens a table of Provisioned Appx packages cached in the Windows image." `
        -OnClick ({ Show-AppxProvGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $btnCapsGrid = New-UltixButton -Parent $tabApps -X 15 -Y 392 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "Capabilities (Full FOD)" `
        -Description "MANUAL INSPECTOR: Scans all installed Features on Demand (FOD) for selective manual removal." `
        -OnClick ({ Show-CapsGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $btnOptGrid = New-UltixButton -Parent $tabApps -X 205 -Y 392 -Width 180 -Height 40 -RGB @(45, 85, 125) `
        -Text "Optional Features (DISM)" `
        -Description "MANUAL INSPECTOR: Scans enabled Windows Optional Features (SMB1, Hypervisor, Legacy Components) for selective disabling." `
        -OnClick ({ Show-OptFeaturesGrid -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    foreach ($row in @($rowOneDrive, $rowBloat, $rowCaps, $rowGC, $rowStubs)) {
        $allTabButtons.AddRange($row.Controls)
    }
    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@($btnAppxUser, $btnAppxImg, $btnCapsGrid, $btnOptGrid))

    $TabControl.Controls.Add($tabApps)
}