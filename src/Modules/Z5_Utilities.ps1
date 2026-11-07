# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - SECURITY, PRIVACY & CONTROL MODULE (v3.14)
# Z5_Utilities: Security & Control module. Privacy & UWP AppPrivacy, Boot & UEFI WPBT block, 4-Layer USB Storage & BadUSB/DMA Perimeter Guard, Dual-Layer SRP+IFEO Execution Locks, Hardened DNS + Native DoH Enforcer, and classic Win32 applets.
# ==========================================

# ------------------------------------------
# Z5: USB MASS STORAGE, WPD/MTP & BADUSB / DMA PERIMETER GUARD
# ------------------------------------------
function Get-UsbSecurityState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 20 }
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $remGuidKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"

    # 1. USB & WPD/MTP Write-Protection (Read-Only Mode for Pendrives, External Disks & Smartphones)
    $wpVal = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies" -Name "WriteProtect" -ErrorAction SilentlyContinue).WriteProtect
    $denyWritePol = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -ErrorAction SilentlyContinue).Deny_Write
    $isReadOnlyActive = ($wpVal -eq 1 -and $denyWritePol -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "USB Read-Only Guard: Block Writing to USB Drives & MTP Phones (Prevents Data Leak)"
        IsDetected    = (-not $isReadOnlyActive)
        OptIn         = $true
        ActionData    = @{ Layer = "WriteProtect"; OptIn = $true }
    })

    # 2. USB Execute-Deny Policy (Blocks launching .exe payloads from USB sticks)
    $denyExecPol = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -ErrorAction SilentlyContinue).Deny_Execute
    $results.Add([PSCustomObject]@{
        UIDisplayName = "USB Execution Guard: Block Running Executables (.exe) from Removable Drives"
        IsDetected    = ($denyExecPol -ne 1)
        OptIn         = $true
        ActionData    = @{ Layer = "DenyExecute"; OptIn = $true }
    })

    # 3. Hard Lock: Disable USBSTOR & UASPStor Kernel Drivers + Full Removable Storage & WPD Policy
    $usbstorStart  = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR" -Name "Start" -ErrorAction SilentlyContinue).Start
    $uaspstorStart = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor" -Name "Start" -ErrorAction SilentlyContinue).Start
    $denyReadPol   = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
    $isHardLocked  = ($usbstorStart -eq 4 -and $uaspstorStart -eq 4 -and $denyReadPol -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "USB Total Blackout: Disable USBSTOR + UASPStor Drivers (Blocks all USB Sticks & SSDs)"
        IsDetected    = (-not $isHardLocked)
        OptIn         = $true
        ActionData    = @{ Layer = "TotalBlock"; OptIn = $true }
    })

    # 4. Anti-BadUSB / Lock-Screen Enumeration & Kernel DMA Guard
    $dmaLock = (Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Policies\Microsoft\FVE" -Name "DisableExternalDMAUnderLock" -ErrorAction SilentlyContinue).DisableExternalDMAUnderLock
    $usbLock = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "DisableUsbEnumerationOnLock" -ErrorAction SilentlyContinue).DisableUsbEnumerationOnLock
    $isBadUsbLocked = ($dmaLock -eq 1 -and $usbLock -eq 1)
    $results.Add([PSCustomObject]@{
        UIDisplayName = "Anti-BadUSB & DMA Guard: Block New USB/PCIe Device Enumeration While Screen is Locked"
        IsDetected    = (-not $isBadUsbLocked)
        ActionData    = @{ Layer = "LockScreenGuard" }
    })

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    return @($results)
}

function Invoke-ApplyUsbSecurity {
    param(
        [Parameter(Mandatory=$true)][array]$SelectedItems,
        [ValidateSet('Apply', 'Revert')][string]$Operation = 'Apply',
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )
    if ($SelectedItems.Count -eq 0) { return }

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -Arguments @($SelectedItems, $Operation) -ScriptBlock {
        param([array]$Items, [string]$Op)
        $remBase    = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
        $remGuidKey = "$remBase\{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}"
        $wpdGuids   = @(
            "$remBase\{6ac27878-a6fa-4155-ba85-f98f491d4f33}",
            "$remBase\{f33fdc04-d1ac-4e8e-9a30-19bbd4b108ae}"
        )
        $storPolKey = "HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies"
        $fveKey     = "HKLM:\SOFTWARE\Policies\Microsoft\FVE"
        $pwrKey     = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"

        $verb    = if ($Op -eq 'Apply') { "Enforcing" } else { "Reverting" }
        $total   = [math]::Max(1, $Items.Count)
        $current = 0

        # Ensure WriteProtect is processed before TotalBlock during Revert so StorageDevicePolicies reflects the final state
        $orderedItems = if ($Op -eq 'Revert') {
            @($Items | Sort-Object { if ($_.ActionData.Layer -eq 'WriteProtect') { 0 } else { 1 } })
        } else {
            $Items
        }

        foreach ($item in $orderedItems) {
            $current++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [int](($current / $total) * 100)
                $UltixSync.Logs.Enqueue(" -> $verb USB Security Layer: $($item.UIDisplayName)")
            }

            $layer = $item.ActionData.Layer
            if (-not (Test-Path -LiteralPath $remGuidKey)) { New-Item -Path $remGuidKey -Force | Out-Null }
            if (-not (Test-Path -LiteralPath $storPolKey)) { New-Item -Path $storPolKey -Force | Out-Null }

            switch ($layer) {
                "WriteProtect" {
                    if ($Op -eq 'Apply') {
                        Set-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -Value 1 -Type DWord -Force
                        Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Force
                        foreach ($wpdKey in $wpdGuids) {
                            if (-not (Test-Path -LiteralPath $wpdKey)) { New-Item -Path $wpdKey -Force | Out-Null }
                            Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Force
                        }
                    } else {
                        Set-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -Value 0 -Type DWord -Force
                        # Only remove Deny_Write if TotalBlock (Deny_Read) is not currently active
                        $denyReadActive = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
                        if ($denyReadActive -ne 1) {
                            Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
                            foreach ($wpdKey in $wpdGuids) {
                                if (Test-Path -LiteralPath $wpdKey) {
                                    Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                }
                "DenyExecute" {
                    if ($Op -eq 'Apply') {
                        Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -Value 1 -Type DWord -Force
                    } else {
                        Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Execute" -Force -ErrorAction SilentlyContinue
                    }
                }
                "TotalBlock" {
                    if ($Op -eq 'Apply') {
                        Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 4
                        Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 4
                        Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -Value 1 -Type DWord -Force
                        Set-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Force
                        foreach ($wpdKey in $wpdGuids) {
                            if (-not (Test-Path -LiteralPath $wpdKey)) { New-Item -Path $wpdKey -Force | Out-Null }
                            Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Read" -Value 1 -Type DWord -Force
                            Set-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Force
                        }
                    } else {
                        Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 3
                        Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 3
                        Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -Force -ErrorAction SilentlyContinue
                        foreach ($wpdKey in $wpdGuids) {
                            if (Test-Path -LiteralPath $wpdKey) {
                                Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Read" -Force -ErrorAction SilentlyContinue
                            }
                        }

                        # Symmetric check: only delete Deny_Write if Layer 1 (WriteProtect) is 0 or not set
                        $wpActive = (Get-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -ErrorAction SilentlyContinue).WriteProtect
                        if ($null -eq $wpActive -or $wpActive -eq 0) {
                            Remove-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
                            foreach ($wpdKey in $wpdGuids) {
                                if (Test-Path -LiteralPath $wpdKey) {
                                    Remove-ItemProperty -LiteralPath $wpdKey -Name "Deny_Write" -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                    }
                }
                "LockScreenGuard" {
                    if (-not (Test-Path -LiteralPath $fveKey)) { New-Item -Path $fveKey -Force | Out-Null }
                    if ($Op -eq 'Apply') {
                        Set-ItemProperty -LiteralPath $fveKey -Name "DisableExternalDMAUnderLock" -Value 1 -Type DWord -Force
                        Set-ItemProperty -LiteralPath $pwrKey -Name "DisableUsbEnumerationOnLock" -Value 1 -Type DWord -Force
                    } else {
                        Remove-ItemProperty -LiteralPath $fveKey -Name "DisableExternalDMAUnderLock" -Force -ErrorAction SilentlyContinue
                        Remove-ItemProperty -LiteralPath $pwrKey -Name "DisableUsbEnumerationOnLock" -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Write-GUI " -> USB Perimeter Security configuration completed ($Operation).`n"
    }.GetNewClosure())
}

# ------------------------------------------
# Z5: DNS ENFORCER (ZERO-WMI .NET ADAPTER DISCOVERY + IPV4/IPV6 + NATIVE DOH)
# ------------------------------------------
function Set-CustomDNS {
    param(
        [Parameter(Mandatory=$true)][string]$Provider,
        [bool]$EnableDoH = $true,
        [bool]$EnableIPv6 = $true,
        [System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    Write-GUI " -> Applying DNS profile '$Provider' (DoH: $EnableDoH, IPv6: $EnableIPv6)..."
    Update-Progress 20

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

        # Fast native Win32 GetAdaptersAddresses enumeration via .NET (~2ms, zero Get-NetRoute / Get-NetAdapter CIM overhead)
        $routedAdapters = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
            if ($nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }

            try {
                $ipProps = $nic.GetIPProperties()
                $validGw = @($ipProps.GatewayAddresses | Where-Object { $_.Address.ToString() -notin @("0.0.0.0", "::") })
                if ($null -eq $ipProps -or $validGw.Count -eq 0) { continue }

                $v4Props = $ipProps.GetIPv4Properties()
                if ($null -eq $v4Props -or $v4Props.Index -le 0) { continue }

                $routedAdapters.Add([PSCustomObject]@{
                    InterfaceIndex = [int]$v4Props.Index
                    InterfaceGuid  = [string]$nic.Id
                    InterfaceName  = [string]$nic.Description
                    InterfaceAlias = [string]$nic.Name
                })
            } catch { }
        }

        if ($routedAdapters.Count -eq 0) {
            $UltixSync.Logs.Enqueue(" [!] No active network adapters with a default gateway found.")
            return
        }

        $wellKnownBase = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DohWellKnownServers"
        $ifSpecBase    = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"
        $hasDohCmd     = ($null -ne (Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue))

        $totalNics = $routedAdapters.Count
        $nicIdx    = 0

        foreach ($nicInfo in $routedAdapters) {
            $nicIdx++
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = 20 + [int](($nicIdx / $totalNics) * 70)
            }

            $ifIndex = $nicInfo.InterfaceIndex
            $ifGuid  = $nicInfo.InterfaceGuid
            $ifName  = $nicInfo.InterfaceName

            $dohV4Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh"
            $dohV6Root = "$ifSpecBase\$ifGuid\DohInterfaceSettings\Doh6"

            if (Test-Path -LiteralPath $dohV4Root) { Remove-Item -LiteralPath $dohV4Root -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $dohV6Root) { Remove-Item -LiteralPath $dohV6Root -Recurse -Force -ErrorAction SilentlyContinue }

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
                    # Clear static IPv6 NameServer directly in Tcpip6 registry without spawning external netsh.exe
                    $tcp6IfKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$ifGuid"
                    if (Test-Path -LiteralPath $tcp6IfKey) {
                        Set-ItemProperty -LiteralPath $tcp6IfKey -Name "NameServer" -Value "" -Type String -Force -ErrorAction SilentlyContinue
                    }
                }
                $UltixSync.Logs.Enqueue(" -> [$ifName]: Enforced servers: $($allServers -join ', ')")
            } catch {
                $UltixSync.Logs.Enqueue(" [!] [$ifName]: Error setting DNS servers: $($_.Exception.Message)")
            }

            if ($UseDoH) {
                if (-not (Test-Path -LiteralPath $wellKnownBase)) { New-Item -Path $wellKnownBase -Force | Out-Null }

                foreach ($ip in $allServers) {
                    $wkKey = "$wellKnownBase\$ip"
                    if (-not (Test-Path -LiteralPath $wkKey)) { New-Item -Path $wkKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $wkKey -Name "Template" -Value $cfg.Template -Type String -Force -ErrorAction SilentlyContinue

                    if ($hasDohCmd) {
                        Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                        Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue
                    }

                    $isV6 = ($ip -match ":")
                    $targetDohKey = if ($isV6) { "$dohV6Root\$ip" } else { "$dohV4Root\$ip" }
                    if (-not (Test-Path -LiteralPath $targetDohKey)) { New-Item -Path $targetDohKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $targetDohKey -Name "DohFlags" -Value ([uint64]1) -Type QWord -Force -ErrorAction SilentlyContinue
                }
                $UltixSync.Logs.Enqueue("    [+] Native DoH encryption activated ($($cfg.Template)).")
            }
        }

        Clear-DnsClientCache -ErrorAction SilentlyContinue
        if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    } -OnComplete ({
        param($nullOut)
        Update-Progress 0
        Update-DNSLabel
        Write-GUI " -> DNS configuration completed and resolver cache flushed.`n"
    }.GetNewClosure())
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
function Start-ClassicGpoOrReg {
    if ([System.IO.File]::Exists("$env:windir\System32\gpedit.msc")) {
        Start-Process "mmc.exe" -ArgumentList "`"$env:windir\System32\gpedit.msc`""
    } else {
        Start-Process "regedit.exe"
    }
}
function Start-ClassicCompMgmt { Start-Process "compmgmt.msc" }

# ------------------------------------------
# Z5: UI INITIALIZATION (SECURITY, PRIVACY, DNS & APPLETS)
# ------------------------------------------
function Initialize-Z5UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabSec = New-Object System.Windows.Forms.TabPage
    $tabSec.Text = "Security"
    $tabSec.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    $invokeSecReg = ({
        param(
            [string]$ScannerFn,
            [string]$CategoryName,
            [string]$ModalTitle,
            [string]$AuditHeader,
            [switch]$AuditOnly
        )
        Invoke-UltixAuditFlow `
            -ScannerFunction $ScannerFn `
            -AuditLabel $AuditHeader `
            -ModalTitle $ModalTitle `
            -ModalDescription "Select security & privacy policies to apply or revert." `
            -ExecutorFunction "Invoke-ApplyRegistry" `
            -ExecutorExtraParams @{
                CategoryName = $CategoryName
                RefreshShell = $true
            } `
            -ControlsToDisable $allTabButtons.ToArray() `
            -AuditOnly:$AuditOnly.IsPresent `
            -AuditPrefix "To Optimize" `
            -EnableRevert
    }.GetNewClosure())

    # 1. Privacy & Background Apps (AppPrivacy)
    $rowPrivacy = New-UltixActionRow -Parent $tabSec -Y 20 -MainRGB @(55, 58, 64) `
        -Text "Privacy & Background Apps (AppPrivacy)" `
        -Description "Blocks OS telemetry, locks 28 UWP background permissions (Camera, Mic, Location, Contacts), disables Edge background boost, and stops ContentDeliveryManager." `
        -AuditDescription "AUDIT: Checks the registry for telemetry, UWP AppPrivacy, Edge, and ContentDeliveryManager blocks." `
        -OnClick ({ & $invokeSecReg "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy & AppPrivacy Policies" "Privacy Policies" }.GetNewClosure()) `
        -OnAudit ({ & $invokeSecReg "Get-RegState_Privacy" "Privacy" "WinUltix - Privacy & AppPrivacy Policies" "Privacy Policies" -AuditOnly }.GetNewClosure())

    # 2. Boot, SvcHost & WPBT (BIOS/UEFI Block)
    $rowBoot = New-UltixActionRow -Parent $tabSec -Y 70 -MainRGB @(55, 58, 64) `
        -Text "Boot, SvcHost & WPBT (BIOS Block)" `
        -Description "Blocks motherboard BIOS/UEFI binary injection (DisableWpbtExecution), disables Fast Startup hibernation bugs, blocks RDP, and consolidates SvcHost processes." `
        -AuditDescription "AUDIT: Verifies WPBT BIOS block, Fast Startup, SvcHost RAM threshold, and RDP locks." `
        -OnClick ({ & $invokeSecReg "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Kernel Security" "Boot & Kernel Security" }.GetNewClosure()) `
        -OnAudit ({ & $invokeSecReg "Get-RegState_SystemBoot" "SystemBoot" "WinUltix - Boot & Kernel Security" "Boot & Kernel Security" -AuditOnly }.GetNewClosure())

    # 3. USB Storage & BadUSB Perimeter Guard
    $rowUsbGuard = New-UltixActionRow -Parent $tabSec -Y 120 -MainRGB @(135, 50, 50) `
        -Text "USB Storage & BadUSB Guard (Lockdown)" `
        -Description "4-Layer USB & MTP perimeter defense: Read-Only Write Protection, Execute-Deny (.exe), Full USBSTOR + UASPStor driver blackout, and Lock-Screen BadUSB/DMA guard." `
        -AuditDescription "AUDIT: Checks USB/MTP Write-Protect, USBSTOR/UASPStor driver states, and Lock-Screen DMA/BadUSB policies." `
        -OnClick ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-UsbSecurityState" -AuditLabel "USB Perimeter Security" -ModalTitle "WinUltix - USB Storage & BadUSB Guard" -ModalDescription "Select USB protection layers to enforce (Apply = Lock, Revert = Unlock to Windows Defaults)." -ExecutorFunction "Invoke-ApplyUsbSecurity" -ControlsToDisable $allTabButtons.ToArray() -EnableRevert
        }.GetNewClosure()) `
        -OnAudit ({
            Invoke-UltixAuditFlow -ScannerFunction "Get-UsbSecurityState" -AuditLabel "USB Perimeter Security" -ControlsToDisable $allTabButtons.ToArray() -AuditOnly -AuditPrefix "Unlocked"
        }.GetNewClosure())

    # 4. Dual-Layer Execution Blocks (SRP + IFEO Kernel Lock) — Aligned to X = 345 for [?]
    $btnRegSRP = New-UltixButton -Parent $tabSec -X 15 -Y 170 -Width 235 -Height 40 -RGB @(135, 50, 50) `
        -Text "Execution Blocks (SRP + IFEO)" `
        -Description "DUAL-LAYER KERNEL LOCK: Combines Software Restriction Policies (Safer API) with Image File Execution Options (IFEO) to permanently block telemetry or custom .exe files." `
        -OnClick ({
            Invoke-UltixAuditFlow `
                -ScannerFunction "Get-RegState_SRP" `
                -AuditLabel "Dual-Layer Execution Locks (SRP + IFEO)" `
                -ModalTitle "WinUltix - SRP & IFEO Lockdown" `
                -ModalDescription "Select executables to permanently block via OS policies (Apply = Lock, Revert = Unlock)." `
                -ExecutorFunction "Invoke-ApplySRP" `
                -ControlsToDisable $allTabButtons.ToArray() `
                -EnableRevert
        }.GetNewClosure())

    $btnAddSRP = New-UltixButton -Parent $tabSec -X 255 -Y 170 -Width 40 -Height 40 -RGB @(45, 95, 60) `
        -Text "+" `
        -Description "ADD CUSTOM TARGET: Browse for an .exe file to add to your custom SRP+IFEO block list." `
        -OnClick ({
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Filter = "Executables (*.exe)|*.exe"
            $dlg.Title = "Select Executable to Block (SRP+IFEO)"
            $dlg.InitialDirectory = "$env:ProgramFiles"
            try {
                if ($dlg.ShowDialog($global:form) -eq [System.Windows.Forms.DialogResult]::OK) {
                    $exeName = [System.IO.Path]::GetFileName($dlg.FileName)
                    $protectedCoreBins = '^(?i)(explorer|svchost|lsass|csrss|smss|wininit|winlogon|services|dwm|sihost|taskhostw|conhost|cmd|powershell|pwsh|regedit|mmc|taskmgr|systray|gpupdate|WinUltix)\.exe$'
                    if ($exeName -match $protectedCoreBins) {
                        [System.Windows.Forms.MessageBox]::Show("Blocking core Windows shell/kernel binary '$exeName' is forbidden to prevent OS lockout.", "WinUltix - Safety Guard", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                        return
                    }
                    $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
                    if (-not (Test-Path -LiteralPath $regKey)) { New-Item -Path $regKey -Force | Out-Null }
                    Set-ItemProperty -LiteralPath $regKey -Name $exeName -Value $dlg.FileName -Type String -Force
                    Write-GUI " -> Added custom SRP+IFEO target: $exeName ($($dlg.FileName))"
                }
            } finally {
                $dlg.Dispose()
            }
        }.GetNewClosure())

    $btnClrSRP = New-UltixButton -Parent $tabSec -X 300 -Y 170 -Width 40 -Height 40 -RGB @(55, 58, 64) `
        -Text "-" `
        -Description "CLEAR CUSTOM TARGETS: Unlocks any active custom SRP+IFEO blocks and purges the custom tracking list." `
        -OnClick ({
            $regKey = "HKLM:\SOFTWARE\WinUltix\SRP"
            if (-not (Test-Path -LiteralPath $regKey)) {
                Write-GUI " -> Custom SRP+IFEO roster is already empty.`n"
                return
            }

            # Symmetrically unlock any active custom SRP+IFEO rules before deleting the tracking key
            $customItems = @(Get-RegState_SRP | Where-Object { $_.ActionData.IsCustom -eq $true })
            Remove-Item -LiteralPath $regKey -Force -Recurse -ErrorAction SilentlyContinue | Out-Null

            if ($customItems.Count -gt 0) {
                Write-GUI " -> Purging custom SRP+IFEO tracking list and reverting $($customItems.Count) custom rule(s)..."
                Invoke-ApplySRP -SelectedItems $customItems -Operation "Revert" -ControlsToDisable $allTabButtons.ToArray()
            } else {
                Write-GUI " -> Custom SRP+IFEO tracking database purged.`n"
            }
        }.GetNewClosure())

    $btnAudSRP = New-UltixButton -Parent $tabSec -X 345 -Y 170 -Width 40 -Height 40 -RGB @(72, 76, 82) `
        -Text "?" `
        -Description "AUDIT: Verifies active Software Restriction Policies (SRP) and IFEO kernel locks." `
        -OnClick ({
            Invoke-UltixAuditFlow `
                -ScannerFunction "Get-RegState_SRP" `
                -AuditLabel "Dual-Layer Execution Locks (SRP + IFEO)" `
                -ControlsToDisable $allTabButtons.ToArray() `
                -AuditOnly `
                -AuditPrefix "To Block"
        }.GetNewClosure())

    # 5. Hardened DNS & Native DoH Enforcer (IPv4 + IPv6)
    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Hardened DNS & Native DoH Enforcer (IPv4 / IPv6)"
    $lblDNS.Location = New-Object System.Drawing.Point(15, 228)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDNS.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 252)
    $comboDNS.Size = New-Object System.Drawing.Size(240, 25)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $comboDNS.Items.AddRange(@("Quad9 (9.9.9.9)", "Cloudflare (1.1.1.1)", "AdGuard (94.140.14.14)", "Google (8.8.8.8)", "OpenDNS (208.67.222.222)", "Default (DHCP)"))
    $comboDNS.SelectedIndex = 0

    $chkDoH = New-Object System.Windows.Forms.CheckBox
    $chkDoH.Text = "Enforce Native DNS-over-HTTPS (DoH)"
    $chkDoH.Location = New-Object System.Drawing.Point(15, 284)
    $chkDoH.Size = New-Object System.Drawing.Size(235, 22)
    $chkDoH.ForeColor = [System.Drawing.Color]::LightGray
    $chkDoH.Checked = $true

    $chkIPv6 = New-Object System.Windows.Forms.CheckBox
    $chkIPv6.Text = "Configure IPv6 DNS"
    $chkIPv6.Location = New-Object System.Drawing.Point(255, 284)
    $chkIPv6.Size = New-Object System.Drawing.Size(135, 22)
    $chkIPv6.ForeColor = [System.Drawing.Color]::LightGray
    $chkIPv6.Checked = $true

    $comboDNS.Add_SelectedIndexChanged({
        $isStatic = ([string]$comboDNS.SelectedItem -ne "Default (DHCP)")
        $chkDoH.Enabled  = $isStatic
        $chkIPv6.Enabled = $isStatic
    }.GetNewClosure())

    $btnApplyDNS = New-UltixButton -Parent $tabSec -X 265 -Y 251 -Width 120 -Height 27 -RGB @(45, 85, 125) `
        -Text "Apply DNS" `
        -Description "Enforces IPv4/IPv6 DNS servers, injects kernel Dnscache DoH encryption flags, and flushes resolver cache." `
        -OnClick ({
            Set-CustomDNS -Provider ([string]$comboDNS.SelectedItem) -EnableDoH $chkDoH.Checked -EnableIPv6 $chkIPv6.Checked -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure())

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from active route..."
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 310)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 22)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $global:lblCurrentDNS.Cursor = [System.Windows.Forms.Cursors]::Hand
    $global:lblCurrentDNS.Add_Click({ Update-DNSLabel })

    # 6. Classic Windows Control Applets (8 Tools)
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Win32 Control & Admin Applets"
    $lblClassic.Location = New-Object System.Drawing.Point(15, 345)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray
    $lblClassic.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)

    $btnNetCpl = New-UltixButton -Parent $tabSec -X 15 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Network Adapters (ncpa)" `
        -Description "Direct launch of the classic Win32 Network Connections applet (ncpa.cpl)." `
        -OnClick { Start-ClassicNet }

    $btnSndCpl = New-UltixButton -Parent $tabSec -X 205 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Sound Subsystem (mmsys)" `
        -Description "Direct launch of playback/recording devices and sample rate properties (mmsys.cpl)." `
        -OnClick { Start-ClassicSound }

    $btnAppCpl = New-UltixButton -Parent $tabSec -X 15 -Y 420 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Programs & Features" `
        -Description "Direct launch of the classic Win32 MSI/InstallShield software uninstaller (appwiz.cpl)." `
        -OnClick { Start-ClassicApps }

    $btnPrnCpl = New-UltixButton -Parent $tabSec -X 205 -Y 420 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Devices and Printers" `
        -Description "Bypasses Windows 11 Settings redirect to open the raw Win32 Devices and Printers shell folder." `
        -OnClick { Start-ClassicPrinters }

    $btnSysCpl = New-UltixButton -Parent $tabSec -X 15 -Y 470 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "System Properties (Env)" `
        -Description "Opens Advanced System Properties (Pagefile, Performance Flags, and Environment Variables)." `
        -OnClick { Start-ClassicSysProp }

    $btnPwrCpl = New-UltixButton -Parent $tabSec -X 205 -Y 470 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Power Plans (powercfg)" `
        -Description "Opens the classic Power Options applet to inspect unhidden CPPC parameters." `
        -OnClick { Start-ClassicPower }

    $btnGpoCpl = New-UltixButton -Parent $tabSec -X 15 -Y 520 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Group Policy / RegEdit" `
        -Description "Opens Local Group Policy Editor (gpedit.msc) or falls back to Registry Editor (regedit.exe) on Home SKUs." `
        -OnClick { Start-ClassicGpoOrReg }

    $btnMgmtCpl = New-UltixButton -Parent $tabSec -X 205 -Y 520 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Computer Mgmt (MSC)" `
        -Description "Opens Computer Management (compmgmt.msc) for Disk Management, Local Users, Event Viewer, and Device Manager." `
        -OnClick { Start-ClassicCompMgmt }

    foreach ($row in @($rowPrivacy, $rowBoot, $rowUsbGuard)) {
        $allTabButtons.AddRange($row.Controls)
    }
    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
        $btnRegSRP, $btnAddSRP, $btnClrSRP, $btnAudSRP,
        $comboDNS, $chkDoH, $chkIPv6, $btnApplyDNS,
        $btnNetCpl, $btnSndCpl, $btnAppCpl, $btnPrnCpl, $btnSysCpl, $btnPwrCpl, $btnGpoCpl, $btnMgmtCpl
    ))

    $tabSec.Controls.AddRange(@(
        $lblDNS, $comboDNS, $chkDoH, $chkIPv6, $global:lblCurrentDNS, $lblClassic
    ))
    $TabControl.Controls.Add($tabSec)
}