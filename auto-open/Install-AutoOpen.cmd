@echo off
setlocal

set "XJTLU_INSTALL=%~dp0Install-AutoOpen.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%XJTLU_INSTALL%"

if errorlevel 1 (
  echo.
  echo Auto-open setup failed. Review the message above.
  pause
)

endlocal
