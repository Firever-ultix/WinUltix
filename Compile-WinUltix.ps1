# ==========================================
# WINULTIX PRO - CLEAN PIPED CSC COMPILER
# Eradicates Dropper/MSIL Heuristics by avoiding %TEMP% file drops
# ==========================================

$rootDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $rootDir

$outDir      = Join-Path $rootDir "build"
$outputPs1   = Join-Path $outDir "WinUltix_Monolith_EN.ps1"
$exeFile     = Join-Path $outDir "WinUltix_Pro_EN.exe"
$mainFile    = Join-Path $rootDir "src\WinUltix_Pro.ps1"
$modulesDir  = Join-Path $rootDir "src\Modules"
$iconFile    = Join-Path $rootDir "assets\winultix.ico"
$cscPath     = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
if (-not (Test-Path $mainFile)) { Write-Error "[!] Entry point $mainFile not found."; exit 1 }

# 1. Assemble Monolith in memory (UTF-8 No-BOM)
Write-Host "Linking modular architecture..." -ForegroundColor Cyan
$sb = [System.Text.StringBuilder]::new()
$mainLines = Get-Content -Path $mainFile -Encoding UTF8

foreach ($line in $mainLines) {
    if ($line -match '^\s*\.\s*\(Join-Path\s+\$ModulesDir\s+"([^"]+)"\)') {
        $modFile = $matches[1]
        $modPath = Join-Path $modulesDir $modFile
        if (Test-Path $modPath) {
            [void]$sb.AppendLine("# >>> INJECTED: $modFile <<<")
            [void]$sb.AppendLine((Get-Content -Path $modPath -Raw -Encoding UTF8))
            [void]$sb.AppendLine("# <<< END INJECTED: $modFile <<<`r`n")
        } else {
            Write-Error "[!] Missing: $modPath"; exit 1
        }
    } elseif ($line -match '^\s*\$ScriptDir\s*=|^\s*\$ModulesDir\s*=') {
        [void]$sb.AppendLine("# $line")
    } else {
        [void]$sb.AppendLine($line)
    }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputPs1, $sb.ToString(), $utf8NoBom)
Write-Host "  [+] Clean UTF-8 No-BOM Monolith saved: $outputPs1" -ForegroundColor Green

# 2. Write raw script to a dedicated resource file (Embedded Resource instead of Base64 string)
$resFile = Join-Path $outDir "Monolith.payload"
[System.IO.File]::WriteAllText($resFile, $sb.ToString(), $utf8NoBom)

# 3. Create Clean In-Memory Piped C# Host
$csharpSource = @"
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Reflection;

[assembly: AssemblyTitle("WinUltix Pro")]
[assembly: AssemblyProduct("WinUltix Pro")]
[assembly: AssemblyCompany("Firever")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("2.7.0.0")]
[assembly: AssemblyFileVersion("2.7.0.0")]

namespace WinUltixLauncher {
    static class Program {
        [STAThread]
        static void Main() {
            string script = string.Empty;
            Assembly asm = Assembly.GetExecutingAssembly();
            
            using (Stream s = asm.GetManifestResourceStream("Monolith.payload"))
            using (StreamReader sr = new StreamReader(s, Encoding.UTF8)) {
                script = sr.ReadToEnd();
            }

            // Pipe script directly into PowerShell process memory without dropping files to disk
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command -";
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.RedirectStandardInput = true;

            using (Process proc = Process.Start(psi)) {
                using (StreamWriter sw = proc.StandardInput) {
                    sw.Write(script);
                    sw.Flush();
                }
                proc.WaitForExit();
            }
        }
    }
}
"@

$csFile = Join-Path $outDir "CleanHost.cs"
[System.IO.File]::WriteAllText($csFile, $csharpSource, $utf8NoBom)

# 4. Manifest requiring Administrator
$manifestSource = @"
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
"@
$manifestFile = Join-Path $outDir "app.manifest"
[System.IO.File]::WriteAllText($manifestFile, $manifestSource, $utf8NoBom)

# 5. Compile via native csc.exe embedding payload as resource
Write-Host "Compiling clean binary via csc.exe..." -ForegroundColor Cyan
$cscArgs = @(
    "/target:winexe",
    "/optimize+",
    "/platform:x64",
    "/win32manifest:`"$manifestFile`"",
    "/resource:`"$resFile`",Monolith.payload",
    "/out:`"$exeFile`""
)

if (Test-Path $iconFile) {
    $cscArgs += "/win32icon:`"$iconFile`""
}
$cscArgs += "`"$csFile`""

$process = Start-Process -FilePath $cscPath -ArgumentList $cscArgs -NoNewWindow -Wait -PassThru

# Cleanup compiler scratch files
Remove-Item -Path $csFile, $manifestFile, $resFile -Force -ErrorAction SilentlyContinue

if ($process.ExitCode -eq 0 -and (Test-Path $exeFile)) {
    $hash = (Get-FileHash -Path $exeFile -Algorithm SHA256).Hash
    Write-Host "[+] SUCCESS: Piped binary built at $exeFile" -ForegroundColor Yellow
    Write-Host "    SHA-256: $hash" -ForegroundColor Green
} else {
    Write-Error "[!] Compilation failed with code $($process.ExitCode)"
}
Read-Host "Press Enter to close."