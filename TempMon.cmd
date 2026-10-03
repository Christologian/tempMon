@echo off
REM TempMon launcher - starts the temperature widget and returns immediately.
REM Uses Windows PowerShell (STA) for WinForms; -WindowStyle Hidden keeps the console out of the way.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0TempMon.ps1"
