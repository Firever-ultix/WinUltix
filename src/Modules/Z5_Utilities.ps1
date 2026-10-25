# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - UTILITIES & APPLETS
# Z5_Utilities: Interactive tools and applets. Uses Out-GridView for selective removal of Appx, Provisioned packages, optional features, and services. Includes a DNS Enforcer (Cloudflare, Quad9, etc.) and classic Windows applet launchers.
# ==========================================

# ------------------------------------------
# Z5: INTERACTIVE GRIDS
# ------------------------------------------
function Show-AppxGrid { 
    Write-GUI " -> Generating installed Appx package table..."
    $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"
    
    $selected = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | 
        Where-Object { $_.NonRemovable -eq $false -and $_.Name -notmatch $protectedPattern } | 
        Select-Object Name, PackageFullName, IsFramework, Status | 
        Out-GridView -Title "Select packages to REMOVE (Protected system/gaming packages are hidden)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($app in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing Appx: $($app.Name)"
            try {
                Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop
                Write-GUI "    [OK] $($app.Name) removed."
            } catch {
                Write-GUI "    [!] Error removing $($app.Name): $($_.Exception.Message)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Appx removal cancelled."
    }
}

function Show-AppxProvGrid { 
    Write-GUI " -> Generating Provisioned Appx table..."
    $protectedPattern = "PeopleExperienceHost|XboxGameCallableUI|XboxIdentityProvider|Microsoft\.VCLibs|Microsoft\.NET|Microsoft\.UI\.Xaml|Microsoft\.WinJS|Microsoft\.Services\.Store|Microsoft\.WindowsAppRuntime|Microsoft\.WindowsAppSDK|Microsoft\.Graphics\.Canvas|Microsoft\.DirectX|Microsoft\.AIFabric|Microsoft\.Windows\.AugLoop"

    $selected = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -notmatch $protectedPattern } | 
        Select-Object DisplayName, PackageName, Version | 
        Out-GridView -Title "Select packages to DEPROVISION (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($app in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Deprovisioning: $($app.DisplayName)"
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($app.DisplayName) deprovisioned."
            } catch {
                Write-GUI "    [!] Error deprovisioning $($app.DisplayName): $($_.Exception.Message)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Deprovisioning cancelled."
    }
}

function Show-CapsGrid { 
    Write-GUI " -> Generating Capabilities (FOD) table..."
    $selected = @(Get-WindowsCapability -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.State -eq 'Installed' } | 
        Select-Object Name | 
        Out-GridView -Title "Select features to REMOVE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($cap in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing capability: $($cap.Name)"
            try {
                Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($cap.Name) removed."
            } catch {
                Write-GUI "    [!] Failed to remove: $($cap.Name)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Capability removal cancelled."
    }
}

function Show-OptFeaturesGrid { 
    Write-GUI " -> Generating Optional Features table..."
    $selected = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.State -eq 'Enabled' } | 
        Select-Object FeatureName | 
        Out-GridView -Title "Select features to DISABLE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($feat in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Disabling feature: $($feat.FeatureName)"
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName $feat.FeatureName -NoRestart -ErrorAction Stop | Out-Null
                Write-GUI "    [OK] $($feat.FeatureName) disabled."
            } catch {
                Write-GUI "    [!] Failed to disable: $($feat.FeatureName)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Optional feature configuration cancelled."
    }
}

function Show-ServicesGrid { 
    Write-GUI " -> Generating system services table..."
    $selected = @(Get-Service | 
        Select-Object Status, Name, DisplayName, StartType | 
        Out-GridView -Title "Select services to HARD DISABLE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($svc in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Deactivating service: $($svc.Name)"
            try {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
                Write-GUI "    [OK] $($svc.Name) stopped and disabled."
            } catch {
                Write-GUI "    [!] Failed to disable: $($svc.Name)"
            }
        }
        Update-Progress 0
    } else {
        Write-GUI " -> Service modification cancelled."
    }
}

function Show-StartupGrid { 
    Write-GUI " -> Generating interactive Startup table..."
    $startupItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    
    $regTargets = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";             Label = "Registry (HKLM x64)" }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; Label = "Registry (HKLM x86)" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";             Label = "Registry (HKCU)" }
    )

    foreach ($reg in $regTargets) {
        if (Test-Path $reg.Path) {
            $keyObj = Get-Item -Path $reg.Path -ErrorAction SilentlyContinue
            if ($null -ne $keyObj) {
                foreach ($valName in $keyObj.Property) {
                    $valData = $keyObj.GetValue($valName)
                    $startupItems.Add([PSCustomObject]@{
                        Name     = $valName
                        Location = $reg.Label
                        Command  = [string]$valData
                        RegPath  = $reg.Path
                        Type     = "Registry"
                    })
                }
            }
        }
    }
    
    $folderTargets = @(
        @{ Path = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; Label = "Folder (All Users)" }
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";         Label = "Folder (Current User)" }
    )

    foreach ($fld in $folderTargets) {
        if (Test-Path $fld.Path) {
            Get-ChildItem -Path $fld.Path -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -ne "desktop.ini") {
                    $startupItems.Add([PSCustomObject]@{
                        Name     = $_.Name
                        Location = $fld.Label
                        Command  = $_.FullName
                        RegPath  = $null
                        Type     = "File"
                    })
                }
            }
        }
    }
    
    $selected = @($startupItems | 
        Select-Object Name, Location, Command, RegPath, Type | 
        Out-GridView -Title "Select Startup entries to REMOVE (Ctrl+Click to select, then click OK)" -PassThru)
    
    $total = $selected.Count
    if ($total -gt 0) { 
        $current = 0
        foreach ($item in $selected) { 
            $current++
            Update-Progress ([int](($current / $total) * 100))
            Write-GUI " -> Removing startup entry: $($item.Name) [$($item.Location)]"
            if ($item.Type -eq "Registry") { 
                Remove-ItemProperty -Path $item.RegPath -Name $item.Name -Force -ErrorAction SilentlyContinue 
            } else { 
                Remove-Item -Path $item.Command -Force -ErrorAction SilentlyContinue 
            } 
        }
        Update-Progress 0
        Write-GUI " -> Selected startup entries permanently removed." 
    } else { 
        Write-GUI " -> Startup cleaning cancelled." 
    } 
}

# ------------------------------------------
# Z5: DNS ENFORCER
# ------------------------------------------
function Set-CustomDNS { 
    param([string]$Provider)
    
    $adapters = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.DefaultIPGateway }

    if (-not $adapters) { 
        Write-GUI " [!] No active network adapters with a default gateway found."
        return 
    }
    
    foreach ($adapter in $adapters) { 
        if ($Provider -eq "Default (DHCP)") { 
            $res = Invoke-CimMethod -InputObject $adapter -MethodName SetDNSServerSearchOrder -Arguments @{ DNSServerSearchOrder = $null } -ErrorAction SilentlyContinue
            if ($null -ne $res -and $res.ReturnValue -eq 0) {
                Write-GUI " -> $($adapter.Description): Reverted to DHCP DNS." 
            } else {
                Write-GUI " [!] $($adapter.Description): Failed to reset DNS (ReturnCode: $($res.ReturnValue))."
            }
        } else { 
            $dnsServers = switch ($Provider) { 
                "Quad9 (9.9.9.9)"          { [string[]]@("9.9.9.9", "149.112.112.112") } 
                "Cloudflare (1.1.1.1)"     { [string[]]@("1.1.1.1", "1.0.0.1") } 
                "AdGuard (94.140.14.14)"   { [string[]]@("94.140.14.14", "94.140.15.15") } 
                "Google (8.8.8.8)"         { [string[]]@("8.8.8.8", "8.8.4.4") } 
                "OpenDNS (208.67.222.222)" { [string[]]@("208.67.222.222", "208.67.220.220") } 
            }
            if ($null -ne $dnsServers) {
                $res = Invoke-CimMethod -InputObject $adapter -MethodName SetDNSServerSearchOrder -Arguments @{ DNSServerSearchOrder = $dnsServers } -ErrorAction SilentlyContinue
                if ($null -ne $res -and $res.ReturnValue -eq 0) {
                    Write-GUI " -> $($adapter.Description): DNS enforced to $Provider" 
                } else {
                    Write-GUI " [!] $($adapter.Description): Failed to set DNS (ReturnCode: $($res.ReturnValue))."
                }
            }
        } 
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue 
    Update-DNSLabel
}

# ------------------------------------------
# Z5: CLASSIC APPLETS
# ------------------------------------------
function Start-ClassicNet      { Start-Process "ncpa.cpl" }
function Start-ClassicApps     { Start-Process "appwiz.cpl" }
function Start-ClassicSound    { Start-Process "mmsys.cpl" }
function Start-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }

function Initialize-Z5UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabUtil = New-Object System.Windows.Forms.TabPage
    $tabUtil.Text = "Utilities"
    $tabUtil.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    # Inspection Labels & Tables
    $lblInspect = New-Object System.Windows.Forms.Label
    $lblInspect.Text = "WARNING: Advanced Tools (Use with caution)"
    $lblInspect.Location = New-Object System.Drawing.Point(15, 15)
    $lblInspect.Size = New-Object System.Drawing.Size(370, 20)
    $lblInspect.ForeColor = [System.Drawing.Color]::Red
    $lblInspect.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblInspect.TextAlign = "MiddleLeft"

    $btnUtilAppx = New-Object System.Windows.Forms.Button
    $btnUtilAppx.Text = "Appx (Accounts)"
    $btnUtilAppx.Location = New-Object System.Drawing.Point(15, 40)
    $btnUtilAppx.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilAppx.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilAppx.ForeColor = [System.Drawing.Color]::White
    $btnUtilAppx.FlatStyle = "Flat"
    $btnUtilAppx.Add_MouseEnter({ Show-Description "Interactive Appx table. Use Ctrl+Click to remove selected apps." })
    $btnUtilAppx.Add_Click({ Show-AppxGrid; Write-GUI "" })

    $btnUtilAppxProv = New-Object System.Windows.Forms.Button
    $btnUtilAppxProv.Text = "Appx (Image)"
    $btnUtilAppxProv.Location = New-Object System.Drawing.Point(205, 40)
    $btnUtilAppxProv.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilAppxProv.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilAppxProv.ForeColor = [System.Drawing.Color]::White
    $btnUtilAppxProv.FlatStyle = "Flat"
    $btnUtilAppxProv.Add_MouseEnter({ Show-Description "Interactive Provisioned table. Use Ctrl+Click to deprovision installers." })
    $btnUtilAppxProv.Add_Click({ Show-AppxProvGrid; Write-GUI "" })

    $btnUtilCaps = New-Object System.Windows.Forms.Button
    $btnUtilCaps.Text = "Capabilities (FOD)"
    $btnUtilCaps.Location = New-Object System.Drawing.Point(15, 90)
    $btnUtilCaps.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilCaps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilCaps.ForeColor = [System.Drawing.Color]::White
    $btnUtilCaps.FlatStyle = "Flat"
    $btnUtilCaps.Add_MouseEnter({ Show-Description "Interactive Capabilities (FOD) table. Select unnecessary packages to remove." })
    $btnUtilCaps.Add_Click({ Show-CapsGrid; Write-GUI "" })

    $btnUtilOpt = New-Object System.Windows.Forms.Button
    $btnUtilOpt.Text = "Optional Features"
    $btnUtilOpt.Location = New-Object System.Drawing.Point(205, 90)
    $btnUtilOpt.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilOpt.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilOpt.ForeColor = [System.Drawing.Color]::White
    $btnUtilOpt.FlatStyle = "Flat"
    $btnUtilOpt.Add_MouseEnter({ Show-Description "Interactive Optional Features table. Allows disabling unnecessary modules." })
    $btnUtilOpt.Add_Click({ Show-OptFeaturesGrid; Write-GUI "" })

    $btnUtilSvc = New-Object System.Windows.Forms.Button
    $btnUtilSvc.Text = "Running Services Management"
    $btnUtilSvc.Location = New-Object System.Drawing.Point(15, 140)
    $btnUtilSvc.Size = New-Object System.Drawing.Size(370, 40)
    $btnUtilSvc.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilSvc.ForeColor = [System.Drawing.Color]::White
    $btnUtilSvc.FlatStyle = "Flat"
    $btnUtilSvc.Add_MouseEnter({ Show-Description "Interactive services table. Selected items will be forcefully stopped and disabled." })
    $btnUtilSvc.Add_Click({ Show-ServicesGrid; Write-GUI "" })

    $btnUtilStartup = New-Object System.Windows.Forms.Button
    $btnUtilStartup.Text = "Startup Management (Registry and Folders)"
    $btnUtilStartup.Location = New-Object System.Drawing.Point(15, 190)
    $btnUtilStartup.Size = New-Object System.Drawing.Size(370, 40)
    $btnUtilStartup.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 100, 150)
    $btnUtilStartup.ForeColor = [System.Drawing.Color]::White
    $btnUtilStartup.FlatStyle = "Flat"
    $btnUtilStartup.Add_MouseEnter({ Show-Description "Interactive table. Aggregates hidden shortcuts and registry keys starting with the system." })
    $btnUtilStartup.Add_Click({ Show-StartupGrid; Write-GUI "" })

    # Classic Applets
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Windows Applets"
    $lblClassic.Location = New-Object System.Drawing.Point(15, 245)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray

    $btnUtilNet = New-Object System.Windows.Forms.Button
    $btnUtilNet.Text = "Network Adapters (ncpa)"
    $btnUtilNet.Location = New-Object System.Drawing.Point(15, 270)
    $btnUtilNet.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilNet.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilNet.ForeColor = [System.Drawing.Color]::White
    $btnUtilNet.FlatStyle = "Flat"
    $btnUtilNet.Add_MouseEnter({ Show-Description "Quick access to the Network Adapters applet." })
    $btnUtilNet.Add_Click({ Start-ClassicNet; Write-GUI "" })

    $btnUtilSound = New-Object System.Windows.Forms.Button
    $btnUtilSound.Text = "Sound Settings"
    $btnUtilSound.Location = New-Object System.Drawing.Point(205, 270)
    $btnUtilSound.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilSound.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilSound.ForeColor = [System.Drawing.Color]::White
    $btnUtilSound.FlatStyle = "Flat"
    $btnUtilSound.Add_MouseEnter({ Show-Description "Quick access to playback and recording devices." })
    $btnUtilSound.Add_Click({ Start-ClassicSound; Write-GUI "" })

    $btnUtilApps = New-Object System.Windows.Forms.Button
    $btnUtilApps.Text = "Programs and Features"
    $btnUtilApps.Location = New-Object System.Drawing.Point(15, 320)
    $btnUtilApps.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilApps.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilApps.ForeColor = [System.Drawing.Color]::White
    $btnUtilApps.FlatStyle = "Flat"
    $btnUtilApps.Add_MouseEnter({ Show-Description "Quick access to the classic Win32 installed software list." })
    $btnUtilApps.Add_Click({ Start-ClassicApps; Write-GUI "" })

    $btnUtilPrint = New-Object System.Windows.Forms.Button
    $btnUtilPrint.Text = "Devices and Printers"
    $btnUtilPrint.Location = New-Object System.Drawing.Point(205, 320)
    $btnUtilPrint.Size = New-Object System.Drawing.Size(180, 40)
    $btnUtilPrint.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnUtilPrint.ForeColor = [System.Drawing.Color]::White
    $btnUtilPrint.FlatStyle = "Flat"
    $btnUtilPrint.Add_MouseEnter({ Show-Description "Trick opening a clean folder of the legacy printers applet." })
    $btnUtilPrint.Add_Click({ Start-ClassicPrinters; Write-GUI "" })

    # DNS Enforcer
    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Fast DNS Server Switch"
    $lblDNS.Location = New-Object System.Drawing.Point(15, 385)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 410)
    $comboDNS.Size = New-Object System.Drawing.Size(240, 25)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
    $comboDNS.SelectedIndex = 0

    $btnApplyDNS = New-Object System.Windows.Forms.Button
    $btnApplyDNS.Text = "Apply DNS"
    $btnApplyDNS.Location = New-Object System.Drawing.Point(265, 409)
    $btnApplyDNS.Size = New-Object System.Drawing.Size(120, 27)
    $btnApplyDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnApplyDNS.ForeColor = [System.Drawing.Color]::White
    $btnApplyDNS.FlatStyle = "Flat"
    $btnApplyDNS.Add_MouseEnter({ Show-Description "Applies the selected secure DNS server for all active network adapters and flushes the DNS resolver cache." })
    $btnApplyDNS.Add_Click({ 
        Set-CustomDNS -Provider $comboDNS.SelectedItem
        Write-GUI " -> DNS configuration completed.`r`n" 
    })

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from the main adapter..."
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 442)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 20)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue

    $tabUtil.Controls.AddRange(@($lblInspect, $btnUtilAppx, $btnUtilAppxProv, $btnUtilCaps, $btnUtilOpt, $btnUtilSvc, $btnUtilStartup, $lblClassic, $btnUtilNet, $btnUtilApps, $btnUtilSound, $btnUtilPrint, $lblDNS, $comboDNS, $btnApplyDNS, $global:lblCurrentDNS))
    $TabControl.Controls.Add($tabUtil)
}