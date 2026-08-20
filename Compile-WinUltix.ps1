Write-Host "Initializing compiler environment..." -ForegroundColor Cyan

Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module ps2exe -ErrorAction Stop

Write-Host "Building monolith via dynamic inline injection..." -ForegroundColor Cyan

$outDir = ".\build"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$outputFile = "$outDir\WinUltix_Monolith_EN.ps1"
$mainFile = ".\src\WinUltix_Pro.ps1"
$modulesDir = ".\src\Modules"

if (-not (Test-Path $mainFile)) {
    Write-Host "[!] ERROR: Entry point $mainFile not found." -ForegroundColor Red
    exit
}

$monolithContent = [System.Text.StringBuilder]::new()
$mainLines = Get-Content $mainFile -Encoding UTF8

foreach ($line in $mainLines) {
    # Inline modules while explicitly keeping the original dot-source reference as a comment
    if ($line -match '\.\s*\(Join-Path\s+\$ModulesDir\s+"([^"]+)"\)') {
        $moduleFile = $matches[1]
        $modulePath = Join-Path $modulesDir $moduleFile
        
        [void]$monolithContent.AppendLine("# $line")
        [void]$monolithContent.AppendLine("# >>> BEGIN INJECTED MODULE: $moduleFile <<<")
        
        if (Test-Path $modulePath) {
            $modContent = Get-Content $modulePath -Raw -Encoding UTF8
            [void]$monolithContent.AppendLine($modContent)
            [void]$monolithContent.AppendLine("# <<< END INJECTED MODULE: $moduleFile <<<`r`n")
        } else {
            Write-Host "[!] ERROR: Missing module file: $modulePath" -ForegroundColor Red
            exit
        }
    }
    # Comment out directory variable declarations to prevent execution in monolith
    elseif ($line -match '^\s*\$ScriptDir\s*=|^\s*\$ModulesDir\s*=') {
        [void]$monolithContent.AppendLine("# $line")
    }
    else {
        [void]$monolithContent.AppendLine($line)
    }
}

# Single I/O dump
Set-Content -Path $outputFile -Value $monolithContent.ToString() -Encoding UTF8

Write-Host "Monolith successfully linked. Executing PS2EXE..." -ForegroundColor Cyan

Invoke-ps2exe -InputFile $outputFile -OutputFile "$outDir\WinUltix_Pro.exe" -NoConsole -RequireAdmin -IconFile ".\assets\winultix.ico"

Write-Host "Deployment successful! WinUltix_Pro.exe is ready." -ForegroundColor Yellow
Read-Host "Press Enter to close."