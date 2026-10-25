# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE
# Z2_Bloatware: Aggressive debloatifier. Uninstalls OneDrive (iterating through profiles), removes FOD packages (Capabilities), cleans orphaned Appx frameworks (Garbage Collector), and mass-removes preinstalled UWP bloatware.
# ==========================================

# ------------------------------------------
# Z2: BLOATWARE AUDITS (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-OneDriveState {
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    # 1. Core Executables & Run Keys (SystemRoot stubs are left dormant for SFC/DISM integrity, so check active user payload/startup)
    $localExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
    $runKey   = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue
    $liveProc = Get-Process -Name "OneDrive", "OneDriveSetup" -ErrorAction SilentlyContinue

    $isCoreDetected = ((Test-Path $localExe) -or ($null -ne $runKey) -or ($null -ne $liveProc))
    
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup and Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    })

    # 2. Zombie Registry Keys
    $zombieKeys = @("HKCU:\Software\Microsoft\OneDrive\SyncEngine", "HKCU:\Software\Microsoft\OneDrive\Client_Policy")
    foreach ($key in $zombieKeys) {
        $results.Add([PSCustomObject]@{
            UIDisplayName = "Registry: $($key | Split-Path -Leaf)"
            IsDetected    = (Test-Path -Path $key)
            ActionData    = @{ Type = "Registry"; Path = $key }
        })
    }

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
    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = False" -ErrorAction SilentlyContinue
    foreach ($cimProfile in $userProfiles) {
        $userName = [System.IO.Path]::GetFileName($cimProfile.LocalPath)
        if ($userName -notmatch '^(Public|Default.*|All Users)$') {
            $userPath = Join-Path -Path $cimProfile.LocalPath -ChildPath "AppData\Local\Microsoft\OneDrive"
            $results.Add([PSCustomObject]@{
                UIDisplayName = "User Data: $userName"
                IsDetected    = (Test-Path -Path $userPath)
                ActionData    = @{ Type = "Folder"; Path = $userPath }
            })
        }
    }

    return $results
}

function Get-CapabilitiesState {
    $capsWildcards = @("*Print.Fax.Scan*", "*App.StepsRecorder*", "*Media.WindowsMediaPlayer*", "*MathRecognizer*", "*App.Support.QuickAssist*", "*Microsoft.Windows.WordPad*", "*Hello.Face*", "*OneCoreUAP.OneSync*", "*Browser.InternetExplorer*", "*Microsoft.Wallpapers.Extended*", "*Print.Management.Console*", "*Language.Handwriting*", "*Language.Speech*", "*Wifi.Client*")
    
    $installedCaps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Installed' })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($capName in $capsWildcards) {
        $found = @($installedCaps | Where-Object { $_.Name -like $capName })
        $isDetected = ($found.Count -gt 0)
        $cleanName = $capName.Replace("*", "") 

        $results.Add([PSCustomObject]@{
            UIDisplayName = "FOD: $cleanName"
            IsDetected    = $isDetected
            ActionData    = $found
        })
    }
    return $results
}

function Get-GarbageCollectorState {
    $allPackages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $standardApps = @($allPackages | Where-Object { $_.IsFramework -eq $false })
    
    $activeDependencies = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($app in $standardApps) { 
        if ($app.Dependencies) {
            foreach ($dep in $app.Dependencies) {
                [void]$activeDependencies.Add($dep.PackageFullName)
            }
        }
    }
    
    # Complete protected framework whitelist per WinUltix architecture standards
    $critical = "Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
    $frameworks = @($allPackages | Where-Object { $_.IsFramework -eq $true -and $_.Name -notmatch $critical })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($fw in $frameworks) { 
        if (-not $activeDependencies.Contains($fw.PackageFullName)) { 
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Framework: $($fw.Name)"
                IsDetected    = $true
                ActionData    = @{ Type = "Framework"; Target = $fw.PackageFullName }
            })
        } 
    }
    
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    foreach ($prov in $provisioned) { 
        if (-not ($allPackages | Where-Object { $_.Name -eq $prov.DisplayName })) { 
            $results.Add([PSCustomObject]@{
                UIDisplayName = "Orphaned Base: $($prov.DisplayName)"
                IsDetected    = $true
                ActionData    = @{ Type = "Provisioned"; Target = $prov.PackageName }
            })
        } 
    } 
    return $results
}

function Get-BloatwareState {
    # Ordered, non-overlapping definitions with clear UI labels matching Windows 11 24H2/25H2/26H2 packages
    $appCatalog = @(
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
        @{ Label = "Windows Copilot & AI Assistant";              Pattern = "*Copilot*" }
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
        @{ Label = "Third-Party Games (CandyCrush / Disney / etc.)"; Pattern = "*CandyCrush*|*BubbleWitch*|*FarmHeroes*|*MarchofEmpires*|*Homescapes*|*Township*|*Disney*" }
        @{ Label = "Third-Party Social & Media (TikTok / Spotify / etc.)"; Pattern = "*TikTok*|*Instagram*|*Facebook*|*Twitter*|*LinkedIn*|*Netflix*|*Spotify*|*Amazon*" }
        @{ Label = "OEM & Antivirus Bloat (McAfee / Norton / OEM)"; Pattern = "*McAfee*|*Norton*|*Lenovo*|*Dell*|*HP*" }
    )

    $protectedRegex = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|WindowsStore|StorePurchaseApp|WindowsCalculator|WindowsNotepad|Paint|WindowsTerminal|ScreenSketch|HEIFImageExtension|HEVCVideoExtension|VP9VideoExtensions|WebMediaExtensions|WebpImageExtension|RawImageExtension|AV1VideoExtension|AVCEncoderVideoExtension|ApplicationCompatibilityEnhancements|MicrosoftEdge\.Stable"

    $installedAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.IsFramework -eq $false -and $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedRegex })
    $provAppx      = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -notmatch $protectedRegex })

    $seenInstalled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seenProv      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $results       = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($entry in $appCatalog) {
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

        $totalSizeMB = 0
        foreach ($pkg in $foundInstalled) {
            $loc = $pkg.InstallLocation
            if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path $loc)) {
                $bytes = (Get-ChildItem -Path $loc -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($null -ne $bytes) { $totalSizeMB += ($bytes / 1MB) }
            }
        }

        # Every registered package in Get-AppxPackage or Provisioned store is flagged for removal (no 10MB blind spot)
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
            ActionData    = @{ Installed = @($foundInstalled); Provisioned = @($foundProv) }
        })
    }

    return $results
}

function Get-CapabilityStubState {
    # Queries CBS directly for any installed packages acting as empty shells/stubs
    $cbsStubs = @(Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match "(?i)stub" -and $_.PackageState -eq "Installed" })
    
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($stub in $cbsStubs) {
        $cleanName = ($stub.PackageName -split '~')[0]
        $results.Add([PSCustomObject]@{
            UIDisplayName = "CBS Stub: $cleanName"
            IsDetected    = $true
            ActionData    = $stub.PackageName
        })
    }
    return $results
}

# ------------------------------------------
# Z2: BLOATWARE & APPS ENGINE
# ------------------------------------------
function Invoke-RemoveOneDrive {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No OneDrive components selected. Aborting."; return }
    $current = 0
    
    # Pre-kill all OneDrive and companion processes holding handles
    Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        $data = $item.ActionData
        try {
            if ($data.Type -eq "Core") {
                $setupX64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
                $setupX86 = "$env:SystemRoot\System32\OneDriveSetup.exe"

                if (Test-Path $setupX64) { 
                    Start-Process $setupX64 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                } elseif (Test-Path $setupX86) { 
                    Start-Process $setupX86 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                }
                
                Start-Sleep -Seconds 2
                Stop-Process -Name "OneDrive", "OneDriveSetup", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue

                # Neutralize execution vectors while preserving dormant SystemRoot binary for SFC/DISM integrity
                reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>$null | Out-Null
                
                Write-GUI "    [+] Core installation payloads purged. SystemRoot stubs neutralized."
            }
            elseif ($data.Type -eq "Registry") {
                if (Test-Path -Path $data.Path) { Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop }
            }
            elseif ($data.Type -eq "Folder") {
                $targetDir = $data.Path
                if (-not [string]::IsNullOrWhiteSpace($targetDir) -and (Test-Path -LiteralPath $targetDir)) {
                    & takeown.exe /F "$targetDir" /R /A /D Y 2>$null | Out-Null
                    & icacls.exe "$targetDir" /grant "*S-1-5-32-544:F" /T /C /Q 2>$null | Out-Null

                    # Evacuate memory-mapped shell extensions (e.g., FileSyncShell64.dll locked by explorer.exe)
                    # Using explicit foreach variable ($dll) so catch block does not overwrite $_ with ErrorRecord
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
                        Write-GUI "    [*] Releasing Shell Extension lock via Explorer refresh..."
                        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Milliseconds 600
                        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
                        if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                            Start-Process "explorer.exe"
                        }
                    }
                    Write-GUI "    [OK] Folder eradicated: $targetDir"
                }
            }
        } catch {
            Write-GUI "    [!] Error purging $($item.UIDisplayName): $($_.Exception.Message)"
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Selected OneDrive components eliminated."
}

function Invoke-RemoveCapabilities {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Removing Capability: $($item.UIDisplayName)"
        foreach ($cap in $item.ActionData) {
            try { Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null } catch { }
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> System features removal completed."
}

function Invoke-GarbageCollector {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> System clean or operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Cleaning: $($item.UIDisplayName)"
        try {
            if ($item.ActionData.Type -eq "Framework") {
                Remove-AppxPackage -Package $item.ActionData.Target -AllUsers -ErrorAction Stop
            } elseif ($item.ActionData.Type -eq "Provisioned") {
                Remove-AppxProvisionedPackage -Online -PackageName $item.ActionData.Target -ErrorAction Stop | Out-Null
            }
        } catch { Write-GUI "    [!] Error removing $($item.UIDisplayName): $($_.Exception.Message)" }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Appx Garbage Collector finished its run."
}

function Invoke-RemoveBloatware {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }
    $current = 0

    Stop-Process -Name "Widgets", "WidgetService", "StoreExperienceHost", "WinStore.App", "Copilot", "msteams", "olk" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        if ($item.UIDisplayName -match "(?i)Copilot") {
            Write-GUI "    [*] Applying local policy constraints for Copilot..."
            $policies = @(
                "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
                "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
            )
            foreach ($pol in $policies) {
                if (-not (Test-Path $pol)) { New-Item -Path $pol -Force | Out-Null }
                Set-ItemProperty -Path $pol -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
            }
        }

        # 1. Process Installed Packages (AllUsers + CurrentUser fallback)
        foreach ($pkg in $item.ActionData.Installed) {
            $pfn = $pkg.PackageFamilyName
            
            try {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                } catch {
                    # Fallback for packages staged only in the current user context
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                }
                
                # Register in Deprovisioned store to prevent Windows Update from reinstalling it
                if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                    $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                    if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                }
                Write-GUI "    [+] Removed Appx: $($pkg.Name)"
            } catch { 
                if ($pkg.Name -match "(?i)Copilot") {
                    Write-GUI "    [!] API uninstallation blocked for $($pkg.Name). Relying on GPO lockdown."
                } else {
                    Write-GUI "    [-] Error removing $($pkg.Name): $($_.Exception.Message)"
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
                Write-GUI "    [+] Deprovisioned base image: $($prov.DisplayName)"
            } catch {
                # Ignore 0x80070002 / 0x80070003 if Remove-AppxPackage -AllUsers already wiped the staging directory
                if ($_.Exception.Message -notmatch "(?i)nie można odnaleźć|cannot find|0x80070002|0x80070003") {
                    Write-GUI "    [-] Error deprovisioning $($prov.DisplayName): $($_.Exception.Message)"
                }
            }
        }
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Aggressive Bloatware Removal completed."
}

function Invoke-RemoveCapabilityStubs {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No stubs selected. Operation aborted."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging CBS Stub: $($item.UIDisplayName)"
        try {
            # Strips the underlying package, implicitly removing it from Get-WindowsCapability payload list
            Remove-WindowsPackage -Online -PackageName $item.ActionData -NoRestart -ErrorAction Stop | Out-Null
        } catch { 
            Write-GUI "    [!] Error purging stub: $($_.Exception.Message)" 
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> CBS capability stubs successfully eradicated."
}

# ------------------------------------------
# Z2: ASYNC SCANNER DISPATCHER (VIA CORE_HELPERS)
# ------------------------------------------
function Invoke-Z2ScannerAsync {
    param(
        [Parameter(Mandatory=$true)][string]$ScannerFunction,
        [Parameter(Mandatory=$true)][string]$AuditLabel,
        [string]$ModalTitle = "",
        [string]$ModalDescription = "",
        [string]$ExecutorFunction = "",
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable,
        [switch]$AuditOnly,
        [switch]$SkipModalIfClean
    )

    if ($AuditOnly) {
        Write-GUI "--- AUDIT: $AuditLabel (Background Thread) ---"
    } else {
        Write-GUI " -> Initializing $AuditLabel Scanner (Background Thread)..."
    }
    Update-Progress 25

    $sb = (Get-Command -Name $ScannerFunction).ScriptBlock
    $isAuditOnly = $AuditOnly.IsPresent
    $skipIfClean = $SkipModalIfClean.IsPresent

    Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $ControlsToDisable -OnComplete {
        param($output)
        Update-Progress 0
        [array]$auditData = @($output | Where-Object { $null -ne $_ })
        $detected = @($auditData | Where-Object { $_.IsDetected })

        if ($isAuditOnly) {
            if ($detected.Count -gt 0) {
                foreach ($d in $detected) { Write-GUI "  [!] Found: $($d.UIDisplayName)" }
                Write-GUI "-> STATUS: $($detected.Count) item(s) detected.`n"
            } else {
                Write-GUI "  [OK] System clean.`n"
            }
            return
        }

        if ($skipIfClean -and $detected.Count -eq 0) {
            Write-GUI "  [OK] System is completely clean. Nothing to remove.`n"
            return
        }

        $selectedData = Show-ActionModal -Title $ModalTitle -Description $ModalDescription -AuditResults $auditData
        if ($null -ne $selectedData -and $null -ne $selectedData.Items -and $selectedData.Items.Count -gt 0) {
            & $ExecutorFunction -SelectedItems $selectedData.Items
            Write-GUI ""
        } else {
            Write-GUI "Operation cancelled.`n"
        }
    }.GetNewClosure()
}

function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloatware"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # OneDrive
    $btnOneDrive = New-Object System.Windows.Forms.Button
    $btnOneDrive.Text = "Uninstall and Deprovision OneDrive"
    $btnOneDrive.Location = New-Object System.Drawing.Point(15, 20)
    $btnOneDrive.Size = New-Object System.Drawing.Size(320, 40)
    $btnOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 100)
    $btnOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnOneDrive.FlatStyle = "Flat"
    $btnOneDrive.Add_MouseEnter({ Show-Description "Completely uninstalls OneDrive, burns it from the Registry, and physically deletes folders across all profiles." })

    $btnAudOneDrive = New-Object System.Windows.Forms.Button
    $btnAudOneDrive.Text = "?"
    $btnAudOneDrive.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudOneDrive.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnAudOneDrive.FlatStyle = "Flat"
    $btnAudOneDrive.Add_MouseEnter({ Show-Description "AUDIT: Scans for active OneDrive installers and startup keys." })

    $btnOneDrive.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ModalTitle "WinUltix - OneDrive" -ModalDescription "Select specific OneDrive traces to eradicate." -ExecutorFunction "Invoke-RemoveOneDrive" -ControlsToDisable @($btnOneDrive, $btnAudOneDrive) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudOneDrive.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-OneDriveState" -AuditLabel "OneDrive" -ControlsToDisable @($btnOneDrive, $btnAudOneDrive) -AuditOnly
    }.GetNewClosure())

    # Capabilities (FOD)
    $btnCaps = New-Object System.Windows.Forms.Button
    $btnCaps.Text = "Remove System Features (FOD)"
    $btnCaps.Location = New-Object System.Drawing.Point(15, 70)
    $btnCaps.Size = New-Object System.Drawing.Size(320, 40)
    $btnCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCaps.ForeColor = [System.Drawing.Color]::White
    $btnCaps.FlatStyle = "Flat"
    $btnCaps.Add_MouseEnter({ Show-Description "Interactive removal of optional built-in Features on Demand (FOD)." })

    $btnAudCaps = New-Object System.Windows.Forms.Button
    $btnAudCaps.Text = "?"
    $btnAudCaps.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudCaps.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudCaps.ForeColor = [System.Drawing.Color]::White
    $btnAudCaps.FlatStyle = "Flat"
    $btnAudCaps.Add_MouseEnter({ Show-Description "AUDIT: Verifies installed unnecessary Capabilities (FOD)." })

    $btnCaps.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ModalTitle "WinUltix - FOD Removal" -ModalDescription "Select features to remove." -ExecutorFunction "Invoke-RemoveCapabilities" -ControlsToDisable @($btnCaps, $btnAudCaps)
    }.GetNewClosure())
    $btnAudCaps.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilitiesState" -AuditLabel "Built-in Features (FOD)" -ControlsToDisable @($btnCaps, $btnAudCaps) -AuditOnly
    }.GetNewClosure())

    # Aggressive Bloatware
    $btnBloat = New-Object System.Windows.Forms.Button
    $btnBloat.Text = "Aggressive Bloatware Removal (Appx)"
    $btnBloat.Location = New-Object System.Drawing.Point(15, 120)
    $btnBloat.Size = New-Object System.Drawing.Size(320, 40)
    $btnBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnBloat.ForeColor = [System.Drawing.Color]::White
    $btnBloat.FlatStyle = "Flat"
    $btnBloat.Add_MouseEnter({ Show-Description "Aggressive, interactive removal of junk Appx applications from the system." })

    $btnAudBloat = New-Object System.Windows.Forms.Button
    $btnAudBloat.Text = "?"
    $btnAudBloat.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudBloat.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudBloat.ForeColor = [System.Drawing.Color]::White
    $btnAudBloat.FlatStyle = "Flat"
    $btnAudBloat.Add_MouseEnter({ Show-Description "AUDIT: Scans the system for target Appx Bloatware and prints a report." })

    $btnBloat.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ModalTitle "WinUltix - Bloatware Removal" -ModalDescription "Select components to remove. Detected items are checked by default." -ExecutorFunction "Invoke-RemoveBloatware" -ControlsToDisable @($btnBloat, $btnAudBloat)
    }.GetNewClosure())
    $btnAudBloat.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-BloatwareState" -AuditLabel "Bloatware (Appx)" -ControlsToDisable @($btnBloat, $btnAudBloat) -AuditOnly
    }.GetNewClosure())

    # Garbage Collector
    $btnGC = New-Object System.Windows.Forms.Button
    $btnGC.Text = "Run Appx Garbage Collector"
    $btnGC.Location = New-Object System.Drawing.Point(15, 170)
    $btnGC.Size = New-Object System.Drawing.Size(320, 40)
    $btnGC.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 80, 40)
    $btnGC.ForeColor = [System.Drawing.Color]::White
    $btnGC.FlatStyle = "Flat"
    $btnGC.Add_MouseEnter({ Show-Description "Intelligently scans application dependencies and removes orphaned frameworks." })

    $btnAudGC = New-Object System.Windows.Forms.Button
    $btnAudGC.Text = "?"
    $btnAudGC.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudGC.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGC.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudGC.ForeColor = [System.Drawing.Color]::White
    $btnAudGC.FlatStyle = "Flat"
    $btnAudGC.Add_MouseEnter({ Show-Description "AUDIT: Scans and lists all orphaned frameworks that will be removed." })

    $btnGC.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ModalTitle "WinUltix - Garbage Collector" -ModalDescription "Select orphaned packages to remove." -ExecutorFunction "Invoke-GarbageCollector" -ControlsToDisable @($btnGC, $btnAudGC) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudGC.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-GarbageCollectorState" -AuditLabel "Garbage Collector" -ControlsToDisable @($btnGC, $btnAudGC) -AuditOnly
    }.GetNewClosure())

    # CBS Capability Stubs
    $btnStubs = New-Object System.Windows.Forms.Button
    $btnStubs.Text = "Purge Capability Stubs (CBS)"
    $btnStubs.Location = New-Object System.Drawing.Point(15, 220)
    $btnStubs.Size = New-Object System.Drawing.Size(320, 40)
    $btnStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 100)
    $btnStubs.ForeColor = [System.Drawing.Color]::White
    $btnStubs.FlatStyle = "Flat"
    $btnStubs.Add_MouseEnter({ Show-Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." })

    $btnAudStubs = New-Object System.Windows.Forms.Button
    $btnAudStubs.Text = "?"
    $btnAudStubs.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudStubs.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudStubs.ForeColor = [System.Drawing.Color]::White
    $btnAudStubs.FlatStyle = "Flat"
    $btnAudStubs.Add_MouseEnter({ Show-Description "AUDIT: Queries CBS registry/payload directly for active stubs." })

    $btnStubs.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ModalTitle "WinUltix - Stub Purge" -ModalDescription "Select stubs to rip from the CBS store." -ExecutorFunction "Invoke-RemoveCapabilityStubs" -ControlsToDisable @($btnStubs, $btnAudStubs) -SkipModalIfClean
    }.GetNewClosure())
    $btnAudStubs.Add_Click({
        Invoke-Z2ScannerAsync -ScannerFunction "Get-CapabilityStubState" -AuditLabel "CBS Stubs" -ControlsToDisable @($btnStubs, $btnAudStubs) -AuditOnly
    }.GetNewClosure())

    $tabApps.Controls.AddRange(@($btnOneDrive, $btnAudOneDrive, $btnCaps, $btnAudCaps, $btnBloat, $btnAudBloat, $btnGC, $btnAudGC, $btnStubs, $btnAudStubs))
    $TabControl.Controls.Add($tabApps)
}