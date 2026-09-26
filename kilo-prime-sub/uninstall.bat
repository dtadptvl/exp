@echo off
setlocal EnableExtensions
cd /d "%~dp0"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set "RC=%ERRORLEVEL%"
if not defined PRIME_SUB_NO_PAUSE pause
exit /b %RC%
