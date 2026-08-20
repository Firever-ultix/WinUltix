# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z2_BLOATWARE.PS1 - BLOATWARE & APPS MODULE
# Z2_Bloatware: Aggressive debloatifier. Uninstalls OneDrive (iterating through profiles), removes FOD packages (Capabilities), cleans orphaned Appx frameworks (Garbage Collector), and mass-removes preinstalled UWP bloatware.
# ==========================================

# ------------------------------------------
# Z2: BLOATWARE AUDITS
# ------------------------------------------
function Get-OneDriveState {
    $results = @()
    
    # 1. Core Executables & Run Keys
    $coreSetupX64 = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    $coreSetupX86 = "$env:SystemRoot\System32\OneDriveSetup.exe"
    $runKey = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue

    $isCoreDetected = ((Test-Path $coreSetupX64) -or (Test-Path $coreSetupX86) -or ($null -ne $runKey))
    
    $results += [PSCustomObject]@{
        UIDisplayName = "Core: OneDrive Setup & Startup Routine"
        IsDetected    = $isCoreDetected
        ActionData    = @{ Type = "Core" }
    }

    # 2. Zombie Registry Keys
    $zombieKeys = @("HKCU:\Software\Microsoft\OneDrive\SyncEngine", "HKCU:\Software\Microsoft\OneDrive\Client_Policy")
    foreach ($key in $zombieKeys) {
        $results += [PSCustomObject]@{
            UIDisplayName = "Registry: $($key | Split-Path -Leaf)"
            IsDetected    = (Test-Path -Path $key)
            ActionData    = @{ Type = "Registry"; Path = $key }
        }
    }

    # 3. System Data Folders
    $staticFolders = @("$env:PROGRAMDATA\Microsoft OneDrive", "C:\OneDriveTemp")
    foreach ($folder in $staticFolders) {
        $results += [PSCustomObject]@{
            UIDisplayName = "Folder: $folder"
            IsDetected    = (Test-Path -Path $folder)
            ActionData    = @{ Type = "Folder"; Path = $folder }
        }
    }

    # 4. User Profiles Data Folders
    $users = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("Public", "Default", "All Users") }
    foreach ($user in $users) { 
        $userPath = "$($user.FullName)\AppData\Local\Microsoft\OneDrive"
        $results += [PSCustomObject]@{
            UIDisplayName = "User Data: $($user.Name)"
            IsDetected    = (Test-Path -Path $userPath)
            ActionData    = @{ Type = "Folder"; Path = $userPath }
        }
    }

    return $results
}

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
        "*DevHome*", "*PowerAutomateDesktop*", "*Copilot*", "*Edge.GameAssist*", 
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

        $validInstalled = @()
        $totalSizeMB = 0

        foreach ($pkg in $foundInstalled) {
            $loc = $pkg.InstallLocation
            $pkgSizeMB = 0
            
            if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path $loc)) {
                # High-speed silent recursive read to bypass isolated ACL locks
                $bytes = (Get-ChildItem -Path $loc -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                if ($null -ne $bytes) { $pkgSizeMB = $bytes / 1MB }
            }
            
            $totalSizeMB += $pkgSizeMB
            
            # Strict 10MB cutoff. Anything smaller is a dead stub/shell.
            if ($pkgSizeMB -ge 10) { 
                $validInstalled += $pkg 
            }
        }

        # Detection logic: Only flag if a substantial payload exists OR if it's deeply rooted in the Provisioned Base Image
        $isDetected = ($validInstalled.Count -gt 0) -or ($foundProv.Count -gt 0)
        $cleanName = $app.Replace("*", "") 

        # Format UX Label
        $sizeLabel = ""
        if ($isDetected) {
            if ($totalSizeMB -ge 10) {
                $sizeLabel = " ([math]::Round($totalSizeMB, 1) MB)"
            } elseif ($foundProv.Count -gt 0) {
                $sizeLabel = " (Provisioned Base Image)"
            }
        }

        $results += [PSCustomObject]@{
            UIDisplayName = "$cleanName$sizeLabel"
            IsDetected    = $isDetected
            ActionData    = @{ Installed = $validInstalled; Provisioned = $foundProv }
        }
    }
    
    return $results
}

function Get-CapabilityStubState {
    # Queries CBS directly for any installed packages acting as empty shells/stubs
    $cbsStubs = Get-WindowsPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -match "(?i)stub" -and $_.PackageState -eq "Installed" }
    
    $results = @()
    foreach ($stub in $cbsStubs) {
        $cleanName = ($stub.PackageName -split '~')[0]
        $results += [PSCustomObject]@{
            UIDisplayName = "CBS Stub: $cleanName"
            IsDetected    = $true
            ActionData    = $stub.PackageName
        }
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
    
    # Pre-kill processes to unlock files/folders
    Stop-Process -Name "OneDrive", "OneDriveSetup" -Force -ErrorAction SilentlyContinue
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

                # 1. Graceful uninstall (removes AppData payloads)
                if (Test-Path $setupX64) { 
                    Start-Process $setupX64 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                } elseif (Test-Path $setupX86) { 
                    Start-Process $setupX86 -ArgumentList "/uninstall" -NoNewWindow -Wait 
                }
                
                Start-Sleep -Seconds 2

                # 2. Bruteforce binary amputation (Bypass TrustedInstaller)
                foreach ($bin in @($setupX64, $setupX86)) {
                    if (Test-Path -Path $bin) {
                        try {
                            & takeown.exe /F $bin /A | Out-Null
                            & icacls.exe $bin /grant "Administrators:F" /c /q | Out-Null
                            Remove-Item -Path $bin -Force -ErrorAction Stop
                        } catch {
                            Write-GUI "    [!] Failed to amputate $($bin): $($_.Exception.Message)"
                        }
                    }
                }

                # 3. Kill Run key
                reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>$null
            }
            elseif ($data.Type -eq "Registry") {
                if (Test-Path -Path $data.Path) { Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop }
            }
            elseif ($data.Type -eq "Folder") {
                if (Test-Path -Path $data.Path) { Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop }
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
            try { Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop } catch { }
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
                Remove-AppxProvisionedPackage -Online -PackageName $item.ActionData.Target -ErrorAction Stop
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

    Stop-Process -Name "Widgets", "StoreExperienceHost", "WinStore.App", "Copilot" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "ClipSVC" -Force -ErrorAction SilentlyContinue

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        # [FIX] Target GPO isolation - strictly bound to selected Copilot
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

        # Process Installed Packages
        foreach ($pkg in $item.ActionData.Installed) {
            $pfn = $pkg.PackageFamilyName
            
            try { 
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop 
                
                # [FIX] Permanently blacklist the package from Appx Deployment Service respawning
                if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                    $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                    if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                }
            } catch { 
                # Scoped Fallback solely for Copilot
                if ($pkg.Name -match "(?i)Copilot") {
                    Write-GUI "    [!] API uninstallation blocked for $($pkg.Name)."
                    Write-GUI "    [*] Forcing physical directory amputation..."
                    
                    $appDir = $pkg.InstallLocation
                    if (-not [string]::IsNullOrWhiteSpace($appDir) -and (Test-Path $appDir)) {
                        try {
                            & takeown.exe /F $appDir /A /R /D Y | Out-Null
                            & icacls.exe $appDir /grant "Administrators:F" /T /C /Q | Out-Null
                            Remove-Item -Path $appDir -Recurse -Force -ErrorAction Stop
                            
                            # Apply blacklist post-amputation
                            if (-not [string]::IsNullOrWhiteSpace($pfn)) {
                                $deprovPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$pfn"
                                if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                            }
                            
                            Write-GUI "    [+] Physical amputation applied. Package is dead."
                        } catch {
                            Write-GUI "    [-] Amputation failed: $($_.Exception.Message)"
                        }
                    } else {
                        Write-GUI "    [-] Install location null or not found. Cannot amputate."
                    }
                } else {
                    Write-GUI "    [-] Error removing $($pkg.Name): $($_.Exception.Message)"
                }
            }
        }
        
        # Process Provisioned Packages (Base Images)
        foreach ($prov in $item.ActionData.Provisioned) {
            try { 
                Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop 
            } catch { 
                Write-GUI "    [-] Error removing provisioned package $($prov.DisplayName): $($_.Exception.Message)"
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
            Remove-WindowsPackage -Online -PackageName $item.ActionData -NoRestart -ErrorAction Stop
        } catch { 
            Write-GUI "    [!] Error purging stub: $($_.Exception.Message)" 
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> CBS capability stubs successfully eradicated."
}

function Initialize-Z2UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabApps = New-Object System.Windows.Forms.TabPage
    $tabApps.Text = "Bloatware"
    $tabApps.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # OneDrive
    $btnOneDrive = New-Object System.Windows.Forms.Button
    $btnOneDrive.Text = "Uninstall & Deprovision OneDrive"
    $btnOneDrive.Location = New-Object System.Drawing.Point(15, 20)
    $btnOneDrive.Size = New-Object System.Drawing.Size(320, 40)
    $btnOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 100)
    $btnOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnOneDrive.FlatStyle = "Flat"
    $btnOneDrive.Add_MouseEnter({ Show-Description "Completely uninstalls OneDrive, burns it from the Registry, and physically deletes folders across all profiles." })
    $btnOneDrive.Add_Click({ 
        Write-GUI "Initializing OneDrive Scanner..."
        $auditData = Get-OneDriveState
        $detected = $auditData | Where-Object { $_.IsDetected }
        
        if ($detected.Count -eq 0) {
            Write-GUI "  [OK] System is perfectly clean. No OneDrive presence detected.`n"
            return
        }
        
        $selectedData = Show-ActionModal -Title "WinUltix - OneDrive" -Description "Select specific OneDrive traces to eradicate." -AuditResults $auditData
        if ($null -ne $selectedData) { 
            Invoke-RemoveOneDrive -SelectedItems $selectedData.Items
            Write-GUI "" 
        } else { 
            Write-GUI "Operation cancelled."
            Write-GUI "" 
        } 
    })

    $btnAudOneDrive = New-Object System.Windows.Forms.Button
    $btnAudOneDrive.Text = "?"
    $btnAudOneDrive.Location = New-Object System.Drawing.Point(345, 20)
    $btnAudOneDrive.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudOneDrive.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudOneDrive.ForeColor = [System.Drawing.Color]::White
    $btnAudOneDrive.FlatStyle = "Flat"
    $btnAudOneDrive.Add_MouseEnter({ Show-Description "AUDIT: Scans for active OneDrive installers and startup keys." })
    $btnAudOneDrive.Add_Click({ 
        Write-GUI "--- AUDIT: OneDrive ---"
        $state = Get-OneDriveState
        $detected = $state | Where-Object { $_.IsDetected }
        
        if ($detected.Count -gt 0) { 
            foreach ($d in $detected) { Write-GUI "  [!] Found: $($d.UIDisplayName)" }
        } else { 
            Write-GUI "  [OK] System clean. No OneDrive presence detected." 
        }
        Write-GUI "" 
    })

    # Capabilities (FOD)
    $btnCaps = New-Object System.Windows.Forms.Button
    $btnCaps.Text = "Remove System Features (FOD)"
    $btnCaps.Location = New-Object System.Drawing.Point(15, 70)
    $btnCaps.Size = New-Object System.Drawing.Size(320, 40)
    $btnCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCaps.ForeColor = [System.Drawing.Color]::White
    $btnCaps.FlatStyle = "Flat"
    $btnCaps.Add_MouseEnter({ Show-Description "Interactive removal of optional built-in Features on Demand (FOD)." })
    $btnCaps.Add_Click({ 
        Write-GUI "Initializing Capabilities Scanner..."
        $auditData = Get-CapabilitiesState
        $selectedData = Show-ActionModal -Title "WinUltix - FOD Removal" -Description "Select features to remove." -AuditResults $auditData
        if ($null -ne $selectedData) { 
            Invoke-RemoveCapabilities -SelectedItems $selectedData.Items
            Write-GUI "" 
        } else { 
            Write-GUI "Operation cancelled."
            Write-GUI "" 
        } 
    })
    
    $btnAudCaps = New-Object System.Windows.Forms.Button
    $btnAudCaps.Text = "?"
    $btnAudCaps.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudCaps.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudCaps.ForeColor = [System.Drawing.Color]::White
    $btnAudCaps.FlatStyle = "Flat"
    $btnAudCaps.Add_MouseEnter({ Show-Description "AUDIT: Verifies installed unnecessary Capabilities (FOD)." })
    $btnAudCaps.Add_Click({ Write-GUI "--- AUDIT: Built-in Features ---"; $state = Get-CapabilitiesState; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] Found: $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Clean." }; Write-GUI "" })

    # Aggressive Bloatware
    $btnBloat = New-Object System.Windows.Forms.Button
    $btnBloat.Text = "Aggressive Bloatware Removal (Appx)"
    $btnBloat.Location = New-Object System.Drawing.Point(15, 120)
    $btnBloat.Size = New-Object System.Drawing.Size(320, 40)
    $btnBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnBloat.ForeColor = [System.Drawing.Color]::White
    $btnBloat.FlatStyle = "Flat"
    $btnBloat.Add_MouseEnter({ Show-Description "Aggressive, interactive removal of junk Appx applications from the system." })
    $btnBloat.Add_Click({ 
        Write-GUI "Initializing Appx Scanner..."
        $auditData = Get-BloatwareState
        $selectedData = Show-ActionModal -Title "WinUltix - Bloatware Removal" -Description "Select components to remove. Detected items are checked by default." -AuditResults $auditData
        if ($null -ne $selectedData) { 
            Invoke-RemoveBloatware -SelectedItems $selectedData.Items
            Write-GUI "" 
        } else { 
            Write-GUI "Operation cancelled."
            Write-GUI "" 
        } 
    })

    $btnAudBloat = New-Object System.Windows.Forms.Button
    $btnAudBloat.Text = "?"
    $btnAudBloat.Location = New-Object System.Drawing.Point(345, 120)
    $btnAudBloat.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudBloat.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudBloat.ForeColor = [System.Drawing.Color]::White
    $btnAudBloat.FlatStyle = "Flat"
    $btnAudBloat.Add_MouseEnter({ Show-Description "AUDIT: Scans the system for target Appx Bloatware and prints a report." })
    $btnAudBloat.Add_Click({ Write-GUI "--- AUDIT: Bloatware (Appx) ---"; $state = Get-BloatwareState; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] Found: $($d.UIDisplayName)" }; Write-GUI "-> STATUS: $($detected.Count) junk apps." } else { Write-GUI "  [OK] Clean." }; Write-GUI "" })

    # Garbage Collector
    $btnGC = New-Object System.Windows.Forms.Button
    $btnGC.Text = "Run Appx Garbage Collector"
    $btnGC.Location = New-Object System.Drawing.Point(15, 170)
    $btnGC.Size = New-Object System.Drawing.Size(320, 40)
    $btnGC.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 80, 40)
    $btnGC.ForeColor = [System.Drawing.Color]::White
    $btnGC.FlatStyle = "Flat"
    $btnGC.Add_MouseEnter({ Show-Description "Intelligently scans application dependencies and removes orphaned frameworks." })
    $btnGC.Add_Click({ 
        Write-GUI "Initializing Garbage Collector..."
        $auditData = Get-GarbageCollectorState
        $detected = $auditData | Where-Object { $_.IsDetected }
        
        if ($detected.Count -eq 0) { 
            Write-GUI "  [OK] System is perfectly clean! No orphaned components.`n"
            return 
        }
        
        $selectedData = Show-ActionModal -Title "WinUltix - Garbage Collector" -Description "Select orphaned packages to remove." -AuditResults $auditData
        if ($null -ne $selectedData) { 
            Invoke-GarbageCollector -SelectedItems $selectedData.Items
            Write-GUI "" 
        } else { 
            Write-GUI "Operation cancelled."
            Write-GUI "" 
        } 
    })

    $btnAudGC = New-Object System.Windows.Forms.Button
    $btnAudGC.Text = "?"
    $btnAudGC.Location = New-Object System.Drawing.Point(345, 170)
    $btnAudGC.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudGC.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudGC.ForeColor = [System.Drawing.Color]::White
    $btnAudGC.FlatStyle = "Flat"
    $btnAudGC.Add_MouseEnter({ Show-Description "AUDIT: Scans and lists all orphaned frameworks that will be removed." })
    $btnAudGC.Add_Click({ Write-GUI "--- AUDIT: Garbage Collector ---"; $state = Get-GarbageCollectorState; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] $($d.UIDisplayName)" } } else { Write-GUI "  [OK] Clean." }; Write-GUI "" })

    # CBS Capability Stubs
    $btnStubs = New-Object System.Windows.Forms.Button
    $btnStubs.Text = "Purge Capability Stubs (CBS)"
    $btnStubs.Location = New-Object System.Drawing.Point(15, 220)
    $btnStubs.Size = New-Object System.Drawing.Size(320, 40)
    $btnStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 60, 100)
    $btnStubs.ForeColor = [System.Drawing.Color]::White
    $btnStubs.FlatStyle = "Flat"
    $btnStubs.Add_MouseEnter({ Show-Description "Scans and eradicates underlying CBS Stub packages to permanently declutter the Windows Capabilities list." })
    $btnStubs.Add_Click({ 
        Write-GUI "Initializing CBS Stub Scanner..."
        $auditData = Get-CapabilityStubState
        $detected = $auditData | Where-Object { $_.IsDetected }
        
        if ($detected.Count -eq 0) { 
            Write-GUI "  [OK] CBS store is completely clean. No stubs detected.`n"
            return 
        }
        
        $selectedData = Show-ActionModal -Title "WinUltix - Stub Purge" -Description "Select stubs to rip from the CBS store." -AuditResults $auditData
        if ($null -ne $selectedData) { 
            Invoke-RemoveCapabilityStubs -SelectedItems $selectedData.Items
            Write-GUI "" 
        } else { 
            Write-GUI "Operation cancelled."
            Write-GUI "" 
        } 
    })

    $btnAudStubs = New-Object System.Windows.Forms.Button
    $btnAudStubs.Text = "?"
    $btnAudStubs.Location = New-Object System.Drawing.Point(345, 220)
    $btnAudStubs.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudStubs.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudStubs.ForeColor = [System.Drawing.Color]::White
    $btnAudStubs.FlatStyle = "Flat"
    $btnAudStubs.Add_MouseEnter({ Show-Description "AUDIT: Queries CBS registry/payload directly for active stubs." })
    $btnAudStubs.Add_Click({ Write-GUI "--- AUDIT: CBS Stubs ---"; $state = Get-CapabilityStubState; $detected = $state | Where-Object { $_.IsDetected }; if ($detected.Count -gt 0) { foreach ($d in $detected) { Write-GUI "  [!] $($d.UIDisplayName)" } } else { Write-GUI "  [OK] No CBS stubs detected." }; Write-GUI "" })

    $tabApps.Controls.AddRange(@($btnOneDrive, $btnAudOneDrive, $btnCaps, $btnAudCaps, $btnBloat, $btnAudBloat, $btnGC, $btnAudGC, $btnStubs, $btnAudStubs ))
    $TabControl.Controls.Add($tabApps)
}