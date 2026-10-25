# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE
# Z6_Integrity: Service and repair module. Executes asynchronous WinSxS analysis, ResetBase compression, network stack refresh, Print Spooler reset, and core OS repairs.
# ==========================================

# ------------------------------------------
# Z6: ASYNC EXTERNAL CONSOLE HELPER (NO ANR)
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
        $proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c title $CmdTitle & color 0A & $CmdChain" -PassThru
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
            Write-GUI " -> [$($res.Title)] finished (Exit Code: $($res.ExitCode)).`n"
        }
    }
}

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE (PURE RUNSPACE WORKERS)
# ------------------------------------------
function Get-WinSxSState {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dism.exe"
    $psi.Arguments = "/Online /Cleanup-Image /AnalyzeComponentStore /English"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $dismOutput = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $proc.Dispose()

    $recommended = ($dismOutput -match "Component Store Cleanup Recommended\s*:\s*Yes")
    $sizeMatch   = [regex]::Match($dismOutput, "Actual Size of Component Store\s*:\s*(.+?)(\r?\n|$)")
    $actualSize  = if ($sizeMatch.Success) { $sizeMatch.Groups[1].Value.Trim() } else { "Unknown" }

    $rebootPending = Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"

    return [PSCustomObject]@{
        UIDisplayName = "WinSxS Payload (Actual Size: $actualSize)"
        IsDetected    = $recommended
        ActionData    = $actualSize
        RebootPending = $rebootPending
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

    $cmd = "echo Aggressive WinSxS compression in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & echo. & echo Operation finished. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - WinSxS ResetBase" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-SystemIntegrity {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo [1/3] Running Online CheckDisk Scan... & chkdsk C: /scan & echo. & echo [2/3] Running DISM RestoreHealth... & dism /online /cleanup-image /restorehealth & echo. & echo [3/3] Running SFC Scan... & sfc /scannow & echo. & echo All integrity checks completed. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - System Integrity Repair" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Clear-NetworkStack {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)
    $cmd = "echo Flushing DNS resolver cache... & ipconfig /flushdns & echo. & echo Resetting Winsock Catalog... & netsh winsock reset & echo. & echo Resetting TCP/IP Stack... & netsh int ip reset & echo. & echo Network stack refreshed. Press any key to close... & pause >nul"
    Start-ExternalConsoleAsync -Title "WinUltix - Network Stack Refresh" -CommandChain $cmd -ControlsToDisable $ControlsToDisable
}

function Repair-PrintSubsystem {
    param([System.Windows.Forms.Control[]]$ControlsToDisable)

    Write-GUI " -> Initiating Print Subsystem First-Aid (Background Thread)..."
    Update-Progress 25

    Invoke-AsyncTask -ControlsToDisable $ControlsToDisable -ScriptBlock {
        $logs = [System.Collections.Generic.List[string]]::new()
        try {
            $spoolerProc = Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue
            if ($spoolerProc) {
                $spoolerProc | Stop-Process -Force -ErrorAction SilentlyContinue
                $logs.Add(" -> Terminated locked spoolsv.exe process.")
            } else {
                Stop-Service -Name "Spooler" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            }

            Start-Sleep -Milliseconds 800

            $spoolPath = "$env:windir\System32\spool\PRINTERS"
            if (Test-Path -Path $spoolPath) {
                $purgedCount = 0
                Get-ChildItem -Path "$spoolPath\*" -Include "*.SHD", "*.SPL", "*.TMP" -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $_.Attributes = 'Normal'
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    $purgedCount++
                }
                $logs.Add(" -> Purged $purgedCount orphaned .SHD/.SPL print queue file(s).")
            }

            $printWorkflow = Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue
            if ($printWorkflow) {
                $printWorkflow | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $printWorkflow | Start-Service -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
                $logs.Add(" -> Restarted dynamic PrintWorkflowUserSvc service.")
            }

            Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction Stop
            $logs.Add(" -> Print Spooler service is back online.")
        } catch {
            $logs.Add(" [!] Failed to reset print subsystem: $($_.Exception.Message)")
        }
        return $logs
    } -OnComplete {
        param($logEntries)
        Update-Progress 0
        foreach ($line in $logEntries) { Write-GUI $line }
        Write-GUI ""
    }
}

function Initialize-Z6UI {
    param([System.Windows.Forms.TabControl]$TabControl)

    $tabWinSXS = New-Object System.Windows.Forms.TabPage
    $tabWinSXS.Text = "Integrity"
    $tabWinSXS.BackColor = [System.Drawing.Color]::FromArgb(255, 45, 45, 45)

    $btnCheckSystem = New-Object System.Windows.Forms.Button
    $btnCheckSystem.Text = "Scan System (ChkDisk + SFC + RestoreHealth)"
    $btnCheckSystem.Location = New-Object System.Drawing.Point(15, 20)
    $btnCheckSystem.Size = New-Object System.Drawing.Size(370, 40)
    $btnCheckSystem.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
    $btnCheckSystem.ForeColor = [System.Drawing.Color]::White
    $btnCheckSystem.FlatStyle = "Flat"
    $btnCheckSystem.Add_MouseEnter({ Show-Description "System First Aid: Scans core Windows OS files for corruption and replaces damaged components using DISM RestoreHealth and SFC without freezing the GUI." })
    $btnCheckSystem.Add_Click({ Repair-SystemIntegrity -ControlsToDisable @($this) })

    $btnResetBase = New-Object System.Windows.Forms.Button
    $btnResetBase.Text = "Aggressive Cleanup (ResetBase)"
    $btnResetBase.Location = New-Object System.Drawing.Point(15, 70)
    $btnResetBase.Size = New-Object System.Drawing.Size(320, 40)
    $btnResetBase.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnResetBase.ForeColor = [System.Drawing.Color]::White
    $btnResetBase.FlatStyle = "Flat"
    $btnResetBase.Add_MouseEnter({ Show-Description "WinSxS Deep Clean: Permanently deletes superseded Windows Update backup layers (/ResetBase) to reclaim gigabytes of disk space." })

    $btnAudWinSxS = New-Object System.Windows.Forms.Button
    $btnAudWinSxS.Text = "?"
    $btnAudWinSxS.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudWinSxS.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudWinSxS.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudWinSxS.ForeColor = [System.Drawing.Color]::White
    $btnAudWinSxS.FlatStyle = "Flat"
    $btnAudWinSxS.Add_MouseEnter({ Show-Description "AUDIT: Asynchronously analyzes true WinSxS footprint in a background Runspace and checks for pending CBS reboots." })

    $btnResetBase.Add_Click({ Optimize-WinSXS -ControlsToDisable @($btnResetBase, $btnAudWinSxS) }.GetNewClosure())
    $btnAudWinSxS.Add_Click({
        Write-GUI "--- AUDIT: CBS Component Store (Background Thread) ---"
        Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
        Update-Progress 30

        $sb = (Get-Command -Name Get-WinSxSState).ScriptBlock
        Invoke-AsyncTask -ScriptBlock $sb -ControlsToDisable @($btnAudWinSxS, $btnResetBase) -OnComplete {
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

    $btnNetFix = New-Object System.Windows.Forms.Button
    $btnNetFix.Text = "Refresh Network (DNS/Winsock)"
    $btnNetFix.Location = New-Object System.Drawing.Point(15, 120)
    $btnNetFix.Size = New-Object System.Drawing.Size(370, 40)
    $btnNetFix.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 100, 100)
    $btnNetFix.ForeColor = [System.Drawing.Color]::White
    $btnNetFix.FlatStyle = "Flat"
    $btnNetFix.Add_MouseEnter({ Show-Description "Network Fix: Flushes DNS cache, resets Winsock catalog, and resets TCP/IP stack parameters." })
    $btnNetFix.Add_Click({ Clear-NetworkStack -ControlsToDisable @($this) })

    $btnFixPrinters = New-Object System.Windows.Forms.Button
    $btnFixPrinters.Text = "Reset Print Subsystem (Spooler)"
    $btnFixPrinters.Location = New-Object System.Drawing.Point(15, 170)
    $btnFixPrinters.Size = New-Object System.Drawing.Size(370, 40)
    $btnFixPrinters.BackColor = [System.Drawing.Color]::FromArgb(255, 120, 80, 40)
    $btnFixPrinters.ForeColor = [System.Drawing.Color]::White
    $btnFixPrinters.FlatStyle = "Flat"
    $btnFixPrinters.Add_MouseEnter({ Show-Description "Printer First-Aid: Kills deadlocked spoolsv.exe, purges stuck .SPL/.SHD files in System32, restarts PrintWorkflowUserSvc, and resumes Spooler." })
    $btnFixPrinters.Add_Click({ Repair-PrintSubsystem -ControlsToDisable @($this) })

    $tabWinSXS.Controls.AddRange(@($btnCheckSystem, $btnResetBase, $btnAudWinSxS, $btnNetFix, $btnFixPrinters))
    $TabControl.Controls.Add($tabWinSXS)
}