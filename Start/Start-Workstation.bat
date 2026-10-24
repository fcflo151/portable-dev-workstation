@echo off
setlocal DisableDelayedExpansion
call "%~dp0Portable-Env.cmd"
if errorlevel 1 exit /b 1
cd /d "%WORKSTATION_ROOT%"
if errorlevel 1 exit /b 1
if /i "%~1"=="--dashboard" start "" "%WORKSTATION_ROOT%\Dashboard\index.html"
echo Portable Workstation: "%WORKSTATION_ROOT%"
echo Run Tools\Setup-Workstation.ps1 to provision optional tools.
echo Type exit to leave this session.
"%ComSpec%" /d /v:off /k
endlocal
