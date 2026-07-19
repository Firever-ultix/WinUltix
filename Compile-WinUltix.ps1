Write-Host "Initializing environment..." -ForegroundColor Cyan

# Temporarily bypass execution policy for this specific process
Set-ExecutionPolicy Bypass -Scope Process -Force
Import-Module ps2exe -ErrorAction Stop

Write-Host "Merging files into WinUltix Pro monolith..." -ForegroundColor Cyan

# Define output directory and ensure it exists
$outDir = ".\build"
if (-not (Test-Path $outDir)) { 
    New-Item -ItemType Directory -Path $outDir | Out-Null 
}

# 1. Define merge order (main WinUltix file always at the end!)
# Adding 'src' folder path to source files
$sourceFiles = @(
    ".\src\Optimizer_Core_EN.ps1", 
    ".\src\Optimizer_Audit_EN.ps1", 
    ".\src\Optimizer_Restore_EN.ps1", 
    ".\src\WinUltix_EN.ps1"
)
$outputFile = "$outDir\WinUltix_Monolith_EN.ps1"

# Clear old output file (if it exists)
if (Test-Path $outputFile) { Remove-Item $outputFile -Force }

# 2. Merge content, forcing UTF8 encoding
foreach ($file in $sourceFiles) {
    if (Test-Path $file) {
        # Read as UTF8
        $content = Get-Content $file -Raw -Encoding UTF8
        $cleanContent = $content -replace '(?m)^\.\s*"\$PSScriptRoot\\.*', ''
        
        # Write as UTF8
        Add-Content $outputFile $cleanContent -Encoding UTF8
        Add-Content $outputFile "`r`n" -Encoding UTF8
    } else {
        Write-Host "[!] ERROR: File $file not found!" -ForegroundColor Red
        exit
    }
}

Write-Host "Base file generated successfully!" -ForegroundColor Green
Write-Host "Starting compilation to .exe file..." -ForegroundColor Cyan

# 3. Run ps2exe on the merged file
# Fetching the input file from build directory and icon from assets directory
Invoke-ps2exe -InputFile $outputFile -OutputFile "$outDir\WinUltix_Pro.exe" -NoConsole -RequireAdmin -IconFile ".\assets\winultix.ico"

Write-Host "Compilation finished! WinUltix_Pro.exe is ready to run." -ForegroundColor Yellow

Read-Host "Press Enter to close the window..."