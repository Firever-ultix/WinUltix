# ==========================================
# WINULTIX - CLEAN PIPED CSC COMPILER (v3.14)
# Pre-Compiles WinUltix.* C# Runtime, Instant Dark Splash & Compact Monolith
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

# 1. Extract C# Runtime from Core_Helpers.ps1 for Native Pre-Compilation into WinUltix.exe
$coreHelpersPath = Join-Path $modulesDir "Core_Helpers.ps1"
$coreRaw = Get-Content -Path $coreHelpersPath -Raw -Encoding UTF8
$extractedCSharp = ""
$csPattern = '(?s)Add-Type\s+-ReferencedAssemblies\s+@\("System\.Windows\.Forms",\s*"System\.Drawing"\)\s+-TypeDefinition\s+@"(.+?)"@\s+-ErrorAction\s+SilentlyContinue'
if ($coreRaw -match $csPattern) {
    $extractedCSharp = $matches[1]
}

# 2. Assemble Compact Monolith in memory (100% 7-bit ASCII-safe UTF-8 No-BOM for 'irm | iex')
Write-Host "Linking & compacting modular architecture (v3.14)..." -ForegroundColor Cyan
$sbPs1 = [System.Text.StringBuilder]::new()
$sbExe = [System.Text.StringBuilder]::new()
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

            # For WinUltix.exe embedded payload, strip the duplicate C# Add-Type text (already compiled into WinUltix.exe MSIL)
            if ($modFile -eq "Core_Helpers.ps1" -and -not [string]::IsNullOrWhiteSpace($extractedCSharp)) {
                $exeModRaw = [regex]::Replace($rawMod, $csPattern, '# [WinUltix.* C# Runtime Pre-Compiled in Host PE]')
                [void]$sbExe.AppendLine((ConvertTo-AsciiSafePowerShell -Content $exeModRaw -Compact))
            } else {
                [void]$sbExe.AppendLine($safeMod)
            }
        } else {
            Write-Error "[!] Missing: $modPath"; exit 1
        }
    } elseif ($line -match '^\s*\$ScriptDir\s*=') {
        $scriptDirLine = '$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($script:MyInvocation.MyCommand.Path) { Split-Path $script:MyInvocation.MyCommand.Path } else { "" }'
        [void]$sbPs1.AppendLine($scriptDirLine)
        [void]$sbExe.AppendLine($scriptDirLine)
    } elseif ($line -match '^\s*\$ModulesDir\s*=') {
        continue
    } else {
        $safeLine = ConvertTo-AsciiSafePowerShell -Content $line -Compact
        if ($safeLine.Length -gt 0) {
            [void]$sbPs1.AppendLine($safeLine)
            [void]$sbExe.AppendLine($safeLine)
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

# 3. Write stripped EXE script payload to resource file (Embedded Resource)
$resFile = Join-Path $outDir "Monolith.payload"
[System.IO.File]::WriteAllText($resFile, $sbExe.ToString(), $utf8NoBom)

# 4. Create C# Host with Instant Dark Splash Screen (<20ms) & Pre-Compiled WinUltix.* Runtime
$csharpSource = @'
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Threading;
using System.Diagnostics;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("WinUltix")]
[assembly: AssemblyProduct("WinUltix")]
[assembly: AssemblyCompany("Firever")]
[assembly: AssemblyCopyright("MIT License")]
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
                _logoBmp = WinUltix.NativeMethods.ExtractHighResExeIcon(_exePath, 256);
                if (_logoBmp == null) {
                    _logoBmp = WinUltix.NativeMethods.ExtractHighResExeIcon(_exePath, 64);
                }
            } catch { }
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
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.SmoothingMode     = System.Drawing.Drawing2D.SmoothingMode.HighQuality;
                g.PixelOffsetMode   = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.DrawImage(_logoBmp, new Rectangle(20, 28, 52, 52));
            } else {
                try {
                    using (Icon ico = Icon.ExtractAssociatedIcon(_exePath)) {
                        if (ico != null) g.DrawIcon(ico, new Rectangle(20, 28, 52, 52));
                    }
                } catch { }
            }

            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
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
            string script = string.Empty;
            Assembly asm = Assembly.GetExecutingAssembly();

            using (Stream s = asm.GetManifestResourceStream("Monolith.payload")) {
                if (s == null) return;
                using (StreamReader sr = new StreamReader(s, Encoding.UTF8)) {
                    script = sr.ReadToEnd();
                }
            }

            bool createdNew;
            using (EventWaitHandle splashReadyEvent = new EventWaitHandle(false, EventResetMode.ManualReset, @"Local\WinUltix_Splash_Close", out createdNew)) {
                DarkSplashForm splash = null;
                Thread splashThread = new Thread(delegate() {
                    try {
                        WinUltix.NativeMethods.EnableGdiDpiScaling();
                        splash = new DarkSplashForm(asm.Location);
                        splash.Show();
                        splash.Refresh();
                        while (!splashReadyEvent.WaitOne(35)) {
                            Application.DoEvents();
                        }
                        splash.Close();
                        splash.Dispose();
                    } catch { }
                });
                splashThread.SetApartmentState(ApartmentState.STA);
                splashThread.IsBackground = true;
                splashThread.Start();

                string bootstrapCmd =
                    "[Console]::InputEncoding = [System.Text.Encoding]::UTF8; " +
                    "$raw = [Console]::In.ReadToEnd(); " +
                    "try { . ([scriptblock]::Create($raw)) } catch { " +
                    "try { $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\\WinUltix_Splash_Close'); [void]$ev.Set() } catch {} " +
                    "Add-Type -AssemblyName System.Windows.Forms; " +
                    "$errText = $_.Exception.ToString() + [Environment]::NewLine + [Environment]::NewLine + $_.InvocationInfo.PositionMessage; " +
                    "[System.Windows.Forms.MessageBox]::Show($errText, 'WinUltix - Startup Error', 'OK', 'Error') | Out-Null }";

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -Command \"" + bootstrapCmd + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardInput = true;
                psi.EnvironmentVariables["WINULTIX_HOST_EXE"] = asm.Location;

                using (Process proc = Process.Start(psi)) {
                    using (StreamWriter sw = new StreamWriter(proc.StandardInput.BaseStream, new UTF8Encoding(false))) {
                        sw.Write(script);
                        sw.Flush();
                    }
                    proc.WaitForExit();
                    splashReadyEvent.Set();
                }
            }
        }
    }
}
'@

$csHostFile    = Join-Path $outDir "CleanHost.cs"
$csRuntimeFile = Join-Path $outDir "UltixRuntime.cs"
[System.IO.File]::WriteAllText($csHostFile, $csharpSource, $utf8NoBom)
[System.IO.File]::WriteAllText($csRuntimeFile, $extractedCSharp, $utf8NoBom)

# 5. Manifest requiring Administrator
$manifestSource = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
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
</assembly>
'@
$manifestFile = Join-Path $outDir "app.manifest"
[System.IO.File]::WriteAllText($manifestFile, $manifestSource, $utf8NoBom)

# 6. Compile via native csc.exe embedding payload, pre-compiled WinUltix.* runtime & Win32 icon
Write-Host "Compiling binary + WinUltix.* native C# runtime via csc.exe..." -ForegroundColor Cyan
if (Test-Path $exeFile) { Remove-Item -Path $exeFile -Force -ErrorAction SilentlyContinue }

$cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/platform:x64",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
    "/win32manifest:$manifestFile",
    "/resource:$resFile,Monolith.payload",
    "/out:$exeFile"
)

if (Test-Path -LiteralPath $iconFile) {
    $resolvedIcon = (Resolve-Path -LiteralPath $iconFile).Path
    $cscArgs += "/win32icon:$resolvedIcon"
    Write-Host "  [+] Embedding Win32 PE Icon: $resolvedIcon" -ForegroundColor Cyan
} else {
    Write-Warning "[!] Icon file not found at $iconFile! Building without custom icon."
}

$cscArgs += $csHostFile
if (-not [string]::IsNullOrWhiteSpace($extractedCSharp)) {
    $cscArgs += $csRuntimeFile
}

& $cscPath @cscArgs
$exitCode = $LASTEXITCODE

# Cleanup compiler scratch files
Remove-Item -Path $csHostFile, $csRuntimeFile, $manifestFile, $resFile -Force -ErrorAction SilentlyContinue

if ($exitCode -eq 0 -and (Test-Path $exeFile)) {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'WinUltixBuild.ShellNotify').Type) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace WinUltixBuild { public static class ShellNotify { [DllImport("shell32.dll")] public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2); } }' -ErrorAction SilentlyContinue
        }
        [WinUltixBuild.ShellNotify]::SHChangeNotify(0x08000000, 0x2000, [IntPtr]::Zero, [IntPtr]::Zero)
    } catch { }

    $hash = (Get-FileHash -Path $exeFile -Algorithm SHA256).Hash
    $exeKB = [math]::Round((Get-Item $exeFile).Length / 1KB, 2)
    Write-Host "[+] SUCCESS: Piped binary built at $exeFile ($exeKB KB)" -ForegroundColor Yellow
    Write-Host "    SHA-256: $hash" -ForegroundColor Green
} else {
    Write-Error "[!] Compilation failed with exit code $exitCode"
}
Read-Host "Press Enter to close."