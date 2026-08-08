# ==========================================
# OPTIMIZER_CORE_EN.PS1 - FUNCTION LIBRARY
# ==========================================

if (-not (Get-Command Write-GUI -ErrorAction SilentlyContinue)) { function Write-GUI { param([string]$Message) Write-Host $Message -ForegroundColor Cyan } }
function Set-RegKey { param($Path, $Name, $Value, $Type="DWord"); if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction SilentlyContinue | Out-Null }; if ($Value -eq $null -and $Type -eq "String") { Set-ItemProperty -Path $Path -Name $Name -Value "" -Type String -Force -ErrorAction SilentlyContinue | Out-Null } else { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue | Out-Null } }

# --- 1. CLEANING ---
function Clean-WindowsUpdateCache { Stop-Service -Name "wuauserv", "bits", "cryptsvc" -Force -ErrorAction SilentlyContinue; Remove-Item -Path "$env:windir\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue; Start-Service -Name "wuauserv", "bits", "cryptsvc" -ErrorAction SilentlyContinue }
function Clean-TempFiles { $globalTempPaths = @("$env:TEMP\*", "$env:windir\Temp\*", "$env:windir\Prefetch\*"); foreach ($path in $globalTempPaths) { Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue }; Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object { $tempPath = "$($_.FullName)\AppData\Local\Temp"; if (Test-Path $tempPath) { Remove-Item -Path "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue } } }
function Clean-EventLogs { Start-Process -FilePath "cmd.exe" -ArgumentList "/c for /F `"tokens=*`" %1 in ('wevtutil el') do wevtutil cl `"%1`" >nul 2>&1" -WindowStyle Hidden -Wait }
function Clean-ThirdPartyCache { $appCachePaths = @("AppData\Local\Microsoft\Edge\User Data\Default\Cache\Cache_Data", "AppData\Local\Google\Chrome\User Data\Default\Cache\Cache_Data", "AppData\Local\Discord\Cache", "AppData\Local\NVIDIA\DXCache", "AppData\Local\AMD\DxCache"); Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object { $userDir = $_.FullName; foreach ($partialPath in $appCachePaths) { $fullPath = "$userDir\$partialPath"; if (Test-Path $fullPath) { Remove-Item -Path "$fullPath\*" -Recurse -Force -ErrorAction SilentlyContinue } } } }
function Clean-RecycleBinHard { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; foreach ($drive in (Get-PSDrive -PSProvider FileSystem)) { $recyclePath = "$($drive.Root)`$Recycle.Bin"; if (Test-Path $recyclePath) { & takeown.exe /F "$recyclePath\*" /R /A /D Y 2>$null; & icacls.exe "$recyclePath\*" /grant Administrators:F /T /C /Q 2>$null; Remove-Item -Path "$recyclePath\*" -Recurse -Force -ErrorAction SilentlyContinue } } }
function Remove-OneDrive { Stop-Process -Name "OneDrive", "OneDriveSetup" -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -ArgumentList "/uninstall" -NoNewWindow -Wait } elseif (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList "/uninstall" -NoNewWindow -Wait }; reg.exe delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>$null; $pathsToClean = @("$env:PROGRAMDATA\Microsoft OneDrive", "C:\OneDriveTemp"); Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object { $pathsToClean += "$($_.FullName)\AppData\Local\Microsoft\OneDrive" }; foreach ($targetPath in $pathsToClean) { if (Test-Path -Path $targetPath) { Remove-Item -Path $targetPath -Force -Recurse -ErrorAction SilentlyContinue } } }

# --- 2. BLOATWARE & APPS ---

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
        } catch { }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Appx Garbage Collector finished its run."
}

function Invoke-RemoveBloatware {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)

    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No items selected. Operation aborted."; return }
    $current = 0

    Stop-Process -Name "*Widget*" -Force -ErrorAction SilentlyContinue

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        
        Write-GUI " -> Purging: $($item.UIDisplayName)"
        
        foreach ($pkg in $item.ActionData.Installed) {
            try { Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop } catch { }
        }
        foreach ($prov in $item.ActionData.Provisioned) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop } catch { }
        }
    }
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Aggressive Bloatware Removal completed."
}

# --- 3. SYSTEM & NETWORK ---
function Optimize-PowerSettings { powercfg.exe /hibernate off; powercfg.exe /change standby-timeout-ac 0; powercfg.exe /change standby-timeout-dc 0; powercfg.exe /change monitor-timeout-ac 60; powercfg.exe /change monitor-timeout-dc 60 }
function Optimize-Network { $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object {$_.IPEnabled -eq $true}; foreach ($adapter in $adapters) { $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.SettingID)"; New-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -PropertyType DWORD -Force | Out-Null; New-ItemProperty -Path $path -Name "TCPNoDelay" -Value 1 -PropertyType DWORD -Force | Out-Null } }

# --- 4. SERVICES & TASKS ---
function Disable-TelemetryTasks { $tasksToDisable = @("\Microsoft\Windows\Customer Experience Improvement Program\*", "\Microsoft\Windows\Feedback\*", "\Microsoft\Windows\PerformanceTrace\*", "\Microsoft\Windows\Windows Error Reporting\*", "\Microsoft\XblGameSave\*"); foreach ($t in $tasksToDisable) { $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -like $t }; foreach ($task in $tasks) { Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null } } }

function Invoke-ApplyServices {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$ProfileName
    )

    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> All target services are already optimized."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        
        Write-GUI " -> Configuring: $($item.UIDisplayName)"
        $svc = $item.ActionData
        
        try {
            # Zatrzymanie usługi w locie (jeśli to możliwe)
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            
            # Wymuszenie startu przez Rejestr (niezawodne)
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($svc.Name)" -Name "Start" -Value $svc.ExpectedStart -Type DWord -ErrorAction Stop
        } catch {
            Write-GUI "    [!] Failed to modify service: $($svc.Name)"
        }
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $ProfileName services enforcement completed."
}

function Force-CleanStartMenu { 
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start" -Name "ConfigureStartPins" -ErrorAction SilentlyContinue
    $startStatePath = "$env:LOCALAPPDATA\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState"
    if (Test-Path "$startStatePath\start.bin") { Remove-Item -Path "$startStatePath\start.bin" -Force -ErrorAction SilentlyContinue }
    if (Test-Path "$startStatePath\start2.bin") { Remove-Item -Path "$startStatePath\start2.bin" -Force -ErrorAction SilentlyContinue }
    Stop-Process -Name "StartMenuExperienceHost" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
}

# --- 5. SYSTEM INTEGRITY ---
function Optimize-WinSXS { Start-Process -FilePath "cmd.exe" -ArgumentList "/c title WinSXS Optimization & color 0A & echo Aggressive cleaning in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & echo. & pause >nul" -Wait }
function Check-SystemIntegrity { Start-Process -FilePath "cmd.exe" -ArgumentList "/c title System Scan & color 0A & echo RestoreHealth... & dism /online /cleanup-image /restorehealth & echo. & echo SFC Scanning... & sfc /scannow & echo. & pause >nul" -Wait }

# --- 6. SYSTEM REGISTRY ---
function Invoke-ApplyRegistry {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [Parameter(Mandatory=$true)][string]$CategoryName
    )

    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> No tweaks selected."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        
        # Wyświetlamy w logu przyjazną, edukacyjną nazwę
        Write-GUI " -> Enforcing: $($item.UIDisplayName)"
        $reg = $item.ActionData
        
        try {
            if (-not (Test-Path $reg.Path)) { 
                New-Item -Path $reg.Path -Force -ErrorAction Stop | Out-Null 
            }
            
            if ($reg.Expected -eq "" -and $reg.Type -eq "String") { 
                Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value "" -Type String -Force -ErrorAction Stop | Out-Null 
            } else { 
                Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Expected -Type $reg.Type -Force -ErrorAction Stop | Out-Null 
            }
        } catch {
            Write-GUI "    [!] Failed to set key (Permissions/Lock): $($reg.Name)"
        }
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> $CategoryName registry modifications completed."
}

# --- 7. UTILITIES & INSPECTION ---
function Show-AppxGrid { Write-GUI "Generating Appx table..."; $selected = Get-AppxPackage -AllUsers | Select-Object Name, PackageFullName, IsFramework, Status | Out-GridView -Title "Select packages to REMOVE (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($app in $selected) { Write-GUI "Removing: $($app.Name)"; Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction SilentlyContinue } } }
function Show-AppxProvGrid { Write-GUI "Generating Provisioned Appx table..."; $selected = Get-AppxProvisionedPackage -Online | Select-Object DisplayName, PackageName, Version | Out-GridView -Title "Select packages to DEPROVISION (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($app in $selected) { Write-GUI "Deprovisioning: $($app.DisplayName)"; Remove-AppxProvisionedPackage -Online -PackageName $app.PackageName -ErrorAction SilentlyContinue } } }
function Show-CapsGrid { Write-GUI "Generating Capabilities table..."; $selected = Get-WindowsCapability -Online | Where-Object State -eq 'Installed' | Select-Object Name | Out-GridView -Title "Select features to REMOVE (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($cap in $selected) { Write-GUI "Removing: $($cap.Name)"; Remove-WindowsCapability -Online -Name $cap.Name -ErrorAction SilentlyContinue } } }
function Show-OptFeaturesGrid { Write-GUI "Generating Optional Features table..."; $selected = Get-WindowsOptionalFeature -Online | Where-Object State -eq 'Enabled' | Select-Object FeatureName | Out-GridView -Title "Select features to DISABLE (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($feat in $selected) { Write-GUI "Disabling: $($feat.FeatureName)"; Disable-WindowsOptionalFeature -Online -FeatureName $feat.FeatureName -NoRestart -ErrorAction SilentlyContinue } } }
function Show-ServicesGrid { Write-GUI "Generating services table..."; $selected = Get-Service | Select-Object Status, Name, DisplayName, StartType | Out-GridView -Title "Select services to HARD DISABLE (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($svc in $selected) { Write-GUI "Deactivating: $($svc.Name)"; Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue; Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue } } }
function Show-StartupGrid { Write-GUI "Generating interactive Startup table..."; $startupItems = @(); $hklm = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; if (Test-Path $hklm) { Get-Item $hklm | Select-Object -ExpandProperty Property | ForEach-Object { $startupItems += [PSCustomObject]@{Name=$_; Location="Registry (All Users)"; Path=(Get-ItemProperty $hklm).$_} } }; $hkcu = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; if (Test-Path $hkcu) { Get-Item $hkcu | Select-Object -ExpandProperty Property | ForEach-Object { $startupItems += [PSCustomObject]@{Name=$_; Location="Registry (Current User)"; Path=(Get-ItemProperty $hkcu).$_} } }; $commonStartup = "$env:ALLUSERSPROFILE\Microsoft\Windows\Start Menu\Programs\Startup"; if (Test-Path $commonStartup) { Get-ChildItem $commonStartup -File | ForEach-Object { $startupItems += [PSCustomObject]@{Name=$_.Name; Location="Folder (All Users)"; Path=$_.FullName} } }; $userStartup = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; if (Test-Path $userStartup) { Get-ChildItem $userStartup -File | ForEach-Object { $startupItems += [PSCustomObject]@{Name=$_.Name; Location="Folder (Current User)"; Path=$_.FullName} } }; $selected = $startupItems | Out-GridView -Title "Select Startup entries to REMOVE (Ctrl+Click to select, then click OK)" -PassThru; if ($selected) { foreach ($item in $selected) { Write-GUI " -> Removing startup entry: $($item.Name)"; if ($item.Location -match "Registry \(All Users\)") { Remove-ItemProperty -Path $hklm -Name $item.Name -ErrorAction SilentlyContinue } elseif ($item.Location -match "Registry \(Current User\)") { Remove-ItemProperty -Path $hkcu -Name $item.Name -ErrorAction SilentlyContinue } else { Remove-Item -Path $item.Path -Force -ErrorAction SilentlyContinue } }; Write-GUI "Selected entries have been permanently removed from startup." } else { Write-GUI "Startup cleaning cancelled." } }
function Set-CustomDNS { param($Provider); $adapters = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }; if (-not $adapters) { Write-GUI "[!] No active network adapters found."; return }; foreach ($adapter in $adapters) { if ($Provider -eq "Default (DHCP)") { $adapter.SetDNSServerSearchOrder() | Out-Null; Write-GUI " -> $($adapter.Description): DHCP DNS applied." } else { $dns1 = ""; $dns2 = ""; switch ($Provider) { "Quad9 (9.9.9.9)" { $dns1 = "9.9.9.9"; $dns2 = "149.112.112.112" } "Cloudflare (1.1.1.1)" { $dns1 = "1.1.1.1"; $dns2 = "1.0.0.1" } "AdGuard (94.140.14.14)" { $dns1 = "94.140.14.14"; $dns2 = "94.140.15.15" } "Google (8.8.8.8)" { $dns1 = "8.8.8.8"; $dns2 = "8.8.4.4" } "OpenDNS (208.67.222.222)" { $dns1 = "208.67.222.222"; $dns2 = "208.67.220.220" } }; $adapter.SetDNSServerSearchOrder(@($dns1, $dns2)) | Out-Null; Write-GUI " -> $($adapter.Description): DNS set to $Provider" } }; Clear-DnsClientCache -ErrorAction SilentlyContinue }

function Open-ClassicNet { Start-Process "ncpa.cpl" }
function Open-ClassicApps { Start-Process "appwiz.cpl" }
function Open-ClassicSound { Start-Process "mmsys.cpl" }
function Open-ClassicPrinters { Start-Process "explorer.exe" -ArgumentList "shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\0\::{A8A91A66-3A7D-4424-8D24-04E180695C7A}" }

function Invoke-Rescue {
    param([Parameter(Mandatory=$true)][array]$SelectedItems)
    
    $total = $SelectedItems.Count
    if ($total -eq 0) { Write-GUI " -> System is fully at factory defaults."; return }
    $current = 0

    foreach ($item in $SelectedItems) {
        $current++
        if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress ([int](($current / $total) * 100)) }
        
        Write-GUI " -> Restoring: $($item.UIDisplayName)"
        $data = $item.ActionData
        
        try {
            if ($data.Type -eq "DeleteKey") {
                if (Test-Path $data.Path) { Remove-Item -Path $data.Path -Recurse -Force -ErrorAction Stop }
            } elseif ($data.Type -eq "Delete") {
                if (Test-Path $data.Path) { Remove-ItemProperty -Path $data.Path -Name $data.Name -ErrorAction Stop }
            } elseif ($data.ExpectedStart) {
                # To jest usługa
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($data.Name)" -Name "Start" -Value $data.ExpectedStart -Type DWord -ErrorAction Stop
            } else {
                # To jest standardowe nadpisanie wartości fabrycznej
                if (-not (Test-Path $data.Path)) { New-Item -Path $data.Path -Force -ErrorAction Stop | Out-Null }
                Set-ItemProperty -Path $data.Path -Name $data.Name -Value $data.DefaultValue -Type $data.Type -Force -ErrorAction Stop | Out-Null
            }
        } catch { 
            Write-GUI "    [!] Failed to restore item (Permissions/Lock)." 
        }
    }
    
    if (Get-Command Update-Progress -ErrorAction SilentlyContinue) { Update-Progress 0 }
    Write-GUI " -> Rescue operations completed. System restart is highly recommended."
}