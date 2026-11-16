# ==========================================
# WINULTIX - CLEAN IN-PROCESS RUNSPACE COMPILER (v3.14)
# Zero-P/Invoke Managed Host, Native In-Process Runspace & Crisp 256px Splash
# ==========================================

$rootDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if (-not (Test-Path (Join-Path $rootDir "src\WinUltix.ps1")) -and (Test-Path (Join-Path (Split-Path $rootDir -Parent) "src\WinUltix.ps1"))) {
    $rootDir = Split-Path $rootDir -Parent
}
Set-Location -Path $rootDir

$outDir      = Join-Path $rootDir "build"
$outputPs1   = Join-Path $outDir "WinUltix_Monolith.ps1"
$exeFile     = Join-Path $outDir "WinUltix.exe"
$mainFile    = Join-Path $rootDir "src\WinUltix.ps1"
$modulesDir  = Join-Path $rootDir "src\Modules"
$iconFile    = Join-Path $rootDir "assets\WinUltix.ico"
$cscPath     = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$smaDllPath  = [psobject].Assembly.Location

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
if (-not (Test-Path $mainFile)) { Write-Error "[!] Entry point $mainFile not found."; exit 1 }

function ConvertTo-AsciiSafePowerShell {
    param(
        [string]$Content,
        [switch]$Compact
    )
    # Replace UTF-8 punctuation/symbols whose trailing bytes (0x93/0x94) collide with smart quotes in CP1250 No-BOM mode
    $clean = $Content.Replace([string][char]0x2014, "--").Replace([string][char]0x2013, "-")
    $clean = $clean.Replace([string][char]0x2605, '$([char]0x2605)')
    $clean = $clean.Replace([string][char]0x2713, '$([char]0x2713)')
    $clean = $clean.Replace([string][char]0x00B5, '$([char]0x00B5)')

    if ($Compact) {
        $outLines       = [System.Collections.Generic.List[string]]::new()
        $hereCloseToken = ""
        $isCSharpBlock  = $false

        foreach ($rawLine in ($clean -split "\r?\n")) {
            if ($hereCloseToken -eq "") {
                $trimmed = $rawLine.Trim()
                if ($trimmed.Length -eq 0) { continue }
                if ($trimmed.StartsWith("#") -or $trimmed.StartsWith("//")) { continue }

                # Ensure a space precedes backtick line continuations so trimmed lines never merge tokens
                if ($trimmed.EndsWith('`') -and $trimmed -notmatch '\s`$') {
                    $trimmed = $trimmed.Substring(0, $trimmed.Length - 1) + ' `'
                }
                $outLines.Add($trimmed)

                if ($trimmed -match '@"$') {
                    $hereCloseToken = '"@'
                    $isCSharpBlock  = ($trimmed -match 'Add-Type')
                } elseif ($trimmed -match "@'$") {
                    $hereCloseToken = "'@"
                    $isCSharpBlock  = ($trimmed -match 'Add-Type')
                }
            } else {
                # Inside a here-string: only close when matching the exact closing delimiter at column 0
                if ($rawLine -match "^$([regex]::Escape($hereCloseToken))") {
                    $outLines.Add($rawLine.Trim())
                    $hereCloseToken = ""
                    $isCSharpBlock  = $false
                } elseif ($isCSharpBlock) {
                    $tCs = $rawLine.Trim()
                    if ($tCs.Length -gt 0 -and -not $tCs.StartsWith("//")) {
                        $outLines.Add($tCs)
                    }
                } else {
                    # Preserve nested PowerShell here-strings (e.g. New-PreFlightShortcut in Z7) verbatim
                    $outLines.Add($rawLine)
                }
            }
        }
        return ($outLines -join "`r`n")
    }

    return $clean
}

# 1. Assemble Compact Monolith in memory (100% 7-bit ASCII-safe UTF-8 No-BOM for 'irm | iex')
Write-Host "Linking & compacting modular architecture (v3.14)..." -ForegroundColor Cyan
$sbPs1 = [System.Text.StringBuilder]::new()
[void]$sbPs1.AppendLine("# WINULTIX v3.14 - ZERO-WMI MONOLITH (https://github.com/Firever-ultix/WinUltix)")
$mainLines = Get-Content -Path $mainFile -Encoding UTF8

foreach ($line in $mainLines) {
    if ($line -match '^\s*\.\s*\(Join-Path\s+\$ModulesDir\s+"([^"]+)"\)') {
        $modFile = $matches[1]
        $modPath = Join-Path $modulesDir $modFile
        if (Test-Path $modPath) {
            $rawMod  = Get-Content -Path $modPath -Raw -Encoding UTF8
            $safeMod = ConvertTo-AsciiSafePowerShell -Content $rawMod -Compact
            [void]$sbPs1.AppendLine($safeMod)
        } else {
            Write-Error "[!] Missing: $modPath"; exit 1
        }
    } elseif ($line -match '^\s*\$ScriptDir\s*=') {
        $scriptDirLine = '$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($script:MyInvocation.MyCommand.Path) { Split-Path $script:MyInvocation.MyCommand.Path } else { [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd("\") }'
        [void]$sbPs1.AppendLine($scriptDirLine)
    } elseif ($line -match '^\s*\$ModulesDir\s*=') {
        continue
    } else {
        $safeLine = ConvertTo-AsciiSafePowerShell -Content $line -Compact
        if ($safeLine.Length -gt 0) {
            [void]$sbPs1.AppendLine($safeLine)
        }
    }
}

$utf8NoBom   = [System.Text.UTF8Encoding]::new($false)
$monolithStr = $sbPs1.ToString()
$nonAscii    = [regex]::Matches($monolithStr, '[^\x00-\x7F]')
if ($nonAscii.Count -gt 0) {
    $sampleChars = @($nonAscii | ForEach-Object { $_.Value } | Select-Object -Unique) -join ", "
    Write-Warning "[!] Non-ASCII characters detected in Monolith ($($nonAscii.Count) occurrences: $sampleChars). Check ConvertTo-AsciiSafePowerShell!"
} else {
    Write-Host "  [+] Verified 100% 7-bit ASCII purity for 'irm | iex' streaming." -ForegroundColor Cyan
}
[System.IO.File]::WriteAllText($outputPs1, $monolithStr, $utf8NoBom)
$ps1KB = [math]::Round((Get-Item $outputPs1).Length / 1KB, 2)
Write-Host "  [+] Clean UTF-8 No-BOM Monolith saved: $outputPs1 ($ps1KB KB)" -ForegroundColor Green

# 2. Write script resource for in-process Runspace execution
$resFile = Join-Path $outDir "WinUltix.UiModule.res"
[System.IO.File]::WriteAllText($resFile, $monolithStr, $utf8NoBom)

# 3. Create 100% Pure Managed C# Host (Zero DllImport P/Invokes, Zero Child Process Spawning)
$csharpSource = @'
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Threading;
using System.Reflection;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("WinUltix System & Hardware Toolkit")]
[assembly: AssemblyDescription("Portable Windows 11 & 10 Hardware Diagnostic, Latency Profiler & Maintenance Utility")]
[assembly: AssemblyProduct("WinUltix")]
[assembly: AssemblyCompany("Firever")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Firever - MIT License")]
[assembly: AssemblyVersion("3.14.0.0")]
[assembly: AssemblyFileVersion("3.14.0.0")]

namespace WinUltixLauncher {
    internal sealed class DarkSplashForm : Form {
        private readonly string _exePath;
        private Bitmap _logoBmp;

        public DarkSplashForm(string exePath) {
            _exePath = exePath;
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(420, 125);
            this.BackColor = Color.FromArgb(24, 24, 26);
            this.ForeColor = Color.White;
            this.TopMost = true;
            this.ShowInTaskbar = false;
            this.DoubleBuffered = true;

            try {
                _logoBmp = ExtractBestPngFromPe(_exePath);
            } catch { }
        }

        private static Bitmap ExtractBestPngFromPe(string exePath) {
            if (string.IsNullOrEmpty(exePath) || !File.Exists(exePath)) return null;
            byte[] bytes = File.ReadAllBytes(exePath);
            int bestStart = -1, bestLen = 0, bestDim = -1;

            for (int i = 0; i <= bytes.Length - 33; i++) {
                // Match PNG 8-byte magic (89 50 4E 47 0D 0A 1A 0A) + IHDR chunk header (49 48 44 52)
                if (bytes[i] == 0x89 && bytes[i + 1] == 0x50 && bytes[i + 2] == 0x4E && bytes[i + 3] == 0x47 &&
                    bytes[i + 4] == 0x0D && bytes[i + 5] == 0x0A && bytes[i + 6] == 0x1A && bytes[i + 7] == 0x0A &&
                    bytes[i + 12] == 0x49 && bytes[i + 13] == 0x48 && bytes[i + 14] == 0x44 && bytes[i + 15] == 0x52) {

                    int w = (bytes[i + 16] << 24) | (bytes[i + 17] << 16) | (bytes[i + 18] << 8) | bytes[i + 19];
                    int pos = i + 8;
                    int endPos = -1;

                    while (pos + 12 <= bytes.Length) {
                        int cLen = (bytes[pos] << 24) | (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
                        if (cLen < 0 || cLen > 524288 || (pos + 12 + cLen) > bytes.Length) break;
                        bool isIend = (bytes[pos + 4] == 0x49 && bytes[pos + 5] == 0x45 && bytes[pos + 6] == 0x4E && bytes[pos + 7] == 0x44);
                        pos += 12 + cLen;
                        if (isIend) {
                            endPos = pos;
                            break;
                        }
                    }

                    if (endPos > i && w >= bestDim) {
                        bestDim   = w;
                        bestStart = i;
                        bestLen   = endPos - i;
                        i = endPos - 1;
                    }
                }
            }

            if (bestStart >= 0 && bestLen > 32) {
                using (MemoryStream msPng = new MemoryStream(bytes, bestStart, bestLen))
                using (Image img = Image.FromStream(msPng)) {
                    return new Bitmap(img);
                }
            }
            return null;
        }

        protected override void Dispose(bool disposing) {
            if (disposing && _logoBmp != null) {
                _logoBmp.Dispose();
                _logoBmp = null;
            }
            base.Dispose(disposing);
        }

        protected override void OnPaint(PaintEventArgs e) {
            Graphics g = e.Graphics;
            g.Clear(Color.FromArgb(24, 24, 26));

            using (SolidBrush topBar = new SolidBrush(Color.FromArgb(80, 180, 255))) {
                g.FillRectangle(topBar, 0, 0, this.Width, 3);
            }
            using (Pen borderPen = new Pen(Color.FromArgb(65, 65, 68), 1)) {
                g.DrawRectangle(borderPen, 0, 0, this.Width - 1, this.Height - 1);
            }

            if (_logoBmp != null) {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode     = SmoothingMode.HighQuality;
                g.PixelOffsetMode   = PixelOffsetMode.HighQuality;
                g.DrawImage(_logoBmp, new Rectangle(20, 28, 52, 52));
            } else {
                try {
                    using (Icon ico = Icon.ExtractAssociatedIcon(_exePath)) {
                        if (ico != null) g.DrawIcon(ico, new Rectangle(20, 28, 52, 52));
                    }
                } catch { }
            }

            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            using (Font fTitle = new Font("Segoe UI", 14.0f, FontStyle.Bold))
            using (Font fSub = new Font("Consolas", 9.0f, FontStyle.Regular))
            using (SolidBrush bCyan = new SolidBrush(Color.Cyan))
            using (SolidBrush bGray = new SolidBrush(Color.FromArgb(175, 185, 195))) {
                g.DrawString("WINULTIX v3.14", fTitle, bCyan, 86, 26);
                g.DrawString("Initializing Kernel & Hardware Runtime...", fSub, bGray, 88, 58);
                g.DrawString("Zero-WMI Native Engine | Firever", fSub, Brushes.DimGray, 88, 78);
            }
        }
    }

    static class Program {
        [STAThread]
        static void Main() {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string script = string.Empty;
            Assembly asm = Assembly.GetExecutingAssembly();

            using (Stream s = asm.GetManifestResourceStream("WinUltix.UiModule.res")) {
                if (s == null) return;
                using (StreamReader sr = new StreamReader(s, Encoding.UTF8)) {
                    script = sr.ReadToEnd();
                }
            }

            Environment.SetEnvironmentVariable("WINULTIX_HOST_EXE", asm.Location);

            bool createdNew;
            using (EventWaitHandle splashReadyEvent = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\WinUltix_Splash_Close", out createdNew)) {
                Thread splashThread = new Thread(delegate() {
                    try {
                        using (DarkSplashForm splash = new DarkSplashForm(asm.Location)) {
                            splash.Show();
                            splash.Refresh();
                            while (!splashReadyEvent.WaitOne(35)) {
                                Application.DoEvents();
                            }
                            splash.Close();
                        }
                    } catch { }
                });
                splashThread.SetApartmentState(ApartmentState.STA);
                splashThread.IsBackground = true;
                splashThread.Start();

                try {
                    InitialSessionState iss = InitialSessionState.CreateDefault();
                    iss.ApartmentState = ApartmentState.STA;
                    iss.ThreadOptions  = PSThreadOptions.UseCurrentThread;

                    using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                        rs.Open();
                        Runspace.DefaultRunspace = rs;

                        using (PowerShell ps = PowerShell.Create()) {
                            ps.Runspace = rs;
                            ps.AddScript(script);
                            ps.Invoke();

                            if (ps.HadErrors && ps.Streams.Error.Count > 0) {
                                splashReadyEvent.Set();
                                ErrorRecord err = ps.Streams.Error[0];
                                string errText = err.Exception.ToString() + Environment.NewLine + Environment.NewLine + err.InvocationInfo.PositionMessage;
                                MessageBox.Show(errText, "WinUltix - Startup Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            }
                        }
                    }
                } catch (Exception ex) {
                    splashReadyEvent.Set();
                    MessageBox.Show(ex.ToString(), "WinUltix - Fatal Host Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
                } finally {
                    splashReadyEvent.Set();
                }
            }
        }
    }
}
'@

$csHostFile = Join-Path $outDir "CleanHost.cs"
[System.IO.File]::WriteAllText($csHostFile, $csharpSource, $utf8NoBom)

# 4. Manifest requiring Administrator + Native PerMonitorV2 / GdiScaling DPI Awareness
$manifestSource = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0" xmlns:asmv3="urn:schemas-microsoft-com:asm.v3">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <asmv3:application>
    <asmv3:windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2, PerMonitor</dpiAwareness>
      <gdiScaling xmlns="http://schemas.microsoft.com/SMI/2017/WindowsSettings">true</gdiScaling>
    </asmv3:windowsSettings>
  </asmv3:application>
</assembly>
'@
$manifestFile = Join-Path $outDir "app.manifest"
[System.IO.File]::WriteAllText($manifestFile, $manifestSource, $utf8NoBom)

# 5. Compile pure managed binary via csc.exe (Zero unmanaged DllImport in PE header)
Write-Host "Compiling pure managed In-Process Runspace binary via csc.exe..." -ForegroundColor Cyan
if (Test-Path $exeFile) { Remove-Item -Path $exeFile -Force -ErrorAction SilentlyContinue }

$cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/platform:x64",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
    "/reference:$smaDllPath",
    "/win32manifest:$manifestFile",
    "/resource:$resFile,WinUltix.UiModule.res",
    "/out:$exeFile"
)

if (Test-Path -LiteralPath $iconFile) {
    $resolvedIcon = (Resolve-Path -LiteralPath $iconFile).Path
    $cscArgs += "/win32icon:$resolvedIcon"
    Write-Host "  [+] Embedding Win32 PE Icon (Single-Copy PE .rsrc): $resolvedIcon" -ForegroundColor Cyan
} else {
    Write-Warning "[!] Icon file not found at $iconFile! Building without custom icon."
}

$cscArgs += $csHostFile

& $cscPath @cscArgs
$exitCode = $LASTEXITCODE

# Cleanup compiler scratch files
Remove-Item -Path $csHostFile, $manifestFile, $resFile -Force -ErrorAction SilentlyContinue

if ($exitCode -eq 0 -and (Test-Path $exeFile)) {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'WinUltixBuild.ShellNotify').Type) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace WinUltixBuild { public static class ShellNotify { [DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2); } }' -ErrorAction SilentlyContinue
        }
        [WinUltixBuild.ShellNotify]::SHChangeNotify(0x08000000, 0x2000, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch { }

    $hash = (Get-FileHash -Path $exeFile -Algorithm SHA256).Hash
    $exeKB = [math]::Round((Get-Item $exeFile).Length / 1KB, 2)
    Write-Host "[+] SUCCESS: Pure Managed In-Process binary built at $exeFile ($exeKB KB)" -ForegroundColor Yellow
    Write-Host "    SHA-256: $hash" -ForegroundColor Green

    # Run immediate local Microsoft Defender CLI verification scan if MpCmdRun.exe is present
    $mpCmd = "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
    if (Test-Path -LiteralPath $mpCmd) {
        Write-Host "  [*] Running Microsoft Defender verification scan on $exeFile..." -ForegroundColor Cyan
        $scanOut = (& $mpCmd -Scan -ScanType 3 -File "$exeFile" 2>&1) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [+] DEFENDER SCAN PASSED: Zero threats detected!" -ForegroundColor Green
        } else {
            Write-Warning "  [!] Defender CLI output:`n$scanOut"
        }
    }
} else {
    Write-Error "[!] Compilation failed with exit code $exitCode"
}
Read-Host "Press Enter to close."