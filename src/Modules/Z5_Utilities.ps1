# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - UTILITIES & APPLETS MODULE (v3.0.0)
# Z5_Utilities: Asynchronous interactive system inspectors (Appx, Provisioned, FOD, Optional Features, Services with TrustedInstaller DACL escalation, Deep Startup Manager with StartupApproved binary decoding, Scheduled Tasks Inspector for 3rd-party/bloat/ghost tasks), Dual-Stack IPv4/IPv6 + Native DoH DNS Enforcer, and classic Windows applet launchers.
# ==========================================

# ------------------------------------------
# Z5: ASYNC INTERACTIVE GRIDS (APPX, PROV, FOD, OPT, SERVICES)
# ------------------------------------------
function Show-AppxGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning installed Appx packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop|ShellExperienceHost|StartMenuExperienceHost|immersivecontrolpanel|SecHealthUI|WindowsDefender"
        
        $pkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
            Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } |
            Select-Object Name, PackageFullName, PackageFamilyName, IsFramework, Status |
            Sort-Object Name)
        return $pkgs
    } -OnComplete {
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
                        if (-not (Test-Path $deprovPath)) { New-Item -Path $deprovPath -Force -ErrorAction SilentlyContinue | Out-Null }
                    }
                    $UltixSync.Logs.Enqueue("    [OK] $($app.Name) removed and deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error removing $($app.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Appx removal routine finished.`n"
        }
    }.GetNewClosure()
}

function Show-AppxProvGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Scanning Provisioned Appx image packages (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
        
        $pkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -notmatch $protectedPattern } |
            Select-Object DisplayName, Version, PackageName |
            Sort-Object DisplayName)
        return $pkgs
    } -OnComplete {
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
                    $UltixSync.Logs.Enqueue("    [OK] $($app.DisplayName) deprovisioned.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Selected Provisioned packages removed from image.`n"
        }
    }.GetNewClosure()
}

function Show-CapsGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Querying installed Windows Capabilities / FOD (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $caps = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.State -eq 'Installed' } |
            Select-Object Name, State |
            Sort-Object Name)
        return $caps
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$caps = @($output | Where-Object { $null -ne $_ })
        if ($caps.Count -eq 0) {
            Write-GUI " -> No installed Capabilities returned.`n"
            return
        }

        $cols = @(
            @{ Header = "Capability Name (FOD)"; Property = "Name";  Width = 680 }
            @{ Header = "State";                 Property = "State"; Width = 160 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Windows Capabilities (FOD)" `
            -Description "Select installed Features on Demand (FOD) to uninstall from the OS image." `
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
                $UltixSync.Logs.Enqueue(" -> Removing capability: $($cap.Name)")
                try {
                    Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                    $UltixSync.Logs.Enqueue("    [OK] $($cap.Name) removed.")
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] Failed to remove $($cap.Name): $($_.Exception.Message)")
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Capability removal finished.`n"
        }
    }.GetNewClosure()
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
    } -OnComplete {
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
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Optional Features processing completed.`n"
        }
    }.GetNewClosure()
}

function Show-ServicesGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Generating complete system services table (Background Thread)..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        # Critical kernel/SCM/RPC services protected from modification
        $criticalServices = "^(RpcSs|DcomLaunch|RpcEptMapper|LSM|SamSs|PlugPlay|EventLog|BFE|mpssvc|nsi|ProfSvc|gpsvc|CryptSvc|TrustedInstaller|WinDefend|WdNisSvc|SecurityHealthService|Dhcp|Dnscache|Winmgmt|Schedule|UserManager|CoreMessagingRegistrar|SystemEventsBroker|Power|BrokerInfrastructure)$"
        
        $svcs = @(Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            $isCrit = ($_.Name -match $criticalServices)
            $startDisp = if ($isCrit) { "$($_.StartType) [CRITICAL - LOCKED]" } else { [string]$_.StartType }
            [PSCustomObject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                Status      = [string]$_.Status
                StartType   = $startDisp
                IsLocked    = $isCrit
            }
        } | Sort-Object Status, Name)
        return $svcs
    } -OnComplete {
        param($output)
        Update-Progress 0
        [array]$svcs = @($output | Where-Object { $null -ne $_ })

        $cols = @(
            @{ Header = "Service Name"; Property = "Name";        Width = 200 }
            @{ Header = "Status";       Property = "Status";      Width = 95  }
            @{ Header = "Start Type";   Property = "StartType";   Width = 175 }
            @{ Header = "Display Name"; Property = "DisplayName"; Width = 375 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - System Services Manager" `
            -Description "Select services to HARD DISABLE or restore to Manual. Critical OS/RPC/Defender services (Red) are visible for inspection but locked against modification." `
            -Data $svcs -Columns $cols -PrimaryButtonText "Stop & Disable Selected" `
            -SecondaryButtonText "Restore to Manual (Demand)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Service modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0
            foreach ($svc in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)
                if ($svc.IsLocked) { continue }

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Disabling service: $($svc.Name) ($($svc.DisplayName))")
                    try {
                        Stop-Service -Name $svc.Name -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 4
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) stopped and locked to Disabled (Start=4).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to disable $($svc.Name): $($_.Exception.Message)")
                    }
                } else {
                    $UltixSync.Logs.Enqueue(" -> Restoring service to Manual: $($svc.Name)")
                    try {
                        Set-ProtectedServiceStart -ServiceName $svc.Name -StartValue 3
                        $UltixSync.Logs.Enqueue("    [OK] $($svc.Name) set to Manual (Start=3).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to modify $($svc.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Service operations completed.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: DEEP STARTUP INSPECTOR (RUN, RUNONCE, POLICIES, STARTUPAPPROVED)
# ------------------------------------------
function Get-StartupState_Worker {
    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    function Resolve-StartupApprovedState {
        param([string]$ApprovedRegPath, [string]$EntryName)
        if ([string]::IsNullOrWhiteSpace($ApprovedRegPath) -or -not (Test-Path $ApprovedRegPath)) {
            return "Enabled"
        }
        try {
            $key = Get-Item -Path $ApprovedRegPath -ErrorAction SilentlyContinue
            if ($null -eq $key) { return "Enabled" }
            try {
                [byte[]]$bin = $key.GetValue($EntryName, $null)
            } finally {
                $key.Dispose()
            }
            if ($null -eq $bin -or $bin.Length -lt 1) { return "Enabled" }

            # In Windows Task Manager, byte[0] == 0x02 or 0x06 indicates Enabled; odd/other bytes (0x03, 0x01) mean Disabled
            $header = [int]$bin[0]
            if ($header -eq 2 -or $header -eq 6) {
                return "Enabled"
            } else {
                if ($bin.Length -ge 12) {
                    $ft = [BitConverter]::ToInt64($bin, 4)
                    if ($ft -gt 0) {
                        $dt = [DateTime]::FromFileTimeUtc($ft).ToLocalTime().ToString("yyyy-MM-dd")
                        return "Disabled ($dt)"
                    }
                }
                return "Disabled (TaskMgr)"
            }
        } catch {
            return "Enabled"
        }
    }

    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKLM Run (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";       Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Label = "HKLM Run (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";                   Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";   Label = "HKCU Run" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKLM RunOnce (x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce";   Approved = "";                                                                               Label = "HKLM RunOnce (x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";               Approved = "";                                                                               Label = "HKCU RunOnce" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKLM)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"; Approved = "";                                                                               Label = "GPO Run (HKCU)" }
    )

    foreach ($reg in $regTargets) {
        if (Test-Path $reg.Path) {
            $keyObj = Get-Item -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $keyObj) {
                try {
                    foreach ($valName in $keyObj.Property) {
                        $valData = [string]$keyObj.GetValue($valName)
                        $state = if ($reg.Approved -ne "") {
                            Resolve-StartupApprovedState -ApprovedRegPath $reg.Approved -EntryName $valName
                        } else {
                            "Enabled (Always)"
                        }
                        $startupItems.Add([PSCustomObject]@{
                            Name         = $valName
                            State        = $state
                            Location     = $reg.Label
                            Command      = $valData
                            RegPath      = $reg.Path
                            ApprovedPath = $reg.Approved
                            Type         = "Registry"
                        })
                    }
                } finally {
                    $keyObj.Dispose()
                }
            }
        }
    }

    $folderTargets = @(
        @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (All Users)" }
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Label = "Folder (Current User)" }
    )

    foreach ($fld in $folderTargets) {
        if (Test-Path $fld.Path) {
            Get-ChildItem -Path $fld.Path -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -ne "desktop.ini") {
                    $state = Resolve-StartupApprovedState -ApprovedRegPath $fld.Approved -EntryName $_.Name
                    $startupItems.Add([PSCustomObject]@{
                        Name         = $_.Name
                        State        = $state
                        Location     = $fld.Label
                        Command      = $_.FullName
                        RegPath      = $null
                        ApprovedPath = $fld.Approved
                        Type         = "File"
                    })
                }
            }
        }
    }

    return @($startupItems | Sort-Object Location, Name)
}

function Show-StartupGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Run, RunOnce, GPO Run, Startup Folders, and StartupApproved binary states..."
    Update-Progress 20

    $sb = (Get-Command -Name Get-StartupState_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete {
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No startup items detected across registry or folders.`n"
            return
        }

        $cols = @(
            @{ Header = "Entry Name"; Property = "Name";     Width = 210 }
            @{ Header = "State";      Property = "State";    Width = 145 }
            @{ Header = "Location";   Property = "Location"; Width = 155 }
            @{ Header = "Command";    Property = "Command";  Width = 340 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Deep Startup Inspector" `
            -Description "Inspect Run, RunOnce, GPO, and StartupApproved states. You can permanently delete entries or toggle their TaskMgr state." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Permanent)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Startup modification cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    # Permanent Removal + StartupApproved orphan cleanup
                    $UltixSync.Logs.Enqueue(" -> Deleting startup entry: $($item.Name) [$($item.Location)]")
                    try {
                        if ($item.Type -eq "Registry") {
                            Remove-ItemProperty -Path $item.RegPath -Name $item.Name -Force -ErrorAction Stop
                        } else {
                            Remove-Item -LiteralPath $item.Command -Force -ErrorAction Stop
                        }
                        if (-not [string]::IsNullOrWhiteSpace($item.ApprovedPath) -and (Test-Path $item.ApprovedPath)) {
                            Remove-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Force -ErrorAction SilentlyContinue
                        }
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    # Non-destructive Toggle via StartupApproved binary header
                    if ([string]::IsNullOrWhiteSpace($item.ApprovedPath)) {
                        $UltixSync.Logs.Enqueue("    [!] $($item.Name) [$($item.Location)] does not support TaskMgr StartupApproved toggling.")
                        continue
                    }
                    try {
                        if (-not (Test-Path $item.ApprovedPath)) {
                            New-Item -Path $item.ApprovedPath -Force | Out-Null
                        }
                        if ($item.State -match "^Disabled") {
                            # Enable: 12-byte array starting with 0x02
                            [byte[]]$enableBytes = @(0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $enableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.Name) [$($item.Location)]")
                        } else {
                            # Disable: 0x03 header + 3 zero padding bytes + 8-byte UTC FILETIME
                            [byte[]]$headerBytes = @(0x03, 0x00, 0x00, 0x00)
                            [byte[]]$timeBytes   = [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())
                            [byte[]]$disableBytes = $headerBytes + $timeBytes
                            Set-ItemProperty -Path $item.ApprovedPath -Name $item.Name -Value $disableBytes -Type Binary -Force -ErrorAction Stop
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.Name) [$($item.Location)]")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Startup configuration updated.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: SCHEDULED TASKS INSPECTOR (3RD-PARTY, BLOAT & GHOST TASKS)
# ------------------------------------------
function Get-ScheduledTasks_Worker {
    $taskItems = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Resolve whether an MSFT_TaskExecAction binary exists on disk
    function Test-TaskExecutableExists {
        param([string]$RawExecute)
        if ([string]::IsNullOrWhiteSpace($RawExecute)) { return $true }

        $clean = [System.Environment]::ExpandEnvironmentVariables($RawExecute.Trim().Trim('"')).Trim()
        if ($clean -match '^"([^"]+)"') {
            $clean = $matches[1]
        } elseif ($clean -match '(?i)^(.+?\.(?:exe|bat|cmd|vbs|ps1|msc))(?:$|\s)') {
            $clean = $matches[1]
        } else {
            $clean = $clean.Split(' ')[0]
        }

        # Ignore shell variables or custom protocol handlers
        if ($clean -match '^\$\(' -or $clean -match '^[a-zA-Z]+://') { return $true }

        if ([System.IO.Path]::IsPathRooted($clean)) {
            return [System.IO.File]::Exists($clean)
        } else {
            $leaf = if ($clean -notmatch '\.') { "$clean.exe" } else { $clean }
            foreach ($dir in @("$env:windir\System32", $env:windir, "$env:windir\SysWOW64", "$env:windir\System32\wbem", "$env:windir\System32\WindowsPowerShell\v1.0")) {
                if ([System.IO.File]::Exists((Join-Path $dir $leaf))) { return $true }
            }
            return $true
        }
    }

    # Format CIM triggers into concise engineering tags
    function ConvertTo-TriggerSummary {
        param([array]$Triggers)
        if ($null -eq $Triggers -or $Triggers.Count -eq 0) { return "OnDemand" }
        $tags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in $Triggers) {
            $className = [string]$t.CimClass.CimClassName
            switch -Wildcard ($className) {
                "*LogonTrigger*"              { [void]$tags.Add("AtLogon") }
                "*BootTrigger*"               { [void]$tags.Add("AtStartup") }
                "*DailyTrigger*"              { [void]$tags.Add("Daily") }
                "*WeeklyTrigger*"             { [void]$tags.Add("Weekly") }
                "*TimeTrigger*"               { [void]$tags.Add("Time/Once") }
                "*IdleTrigger*"               { [void]$tags.Add("OnIdle") }
                "*EventTrigger*"              { [void]$tags.Add("OnEvent") }
                "*SessionStateChangeTrigger*" { [void]$tags.Add("SessionChange") }
                "*RegistrationTrigger*"       { [void]$tags.Add("OnRegister") }
                default                       { [void]$tags.Add("Custom") }
            }
            if ($null -ne $t.Repetition -and -not [string]::IsNullOrWhiteSpace($t.Repetition.Interval)) {
                [void]$tags.Add("Periodic")
            }
        }
        return ($tags -join ", ")
    }

    # Shield WinUltix internal failsafe and critical OS security tasks
    $protectedTaskNames = "^(WinUltix_CPPC_Failsafe|MpIdleTask|Windows Defender.*|BitLocker.*)$"
    $msTelemetryPaths   = "(?i)^\\Microsoft\\Windows\\(Application Experience|Autochk|Customer Experience Improvement Program|DiskDiagnostic|Feedback|Location|Maps|Mobile Broadband Accounts|NetTrace|Power Efficiency Diagnostics|PushToInstall|RetailDemo|CloudExperienceHost|Windows Error Reporting|WaaSMedic)\\"

    $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    $total = [math]::Max(1, $allTasks.Count)
    $idx = 0

    foreach ($task in $allTasks) {
        $idx++
        if ($null -ne $UltixSync -and ($idx % 15 -eq 0 -or $idx -eq $total)) {
            $UltixSync.Progress = [int](($idx / $total) * 100)
        }

        $tName  = [string]$task.TaskName
        $tPath  = [string]$task.TaskPath
        $tState = [string]$task.State

        if ($tName -match $protectedTaskNames) { continue }

        # Extract execution action and verify binary presence
        $execAction = $task.Actions | Where-Object { $null -ne $_.Execute -and $_.Execute -ne "" } | Select-Object -First 1
        $cmdLine = ""
        $isGhost = $false

        if ($null -ne $execAction) {
            $rawExe  = [string]$execAction.Execute
            $rawArgs = [string]$execAction.Arguments
            $cmdLine = "$rawExe $rawArgs".Trim()
            if (-not (Test-TaskExecutableExists -RawExecute $rawExe)) {
                $isGhost = $true
            }
        } else {
            $comAction = $task.Actions | Where-Object { $null -ne $_.ClassId } | Select-Object -First 1
            if ($null -ne $comAction) {
                $cmdLine = "[COM Handler] $($comAction.ClassId)"
            } else {
                $cmdLine = "[Internal Handler]"
            }
        }

        # Categorize and filter out standard non-telemetry Microsoft\Windows OS internals unless orphaned
        $category = ""
        if ($isGhost) {
            $category = "[GHOST / Missing Exe]"
        } elseif ($tPath -notlike "\Microsoft\Windows\*") {
            if ($tPath -like "\Microsoft\*") {
                $category = "[MS App / Updater]"
            } else {
                $category = "[3rd-Party / Root]"
            }
        } elseif ($tPath -match $msTelemetryPaths -or $tPath -like "\Microsoft\XblGameSave\*") {
            $category = "[MS Telemetry / Bloat]"
        } else {
            # Core healthy Windows internal task - skip to keep the grid clean and high-signal
            continue
        }

        $trigSummary = ConvertTo-TriggerSummary -Triggers @($task.Triggers)

        $taskItems.Add([PSCustomObject]@{
            Name     = $tName
            Category = $category
            State    = $tState
            Triggers = $trigSummary
            TaskPath = $tPath
            Command  = $cmdLine
        })
    }

    return @($taskItems | Sort-Object Category, TaskPath, Name)
}

function Show-TasksGrid {
    param([System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI " -> Auditing Task Scheduler for 3rd-party updaters, telemetry, and orphaned ghost tasks..."
    Update-Progress 10

    $sb = (Get-Command -Name Get-ScheduledTasks_Worker).ScriptBlock
    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock $sb -OnComplete {
        param($output)
        Update-Progress 0
        [array]$items = @($output | Where-Object { $null -ne $_ })
        if ($items.Count -eq 0) {
            Write-GUI " -> No third-party, telemetry, or orphaned scheduled tasks found.`n"
            return
        }

        $cols = @(
            @{ Header = "Task Name"; Property = "Name";     Width = 195 }
            @{ Header = "Category";  Property = "Category"; Width = 155 }
            @{ Header = "State";     Property = "State";    Width = 80  }
            @{ Header = "Triggers";  Property = "Triggers"; Width = 120 }
            @{ Header = "Folder";    Property = "TaskPath"; Width = 140 }
            @{ Header = "Action";    Property = "Command";  Width = 280 }
        )

        $res = Show-UltixGridModal -Title "WinUltix - Scheduled Tasks Inspector (3rd-Party, Telemetry & Ghosts)" `
            -Description "Core Windows tasks are hidden. Inspect 3rd-party updaters, MS bloat, and [GHOST] tasks with missing binaries." `
            -Data $items -Columns $cols -PrimaryButtonText "Remove Selected (Unregister)" `
            -SecondaryButtonText "Toggle State (Enable / Disable)"

        if ($null -eq $res -or $res.Items.Count -eq 0) {
            Write-GUI " -> Scheduled tasks operation cancelled.`n"
            return
        }

        Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($res.Items, $res.Action) -ScriptBlock {
            param([array]$Selected, [string]$Action)
            $total = $Selected.Count
            $current = 0

            foreach ($item in $Selected) {
                $current++
                $UltixSync.Progress = [int](($current / $total) * 100)

                if ($Action -eq "Primary") {
                    $UltixSync.Logs.Enqueue(" -> Unregistering task: $($item.TaskPath)$($item.Name)")
                    try {
                        Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                        Unregister-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -Confirm:$false -ErrorAction Stop
                        $UltixSync.Logs.Enqueue("    [OK] Permanently removed $($item.Name).")
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to remove $($item.Name): $($_.Exception.Message)")
                    }
                } else {
                    try {
                        if ($item.State -eq "Disabled") {
                            Enable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [ENABLED]  $($item.TaskPath)$($item.Name)")
                        } else {
                            Stop-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction SilentlyContinue | Out-Null
                            Disable-ScheduledTask -TaskName $item.Name -TaskPath $item.TaskPath -ErrorAction Stop | Out-Null
                            $UltixSync.Logs.Enqueue(" -> [DISABLED] $($item.TaskPath)$($item.Name)")
                        }
                    } catch {
                        $UltixSync.Logs.Enqueue("    [!] Failed to toggle $($item.Name): $($_.Exception.Message)")
                    }
                }
            }
        } -OnComplete {
            param($nullOut)
            Update-Progress 0
            Write-GUI " -> Scheduled Tasks operations completed.`n"
        }
    }.GetNewClosure()
}

# ------------------------------------------
# Z5: DNS ENFORCER (IPV4 + IPV6 + NATIVE WINDOWS 11 DOH)
# ------------------------------------------
function Set-CustomDNS {
    param(
        [Parameter(Mandatory=$true)][string]$Provider,
        [bool]$EnableDoH = $true,
        [bool]$EnableIPv6 = $true,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    Write-GUI " -> Applying DNS profile '$Provider' (DoH: $EnableDoH, IPv6: $EnableIPv6)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($Provider, $EnableDoH, $EnableIPv6) -ScriptBlock {
        param([string]$TargetProvider, [bool]$UseDoH, [bool]$UseIPv6)

        $dnsCatalog = @{
            "Quad9 (9.9.9.9)" = @{
                IPv4     = @("9.9.9.9", "149.112.112.112")
                IPv6     = @("2620:fe::fe", "2620:fe::9")
                Template = "https://dns.quad9.net/dns-query"
            }
            "Cloudflare (1.1.1.1)" = @{
                IPv4     = @("1.1.1.1", "1.0.0.1")
                IPv6     = @("2606:4700:4700::1111", "2606:4700:4700::1001")
                Template = "https://cloudflare-dns.com/dns-query"
            }
            "AdGuard (94.140.14.14)" = @{
                IPv4     = @("94.140.14.14", "94.140.15.15")
                IPv6     = @("2a10:50c0::ad1:ff", "2a10:50c0::ad2:ff")
                Template = "https://dns.adguard-dns.com/dns-query"
            }
            "Google (8.8.8.8)" = @{
                IPv4     = @("8.8.8.8", "8.8.4.4")
                IPv6     = @("2001:4860:4860::8888", "2001:4860:4860::8844")
                Template = "https://dns.google/dns-query"
            }
            "OpenDNS (208.67.222.222)" = @{
                IPv4     = @("208.67.222.222", "208.67.220.220")
                IPv6     = @("2620:119:35::35", "2620:119:53::53")
                Template = "https://doh.opendns.com/dns-query"
            }
        }

        # Discover active routed interfaces
        $routedIndices = @(Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty InterfaceIndex -Unique)

        if ($routedIndices.Count -eq 0) {
            $UltixSync.Logs.Enqueue(" [!] No active network adapters with a default gateway found.")
            return
        }

        $wellKnownBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
        $ifSpecBase    = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"

        foreach ($ifIndex in $routedIndices) {
            $adapter = Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
            if ($null -eq $adapter) { continue }
            $ifGuid  = $adapter.InterfaceGuid
            $ifName  = $adapter.InterfaceDescription

            $dohV4Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh"
            $dohV6Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh6"

            # Wipe previous per-interface DoH bindings first
            if (Test-Path $dohV4Root) { Remove-Item -Path $dohV4Root -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path $dohV6Root) { Remove-Item -Path $dohV6Root -Recurse -Force -ErrorAction SilentlyContinue }

            if ($TargetProvider -eq "Default (DHCP)") {
                try {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses -ErrorAction Stop
                    $UltixSync.Logs.Enqueue(" -> [$ifName]: Reverted IPv4/IPv6 DNS to DHCP and cleared DoH locks.")
                } catch {
                    $UltixSync.Logs.Enqueue(" [!] [$ifName]: Failed to reset DNS: $($_.Exception.Message)")
                }
                continue
            }

            $cfg = $dnsCatalog[$TargetProvider]
            if ($null -eq $cfg) { continue }

            $allServers = [System.Collections.Generic.List[string]]::new()
            foreach ($ip4 in $cfg.IPv4) { $allServers.Add($ip4) }
            if ($UseIPv6) {
                foreach ($ip6 in $cfg.IPv6) { $allServers.Add($ip6) }
            }

            try {
                Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($allServers) -ErrorAction Stop
                if (-not $UseIPv6) {
                    # Reset IPv6 DNS to DHCP if user unchecked IPv6 enforcement
                    netsh.exe interface ipv6 set dnsservers name="$($adapter.Name)" source=dhcp 2>$null | Out-Null
                }
                $UltixSync.Logs.Enqueue(" -> [$ifName]: Enforced servers: $($allServers -join ', ')")
            } catch {
                $UltixSync.Logs.Enqueue(" [!] [$ifName]: Error setting DNS servers: $($_.Exception.Message)")
            }

            if ($UseDoH) {
                if (-not (Test-Path $wellKnownBase)) { New-Item -Path $wellKnownBase -Force | Out-Null }

                foreach ($ip in $allServers) {
                    # 1. Register global DoH template in Dnscache well-known store & runtime API
                    $wkKey = "$wellKnownBase\$ip"
                    if (-not (Test-Path $wkKey)) { New-Item -Path $wkKey -Force | Out-Null }
                    Set-ItemProperty -Path $wkKey -Name "Template" -Value $cfg.Template -Type String -Force -ErrorAction SilentlyContinue

                    if (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue) {
                        Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                        Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                    }

                    # 2. Enforce per-interface DoH encryption (DohFlags = 1 QWord)
                    $isV6 = ($ip -match ":")
                    $targetDohKey = if ($isV6) { "$dohV6Root\$ip" } else { "$dohV4Root\$ip" }
                    if (-not (Test-Path $targetDohKey)) { New-Item -Path $targetDohKey -Force | Out-Null }
                    Set-ItemProperty -Path $targetDohKey -Name "DohFlags" -Value ([uint64]1) -Type QWord -Force -ErrorAction SilentlyContinue
                }
                $UltixSync.Logs.Enqueue("    [+] Native DoH encryption activated ($($cfg.Template)).")
            }
        }

        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $UltixSync.Progress = 100
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Update-DNSLabel
        Write-GUI " -> DNS configuration completed and resolver cache flushed.`n"
    }
}

# ------------------------------------------
# Z5: CLASSIC APPLETS
# ------------------------------------------
function Start-ClassicNet      { Start-Process "ncpa.cpl" }
function Start-ClassicApps     { Start-Process "appwiz.cpl" }
function Start-ClassicSound    { Start-Process "mmsys.cpl" }
function Start-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\0\::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }
function Start-ClassicSysProp  { Start-Process "SystemPropertiesAdvanced.exe" }
function Start-ClassicPower    { Start-Process "powercfg.cpl" }

# ------------------------------------------
# Z5: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z5UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabUtil = New-Object System.Windows.Forms.TabPage
    $tabUtil.Text = "Utilities"
    $tabUtil.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # 1. Advanced System Inspectors
    $lblInspect = New-Object System.Windows.Forms.Label
    $lblInspect.Text = "WARNING: Advanced System Inspectors"
    $lblInspect.Location = New-Object System.Drawing.Point(15, 15)
    $lblInspect.Size = New-Object System.Drawing.Size(370, 20)
    $lblInspect.ForeColor = [System.Drawing.Color]::OrangeRed
    $lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblInspect.TextAlign = "MiddleLeft"

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 40 -Width 180 -Height 40 `
        -Text "Appx (Accounts)" `
        -Description "Opens a native dark table of installed Appx packages with live filtering and Deprovisioned store locking." `
        -OnClick { Show-AppxGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 40 -Width 180 -Height 40 `
        -Text "Appx (Image)" `
        -Description "Opens a native dark table of Provisioned Appx packages cached in the Windows image." `
        -OnClick { Show-AppxProvGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 90 -Width 180 -Height 40 `
        -Text "Capabilities (FOD)" `
        -Description "Asynchronously scans installed Features on Demand (FOD) for selective removal." `
        -OnClick { Show-CapsGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 90 -Width 180 -Height 40 `
        -Text "Optional Features" `
        -Description "Asynchronously scans enabled Windows Optional Features to disable unnecessary OS components." `
        -OnClick { Show-OptFeaturesGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 140 -Width 370 -Height 40 `
        -Text "System Services Inspector" `
        -Description "Interactive Services Manager. Hard-disable unneeded services or restore them to Manual (Critical boot services are shielded)." `
        -OnClick { Show-ServicesGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 190 -Width 370 -Height 40 -RGB @(60, 100, 150) `
        -Text "Deep Startup Manager (Run / StartupApproved)" `
        -Description "Audits Run, RunOnce, GPO Run, Startup folders, and decodes TaskMgr StartupApproved binary headers. Supports Toggle or Delete." `
        -OnClick { Show-StartupGrid -ControlsToDisable @($this) })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 240 -Width 370 -Height 40 -RGB @(100, 60, 120) `
        -Text "Scheduled Tasks Inspector (3rd-Party / Ghosts)" `
        -Description "Filters out core OS noise to expose 3rd-party updaters, Microsoft bloat, and orphaned [GHOST] tasks pointing to missing .exe files." `
        -OnClick { Show-TasksGrid -ControlsToDisable @($this) })

    # 2. Classic Windows Control Applets
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Windows Control Applets"
    $lblClassic.Location = New-Object System.Drawing.Point(15, 295)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 320 -Width 180 -Height 40 `
        -Text "Network Adapters (ncpa)" `
        -Description "Direct launch of the classic Win32 Network Connections applet (ncpa.cpl)." `
        -OnClick { Start-ClassicNet })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 320 -Width 180 -Height 40 `
        -Text "Sound Subsystem (mmsys)" `
        -Description "Direct launch of playback/recording devices and sample rate properties (mmsys.cpl)." `
        -OnClick { Start-ClassicSound })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 370 -Width 180 -Height 40 `
        -Text "Programs & Features" `
        -Description "Direct launch of the classic Win32 MSI/InstallShield software uninstaller (appwiz.cpl)." `
        -OnClick { Start-ClassicApps })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 370 -Width 180 -Height 40 `
        -Text "Devices and Printers" `
        -Description "Bypasses Windows 11 Settings redirect to open the raw Win32 Devices and Printers shell folder." `
        -OnClick { Start-ClassicPrinters })

    [void](New-UltixButton -Parent $tabUtil -X 15 -Y 420 -Width 180 -Height 40 `
        -Text "System Properties (Env)" `
        -Description "Opens Advanced System Properties (Pagefile, Performance Flags, and Environment Variables)." `
        -OnClick { Start-ClassicSysProp })

    [void](New-UltixButton -Parent $tabUtil -X 205 -Y 420 -Width 180 -Height 40 `
        -Text "Power Plans (powercfg)" `
        -Description "Opens the classic Power Options applet to inspect unhidden CPPC parameters." `
        -OnClick { Start-ClassicPower })

    # 3. DNS Enforcer (IPv4 + IPv6 + DoH)
    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Hardened DNS & DoH Enforcer (IPv4 / IPv6)"
    $lblDNS.Location = New-Object System.Drawing.Point(15, 480)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 505)
    $comboDNS.Size = New-Object System.Drawing.Size(240, 25)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
    $comboDNS.SelectedIndex = 0

    $chkDoH = New-Object System.Windows.Forms.CheckBox
    $chkDoH.Text = "Enforce Native DNS-over-HTTPS (DoH)"
    $chkDoH.Location = New-Object System.Drawing.Point(15, 538)
    $chkDoH.Size = New-Object System.Drawing.Size(235, 22)
    $chkDoH.ForeColor = [System.Drawing.Color]::LightGray
    $chkDoH.Checked = $true

    $chkIPv6 = New-Object System.Windows.Forms.CheckBox
    $chkIPv6.Text = "Configure IPv6 DNS"
    $chkIPv6.Location = New-Object System.Drawing.Point(255, 538)
    $chkIPv6.Size = New-Object System.Drawing.Size(135, 22)
    $chkIPv6.ForeColor = [System.Drawing.Color]::LightGray
    $chkIPv6.Checked = $true

    $btnApplyDNS = New-UltixButton -Parent $tabUtil -X 265 -Y 504 -Width 120 -Height 27 -RGB @(100, 40, 40) `
        -Text "Apply DNS" `
        -Description "Enforces IPv4/IPv6 DNS servers, injects kernel Dnscache DoH encryption flags, and flushes resolver cache."
    $btnApplyDNS.Add_Click({
        Set-CustomDNS -Provider $comboDNS.SelectedItem -EnableDoH $chkDoH.Checked -EnableIPv6 $chkIPv6.Checked -ControlsToDisable @($btnApplyDNS)
    }.GetNewClosure())

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from active route..."
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 566)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 22)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $tabUtil.Controls.AddRange(@(
        $lblInspect, $lblClassic, $lblDNS,
        $comboDNS, $chkDoH, $chkIPv6, $global:lblCurrentDNS
    ))
    $TabControl.Controls.Add($tabUtil)
}