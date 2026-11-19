# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE
# Z6_Integrity: System First-Aid & OS repair (ChkDisk + DISM + SFC with fast health audit, WinSxS ResetBase compression, WMI repository salvage, Windows Update & CryptSvc reset, Network Stack refresh, Print Spooler First-Aid, and Icon Cache rebuild).
# ==========================================

# ------------------------------------------
# Z6: ASYNC EXTERNAL CONSOLE HELPER (REAL EXIT CODE LATCH)
# ------------------------------------------
function Start-ExternalConsoleAsync {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CommandChain,
        [AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @()
    )

    $validControls = @($ControlsToDisable | Where-Object { $null -ne $_ })
    Write-GUI " -> Launching external maintenance console: $Title..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $validControls -ScriptBlock {
        param($CmdTitle, $CmdChain)
        # /v:on enables delayed environment variable expansion (!ERRORLEVEL! / !WUX_ERR!)
        # Preserves real command exit code across 'pause >nul'
        $safeTitle = $CmdTitle -replace '["&|<>^]', ''
        $fullArgs  = "/v:on /c `"title $safeTitle & color 0A & set WUX_ERR=0 & $CmdChain & if !WUX_ERR! EQU 0 (set WUX_ERR=!ERRORLEVEL!) & echo. & echo Operation finished (Exit Code: !WUX_ERR!). Press any key to close... & pause >nul & exit /b !WUX_ERR!`""
        
        Write-UltixExpertCommand -CommandText "cmd.exe $fullArgs" -Module "Z6_Integrity"
        $exitCode = -1
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $fullArgs -PassThru -ErrorAction Stop
        try {
            $proc.WaitForExit()
            $exitCode = $proc.ExitCode
        } finally {
            $proc.Dispose()
        }
        Write-UltixExpertResult -OutputText "External maintenance console [$CmdTitle] closed" -ExitCode $exitCode -Module "Z6_Integrity"

        return [PSCustomObject]@{
            Title    = $CmdTitle
            ExitCode = $exitCode
        }
    } -Arguments @($Title, $CommandChain) -OnComplete ({
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            $code = [int]$res.ExitCode
            if ($code -eq 0) {
                Write-GUI " -> [$($res.Title)] completed successfully (Exit Code: 0).`n"
            } elseif ($code -eq 3010) {
                Write-GUI " -> [$($res.Title)] completed (Exit Code: 3010 - Reboot Required to finalize changes).`n"
            } else {
                $hexCode = "0x{0:X8}" -f ([uint32]$code)
                Write-GUI " -> [!] [$($res.Title)] finished with non-zero Exit Code: $code ($hexCode).`n"
            }
        }
    }.GetNewClosure())
}

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE (REAL-TIME $ULTIXSYNC WORKERS)
# ------------------------------------------
function Get-WinSxSState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }

    Unlock-UltixTrustedInstaller

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "dism.exe"
    $psi.Arguments              = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardInput  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow         = $true

    $sbOutput       = [System.Text.StringBuilder]::new()
    $exitCode       = -1
    $proc           = $null
    $loggedFinalize = $false

    Write-UltixExpertCommand -CommandText "dism.exe /Online /Cleanup-Image /AnalyzeComponentStore /English" -Module "Z6_Integrity"

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        if ($null -ne $proc) {
            # Immediately close stdin and drain stderr asynchronously without unused variable assignment
            try { $proc.StandardInput.Close() } catch { }
            [void]$proc.StandardError.ReadToEndAsync()

            $charBuf  = New-Object char[] 1024
            $readTask = $proc.StandardOutput.ReadAsync($charBuf, 0, $charBuf.Length)
            $idleTicksAfterTable = 0

            while ($true) {
                if ($readTask.Wait(250)) {
                    $charsRead = $readTask.Result
                    if ($charsRead -le 0) { break }

                    $chunk = [string]::new($charBuf, 0, $charsRead)
                    [void]$sbOutput.Append($chunk)

                    $pctMatches = [regex]::Matches($chunk, '(\d{1,3})\.\d+%')
                    if ($pctMatches.Count -gt 0) {
                        $lastPct = [int]$pctMatches[$pctMatches.Count - 1].Groups[1].Value
                        if ($null -ne $UltixSync) {
                            $UltixSync.Progress = [math]::Max(5, [math]::Min(99, $lastPct))
                            if ($lastPct -ge 100 -and -not $loggedFinalize) {
                                $loggedFinalize = $true
                                $UltixSync.Logs.Enqueue("  [*] 100% scan reached — waiting for CBS (TiWorker) to finalize WinSxS size table...")
                            }
                        }
                    }

                    $readTask = $proc.StandardOutput.ReadAsync($charBuf, 0, $charBuf.Length)
                    $idleTicksAfterTable = 0
                } else {
                    $curText = $sbOutput.ToString()
                    # Locale-independent table completion check: 2 colon-separated lines after the YYYY-MM-DD HH:MM:SS timestamp
                    $hasTableEnd = (
                        $curText -match '(?s)\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}.*?:\s*\d+\s*\r?\n[^\r\n:]+:\s*\S+' -or
                        $curText -match '(?im)Recommended.*?:\s*\S+'
                    )

                    if ($proc.HasExited) {
                        $idleTicksAfterTable++
                        if ($idleTicksAfterTable -ge 2) { break }
                    } elseif ($hasTableEnd) {
                        $idleTicksAfterTable++
                        # Break if DismHost.exe / TiWorker.exe holds an inherited stdout pipe handle after table completion
                        if ($idleTicksAfterTable -ge 6) { break }
                    }
                }
            }

            [void]$proc.WaitForExit(3000)
            if ($proc.HasExited) {
                $exitCode = $proc.ExitCode
            } else {
                $exitCode = 0
            }
        }
    } catch {
        if ($null -ne $UltixSync) {
            $UltixSync.Logs.Enqueue(" [!] DISM component store analysis failed: $($_.Exception.Message)")
        }
    } finally {
        if ($null -ne $proc) { $proc.Dispose() }
    }

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    $dismOutput = $sbOutput.ToString()

    # 100% locale-independent positional extraction: in DISM AnalyzeComponentStore table,
    # the 2nd colon-separated size entry (Bytes/KB/MB/GB/TB) is always Actual Size of Component Store
    $sizeMatches = @([regex]::Matches($dismOutput, '(?im):\s*([\d\.,]+\s*(?:[TGMK]B|Bytes))\b'))
    $actualSize  = if ($sizeMatches.Count -ge 2) {
        $sizeMatches[1].Groups[1].Value.Trim()
    } elseif ($sizeMatches.Count -eq 1) {
        $sizeMatches[0].Groups[1].Value.Trim()
    } else {
        "Unknown"
    }

    # Extract integer count of Reclaimable Packages (line immediately following YYYY-MM-DD HH:MM:SS timestamp)
    $reclaimableCount = 0
    if ($dismOutput -match '(?s)\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\s*\r?\n[^\r\n:]+:\s*(\d+)\b') {
        $reclaimableCount = [int]$matches[1]
    }
    $recommended = (
        $reclaimableCount -gt 0 -or
        ($dismOutput -match "(?im)Recommended.*?:\s*(Yes|True|1)\b")
    )

    $rebootPending = Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    Write-UltixExpertResult -OutputText "Actual Size: $actualSize | Reclaimable Packages: $reclaimableCount | Cleanup Recommended: $recommended" -ExitCode $exitCode -Module "Z6_Integrity"

    return [PSCustomObject]@{
        UIDisplayName = "WinSxS Payload (Actual Size: $actualSize)"
        IsDetected    = $recommended
        ActionData    = $actualSize
        RebootPending = $rebootPending
        ExitCode      = $exitCode
    }
}

function Optimize-WinSXS {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    if (Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $warnMsg = "A pending Windows servicing reboot was detected in the CBS registry.`n`nRunning DISM /ResetBase while a reboot is pending on Windows 11 24H2/26H2 may fail with error 0x800f0806.`n`nDo you still want to force execution?"
        $ans = [System.Windows.Forms.MessageBox]::Show($warnMsg, "WinUltix - CBS Reboot Pending", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-GUI " -> WinSxS ResetBase aborted due to pending reboot.`n"
            return
        }
    }

    $cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Unlock-UltixTrustedInstaller
    Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Invoke-SystemHealthAudit {
    param([AllowEmptyCollection()][System.Windows.Forms.Control[]]$ControlsToDisable = @())

    Write-GUI "--- AUDIT: OS Image, CBS & NTFS Volume Health (Background Thread) ---"
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        Unlock-UltixTrustedInstaller
        $UltixSync.Progress = 35
        $dismExit = Invoke-UltixExe -FilePath "dism.exe" -Arguments @("/Online", "/Cleanup-Image", "/CheckHealth", "/English") -Module "Z6_Integrity"

        # 100% locale-independent CBS corruption registry markers + DISM exit code
        $cbsKey     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"
        $cbsProps   = Get-ItemProperty -LiteralPath $cbsKey -Name "CorruptionFlags", "StoreCorrupt", "UnavailableRepairCount" -ErrorAction SilentlyContinue
        $hasRegCorr = ($null -ne $cbsProps) -and (
            ($null -ne $cbsProps.CorruptionFlags -and $cbsProps.CorruptionFlags -ne 0) -or
            ($null -ne $cbsProps.StoreCorrupt -and $cbsProps.StoreCorrupt -ne 0) -or
            ($null -ne $cbsProps.UnavailableRepairCount -and $cbsProps.UnavailableRepairCount -gt 0)
        )
        $isHealthy = ($dismExit -eq 0 -and -not $hasRegCorr)

        # Zero-WMI, 100% locale-independent NTFS Dirty Bit verification via kernel32!DeviceIoControl (FSCTL_IS_VOLUME_DIRTY)
        $UltixSync.Progress = 70
        $sysDrive  = $env:SystemDrive.TrimEnd('\')
        $dirtyCode = Invoke-UltixStep -Command "[WinUltix.NativeMethods]::IsVolumeDirty('$sysDrive') (FSCTL_IS_VOLUME_DIRTY)" -Action {
            [WinUltix.NativeMethods]::IsVolumeDirty($sysDrive)
        } -Module "Z6_Integrity"
        $isDirty   = ($dirtyCode -eq 1)

        $UltixSync.Progress = 90
        $cbsReboot = Test-Path -LiteralPath "$cbsKey\RebootPending"
        $sfcPend   = Test-Path -LiteralPath "$cbsKey\PackagesPending"

        $UltixSync.Progress = 100
        return [PSCustomObject]@{
            ImageHealthy = $isHealthy
            NtfsDirty    = $isDirty
            DriveName    = $sysDrive
            CbsReboot    = $cbsReboot
            SfcPending   = $sfcPend
        }
    } -OnComplete ({
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            if ($res.ImageHealthy) {
                Write-GUI "  [OK] DISM CheckHealth: No component store corruption detected (CBS Store Clean)."
            } else {
                Write-GUI "  [!] WARNING: DISM flagged component store corruption! Run 'Scan System' repair."
            }

            if (-not $res.NtfsDirty) {
                Write-GUI "  [OK] NTFS Volume ($($res.DriveName)): Clean (VolumeDirty = False)."
            } else {
                Write-GUI "  [!] WARNING: NTFS Volume ($($res.DriveName)) has Dirty Bit set! Run 'Scan System' repair."
            }

            if ($res.CbsReboot -or $res.SfcPending) {
                Write-GUI "  [!] CBS Servicing Status: Pending reboot / package repair detected.`n"
            } else {
                Write-GUI "  [OK] CBS Servicing Queue: Clean (Zero pending repairs).`n"
            }
        }
    }.GetNewClosure())
}

function Repair-SystemIntegrity {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    $sysDrive = $env:SystemDrive.TrimEnd('\')
    $msg = "This operation will open an external maintenance console and execute:`n`n" +
           "  1. Online CheckDisk Scan (chkdsk $sysDrive /scan)`n" +
           "  2. DISM Image Repair (DISM /Online /Cleanup-Image /RestoreHealth)`n" +
           "  3. System File Checker (sfc /scannow)`n`n" +
           "Full verification typically takes 5 to 15 minutes. Do you want to proceed?"
    $ans = [System.Windows.Forms.MessageBox]::Show($msg, "WinUltix - System Integrity Repair", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-GUI " -> System Integrity Repair cancelled by user.`n"
        return
    }

    $cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk $sysDrive /scan & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Unlock-UltixTrustedInstaller
    Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Clear-NetworkStack {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Full Network Stack Refresh (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/4] Flushing DNS Resolver Cache (ipconfig /flushdns)...")
            $null = Invoke-UltixExe -FilePath "ipconfig.exe" -Arguments @("/flushdns") -Module "Z6_Integrity"

            $UltixSync.Progress = 50
            $UltixSync.Logs.Enqueue(" -> [2/4] Clearing ARP routing tables & resetting WinHTTP proxy...")
            $null = Invoke-UltixExe -FilePath "arp.exe" -Arguments @("-d", "*") -Module "Z6_Integrity"
            $null = Invoke-UltixExe -FilePath "netsh.exe" -Arguments @("winhttp", "reset", "proxy") -Module "Z6_Integrity"

            $UltixSync.Progress = 75
            $UltixSync.Logs.Enqueue(" -> [3/4] Resetting Winsock Catalog (netsh winsock reset)...")
            $null = Invoke-UltixExe -FilePath "netsh.exe" -Arguments @("winsock", "reset") -Module "Z6_Integrity"

            $UltixSync.Progress = 95
            $UltixSync.Logs.Enqueue(" -> [4/4] Resetting TCP/IPv4 & IPv6 Stack (netsh int ip/ipv6 reset)...")
            $null = Invoke-UltixExe -FilePath "netsh.exe" -Arguments @("int", "ip", "reset") -Module "Z6_Integrity"
            $null = Invoke-UltixExe -FilePath "netsh.exe" -Arguments @("int", "ipv6", "reset") -Module "Z6_Integrity"

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Network stack refreshed (Reboot recommended to finalize Winsock reset).")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Network stack refresh failed: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Repair-PrintSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 20

            # Auto-heal if Spooler was disabled (Start=4) by Gaming Heavy Service Profile
            $spoolReg = "HKLM:\SYSTEM\CurrentControlSet\Services\Spooler"
            $curStart = (Get-ItemProperty -LiteralPath $spoolReg -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($curStart -eq 4) {
                Set-ProtectedServiceStart -ServiceName "Spooler" -StartValue 2 -Module "Z6_Integrity"
                $UltixSync.Logs.Enqueue(" -> Re-enabled Print Spooler service (Was locked to Disabled by Gaming Profile).")
            }

            Stop-UltixService -ServiceName "Spooler" -Module "Z6_Integrity"
            $killedSpool = Stop-UltixProcess -Name "spoolsv" -Module "Z6_Integrity"
            if ($killedSpool -gt 0) {
                $UltixSync.Logs.Enqueue(" -> Terminated locked spoolsv.exe process.")
            } else {
                $UltixSync.Logs.Enqueue(" -> Stopped Print Spooler service.")
            }

            Start-Sleep -Milliseconds 800
            $UltixSync.Progress = 50

            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path -LiteralPath $spoolPath) {
                $purgedCount = Invoke-UltixStep -Command "Remove-Item '$spoolPath\*.SHD,*.SPL,*.TMP' -Force" -Action {
                    $cnt = 0
                    Get-ChildItem -Path "$spoolPath\*" -Include "*.SHD", "*.SPL", "*.TMP" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            $cnt++
                        } catch { }
                    }
                    return $cnt
                } -SuccessOutput "Purged orphaned print queue files" -Module "Z6_Integrity"
                $UltixSync.Logs.Enqueue(" -> Purged $purgedCount orphaned .SHD/.SPL print queue file(s).")
            }

            $UltixSync.Progress = 80
            $printWorkflow = @(Get-Service -Name "PrintWorkflowUserSvc_*" -ErrorAction SilentlyContinue)
            if ($printWorkflow.Count -gt 0) {
                Stop-UltixService -ServiceName "PrintWorkflowUserSvc" -IncludePerUserInstances -Module "Z6_Integrity"
                foreach ($wfSvc in $printWorkflow) {
                    $wfName = $wfSvc.Name
                    $wfSvc.Dispose()
                    Invoke-UltixStep -Command "Start-Service -Name '$wfName'" -Action {
                        Start-Service -Name $wfName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                    } -SuccessOutput "Started $wfName" -Module "Z6_Integrity"
                }
                $UltixSync.Logs.Enqueue(" -> Restarted $($printWorkflow.Count) dynamic PrintWorkflowUserSvc instance(s).")
            }

            Invoke-UltixStep -Command "Start-Service -Name 'Spooler'" -Action {
                Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
            } -SuccessOutput "Print Spooler service started" -Module "Z6_Integrity"
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Print Spooler service is back online.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
            Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Repair-WindowsUpdateSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Windows Update & Cryptographic First-Aid (Background Thread)..."
    Update-Progress 5

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $wuServices = @("dosvc", "bits", "wuauserv", "cryptSvc", "msiserver")
        try {
            # Stage 1: Stop WU, BITS, Cryptographic & MSI services via unified SCM stopper
            $UltixSync.Progress = 15
            $UltixSync.Logs.Enqueue(" -> [1/5] Stopping wuauserv, cryptSvc, bits, dosvc, and msiserver...")
            foreach ($svc in $wuServices) {
                Stop-UltixService -ServiceName $svc -Module "Z6_Integrity"
            }
            Start-Sleep -Milliseconds 500

            # Stage 2: Purge corrupted BITS queue files (qmgr*.dat)
            $UltixSync.Progress = 35
            $bitsPaths = @(
                "$env:ProgramData\Microsoft\Network\Downloader",
                "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader"
            ) | Select-Object -Unique

            $qmgrCount = Invoke-UltixStep -Command "Remove-Item '$env:ProgramData\Microsoft\Network\Downloader\qmgr*' -Force" -Action {
                $cnt = 0
                foreach ($bPath in $bitsPaths) {
                    if (Test-Path -LiteralPath $bPath) {
                        Get-ChildItem -Path "$bPath\qmgr*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try {
                                $_.Attributes = 'Normal'
                                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                                $cnt++
                            } catch { }
                        }
                    }
                }
                return $cnt
            } -SuccessOutput "Purged BITS transfer queue files" -Module "Z6_Integrity"
            $UltixSync.Logs.Enqueue(" -> [2/5] Purged $qmgrCount corrupted BITS transfer queue file(s) (qmgr*.dat).")

            # Stage 3: Reset Catroot2 signature cache & SoftwareDistribution DataStore
            $UltixSync.Progress = 55
            $catroot2  = "$env:windir\System32\catroot2"
            $dataStore = "$env:windir\SoftwareDistribution\DataStore"
            Invoke-UltixStep -Command "Remove-Item '$catroot2\*', '$dataStore\*' -Recurse -Force" -Action {
                foreach ($targetDir in @($catroot2, $dataStore)) {
                    if (Test-Path -LiteralPath $targetDir) {
                        Get-ChildItem -LiteralPath $targetDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try {
                                $_.Attributes = 'Normal'
                                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                            } catch { }
                        }
                    }
                }
            } -SuccessOutput "Flushed Catroot2 catalog cache and WU DataStore" -Module "Z6_Integrity"
            $UltixSync.Logs.Enqueue(" -> [3/5] Flushed Catroot2 cryptographic catalog cache and WU DataStore.")

            # Stage 4: Single-pass batch re-registration of active Win10/11 Cryptographic & WU COM DLLs
            $UltixSync.Progress = 75
            $modernDlls = @(
                "atl.dll", "urlmon.dll", "jscript.dll", "vbscript.dll", "scrrun.dll",
                "msxml3.dll", "msxml6.dll", "actxprxy.dll", "softpub.dll", "wintrust.dll",
                "dssenh.dll", "rsaenh.dll", "cryptdlg.dll", "oleaut32.dll", "ole32.dll",
                "shell32.dll", "wuapi.dll", "wuaueng.dll", "wups.dll", "wups2.dll", "qmgr.dll"
            )

            $validDllPaths = [System.Collections.Generic.List[string]]::new()
            foreach ($dll in $modernDlls) {
                $dllFull = "$env:windir\System32\$dll"
                if ([System.IO.File]::Exists($dllFull)) {
                    $validDllPaths.Add("`"$dllFull`"")
                }
            }

            if ($validDllPaths.Count -gt 0) {
                $null = Invoke-UltixExe -FilePath "regsvr32.exe" -Arguments (@("/s") + $validDllPaths) -Module "Z6_Integrity"
            }
            $UltixSync.Logs.Enqueue(" -> [4/5] Batch re-registered $($validDllPaths.Count) Cryptographic, WinTrust, and WU COM DLLs.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Error during Windows Update subsystem repair: $($_.Exception.Message)")
        } finally {
            # Stage 5: Deterministic restoration of core services (auto-unlocks Start=4 in live SCM if blocked)
            $UltixSync.Progress = 95
            $svcDefaults = @{ "cryptSvc" = 2; "bits" = 3; "wuauserv" = 3; "dosvc" = 2; "msiserver" = 3 }
            foreach ($svc in @("cryptSvc", "bits", "wuauserv", "dosvc", "msiserver")) {
                $sPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
                if (-not (Test-Path -LiteralPath $sPath)) { continue }
                $curSt = (Get-ItemProperty -LiteralPath $sPath -Name "Start" -ErrorAction SilentlyContinue).Start
                $targetSt = if ($null -eq $curSt -or $curSt -eq 4) { $svcDefaults[$svc] } else { [int]$curSt }
                $startNow = ($svc -in @("cryptSvc", "bits", "wuauserv", "dosvc"))
                Set-ProtectedServiceStart -ServiceName $svc -StartValue $targetSt -StartService:$startNow -Module "Z6_Integrity"
            }
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [5/5] [OK] Windows Update, Delivery Optimization & Cryptographic services restored and online.")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Invoke-WMIAudit {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI "--- AUDIT: WMI / CIM Repository Health (Background Thread) ---"
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $UltixSync.Progress = 40
        $verifyOut = Invoke-UltixStep -Command "winmgmt.exe /verifyrepository" -Action {
            (& winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
        } -Module "Z6_Integrity"

        $UltixSync.Progress = 75
        $cimHealthy = Invoke-UltixStep -Command "Test-CimNamespaces (root\cimv2, root\StandardCimv2)" -Action {
            try {
                $null = Get-CimInstance -Namespace "root\cimv2" -ClassName Win32_OperatingSystem -Property Caption -ErrorAction Stop
                $null = Get-CimInstance -Namespace "root\StandardCimv2" -ClassName MSFT_NetAdapter -ErrorAction Stop
                return $true
            } catch {
                return $false
            }
        } -Module "Z6_Integrity"

        $UltixSync.Progress = 100
        return [PSCustomObject]@{
            VerifyOutput = $verifyOut
            CimHealthy   = $cimHealthy
        }
    } -OnComplete {
        param($res)
        Update-Progress 0
        if ($null -ne $res) {
            Write-GUI "  [*] winmgmt /verifyrepository: $($res.VerifyOutput)"
            if ($res.CimHealthy) {
                Write-GUI "  [OK] Core CIM namespaces (root\cimv2 & root\StandardCimv2) responded normally.`n"
            } else {
                Write-GUI "  [!] WARNING: CIM namespace query failed! Run 'Verify & Salvage WMI Repository' immediately.`n"
            }
        }
    }
}

function Repair-WMIRepository {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating WMI / CIM Repository Salvage (Background Thread)..."
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $wmiReg   = "HKLM:\SYSTEM\CurrentControlSet\Services\Winmgmt"
            $wmiStart = (Get-ItemProperty -LiteralPath $wmiReg -Name "Start" -ErrorAction SilentlyContinue).Start
            if ($wmiStart -eq 4) {
                Set-ProtectedServiceStart -ServiceName "Winmgmt" -StartValue 2 -StartService -Module "Z6_Integrity"
            } else {
                Start-Service -Name "Winmgmt" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }

            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/3] Running winmgmt /verifyrepository...")
            $verifyOut = Invoke-UltixStep -Command "winmgmt.exe /verifyrepository" -Action {
                (& winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
            } -Module "Z6_Integrity"
            $UltixSync.Logs.Enqueue("    [*] Status: $verifyOut")

            $UltixSync.Progress = 55
            $UltixSync.Logs.Enqueue(" -> [2/3] Executing non-destructive winmgmt /salvagerepository...")
            $salvageOut = Invoke-UltixStep -Command "winmgmt.exe /salvagerepository" -Action {
                (& winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
            } -Module "Z6_Integrity"
            $UltixSync.Logs.Enqueue("    [*] Result: $salvageOut")

            $UltixSync.Progress = 85
            $UltixSync.Logs.Enqueue(" -> [3/3] Refreshing WMI Performance Adapter (wmiadap /f)...")
            $null = Invoke-UltixExe -FilePath "wmiadap.exe" -Arguments @("/f") -Module "Z6_Integrity"

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] WMI Repository verification and salvage routine finished.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] WMI repair failed: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Clear-ShellIconCache {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Shell Icon & Thumbnail Cache First-Aid (Background Thread)..."
    Update-Progress 15

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/4] Stopping Explorer shell to release memory-mapped .db handles...")
            $null = Stop-UltixProcess -Name "explorer" -Module "Z6_Integrity"
            Start-Sleep -Milliseconds 600

            $UltixSync.Progress = 55
            $explorerCacheDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            $counts = Invoke-UltixStep -Command "Remove-Item '$explorerCacheDir\iconcache*.db,thumbcache*.db' -Force" -Action {
                $pIcons  = 0
                $pThumbs = 0
                if (Test-Path -LiteralPath $explorerCacheDir) {
                    Get-ChildItem -Path "$explorerCacheDir\iconcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            $pIcons++
                        } catch { }
                    }
                    Get-ChildItem -Path "$explorerCacheDir\thumbcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            $pThumbs++
                        } catch { }
                    }
                }

                $legacyIconDb = "$env:LOCALAPPDATA\IconCache.db"
                if (Test-Path -LiteralPath $legacyIconDb) {
                    try {
                        $item = Get-Item -LiteralPath $legacyIconDb -Force -ErrorAction SilentlyContinue
                        if ($null -ne $item) { $item.Attributes = 'Normal' }
                        Remove-Item -LiteralPath $legacyIconDb -Force -ErrorAction Stop
                        $pIcons++
                    } catch { }
                }
                return @($pIcons, $pThumbs)
            } -SuccessOutput "Purged icon and thumbnail cache databases" -Module "Z6_Integrity"
            $purgedIcons  = $counts[0]
            $purgedThumbs = $counts[1]

            $UltixSync.Logs.Enqueue(" -> [2/4] Purged $purgedIcons iconcache_*.db and $purgedThumbs thumbcache_*.db file(s).")

            $UltixSync.Progress = 80
            $UltixSync.Logs.Enqueue(" -> [3/4] Triggering ie4uinit.exe cache rebuild...")
            $null = Invoke-UltixExe -FilePath "ie4uinit.exe" -Arguments @("-show") -Module "Z6_Integrity"

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [4/4] [OK] Shell Icon & Thumbnail caches rebuilt cleanly.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to rebuild Icon/Thumbnail cache: $($_.Exception.Message)")
        } finally {
            $expProcs = @(Get-Process -Name "explorer" -ErrorAction SilentlyContinue)
            if ($expProcs.Count -eq 0) {
                Invoke-UltixStep -Command "Start-Process 'explorer.exe'" -Action {
                    Start-Process "explorer.exe"
                } -SuccessOutput "Explorer shell restarted" -Module "Z6_Integrity"
            } else {
                foreach ($ep in $expProcs) { $ep.Dispose() }
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Repair-TimeSynchronization {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Time & NTP Clock Synchronization First-Aid (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/4] Re-registering Windows Time service (W32Time) & unlocking SCM configuration...")
            Stop-UltixService -ServiceName "W32Time" -Module "Z6_Integrity"
            $null = Invoke-UltixExe -FilePath "w32tm.exe" -Arguments @("/unregister") -Module "Z6_Integrity"
            Start-Sleep -Milliseconds 300
            $null = Invoke-UltixExe -FilePath "w32tm.exe" -Arguments @("/register") -Module "Z6_Integrity"
            Set-ProtectedServiceStart -ServiceName "W32Time" -StartValue 3 -Module "Z6_Integrity"

            $UltixSync.Progress = 55
            $UltixSync.Logs.Enqueue(" -> [2/4] Starting Windows Time service & configuring resilient NTP pool (Cloudflare / Pool.ntp / MS)...")
            Invoke-UltixStep -Command "Start-Service -Name 'W32Time'" -Action {
                Start-Service -Name "W32Time" -WarningAction SilentlyContinue -ErrorAction Stop
            } -SuccessOutput "W32Time service started" -Module "Z6_Integrity"

            $ntpPeers = "pool.ntp.org,0x8 time.cloudflare.com,0x8 time.windows.com,0x9"
            $null = Invoke-UltixExe -FilePath "w32tm.exe" -Arguments @("/config", "/manualpeerlist:$ntpPeers", "/syncfromflags:manual", "/reliable:yes", "/update") -Module "Z6_Integrity"

            $UltixSync.Progress = 85
            $UltixSync.Logs.Enqueue(" -> [3/4] Triggering immediate NTP clock resynchronization (w32tm /resync /rediscover)...")
            $null = Invoke-UltixExe -FilePath "w32tm.exe" -Arguments @("/resync", "/rediscover") -Module "Z6_Integrity"
            $srcOut = Invoke-UltixStep -Command "w32tm.exe /query /source" -Action {
                (& w32tm.exe /query /source 2>&1 | Out-String).Trim()
            } -Module "Z6_Integrity"

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [4/4] [OK] System clock synchronized (Active NTP Source: $srcOut).")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Time synchronization repair failed: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

function Repair-UwpGamingRuntime {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating UWP, Store, WinGet & Xbox Gaming Services First-Aid (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 15
            $UltixSync.Logs.Enqueue(" -> [1/4] Unlocking & starting UWP, Delivery Optimization (DoSvc) & Xbox Gaming Services...")
            $svcMap = [ordered]@{
                "AppXSvc"             = 3
                "ClipSVC"             = 3
                "StateRepository"     = 3
                "LicenseManager"      = 3
                "InstallService"      = 3
                "TokenBroker"         = 3
                "wlidsvc"             = 3
                "NlaSvc"              = 2
                "netprofm"            = 3
                "Wcmsvc"              = 2
                "WinHttpAutoProxySvc" = 3
                "dosvc"               = 2
                "bits"                = 3
                "wuauserv"            = 3
                "GamingServices"      = 3
                "GamingServicesNet"   = 3
            }
            foreach ($svc in $svcMap.Keys) {
                $sPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$svc"
                if (Test-Path -LiteralPath $sPath) {
                    $curSt = (Get-ItemProperty -LiteralPath $sPath -Name "Start" -ErrorAction SilentlyContinue).Start
                    $targetSt = if ($curSt -eq 4 -or $svc -eq "dosvc") { $svcMap[$svc] } else { [int]$curSt }
                    Set-ProtectedServiceStart -ServiceName $svc -StartValue $targetSt -StartService -Module "Z6_Integrity"
                }
            }

            # Clear any accidental Deprovisioned registry locks blocking Store, WinGet, or Xbox packages
            $deprovRoot = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned"
            if (Test-Path -LiteralPath $deprovRoot) {
                Get-ChildItem -LiteralPath $deprovRoot -ErrorAction SilentlyContinue | Where-Object {
                    $_.PSChildName -match '(?i)(Winget|DesktopAppInstaller|WindowsStore|StorePurchaseApp|Xbox|GamingServices|VCLibs|UI\.Xaml|WindowsAppRuntime)'
                } | ForEach-Object {
                    Remove-UltixRegItem -Path "$deprovRoot\$($_.PSChildName)" -IgnoreMissing -Module "Z6_Integrity"
                }
            }

            $UltixSync.Progress = 35
            $UltixSync.Logs.Enqueue(" -> [2/4] Flushing corrupted Microsoft Store LocalCache & running wsreset -i...")
            $null = Stop-UltixProcess -Name @("WinStore.App", "StoreExperienceHost", "WindowsPackageManagerServer", "winget") -Module "Z6_Integrity"
            $storeCache = Get-ChildItem -Path "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_*\LocalCache" -Directory -ErrorAction SilentlyContinue
            foreach ($dir in $storeCache) {
                Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            Invoke-UltixStep -Command "wsreset.exe -i" -Action {
                $wsProc = Start-Process -FilePath "wsreset.exe" -ArgumentList "-i" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                if ($null -ne $wsProc) {
                    try { $wsProc.WaitForExit(6000) | Out-Null } finally { $wsProc.Dispose() }
                }
            } -SuccessOutput "Triggered Microsoft Store reset (wsreset -i)" -Module "Z6_Integrity"

            $UltixSync.Progress = 50
            $UltixSync.Logs.Enqueue(" -> [3/4] Re-registering Store, WinGet (DesktopAppInstaller) & Xbox manifests...")
            # Strictly target Store, WinGet & Xbox packages (skipping running Shell hosts & 40+ redundant framework builds)
            $corePattern = "^(?i).*(WindowsStore|StorePurchaseApp|DesktopAppInstaller|Winget\.Source|XboxIdentityProvider|XboxGameCallableUI|GamingServices)$"
            $targetPkgs  = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $corePattern })

            $reRegCount = 0
            $pkgTotal   = [math]::Max(1, $targetPkgs.Count)
            $pkgIdx     = 0
            foreach ($pkg in $targetPkgs) {
                $pkgIdx++
                $UltixSync.Progress = 50 + [int](($pkgIdx / $pkgTotal) * 25)
                if (-not [string]::IsNullOrWhiteSpace($pkg.InstallLocation)) {
                    $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
                    if ([System.IO.File]::Exists($manifest)) {
                        try {
                            Invoke-UltixStep -Command "Add-AppxPackage -DisableDevelopmentMode -Register '$manifest'" -Action {
                                Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                            } -SuccessOutput "Registered $($pkg.Name)" -Module "Z6_Integrity"
                            $reRegCount++
                        } catch { }
                    }
                }
            }
            $UltixSync.Logs.Enqueue("    [OK] Re-registered $reRegCount Store, WinGet & Xbox manifest(s).")

            # Stage 4: Clear dead WinHTTP/WinINet proxy locks & repair WinGet repository index (source2.msix)
            $UltixSync.Progress = 80
            $UltixSync.Logs.Enqueue(" -> [4/4] Resetting WinHTTP proxy locks & repairing WinGet source index (source2.msix)...")
            $null = Invoke-UltixExe -FilePath "netsh.exe" -Arguments @("winhttp", "reset", "proxy") -Module "Z6_Integrity"
            Set-UltixRegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -Value 0 -Type DWord -Module "Z6_Integrity"
            $tmpMsix    = Join-Path $env:TEMP "WinUltix_WingetSource2.msix"
            $sourceUrl  = "https://cdn.winget.microsoft.com/cache/source2.msix"
            $activeNics = @(Get-UltixActiveNetworkAdapters)

            if ($activeNics.Count -eq 0 -or -not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
                $UltixSync.Logs.Enqueue("    [*] Offline environment detected (no routed gateway) — skipping remote WinGet source2.msix download.")
            } else {
                try {
                    $dlBytes = Invoke-UltixStep -Command "HttpWebRequest GET '$sourceUrl' (Timeout: 10s/15s) -> '$tmpMsix'" -Action {
                        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                        $req = [System.Net.HttpWebRequest]::Create($sourceUrl)
                        $req.Method           = "GET"
                        $req.Timeout          = 10000
                        $req.ReadWriteTimeout = 15000
                        $req.UserAgent        = "WinUltix-Integrity/3.19"

                        $resp = $null
                        $inStream = $null
                        $outStream = $null
                        try {
                            $resp      = $req.GetResponse()
                            $inStream  = $resp.GetResponseStream()
                            $outStream = [System.IO.File]::Create($tmpMsix)
                            $inStream.CopyTo($outStream)
                            $outStream.Flush()
                            return [int64]$outStream.Length
                        } finally {
                            if ($null -ne $outStream) { $outStream.Dispose() }
                            if ($null -ne $inStream)  { $inStream.Dispose() }
                            if ($null -ne $resp)      { $resp.Dispose() }
                        }
                    } -Module "Z6_Integrity"

                    $UltixSync.Progress = 92
                    if ([System.IO.File]::Exists($tmpMsix) -and $dlBytes -gt 1048576) {
                        Invoke-UltixStep -Command "Add-AppxPackage -Path '$tmpMsix' -ForceApplicationShutdown" -Action {
                            Add-AppxPackage -Path $tmpMsix -ForceApplicationShutdown -ErrorAction Stop
                        } -SuccessOutput "Installed WinGet v2 index package (source2.msix)" -Module "Z6_Integrity"
                        $UltixSync.Logs.Enqueue("    [OK] Installed fresh WinGet v2 index package (source2.msix).")
                    }
                } catch {
                    $UltixSync.Logs.Enqueue("    [!] WinGet source2.msix refresh skipped (offline/timeout): $($_.Exception.Message)")
                } finally {
                    if (Test-Path -LiteralPath $tmpMsix) {
                        Remove-Item -LiteralPath $tmpMsix -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Store, WinGet & Xbox Gaming runtime repair completed.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] UWP & Gaming runtime repair failed: $($_.Exception.Message)")
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

# ------------------------------------------
# Z6: UI INITIALIZATION (INTEGRITY & SYSTEM FIRST-AID)
# ------------------------------------------
function Initialize-Z6UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabWinSXS = New-Object System.Windows.Forms.TabPage
    $tabWinSXS.Text = "Integrity"
    $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 40, 40, 42)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. System Scan (ChkDisk + DISM + SFC) + Fast Health Audit [?]
    $rowCheckSystem = New-UltixActionRow -Parent $tabWinSXS -Y 20 -MainRGB @(55, 58, 64) `
        -Text "Scan System (ChkDisk + SFC + DISM)" `
        -Description "System First-Aid: Scans core Windows OS files for corruption and replaces damaged components using ChkDisk, DISM RestoreHealth, and SFC." `
        -AuditDescription "AUDIT: Runs a fast (<3s) DISM /CheckHealth scan, checks the NTFS dirty bit via native FSCTL_IS_VOLUME_DIRTY, and inspects CBS pending repair flags." `
        -OnClick ({ Repair-SystemIntegrity -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Invoke-SystemHealthAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 2. WinSxS ResetBase + Audit [?]
    $rowWinSxS = New-UltixActionRow -Parent $tabWinSXS -Y 70 -MainRGB @(135, 50, 50) `
        -Text "WinSxS Store Compression (ResetBase)" `
        -Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." `
        -AuditDescription "AUDIT: Streams real-time DISM AnalyzeComponentStore progress in a background Runspace and checks for pending CBS reboots." `
        -OnClick ({ Optimize-WinSXS -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({
            Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
            Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
            Update-Progress 5

            $sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
            Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $allTabButtons.ToArray() -OnComplete ({
                param($output)
                Update-Progress 0
                $auditResult = $output | Select-Object -First 1
                if ($null -ne $auditResult) {
                    Write-GUI "  [*] Actual Store Size: $($auditResult.ActionData)"
                    if ($auditResult.RebootPending) {
                        Write-GUI "  [!] WARNING: Pending CBS reboot detected! Reboot before running ResetBase to avoid 0x800f0806."
                    }
                    if ($auditResult.IsDetected) {
                        Write-GUI "  [!] Cleanup Recommended by OS."
                    } else {
                        Write-GUI "  [OK] CBS reports no mandatory cleanup, though I can still force ResetBase payload amputation."
                    }
                    Write-GUI ""
                }
            }.GetNewClosure())
        }.GetNewClosure())

    # 3. WMI / CIM Repository Salvage + Audit [?]
    $rowWMI = New-UltixActionRow -Parent $tabWinSXS -Y 120 -MainRGB @(55, 58, 64) `
        -Text "Verify & Salvage WMI Repository" `
        -Description "WMI First-Aid: Verifies CIM repository consistency, runs non-destructive 'winmgmt /salvagerepository', and refreshes WMI performance counters." `
        -AuditDescription "AUDIT: Runs 'winmgmt /verifyrepository' and tests live CIM queries against root\cimv2 and root\StandardCimv2." `
        -OnClick ({ Repair-WMIRepository -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Invoke-WMIAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 4. Windows Update & Cryptographic Subsystem First-Aid
    $btnFixWU = New-UltixButton -Parent $tabWinSXS -X 15 -Y 170 -RGB @(55, 58, 64) `
        -Text "Reset Windows Update & CryptSvc" `
        -Description "WU First-Aid: Stops wuauserv/bits/cryptSvc, purges corrupted qmgr*.dat queues, resets Catroot2 & DataStore, and batch re-registers 21 core COM DLLs." `
        -OnClick ({ Repair-WindowsUpdateSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 5. Network Stack Refresh
    $btnNetFix = New-UltixButton -Parent $tabWinSXS -X 15 -Y 220 -RGB @(55, 58, 64) `
        -Text "Refresh Network Stack (DNS / Winsock)" `
        -Description "Network First-Aid: Flushes DNS cache, clears ARP tables, resets WinHTTP proxy, resets Winsock catalog, and resets TCP/IPv4 & IPv6 stack." `
        -OnClick ({ Clear-NetworkStack -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 6. Print Subsystem First-Aid
    $btnFixPrinters = New-UltixButton -Parent $tabWinSXS -X 15 -Y 270 -RGB @(55, 58, 64) `
        -Text "Reset Print Subsystem (Spooler)" `
        -Description "Printer First-Aid: Auto-unlocks Spooler if disabled, kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files, and restarts PrintWorkflowUserSvc." `
        -OnClick ({ Repair-PrintSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 7. Shell Icon & Thumbnail Cache First-Aid
    $btnFixIcons = New-UltixButton -Parent $tabWinSXS -X 15 -Y 320 -RGB @(55, 58, 64) `
        -Text "Rebuild Shell Icon & Thumbnail Cache" `
        -Description "Shell First-Aid: Gracefully cycles Explorer, purges corrupted iconcache_*.db and thumbcache_*.db files, and forces a clean rebuild via ie4uinit." `
        -OnClick ({ Clear-ShellIconCache -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 8. Time & NTP Clock Sync First-Aid
    $btnFixTime = New-UltixButton -Parent $tabWinSXS -X 15 -Y 370 -RGB @(55, 58, 64) `
        -Text "Repair Time & NTP Clock Sync (w32time)" `
        -Description "Time First-Aid: Re-registers W32Time service, configures resilient Cloudflare/NTP.org peers, and forces immediate clock resynchronization." `
        -OnClick ({ Repair-TimeSynchronization -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 9. UWP Shell, Store, WinGet & Xbox Gaming Services First-Aid
    $btnFixUwp = New-UltixButton -Parent $tabWinSXS -X 15 -Y 420 -RGB @(45, 85, 125) `
        -Text "Repair UWP, Store & Gaming Services" `
        -Description "UWP, WinGet & Gaming First-Aid: Unlocks ClipSVC/AppXSvc/InstallService/DoSvc, runs silent wsreset -i, and re-registers Shell, Store, WinGet & Xbox manifests." `
        -OnClick ({ Repair-UwpGamingRuntime -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    foreach ($row in @($rowCheckSystem, $rowWinSxS, $rowWMI)) {
        $allTabButtons.AddRange($row.Controls)
    }
    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
        $btnFixWU, $btnNetFix, $btnFixPrinters, $btnFixIcons, $btnFixTime, $btnFixUwp
    ))

    $TabControl.Controls.Add($tabWinSXS)
}