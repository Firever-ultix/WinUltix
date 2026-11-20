# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z5_UTILITIES.PS1 - SECURITY, PRIVACY & CONTROL MODULE
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
    $usbstorStart   = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR" -Name "Start" -ErrorAction SilentlyContinue).Start
    $uaspKeyExists  = Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor"
    $uaspstorStart  = if ($uaspKeyExists) { (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor" -Name "Start" -ErrorAction SilentlyContinue).Start } else { 4 }
    $denyReadPol    = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
    $isHardLocked   = ($usbstorStart -eq 4 -and $uaspstorStart -eq 4 -and $denyReadPol -eq 1)
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

            switch ($layer) {
                "WriteProtect" {
                    if ($Op -eq 'Apply') {
                        Set-UltixRegValue -Path $storPolKey -Name "WriteProtect" -Value 1 -Type DWord -Module "Z5_Utilities"
                        Set-UltixRegValue -Path $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Module "Z5_Utilities"
                        foreach ($wpdKey in $wpdGuids) {
                            Set-UltixRegValue -Path $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Module "Z5_Utilities"
                        }
                    } else {
                        Set-UltixRegValue -Path $storPolKey -Name "WriteProtect" -Value 0 -Type DWord -Module "Z5_Utilities"
                        # Only remove Deny_Write if TotalBlock (Deny_Read) is not currently active
                        $denyReadActive = (Get-ItemProperty -LiteralPath $remGuidKey -Name "Deny_Read" -ErrorAction SilentlyContinue).Deny_Read
                        if ($denyReadActive -ne 1) {
                            Remove-UltixRegItem -Path $remGuidKey -Name "Deny_Write" -IgnoreMissing -Module "Z5_Utilities"
                            foreach ($wpdKey in $wpdGuids) {
                                if (Test-Path -LiteralPath $wpdKey) {
                                    Remove-UltixRegItem -Path $wpdKey -Name "Deny_Write" -IgnoreMissing -Module "Z5_Utilities"
                                }
                            }
                        }
                    }
                }
                "DenyExecute" {
                    if ($Op -eq 'Apply') {
                        Set-UltixRegValue -Path $remGuidKey -Name "Deny_Execute" -Value 1 -Type DWord -Module "Z5_Utilities"
                    } else {
                        Remove-UltixRegItem -Path $remGuidKey -Name "Deny_Execute" -IgnoreMissing -Module "Z5_Utilities"
                    }
                }
                "TotalBlock" {
                    if ($Op -eq 'Apply') {
                        Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 4 -Module "Z5_Utilities"
                        if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor") {
                            Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 4 -Module "Z5_Utilities"
                        }
                        Set-UltixRegValue -Path $remGuidKey -Name "Deny_Read" -Value 1 -Type DWord -Module "Z5_Utilities"
                        Set-UltixRegValue -Path $remGuidKey -Name "Deny_Write" -Value 1 -Type DWord -Module "Z5_Utilities"
                        foreach ($wpdKey in $wpdGuids) {
                            Set-UltixRegValue -Path $wpdKey -Name "Deny_Read" -Value 1 -Type DWord -Module "Z5_Utilities"
                            Set-UltixRegValue -Path $wpdKey -Name "Deny_Write" -Value 1 -Type DWord -Module "Z5_Utilities"
                        }
                    } else {
                        Set-ProtectedServiceStart -ServiceName "USBSTOR" -StartValue 3 -Module "Z5_Utilities"
                        if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor") {
                            Set-ProtectedServiceStart -ServiceName "UASPStor" -StartValue 3 -Module "Z5_Utilities"
                        }
                        Remove-UltixRegItem -Path $remGuidKey -Name "Deny_Read" -IgnoreMissing -Module "Z5_Utilities"
                        foreach ($wpdKey in $wpdGuids) {
                            if (Test-Path -LiteralPath $wpdKey) {
                                Remove-UltixRegItem -Path $wpdKey -Name "Deny_Read" -IgnoreMissing -Module "Z5_Utilities"
                            }
                        }

                        # Symmetric check: only delete Deny_Write if Layer 1 (WriteProtect) is 0 or not set
                        $wpActive = (Get-ItemProperty -LiteralPath $storPolKey -Name "WriteProtect" -ErrorAction SilentlyContinue).WriteProtect
                        if ($null -eq $wpActive -or $wpActive -eq 0) {
                            Remove-UltixRegItem -Path $remGuidKey -Name "Deny_Write" -IgnoreMissing -Module "Z5_Utilities"
                            foreach ($wpdKey in $wpdGuids) {
                                if (Test-Path -LiteralPath $wpdKey) {
                                    Remove-UltixRegItem -Path $wpdKey -Name "Deny_Write" -IgnoreMissing -Module "Z5_Utilities"
                                }
                            }
                        }
                    }
                    Set-UltixRebootRequired -Reason "USB Guard"
                }
                "LockScreenGuard" {
                    if ($Op -eq 'Apply') {
                        Set-UltixRegValue -Path $fveKey -Name "DisableExternalDMAUnderLock" -Value 1 -Type DWord -Module "Z5_Utilities"
                        Set-UltixRegValue -Path $pwrKey -Name "DisableUsbEnumerationOnLock" -Value 1 -Type DWord -Module "Z5_Utilities"
                    } else {
                        Remove-UltixRegItem -Path $fveKey -Name "DisableExternalDMAUnderLock" -IgnoreMissing -Module "Z5_Utilities"
                        Remove-UltixRegItem -Path $pwrKey -Name "DisableUsbEnumerationOnLock" -IgnoreMissing -Module "Z5_Utilities"
                    }
                    Set-UltixRebootRequired -Reason "USB Guard"
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

        $dnsCatalog = Get-UltixDnsCatalog
        $isDhcp     = ($TargetProvider -eq "Default (DHCP)")
        $cfg        = if (-not $isDhcp -and $dnsCatalog.Contains($TargetProvider)) { $dnsCatalog[$TargetProvider] } else { $null }
        if (-not $isDhcp -and $null -eq $cfg) {
            $UltixSync.Logs.Enqueue(" [!] Unknown DNS provider profile '$TargetProvider'. Aborting without changes.")
            return
        }

        # Canonical Zero-WMI routed NIC discovery shared with Update-DNSLabel & Export/Import-WinUltixProfile
        $routedAdapters = @(Get-UltixActiveNetworkAdapters)
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

            Remove-UltixRegItem -Path $dohV4Root -IgnoreMissing -Module "Z5_Utilities"
            Remove-UltixRegItem -Path $dohV6Root -IgnoreMissing -Module "Z5_Utilities"

            if ($isDhcp) {
                try {
                    Invoke-UltixStep -Command "Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses" -Action {
                        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses -ErrorAction Stop
                    } -SuccessOutput "Reset DNS to DHCP on [$ifName]" -Module "Z5_Utilities"
                    $UltixSync.Logs.Enqueue(" -> [$ifName]: Reverted IPv4/IPv6 DNS to DHCP and cleared DoH locks.")
                } catch {
                    $UltixSync.Logs.Enqueue(" [!] [$ifName]: Failed to reset DNS: $($_.Exception.Message)")
                }
                continue
            }

            $allServers = [System.Collections.Generic.List[string]]::new()
            $v4List     = @($cfg.IPv4)
            $v6List     = @($cfg.IPv6)
            $v4Literal  = ($v4List | ForEach-Object { "'$_'" }) -join ","

            # Flush live NSI IPv6 static DNS before applying IPv4-only targets so Dnscache drops old IPv6 resolvers immediately
            if ((-not $UseIPv6 -or $v6List.Count -eq 0) -and -not [string]::IsNullOrWhiteSpace($nicInfo.StaticNameServerV6)) {
                try {
                    Invoke-UltixStep -Command "Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses" -Action {
                        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ResetServerAddresses -ErrorAction Stop
                    } -SuccessOutput "Cleared live static IPv6 DNS in NSI on [$ifName]" -Module "Z5_Utilities"
                } catch { }
            }

            try {
                Invoke-UltixStep -Command "Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($v4Literal)" -Action {
                    Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v4List -ErrorAction Stop
                } -SuccessOutput "Enforced IPv4 DNS ($($v4List -join ', ')) on [$ifName]" -Module "Z5_Utilities"
                foreach ($ip4 in $v4List) { $allServers.Add($ip4) }
            } catch {
                $UltixSync.Logs.Enqueue(" [!] [$ifName]: Error setting IPv4 DNS servers: $($_.Exception.Message)")
            }

            if ($UseIPv6 -and $v6List.Count -gt 0) {
                $v6Literal = ($v6List | ForEach-Object { "'$_'" }) -join ","
                try {
                    Invoke-UltixStep -Command "Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses @($v6Literal)" -Action {
                        Set-DnsClientServerAddress -InterfaceIndex $ifIndex -ServerAddresses $v6List -ErrorAction Stop
                    } -SuccessOutput "Enforced IPv6 DNS ($($v6List -join ', ')) on [$ifName]" -Module "Z5_Utilities"
                    foreach ($ip6 in $v6List) { $allServers.Add($ip6) }
                } catch {
                    $UltixSync.Logs.Enqueue(" [!] [$ifName]: IPv6 stack unbound or unavailable ($($_.Exception.Message)).")
                }
            } else {
                if ($UseIPv6 -and $v6List.Count -eq 0) {
                    $UltixSync.Logs.Enqueue(" [!] [$ifName]: '$TargetProvider' is IPv4-only (no native IPv6 DNS). Cleared static IPv6 override to prevent filter bypass.")
                }
                # Fallback: ensure Tcpip6 static NameServer registry value is empty if NSI reset did not reach an unbound IPv6 stack
                $tcp6IfKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$ifGuid"
                if (Test-Path -LiteralPath $tcp6IfKey) {
                    $curV6Ns = (Get-ItemProperty -LiteralPath $tcp6IfKey -Name "NameServer" -ErrorAction SilentlyContinue).NameServer
                    if (-not [string]::IsNullOrWhiteSpace($curV6Ns)) {
                        try {
                            Set-UltixRegValue -Path $tcp6IfKey -Name "NameServer" -Value "" -Type String -Module "Z5_Utilities"
                        } catch { }
                    }
                }
            }

            if ($allServers.Count -gt 0) {
                $UltixSync.Logs.Enqueue(" -> [$ifName]: Enforced servers: $($allServers -join ', ')")
            }

            if ($UseDoH) {
                foreach ($ip in $allServers) {
                    $wkKey = "$wellKnownBase\$ip"
                    try {
                        Set-UltixRegValue -Path $wkKey -Name "Template" -Value $cfg.Template -Type String -Module "Z5_Utilities"
                    } catch { }

                    if ($hasDohCmd) {
                        try {
                            Invoke-UltixStep -Command "Add-DnsClientDohServerAddress -ServerAddress '$ip' -DohTemplate '$($cfg.Template)' -AllowFallbackToUdp `$true -AutoUpgrade `$true" -Action {
                                Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction SilentlyContinue
                                Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $cfg.Template -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction SilentlyContinue
                            } -SuccessOutput "Configured DoH template for $ip" -Module "Z5_Utilities"
                        } catch { }
                    }

                    $isV6 = ($ip -match ":")
                    $targetDohKey = if ($isV6) { "$dohV6Root\$ip" } else { "$dohV4Root\$ip" }
                    try {
                        Set-UltixRegValue -Path $targetDohKey -Name "DohFlags" -Value ([uint64]1) -Type QWord -Module "Z5_Utilities"
                    } catch { }
                }
                $UltixSync.Logs.Enqueue("    [+] Native DoH encryption activated ($($cfg.Template)).")
            }
        }

        try {
            Invoke-UltixStep -Command "Clear-DnsClientCache" -Action {
                Clear-DnsClientCache -ErrorAction SilentlyContinue
            } -SuccessOutput "Flushed DNS resolver cache" -Module "Z5_Utilities"
        } catch { }
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
function Start-ClassicNet {
    Invoke-UltixStep -Command "Start-Process 'ncpa.cpl'" -Action {
        Start-Process "ncpa.cpl"
    } -SuccessOutput "Launched Network Connections (ncpa.cpl)" -Module "Z5_Utilities"
}
function Start-ClassicApps {
    Invoke-UltixStep -Command "Start-Process 'appwiz.cpl'" -Action {
        Start-Process "appwiz.cpl"
    } -SuccessOutput "Launched Programs and Features (appwiz.cpl)" -Module "Z5_Utilities"
}
function Start-ClassicSound {
    Invoke-UltixStep -Command "Start-Process 'mmsys.cpl'" -Action {
        Start-Process "mmsys.cpl"
    } -SuccessOutput "Launched Sound Properties (mmsys.cpl)" -Module "Z5_Utilities"
}
function Start-ClassicPrinters {
    $shellUri = "shell:::{26EE0668-A00A-44D7-9371-BEB064C98683}\0\::{A8A91A66-3A7D-4424-8D24-04E180695C7A}"
    Invoke-UltixStep -Command "Start-Process 'explorer.exe' -ArgumentList '$shellUri'" -Action {
        Start-Process "explorer.exe" -ArgumentList $shellUri
    } -SuccessOutput "Launched Win32 Devices and Printers" -Module "Z5_Utilities"
}
function Start-ClassicSysProp {
    Invoke-UltixStep -Command "Start-Process 'SystemPropertiesAdvanced.exe'" -Action {
        Start-Process "SystemPropertiesAdvanced.exe"
    } -SuccessOutput "Launched Advanced System Properties" -Module "Z5_Utilities"
}
function Start-ClassicPower {
    Invoke-UltixStep -Command "Start-Process 'powercfg.cpl'" -Action {
        Start-Process "powercfg.cpl"
    } -SuccessOutput "Launched Power Options (powercfg.cpl)" -Module "Z5_Utilities"
}
function Start-ClassicGpoOrReg {
    if ([System.IO.File]::Exists("$env:windir\System32\gpedit.msc")) {
        $gpoPath = "$env:windir\System32\gpedit.msc"
        Invoke-UltixStep -Command "Start-Process 'mmc.exe' -ArgumentList '`"$gpoPath`"'" -Action {
            Start-Process "mmc.exe" -ArgumentList "`"$gpoPath`""
        } -SuccessOutput "Launched Local Group Policy Editor (gpedit.msc)" -Module "Z5_Utilities"
    } else {
        Invoke-UltixStep -Command "Start-Process 'regedit.exe'" -Action {
            Start-Process "regedit.exe"
        } -SuccessOutput "Launched Registry Editor (regedit.exe)" -Module "Z5_Utilities"
    }
}
function Start-ClassicCompMgmt {
    Invoke-UltixStep -Command "Start-Process 'compmgmt.msc'" -Action {
        Start-Process "compmgmt.msc"
    } -SuccessOutput "Launched Computer Management (compmgmt.msc)" -Module "Z5_Utilities"
}

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
                    $fullPath = [System.IO.Path]::GetFullPath($dlg.FileName)
                    $exeName  = [System.IO.Path]::GetFileName($fullPath)
                    $protectedCoreBins = '^(?i)(ntoskrnl|winload|bootmgr|explorer|svchost|lsass|csrss|smss|wininit|winlogon|userinit|logonui|consent|credentialuibroker|services|dwm|fontdrvhost|sihost|taskhostw|runtimebroker|startmenuexperiencehost|shellexperiencehost|conhost|cmd|powershell|pwsh|regedit|mmc|taskmgr|systray|gpupdate|rundll32|dllhost|msiexec|dism|sfc|sc|net|net1|icacls|bcdedit|msmpeng|nissrv|securityhealthservice|smartscreen|WinUltix)\.exe$'
                    if ($exeName -match $protectedCoreBins) {
                        [System.Windows.Forms.MessageBox]::Show("Blocking core Windows shell, security, or kernel binary '$exeName' is forbidden to prevent OS lockout.", "WinUltix - Safety Guard", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                        return
                    }

                    $regKey   = "HKLM:\SOFTWARE\WinUltix\SRP"
                    $valLabel = $exeName

                    if (Test-Path -LiteralPath $regKey) {
                        $existingProps = Get-ItemProperty -LiteralPath $regKey -ErrorAction SilentlyContinue
                        if ($null -ne $existingProps) {
                            $existingNames = @($existingProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' } | Select-Object -ExpandProperty Name)
                            foreach ($en in $existingNames) {
                                if ([string]::Equals([string]$existingProps.$en, $fullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                                    Write-GUI " -> Custom SRP+IFEO target already registered: $en ($fullPath)`n"
                                    return
                                }
                            }
                            if ($existingNames -contains $valLabel) {
                                $parentFolder = [System.IO.Path]::GetFileName([System.IO.Path]::GetDirectoryName($fullPath))
                                $baseAlias    = if (-not [string]::IsNullOrWhiteSpace($parentFolder)) { "$exeName ($parentFolder)" } else { "$exeName #2" }
                                $valLabel     = $baseAlias
                                $suffixIdx    = 2
                                while ($existingNames -contains $valLabel) {
                                    $valLabel = "$baseAlias #$suffixIdx"
                                    $suffixIdx++
                                }
                            }
                        }
                    }

                    Set-UltixRegValue -Path $regKey -Name $valLabel -Value $fullPath -Type String -Module "Z5_Utilities"
                    Write-GUI " -> Added custom SRP+IFEO target: $valLabel ($fullPath)`n"
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

            # Read custom SRP entries before removing tracking key so Revert has full path & GUID metadata
            $customItems = @(Get-RegState_SRP | Where-Object { $_.ActionData.IsCustom -eq $true })
            Remove-UltixRegItem -Path $regKey -IgnoreMissing -Module "Z5_Utilities"

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

    # 5. Hardened DNS, Parental Control & Native DoH Enforcer (IPv4 + IPv6)
    $dnsCatalogRef = Get-UltixDnsCatalog
    $dnsUiState    = @{ LastPreview = "" }

    $lblDNS = New-Object System.Windows.Forms.Label
    $lblDNS.Text = "Hardened DNS, Parental Control & Native DoH"
    $lblDNS.AccessibleName = "SectionHeader"
    $lblDNS.UseMnemonic = $false
    $lblDNS.Location = New-Object System.Drawing.Point(15, 224)
    $lblDNS.Size = New-Object System.Drawing.Size(370, 20)
    $lblDNS.ForeColor = [System.Drawing.Color]::DarkGray
    $lblDNS.Font = Get-UltixFont -Role "SectionHeader"

    $comboDNS = New-Object System.Windows.Forms.ComboBox
    $comboDNS.Location = New-Object System.Drawing.Point(15, 247)
    $comboDNS.Size = New-Object System.Drawing.Size(260, 28)
    $comboDNS.BackColor = [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
    $comboDNS.ForeColor = [System.Drawing.Color]::White
    $comboDNS.DropDownStyle = "DropDownList"
    $comboDNS.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $comboDNS.ItemHeight = 22
    $comboDNS.IntegralHeight = $false
    $comboDNS.MaxDropDownItems = $dnsCatalogRef.Count
    $comboDNS.DropDownHeight = [math]::Min(410, ($dnsCatalogRef.Count * 22) + 8)
    $comboDNS.DropDownWidth = 480
    $comboDNS.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $comboDNS.Items.AddRange([object[]]@($dnsCatalogRef.Keys))
    $comboDNS.SelectedIndex = 0

    $dnsBadgeFont = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Bold)

    $comboDNS.Add_DrawItem({
        param($src, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $src.Items.Count) { return }

        $itemName   = [string]$src.Items[$e.Index]
        $isEditBox  = (($e.State -band [System.Windows.Forms.DrawItemState]::ComboBoxEdit) -ne 0)
        $isSelected = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)

        if (-not $isEditBox -and $isSelected -and $dnsUiState.LastPreview -ne $itemName) {
            $dnsUiState.LastPreview = $itemName
            Show-Description (Format-UltixDnsDescription -Provider $itemName)
        }

        $bgColor = if ($isSelected -and -not $isEditBox) {
            [System.Drawing.Color]::FromArgb(255, 45, 85, 125)
        } elseif ($isEditBox) {
            [System.Drawing.Color]::FromArgb(255, 55, 58, 64)
        } elseif (($e.Index % 2) -eq 1) {
            [System.Drawing.Color]::FromArgb(255, 36, 39, 45)
        } else {
            [System.Drawing.Color]::FromArgb(255, 28, 30, 34)
        }

        $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
        try {
            $e.Graphics.FillRectangle($bgBrush, $e.Bounds)
        } finally {
            $bgBrush.Dispose()
        }

        $cfg = if ($dnsCatalogRef.Contains($itemName)) { $dnsCatalogRef[$itemName] } else { $null }
        $nameColor = if ($null -ne $cfg -and $cfg.Category -eq "Parental" -and -not $isEditBox) {
            [System.Drawing.Color]::FromArgb(255, 255, 232, 165)
        } else {
            [System.Drawing.Color]::White
        }

        if ($isEditBox) {
            $editRect = New-Object System.Drawing.Rectangle(($e.Bounds.X + 2), $e.Bounds.Y, [math]::Max(10, $e.Bounds.Width - 4), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText(
                $e.Graphics, $itemName, $src.Font, $editRect, $nameColor,
                ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix)
            )
            return
        }

        $badgeText  = if ($null -ne $cfg) { [string]$cfg.Badge } else { "" }
        $badgeColor = [System.Drawing.Color]::Silver
        if ($null -ne $cfg) {
            switch ($cfg.Category) {
                "Parental" { $badgeColor = [System.Drawing.Color]::Gold }
                "AdBlock"  { $badgeColor = [System.Drawing.Color]::LightGreen }
                "Security" { $badgeColor = [System.Drawing.Color]::LightSkyBlue }
                "Standard" { $badgeColor = [System.Drawing.Color]::FromArgb(255, 190, 200, 212) }
            }
        }

        $badgeWidth = 175
        $nameRect   = New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, [math]::Max(10, $e.Bounds.Width - $badgeWidth - 12), $e.Bounds.Height)
        $badgeRect  = New-Object System.Drawing.Rectangle(($e.Bounds.Right - $badgeWidth - 6), $e.Bounds.Y, $badgeWidth, $e.Bounds.Height)

        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics, $itemName, $src.Font, $nameRect, $nameColor,
            ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix)
        )
        if (-not [string]::IsNullOrWhiteSpace($badgeText)) {
            [System.Windows.Forms.TextRenderer]::DrawText(
                $e.Graphics, $badgeText, $dnsBadgeFont, $badgeRect, $badgeColor,
                ([System.Windows.Forms.TextFormatFlags]::Right -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix)
            )
        }
    }.GetNewClosure())

    $comboDNS.Add_Disposed({
        if ($null -ne $dnsBadgeFont) { $dnsBadgeFont.Dispose() }
    }.GetNewClosure())

    $chkDoH = New-Object System.Windows.Forms.CheckBox
    $chkDoH.Text = "Enforce Native DNS-over-HTTPS (DoH)"
    $chkDoH.Location = New-Object System.Drawing.Point(15, 280)
    $chkDoH.Size = New-Object System.Drawing.Size(235, 22)
    $chkDoH.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $chkDoH.ForeColor = [System.Drawing.Color]::LightGray
    $chkDoH.Checked = $true

    $chkIPv6 = New-Object System.Windows.Forms.CheckBox
    $chkIPv6.Text = "Configure IPv6 DNS"
    $chkIPv6.Location = New-Object System.Drawing.Point(255, 280)
    $chkIPv6.Size = New-Object System.Drawing.Size(135, 22)
    $chkIPv6.Font = New-Object System.Drawing.Font("Segoe UI", 9.0)
    $chkIPv6.ForeColor = [System.Drawing.Color]::LightGray
    $chkIPv6.Checked = $false

    $syncDnsControls = ({
        $selName    = [string]$comboDNS.SelectedItem
        $isStatic   = ($selName -ne "Default (DHCP)")
        $cfg        = if ($dnsCatalogRef.Contains($selName)) { $dnsCatalogRef[$selName] } else { $null }
        $supportsV6 = ($null -ne $cfg -and @($cfg.IPv6).Count -gt 0)

        $chkDoH.Enabled  = $isStatic
        $chkIPv6.Enabled = ($isStatic -and $supportsV6)
        if (-not $supportsV6) { $chkIPv6.Checked = $false }
    }.GetNewClosure())

    $comboDNS.Add_SelectedIndexChanged({
        & $syncDnsControls
        $dnsUiState.LastPreview = [string]$comboDNS.SelectedItem
        Show-Description (Format-UltixDnsDescription -Provider ([string]$comboDNS.SelectedItem))
    }.GetNewClosure())

    $comboDNS.Add_DropDownClosed({
        $dnsUiState.LastPreview = [string]$comboDNS.SelectedItem
        Show-Description (Format-UltixDnsDescription -Provider ([string]$comboDNS.SelectedItem))
    }.GetNewClosure())

    $comboDNS.Add_MouseEnter({
        Show-Description (Format-UltixDnsDescription -Provider ([string]$comboDNS.SelectedItem))
    }.GetNewClosure())

    $comboDNS.Add_MouseLeave({
        if (-not $comboDNS.DroppedDown) { Restore-Log }
    }.GetNewClosure())

    $btnApplyDNS = New-UltixButton -Parent $tabSec -X 285 -Y 247 -Width 100 -Height 28 -RGB @(45, 85, 125) `
        -Text "Apply DNS" `
        -OnClick ({
            Set-CustomDNS -Provider ([string]$comboDNS.SelectedItem) -EnableDoH $chkDoH.Checked -EnableIPv6 $chkIPv6.Checked -ControlsToDisable $allTabButtons.ToArray()
        }.GetNewClosure())

    $btnApplyDNS.Add_MouseEnter({
        Show-Description (Format-UltixDnsDescription -Provider ([string]$comboDNS.SelectedItem))
    }.GetNewClosure())

    $global:lblCurrentDNS = New-Object System.Windows.Forms.Label
    $global:lblCurrentDNS.Text = "Current DNS: Reading from active route..."
    $global:lblCurrentDNS.UseMnemonic = $false
    $global:lblCurrentDNS.Location = New-Object System.Drawing.Point(15, 305)
    $global:lblCurrentDNS.Size = New-Object System.Drawing.Size(370, 34)
    $global:lblCurrentDNS.Font = New-Object System.Drawing.Font("Consolas", 8.75, [System.Drawing.FontStyle]::Bold)
    $global:lblCurrentDNS.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $global:lblCurrentDNS.Add_MouseEnter({
        if (-not [string]::IsNullOrWhiteSpace($this.AccessibleDescription)) {
            Show-Description $this.AccessibleDescription
        }
    })
    $global:lblCurrentDNS.Add_MouseLeave({ Restore-Log })

    # 6. Classic Windows Control Applets (8 Tools)
    $lblClassic = New-Object System.Windows.Forms.Label
    $lblClassic.Text = "Classic Win32 Control & Admin Applets"
    $lblClassic.AccessibleName = "SectionHeader"
    $lblClassic.UseMnemonic = $false
    $lblClassic.Location = New-Object System.Drawing.Point(15, 345)
    $lblClassic.Size = New-Object System.Drawing.Size(370, 20)
    $lblClassic.ForeColor = [System.Drawing.Color]::DarkGray
    $lblClassic.Font = Get-UltixFont -Role "SectionHeader"

    $btnNetCpl = New-UltixButton -Parent $tabSec -X 15 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Network Adapters (ncpa)" `
        -Description "Direct launch of the classic Win32 Network Connections applet (ncpa.cpl)." `
        -OnClick { Start-ClassicNet }

    $btnSndCpl = New-UltixButton -Parent $tabSec -X 205 -Y 370 -Width 180 -Height 40 -RGB @(55, 58, 64) `
        -Text "Sound Devices (mmsys)" `
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