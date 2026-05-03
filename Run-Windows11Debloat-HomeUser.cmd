@echo off
:: =============================================================================
:: Run-Windows11Debloat-HomeUser.cmd
:: Double-click launcher for Run-Windows11Debloat-HomeUser.ps1
:: Must be run as Administrator
:: =============================================================================
setlocal

:: Check for administrator rights and re-launch elevated if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "SCRIPT_DIR=%~dp0"
set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PS_EXE%" set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Run-Windows11Debloat-HomeUser.ps1"
exit /b %errorlevel%
