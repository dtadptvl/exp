@echo off
setlocal
where python >nul 2>nul
if errorlevel 1 (
  echo Python was not found on PATH.
  exit /b 1
)
python "%~dp0tests\test_artifact.py"
exit /b %ERRORLEVEL%
