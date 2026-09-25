@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "rc=%ERRORLEVEL%"
if not "%rc%"=="0" echo.
if not "%rc%"=="0" echo Setup failed. Review CONFIG-MERGE-GUIDE.md, then run this file again.
exit /b %rc%
