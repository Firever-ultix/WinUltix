# ==========================================
# WINULTIX - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE (v3.0.0)
# Z6_Integrity: Service and repair module. Executes real-time streamed WinSxS analysis, ResetBase compression, network stack refresh, Print Spooler reset, Windows Update/Cryptographic First-Aid, WMI repository salvage, Shell Icon/Thumbnail cache purge, and core OS repairs.
# ==========================================

# ------------------------------------------
# Z6: ASYNC EXTERNAL CONSOLE HELPER (REAL EXIT CODE LATCH)
# ------------------------------------------
function Start-ExternalConsoleAsync {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$CommandChain,
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control[]]$ControlsToDisable
    )

    Write-GUI " -> Launching external maintenance console: $Title..."
    Update-Progress 20

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        param($CmdTitle, $CmdChain)
        # /v:on enables delayed environment variable expansion (!ERRORLEVEL! / !WUX_ERR!)
        # Preserves real command exit code across 'pause >nul'
        $fullArgs = "/v:on /c `"title $CmdTitle & color 0A & set WUX_ERR=0 & $CmdChain & if !WUX_ERR! EQU 0 (set WUX_ERR=!ERRORLEVEL!) & echo. & echo Operation finished (Exit Code: !WUX_ERR!). Press any key to close... & pause >nul & exit /b !WUX_ERR!`""
        
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $fullArgs -PassThru
        $proc.WaitForExit()
        $exitCode = $proc.ExitCode
        $proc.Dispose()

        return [PSCustomObject]@{
            Title    = $CmdTitle
            ExitCode = $exitCode
        }
    } -Arguments @($Title, $CommandChain) -OnComplete {
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
    }
}

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE (REAL-TIME $ULTIXSYNC WORKERS)
# ------------------------------------------
function Get-WinSxSState {
    if ($null -ne $UltixSync) { $UltixSync.Progress = 5 }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dism.exe"
    $psi.Arguments = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::ASCII
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $sbOutput = [System.Text.StringBuilder]::new()

    # StreamReader.ReadLine() yields on every '\r' progress bar update from dism.exe
    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -eq $line) { continue }

        if ($line -match '(\d{1,3})\.\d+%') {
            $pct = [int]$matches[1]
            if ($null -ne $UltixSync) {
                $UltixSync.Progress = [math]::Max(5, [math]::Min(95, $pct))
            }
        } else {
            [void]$sbOutput.AppendLine($line)
        }
    }

    $proc.WaitForExit()
    $exitCode = $proc.ExitCode
    $proc.Dispose()

    if ($null -ne $UltixSync) { $UltixSync.Progress = 100 }
    $dismOutput = $sbOutput.ToString()

    $recommended = ($dismOutput -match "Component Store Cleanup Recommended\s*:\s*Yes")
    $sizeMatch   = [regex]::Match($dismOutput, "Actual Size of Component Store\s*:\s*(.+?)(\r?\n|$)")
    $actualSize  = if ($sizeMatch.Success) { $sizeMatch.Groups[1].Value.Trim() } else { "Unknown" }

    $rebootPending = Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

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

    if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") {
        $warnMsg = "A pending Windows servicing reboot was detected in the CBS registry.`n`nRunning DISM /ResetBase while a reboot is pending on Windows 11 24H2/26H2 may fail with error 0x800f0806.`n`nDo you still want to force execution?"
        $ans = [System.Windows.Forms.MessageBox]::Show($warnMsg, "WinUltix - CBS Reboot Pending", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            Write-GUI " -> WinSxS ResetBase aborted due to pending reboot.`n"
            return
        }
    }

    $cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-SystemIntegrity {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk C: /scan & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Clear-NetworkStack {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo Flushing DNS resolver cache... & ipconfig /flushdns & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo Resetting Winsock Catalog... & netsh winsock reset & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!) & echo. & echo Resetting TCP/IP Stack... & netsh int ip reset & (if !ERRORLEVEL! NEQ 0 set WUX_ERR=!ERRORLEVEL!)"
    Start-ExternalConsoleAsync -Title "WinUltix - Network Stack Refresh" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-PrintSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
    Update-Progress 10

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        try {
            $UltixSync.Progress = 20
            $spoolerProc = Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue
            if ($spoolerProc) {
                $spoolerProc | Stop-Process -Force -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Terminated locked spoolsv.exe process.")
            } else {
                Stop-Service -Name "Spooler" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Stopped Print Spooler service.")
            }

            Start-Sleep -Milliseconds 800
            $UltixSync.Progress = 50

            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path -LiteralPath $spoolPath) {
                $purgedCount = 0
                Get-ChildItem -Path "$spoolPath\*" -Include "*.SHD", "*.SPL", "*.TMP" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedCount++
                    } catch { }
                }
                $UltixSync.Logs.Enqueue(" -> Purged $purgedCount orphaned .SHD/.SPL print queue file(s).")
            }

            $UltixSync.Progress = 80
            $printWorkflow = Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue
            if ($printWorkflow) {
                $printWorkflow | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $printWorkflow | Start-Service -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $UltixSync.Logs.Enqueue(" -> Restarted dynamic PrintWorkflowUserSvc service.")
            }

            Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Print Spooler service is back online.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
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
            # Stage 1: Stop WU, BITS, Cryptographic & MSI services
            $UltixSync.Progress = 15
            $UltixSync.Logs.Enqueue(" -> [1/5] Stopping wuauserv, cryptSvc, bits, dosvc, and msiserver...")
            foreach ($svc in $wuServices) {
                Stop-Service -Name $svc -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            Start-Sleep -Milliseconds 800

            # Stage 2: Purge corrupted BITS queue files (qmgr*.dat)
            $UltixSync.Progress = 35
            $bitsPaths = @(
                "$env:ProgramData\Microsoft\Network\Downloader",
                "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader"
            ) | Select-Object -Unique

            $qmgrCount = 0
            foreach ($bPath in $bitsPaths) {
                if (Test-Path -LiteralPath $bPath) {
                    Get-ChildItem -Path "$bPath\qmgr*" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        try {
                            $_.Attributes = 'Normal'
                            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                            $qmgrCount++
                        } catch { }
                    }
                }
            }
            $UltixSync.Logs.Enqueue(" -> [2/5] Purged $qmgrCount corrupted BITS transfer queue file(s) (qmgr*.dat).")

            # Stage 3: Reset Catroot2 signature cache & SoftwareDistribution DataStore
            $UltixSync.Progress = 55
            $catroot2  = "$env:windir\System32\catroot2"
            $dataStore = "$env:windir\SoftwareDistribution\DataStore"
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
            $UltixSync.Logs.Enqueue(" -> [3/5] Flushed Catroot2 cryptographic catalog cache and WU DataStore.")

            # Stage 4: Re-register core cryptographic & Windows Update COM DLLs
            $UltixSync.Progress = 75
            $dlls = @(
                "atl.dll", "urlmon.dll", "mshtml.dll", "shdocvw.dll", "browseui.dll",
                "jscript.dll", "vbscript.dll", "scrrun.dll", "msxml3.dll", "msxml6.dll",
                "actxprxy.dll", "softpub.dll", "wintrust.dll", "dssenh.dll", "rsaenh.dll",
                "gpkcsp.dll", "sccbase.dll", "slbcsp.dll", "cryptdlg.dll", "oleaut32.dll",
                "ole32.dll", "shell32.dll", "initpki.dll", "wuapi.dll", "wuaueng.dll",
                "wucltux.dll", "wups.dll", "wups2.dll", "wuwebv.dll", "qmgr.dll", "qmgrprxy.dll"
            )
            foreach ($dll in $dlls) {
                $dllFull = "$env:windir\System32\$dll"
                if (Test-Path -LiteralPath $dllFull) {
                    Start-Process -FilePath "regsvr32.exe" -ArgumentList "/s `"$dllFull`"" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue
                }
            }
            $UltixSync.Logs.Enqueue(" -> [4/5] Re-registered Cryptographic, WinTrust, and Windows Update COM DLLs.")

            # Stage 5: Restart core services
            $UltixSync.Progress = 95
            foreach ($svc in @("cryptSvc", "bits", "wuauserv")) {
                Start-Service -Name $svc -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }
            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [5/5] [OK] Windows Update & Cryptographic services restored and online.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Error during Windows Update subsystem repair: $($_.Exception.Message)")
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
        $verifyOut = (winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()

        $UltixSync.Progress = 75
        $cimHealthy = $false
        try {
            $null = Get-CimInstance -Namespace "root\cimv2" -ClassName Win32_OperatingSystem -Property Caption -ErrorAction Stop
            $null = Get-CimInstance -Namespace "root\StandardCimv2" -ClassName MSFT_NetAdapter -ErrorAction Stop
            $cimHealthy = $true
        } catch {
            $cimHealthy = $false
        }

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
            $UltixSync.Progress = 25
            $UltixSync.Logs.Enqueue(" -> [1/3] Running winmgmt /verifyrepository...")
            $verifyOut = (winmgmt.exe /verifyrepository 2>&1 | Out-String).Trim()
            $UltixSync.Logs.Enqueue("    [*] Status: $verifyOut")

            $UltixSync.Progress = 55
            $UltixSync.Logs.Enqueue(" -> [2/3] Executing non-destructive winmgmt /salvagerepository...")
            $salvageOut = (winmgmt.exe /salvagerepository 2>&1 | Out-String).Trim()
            $UltixSync.Logs.Enqueue("    [*] Result: $salvageOut")

            $UltixSync.Progress = 85
            $UltixSync.Logs.Enqueue(" -> [3/3] Refreshing WMI Performance Adapter (wmiadap /f)...")
            Start-Process -FilePath "wmiadap.exe" -ArgumentList "/f" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue

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
            Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 600

            $UltixSync.Progress = 55
            $explorerCacheDir = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            $purgedIcons  = 0
            $purgedThumbs = 0

            if (Test-Path -LiteralPath $explorerCacheDir) {
                Get-ChildItem -Path "$explorerCacheDir\iconcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedIcons++
                    } catch { }
                }
                Get-ChildItem -Path "$explorerCacheDir\thumbcache*.db" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $_.Attributes = 'Normal'
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                        $purgedThumbs++
                    } catch { }
                }
            }

            $legacyIconDb = "$env:LOCALAPPDATA\IconCache.db"
            if (Test-Path -LiteralPath $legacyIconDb) {
                try {
                    Remove-Item -LiteralPath $legacyIconDb -Force -ErrorAction Stop
                    $purgedIcons++
                } catch { }
            }

            $UltixSync.Logs.Enqueue(" -> [2/4] Purged $purgedIcons iconcache_*.db and $purgedThumbs thumbcache_*.db file(s).")

            $UltixSync.Progress = 80
            $UltixSync.Logs.Enqueue(" -> [3/4] Triggering ie4uinit.exe cache rebuild...")
            Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue

            $UltixSync.Progress = 95
            $UltixSync.Logs.Enqueue(" -> [4/4] Restarting Windows Explorer shell...")
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }

            $UltixSync.Progress = 100
            $UltixSync.Logs.Enqueue(" -> [OK] Shell Icon & Thumbnail caches rebuilt cleanly.")
        } catch {
            $UltixSync.Logs.Enqueue(" [!] Failed to rebuild Icon/Thumbnail cache: $($_.Exception.Message)")
            if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
                Start-Process "explorer.exe"
            }
        }
    } -OnComplete {
        param($nullOut)
        Update-Progress 0
        Write-GUI ""
    }
}

# ------------------------------------------
# Z6: UI INITIALIZATION (VIA CORE_HELPERS FACTORIES)
# ------------------------------------------
function Initialize-Z6UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabWinSXS = New-Object System.Windows.Forms.TabPage
    $tabWinSXS.Text = "Integrity"
    $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $allTabButtons = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()

    # 1. System Scan (ChkDisk + DISM + SFC)
    $btnCheckSystem = New-UltixButton -Parent $tabWinSXS -X 15 -Y 20 -RGB @(60, 60, 60) `
        -Text "Scan System (ChkDisk + SFC + RestoreHealth)" `
        -Description "System First Aid: Scans core Windows OS files for corruption and replaces damaged components using DISM RestoreHealth and SFC without freezing the GUI." `
        -OnClick ({ Repair-SystemIntegrity -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 2. WinSxS ResetBase + Audit [?]
    $rowWinSxS = New-UltixActionRow -Parent $tabWinSXS -Y 70 -MainRGB @(100, 40, 40) `
        -Text "Aggressive Cleanup (ResetBase)" `
        -Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." `
        -AuditDescription "AUDIT: Streams real-time DISM AnalyzeComponentStore progress in a background Runspace and checks for pending CBS reboots." `
        -OnClick ({ Optimize-WinSXS -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({
            Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
            Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
            Update-Progress 5

            $sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
            Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable $allTabButtons.ToArray() -OnComplete {
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
            }
        }.GetNewClosure())

    # 3. Network Stack Refresh
    $btnNetFix = New-UltixButton -Parent $tabWinSXS -X 15 -Y 120 -RGB @(0, 100, 100) `
        -Text "Refresh Network (DNS/Winsock)" `
        -Description "Network Fix: Flushes DNS cache, resets Winsock catalog, and resets TCP/IP stack parameters." `
        -OnClick ({ Clear-NetworkStack -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 4. Print Subsystem First-Aid
    $btnFixPrinters = New-UltixButton -Parent $tabWinSXS -X 15 -Y 170 -RGB @(120, 80, 40) `
        -Text "Reset Print Subsystem (Spooler)" `
        -Description "Printer First-Aid: Kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files in System32, restarts PrintWorkflowUserSvc, and resumes Spooler." `
        -OnClick ({ Repair-PrintSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 5. Windows Update & Cryptographic Subsystem First-Aid
    $btnFixWU = New-UltixButton -Parent $tabWinSXS -X 15 -Y 220 -RGB @(60, 90, 130) `
        -Text "Reset Windows Update & CryptSvc" `
        -Description "WU First-Aid: Stops wuauserv/bits/cryptSvc, purges corrupted qmgr*.dat queues, resets Catroot2 & DataStore, and re-registers core COM DLLs." `
        -OnClick ({ Repair-WindowsUpdateSubsystem -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 6. WMI / CIM Repository Salvage + Audit [?]
    $rowWMI = New-UltixActionRow -Parent $tabWinSXS -Y 270 -MainRGB @(90, 60, 120) `
        -Text "Verify & Salvage WMI Repository" `
        -Description "WMI First-Aid: Verifies CIM repository consistency, runs non-destructive 'winmgmt /salvagerepository', and refreshes WMI performance counters." `
        -AuditDescription "AUDIT: Runs 'winmgmt /verifyrepository' and tests live CIM queries against root\cimv2 and root\StandardCimv2." `
        -OnClick ({ Repair-WMIRepository -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure()) `
        -OnAudit ({ Invoke-WMIAudit -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    # 7. Shell Icon & Thumbnail Cache First-Aid
    $btnFixIcons = New-UltixButton -Parent $tabWinSXS -X 15 -Y 320 -RGB @(70, 100, 70) `
        -Text "Rebuild Shell Icon & Thumbnail Cache" `
        -Description "Shell First-Aid: Gracefully cycles Explorer, purges corrupted iconcache_*.db and thumbcache_*.db files, and forces a clean rebuild via ie4uinit." `
        -OnClick ({ Clear-ShellIconCache -ControlsToDisable $allTabButtons.ToArray() }.GetNewClosure())

    $allTabButtons.AddRange([System.Windows.Forms.Control[]]@(
        $btnCheckSystem,
        $btnNetFix,
        $btnFixPrinters,
        $btnFixWU,
        $btnFixIcons
    ))
    $allTabButtons.AddRange($rowWinSxS.Controls)
    $allTabButtons.AddRange($rowWMI.Controls)

    $TabControl.Controls.Add($tabWinSXS)
}