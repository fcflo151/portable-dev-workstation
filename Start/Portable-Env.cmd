@echo off
rem CALL this file from cmd.exe. Changes affect only this process and children.
rem Keep delayed expansion disabled: paths may contain exclamation marks.
for %%I in ("%~dp0..") do set "WORKSTATION_ROOT=%%~fI"
if defined PORTABLE_ENV_ROOT if /i "%PORTABLE_ENV_ROOT%"=="%WORKSTATION_ROOT%" exit /b 0
if defined PORTABLE_ENV_ROOT (
  echo A different workstation environment is already active. Open a fresh terminal.
  exit /b 1
)
set "HOME=%WORKSTATION_ROOT%\Data\PortableHome"
set "USERPROFILE=%HOME%"
set "APPDATA=%HOME%\AppData\Roaming"
set "LOCALAPPDATA=%HOME%\AppData\Local"
set "TEMP=%HOME%\Temp"
set "TMP=%TEMP%"
for %%I in ("%HOME%" "%APPDATA%" "%LOCALAPPDATA%" "%TEMP%" "%WORKSTATION_ROOT%\Data\Cache" "%WORKSTATION_ROOT%\Data\Logs" "%WORKSTATION_ROOT%\Data\Backups" "%WORKSTATION_ROOT%\Data\Config") do (
  if not exist "%%~I" mkdir "%%~I"
  if not exist "%%~I" exit /b 1
)
set "HOMEDRIVE=%~d0"
set "HOMEPATH=%HOME:~2%"
set "XDG_CONFIG_HOME=%HOME%\.config"
set "XDG_CACHE_HOME=%WORKSTATION_ROOT%\Data\Cache"
set "XDG_DATA_HOME=%HOME%\.local\share"
set "GIT_CONFIG_GLOBAL=%HOME%\.gitconfig"
set "GIT_CONFIG_NOSYSTEM=1"
rem Start without inherited Git overrides, host agents, tokens or injected runtime code.
for %%V in (GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_EXEC_PATH GIT_TEMPLATE_DIR GIT_SSH GIT_SSH_COMMAND SSH_AUTH_SOCK GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN BASH_ENV ENV NODE_OPTIONS NODE_PATH PYTHONHOME PYTHONPATH VIRTUAL_ENV) do set "%%V="
set "NPM_CONFIG_CACHE=%WORKSTATION_ROOT%\Data\Cache\npm"
set "NPM_CONFIG_PREFIX=%HOME%\npm"
set "NPM_CONFIG_USERCONFIG=%HOME%\.npmrc"
set "PYTHONUSERBASE=%HOME%\Python"
set "PYTHONPYCACHEPREFIX=%WORKSTATION_ROOT%\Data\Cache\pycache"
set "PIP_CACHE_DIR=%WORKSTATION_ROOT%\Data\Cache\pip"
set "DOTNET_CLI_HOME=%HOME%\.dotnet"
set "NUGET_PACKAGES=%WORKSTATION_ROOT%\Data\Cache\nuget"
set "CARGO_HOME=%HOME%\.cargo"
set "RUSTUP_HOME=%HOME%\.rustup"
set "GH_CONFIG_DIR=%WORKSTATION_ROOT%\Data\Config\gh"
rem Do not pass PowerShell 7 core modules through cmd.exe into Windows PowerShell.
set "PSModulePath=%HOME%\PowerShell\Modules;%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
set "PATH=%WORKSTATION_ROOT%\Apps\Git\cmd;%WORKSTATION_ROOT%\Apps\Node;%WORKSTATION_ROOT%\Apps\Python;%WORKSTATION_ROOT%\Apps\7Zip;%HOME%\npm;%PATH%"
set "PORTABLE_ENV_ROOT=%WORKSTATION_ROOT%"
exit /b 0
