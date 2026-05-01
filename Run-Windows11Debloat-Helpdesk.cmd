@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PS_EXE=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PS_EXE%" set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Windows11Debloat.ps1" -HelpdeskMode %*
exit /b %errorlevel%
