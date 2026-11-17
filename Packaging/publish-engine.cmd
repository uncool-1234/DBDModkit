@echo off
rem Builds and archives a release of the modkit engine. Options are passed to publish-engine.ps1 (see its header), for example:
rem   publish-engine.cmd -NonInteractive -NoSmokeTest -Password <password>
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish-engine.ps1" %*
set "RC=%ERRORLEVEL%"
echo %* | findstr /i /c:"-NonInteractive" >nul || pause
exit /b %RC%
