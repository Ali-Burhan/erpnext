@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows-ai.ps1"
if errorlevel 1 (
  echo.
  echo Setup did not finish. Read the error above, then double-click this file to retry.
)
pause
