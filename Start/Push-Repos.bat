@echo off
setlocal
call "%~dp0..\Tools\Portable-Env.cmd"
if errorlevel 1 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\Tools\Push-Repos.ps1"
set "repo_exit=%ERRORLEVEL%"
echo.
pause
exit /b %repo_exit%
