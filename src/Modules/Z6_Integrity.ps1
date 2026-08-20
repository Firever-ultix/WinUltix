# ==========================================
# WINULTIX PRO - ULTIMATE SYSTEM TOOLKIT
# https://github.com/Firever-ultix/WinUltix
# Z6_INTEGRITY.PS1 - SYSTEM INTEGRITY MODULE
# Z6_Integrity: Service and repair module. Executes aggressive WinSXS compression (DISM /ResetBase) and runs integrated system file repairs (DISM /RestoreHealth + SFC /scannow).
# ==========================================

# ------------------------------------------
# Z6: SYSTEM INTEGRITY ENGINE
# ------------------------------------------
function Get-WinSxSState {
    Write-GUI " -> Analyzing CBS Component Store (WinSxS)... Expect heavy I/O."
    
    # Offload DISM execution from the main UI thread
    $tempFile = [System.IO.Path]::GetTempFileName()
    $process = Start-Process -FilePath "dism.exe" -ArgumentList "/Online /Cleanup-Image /AnalyzeComponentStore /English" -WindowStyle Hidden -RedirectStandardOutput $tempFile -PassThru
    
    # Maintain UI responsiveness (process Windows messages) while DISM is running
    while (-not $process.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    
    $dismOutput = Get-Content -Path $tempFile -Raw
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    
    $recommended = $false
    if ($dismOutput -match "Component Store Cleanup Recommended : Yes") { 
        $recommended = $true 
    }
    
    $sizeMatch = [regex]::Match($dismOutput, "Actual Size of Component Store : (.*?)\r?\n")
    $actualSize = if ($sizeMatch.Success) { $sizeMatch.Groups[1].Value.Trim() } else { "Unknown" }
    
    return [PSCustomObject]@{
        UIDisplayName = "WinSxS Payload (Actual Size: $actualSize)"
        IsDetected    = $recommended
        ActionData    = $actualSize
    }
}

function Optimize-WinSXS { 
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c title WinSXS Optimization & color 0A & echo Aggressive cleaning in progress (ResetBase)... & dism /online /cleanup-image /startcomponentcleanup /resetbase & echo. & pause >nul" -Wait 
}

function Repair-SystemIntegrity { 
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c title System Scan & color 0A & echo Running CheckDisk Scan... & chkdsk C: /scan & echo. & echo RestoreHealth... & dism /online /cleanup-image /restorehealth & echo. & echo SFC Scanning... & sfc /scannow & echo. & pause >nul" -Wait }

function Clear-NetworkStack {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c title Network Fix & color 0A & ipconfig /flushdns & echo. & echo Resetting Winsock... & netsh winsock reset & echo. & pause >nul" -Wait
}

function Repair-PrintSubsystem {
    Write-GUI " -> Initiating Print Subsystem reset..."
    
    try {
        # Forcefully terminate the spooler process to bypass 'StopPending' deadlocks
        $spoolerProc = Get-Process -Name "spoolsv" -ErrorAction SilentlyContinue
        if ($spoolerProc) {
            Stop-Process -Id $spoolerProc.Id -Force -ErrorAction SilentlyContinue
        } else {
            Stop-Service -Name "Spooler" -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }
        
        Start-Sleep -Seconds 1
        
        # Purge RAW and SHD files
        $spoolPath = "$env:windir\System32\spool\PRINTERS"
        if (Test-Path -Path $spoolPath) {
            Remove-Item -Path "$spoolPath\*" -Force -Recurse -ErrorAction SilentlyContinue
            Write-GUI " -> Spool directory purged."
        }
        
        # Reset Windows 11 Modern Print Dialog service (per-user service, requires wildcard)
        $printWorkflow = Get-Service -Name "PrintWorkflowUserSvc*" -ErrorAction SilentlyContinue
        if ($printWorkflow) {
            $printWorkflow | Stop-Service -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            Write-GUI " -> Modern Print Workflow service reset."
        }

        # Bring the stack back online
        Start-Service -Name "Spooler" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Write-GUI " -> Print Spooler is back online."
    } catch {
        Write-GUI " [!] Failed to reset print subsystem: $($_.Exception.Message)"
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
    $btnCheckSystem.Add_MouseEnter({ Show-Description "System First Aid: Scans the core Windows OS files for corruption and replaces damaged components with fresh copies downloaded directly from Microsoft servers (SFC & DISM)." })
    $btnCheckSystem.Add_Click({ Repair-SystemIntegrity; Write-GUI "Completed."; Write-GUI "" })

    # Aggressive Cleanup (ResetBase)
    $btnResetBase = New-Object System.Windows.Forms.Button
    $btnResetBase.Text = "Aggressive Cleanup (ResetBase)"
    $btnResetBase.Location = New-Object System.Drawing.Point(15, 70)
    $btnResetBase.Size = New-Object System.Drawing.Size(320, 40) # Resized from 370
    $btnResetBase.BackColor = [System.Drawing.Color]::FromArgb(255, 100, 40, 40)
    $btnResetBase.ForeColor = [System.Drawing.Color]::White
    $btnResetBase.FlatStyle = "Flat"
    $btnResetBase.Add_MouseEnter({ Show-Description "WinSXS Deep Clean: Permanently deletes superseded Windows Update backup files. Reclaims gigabytes of C: drive space, but you will NOT be able to uninstall previously applied Windows Updates." })
    $btnResetBase.Add_Click({ Optimize-WinSXS; Write-GUI "Completed."; Write-GUI "" })

    $btnAudWinSxS = New-Object System.Windows.Forms.Button
    $btnAudWinSxS.Text = "?"
    $btnAudWinSxS.Location = New-Object System.Drawing.Point(345, 70)
    $btnAudWinSxS.Size = New-Object System.Drawing.Size(40, 40)
    $btnAudWinSxS.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    $btnAudWinSxS.ForeColor = [System.Drawing.Color]::White
    $btnAudWinSxS.FlatStyle = "Flat"
    $btnAudWinSxS.Add_MouseEnter({ Show-Description "AUDIT: Analyzes true WinSxS size (bypassing hardlinks) and queries CBS for optimization recommendations." })
    $btnAudWinSxS.Add_Click({ 
        # Prevent parallel executions and force UI redraw
        $this.Enabled = $false
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 60, 60, 60)
        [System.Windows.Forms.Application]::DoEvents()

        Write-GUI "--- AUDIT: CBS Component Store ---"
        
        $state = Get-WinSxSState
        
        Write-GUI "  [*] Actual Store Size: $($state.ActionData)"
        if ($state.IsDetected) { 
            Write-GUI "  [!] Cleanup Recommended by OS." 
        } else { 
            Write-GUI "  [OK] CBS reports no mandatory cleanup, but ResetBase can still force payload amputation." 
        }
        Write-GUI "" 
        
        # Restore button state
        $this.Enabled = $true
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 80, 80, 80)
    }.GetNewClosure())

    $btnNetFix = New-Object System.Windows.Forms.Button
    $btnNetFix.Text = "Refresh Network (DNS/Winsock)"
    $btnNetFix.Location = New-Object System.Drawing.Point(15, 120) # Dostosuj współrzędną
    $btnNetFix.Size = New-Object System.Drawing.Size(370, 40)
    $btnNetFix.BackColor = [System.Drawing.Color]::FromArgb(255, 0, 100, 100)
    $btnNetFix.ForeColor = [System.Drawing.Color]::White
    $btnNetFix.FlatStyle = "Flat"
    $btnNetFix.Add_MouseEnter({ Show-Description "Network Fix: Flushes DNS cache and resets the Winsock catalog. Useful for fixing connection issues or 'No Internet' errors despite a working Wi-Fi/LAN." })
    $btnNetFix.Add_Click({ Clear-NetworkStack; Write-GUI "Completed."; Write-GUI "" })

    $btnFixPrinters = New-Object System.Windows.Forms.Button
    $btnFixPrinters.Text = "Reset Print Subsystem (Spooler)"
    $btnFixPrinters.Location = New-Object System.Drawing.Point(15, 170)
    $btnFixPrinters.Size = New-Object System.Drawing.Size(370, 40)
    $btnFixPrinters.BackColor = [System.Drawing.Color]::FromArgb(255, 120, 80, 40)
    $btnFixPrinters.ForeColor = [System.Drawing.Color]::White
    $btnFixPrinters.FlatStyle = "Flat"
    $btnFixPrinters.Add_MouseEnter({ Show-Description "Printer Fix: Kills deadlocked spoolsv.exe, purges stuck RAW/SHD files in System32, resets the Windows 11 PrintWorkflow service, and brings the spooler back online." })
    $btnFixPrinters.Add_Click({ Repair-PrintSubsystem; Write-GUI "Completed."; Write-GUI "" })

    $tabWinSXS.Controls.AddRange(@($btnCheckSystem, $btnResetBase, $btnAudWinSxS, $btnNetFix, $btnFixPrinters))
    
    $TabControl.Controls.Add($tabWinSXS)
}