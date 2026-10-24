@echo off
setlocal DisableDelayedExpansion
call "%~dp0Portable-Env.cmd"
if errorlevel 1 exit /b 1
set "browser=%WORKSTATION_ROOT%\Apps\Browser\chrome-win64\chrome.exe"
if not exist "%browser%" (
  echo SSD Chrome is missing: Apps\Browser\chrome-win64\chrome.exe
  exit /b 1
)
if not exist "%WORKSTATION_ROOT%\Data\Browser" mkdir "%WORKSTATION_ROOT%\Data\Browser"
if not exist "%WORKSTATION_ROOT%\Data\Browser" exit /b 1
if not exist "%WORKSTATION_ROOT%\Data\Cache\Browser" mkdir "%WORKSTATION_ROOT%\Data\Cache\Browser"
if not exist "%WORKSTATION_ROOT%\Data\Cache\Browser" exit /b 1
start "" /D "%WORKSTATION_ROOT%\Data\Browser" "%browser%" --user-data-dir="%WORKSTATION_ROOT%\Data\Browser" --disk-cache-dir="%WORKSTATION_ROOT%\Data\Cache\Browser" --no-first-run --no-default-browser-check --app=https://web.whatsapp.com/
exit /b %ERRORLEVEL%
