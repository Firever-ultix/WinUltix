Write-Host "Initializing compiler environment..." -ForegroundColor Cyan

Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module ps2exe -ErrorAction Stop

# Anchor working directory to script location
$rootDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location -Path $rootDir

Write-Host "Building monolith via dynamic inline injection..." -ForegroundColor Cyan

$outDir     = Join-Path $rootDir "build"
$outputFile = Join-Path $outDir "WinUltix_Monolith_EN.ps1"
$exeFile    = Join-Path $outDir "WinUltix_Pro_EN.exe"
$mainFile   = Join-Path $rootDir "src\WinUltix_Pro.ps1"
$modulesDir = Join-Path $rootDir "src\Modules"
$iconFile   = Join-Path $rootDir "assets\winultix.ico"

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

if (-not (Test-Path $mainFile)) {
    Write-Host "[!] ERROR: Entry point $mainFile not found." -ForegroundColor Red
    exit 1
}

$monolithContent = [System.Text.StringBuilder]::new()
$mainLines       = Get-Content -Path $mainFile -Encoding UTF8
$detectedVersion = "2.7.0.0"

foreach ($line in $mainLines) {
    # Extract version dynamically from $Global:AppVersion = "vX.Y.Z"
    if ($line -match '^\s*\$Global:AppVersion\s*=\s*"v?(\d+\.\d+\.\d+)"') {
        $detectedVersion = "$($matches[1]).0"
    }

    # 1. Inline active module loads while keeping the original dot-source line as a comment
    if ($line -match '^\s*\.\s*\(Join-Path\s+\$ModulesDir\s+"([^"]+)"\)') {
        $moduleFile = $matches[1]
        $modulePath = Join-Path $modulesDir $moduleFile
        
        [void]$monolithContent.AppendLine("# $line")
        [void]$monolithContent.AppendLine("# >>> BEGIN INJECTED MODULE: $moduleFile <<<")
        
        if (Test-Path $modulePath) {
            $modContent = Get-Content -Path $modulePath -Raw -Encoding UTF8
            [void]$monolithContent.AppendLine($modContent)
            [void]$monolithContent.AppendLine("# <<< END INJECTED MODULE: $moduleFile <<<`r`n")
            Write-Host "  [+] Injected module: $moduleFile" -ForegroundColor Green
        } else {
            Write-Host "[!] ERROR: Missing module file: $modulePath" -ForegroundColor Red
            exit 1
        }
    }
    # 2. Comment out environment directory variables so they remain visible but inactive in monolith
    elseif ($line -match '^\s*\$ScriptDir\s*=|^\s*\$ModulesDir\s*=') {
        [void]$monolithContent.AppendLine("# $line")
    }
    # 3. Preserve all other lines untouched
    else {
        [void]$monolithContent.AppendLine($line)
    }
}

# Single I/O dump (Strict UTF-8 No-BOM to prevent \uFEFF parser error in Invoke-Expression)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputFile, $monolithContent.ToString(), $utf8NoBom)

Write-Host "Monolith successfully linked ($outputFile). Executing PS2EXE (v$detectedVersion)..." -ForegroundColor Cyan

$ps2exeParams = @{
    InputFile    = $outputFile
    OutputFile   = $exeFile
    NoConsole    = $true
    NoOutput     = $true
    RequireAdmin = $true
    STA          = $true
    Title        = "WinUltix Pro"
    Description  = "WinUltix Pro - Ultimate Windows 11 Optimizer & Hardware Tuning Toolkit"
    Company      = "Firever (Ultix Ecosystem)"
    Product      = "WinUltix Pro"
    Copyright    = "MIT License - https://github.com/Firever-ultix/WinUltix"
    Version      = $detectedVersion
}

if (Test-Path $iconFile) {
    $ps2exeParams.IconFile = $iconFile
} else {
    Write-Host "  [!] Warning: Icon file not found at $iconFile. Compiling with default icon." -ForegroundColor DarkYellow
}

Invoke-ps2exe @ps2exeParams

Write-Host "Deployment successful! $exeFile is ready." -ForegroundColor Yellow
Read-Host "Press Enter to close."