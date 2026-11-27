@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Concat-Dev.ps1" %*
set "result=%ERRORLEVEL%"
if not "%result%"=="0" if "%~1"=="" pause
exit /b %result%
