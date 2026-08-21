@echo off
TITLE Uruchamianie System Optimizer Pro...

:: Wymuszenie uruchomienia skryptu GUI w nowym oknie jako Administrator z ukrytą konsolą
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%~dp0WinUltix_Pro.ps1""' -Verb RunAs"

:: Błyskawiczne zamknięcie czarnego okna
exit