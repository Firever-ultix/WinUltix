# ==========================================
# WINULTIX - CLEAN PIPED CSC COMPILER (v3.1.0)
# Eradicates Dropper/MSIL Heuristics by avoiding %TEMP% file drops
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
    param([string]$Content)
    # Replace UTF-8 punctuation/symbols whose trailing bytes (0x93/0x94) collide with smart quotes in CP1250 No-BOM mode
    $clean = $Content.Replace([string][char]0x2014, "--").Replace([string][char]0x2013, "-")
    $clean = $clean.Replace([string][char]0x2605, '$([char]0x2605)')
    $clean = $clean.Replace([string][char]0x2713, '$([char]0x2713)')
    $clean = $clean -replace 'nie mo.na odnale..', 'nie mo.na odnale..'
    $clean = $clean -replace 'Urz.dzenie kompozytowe', 'Urz.dzenie kompozytowe'
    $clean = $clean -replace 'Urz.dzenie wej.ciowe', 'Urz.dzenie wej.ciowe'
    $clean = $clean -replace 'Urz.dzenie klawiatury HID', 'Urz.dzenie klawiatury HID'
    $clean = $clean.Replace("S[i" + [char]0x00ED + "]", "S[i\u00ED]")
    return $clean
}

# 1. Assemble Monolith in memory (100% 7-bit ASCII-safe UTF-8 No-BOM for both local PS 5.1 & 'irm | iex')
Write-Host "Linking modular architecture (v3.1.0)..." -ForegroundColor Cyan
$sb = [System.Text.StringBuilder]::new()
$mainLines = Get-Content -Path $mainFile -Encoding UTF8

foreach ($line in $mainLines) {
    if ($line -match '^\s*\.\s*\(Join-Path\s+\$ModulesDir\s+"([^"]+)"\)') {
        $modFile = $matches[1]
        $modPath = Join-Path $modulesDir $modFile
        if (Test-Path $modPath) {
            $rawMod = Get-Content -Path $modPath -Raw -Encoding UTF8
            $safeMod = ConvertTo-AsciiSafePowerShell -Content $rawMod
            [void]$sb.AppendLine("# >>> INJECTED: $modFile <<<")
            [void]$sb.AppendLine($safeMod)
            [void]$sb.AppendLine("# <<< END INJECTED: $modFile <<<`r`n")
        } else {
            Write-Error "[!] Missing: $modPath"; exit 1
        }
    } elseif ($line -match '^\s*\$ScriptDir\s*=') {
        [void]$sb.AppendLine('$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($script:MyInvocation.MyCommand.Path) { Split-Path $script:MyInvocation.MyCommand.Path } else { "" }')
    } elseif ($line -match '^\s*\$ModulesDir\s*=') {
        [void]$sb.AppendLine("# $line")
    } else {
        [void]$sb.AppendLine((ConvertTo-AsciiSafePowerShell -Content $line))
    }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPs1, $sb.ToString(), $utf8NoBom)
Write-Host "  [+] Clean UTF-8 No-BOM Monolith saved: $outputPs1" -ForegroundColor Green

# 2. Write raw script to a dedicated resource file (Embedded Resource)
$resFile = Join-Path $outDir "Monolith.payload"
[System.IO.File]::WriteAllText($resFile, $sb.ToString(), $utf8NoBom)

# 3. Create Clean In-Memory Piped C# Host (Passes WINULTIX_HOST_EXE for native PE icon extraction)
$csharpSource = @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Reflection;

[assembly: AssemblyTitle("WinUltix Pro")]
[assembly: AssemblyProduct("WinUltix Pro")]
[assembly: AssemblyCompany("Firever")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("3.1.0.0")]
[assembly: AssemblyFileVersion("3.1.0.0")]

namespace WinUltixLauncher {
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

            string bootstrapCmd =
                "[Console]::InputEncoding = [System.Text.Encoding]::UTF8; " +
                "$raw = [Console]::In.ReadToEnd(); " +
                "try { . ([scriptblock]::Create($raw)) } catch { " +
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
            }
        }
    }
}
'@

$csFile = Join-Path $outDir "CleanHost.cs"
[System.IO.File]::WriteAllText($csFile, $csharpSource, $utf8NoBom)

# 4. Manifest requiring Administrator
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

# 5. Compile via native csc.exe embedding payload & Win32 icon resource
Write-Host "Compiling clean binary via csc.exe..." -ForegroundColor Cyan
if (Test-Path $exeFile) { Remove-Item -Path $exeFile -Force -ErrorAction SilentlyContinue }

$cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/platform:x64",
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
$cscArgs += $csFile

& $cscPath @cscArgs
$exitCode = $LASTEXITCODE

# Cleanup compiler scratch files
Remove-Item -Path $csFile, $manifestFile, $resFile -Force -ErrorAction SilentlyContinue

if ($exitCode -eq 0 -and (Test-Path $exeFile)) {
    # Flush Windows Explorer shell icon cache so updated .exe icon is immediately visible
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