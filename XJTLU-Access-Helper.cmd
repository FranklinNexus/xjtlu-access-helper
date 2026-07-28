@echo off
setlocal

set "XJTLU_SCRIPT=%~dp0XJTLU-Access-Helper.ps1"

if not exist "%XJTLU_SCRIPT%" (
  echo XJTLU-Access-Helper.ps1 was not found next to this launcher.
  pause
  exit /b 1
)

rem ExecutionPolicy applies only to this process and does not change Windows settings.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%XJTLU_SCRIPT%" %*

if errorlevel 1 (
  echo.
  echo The helper stopped with an error. Review the message above.
  pause
)

endlocal
