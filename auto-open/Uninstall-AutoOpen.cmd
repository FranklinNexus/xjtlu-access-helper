@echo off
setlocal

set "XJTLU_UNINSTALL=%~dp0Uninstall-AutoOpen.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%XJTLU_UNINSTALL%"

if errorlevel 1 (
  echo.
  echo Auto-open removal failed. Review the message above.
  pause
)

endlocal
