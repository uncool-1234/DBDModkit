@echo off
rem Starts the modkit editor with an isolated DDC. Engine location: %MODKIT_ENGINE% if set, else ..\Windows (sibling of this template in the package).
setlocal
set "PROJ=%~dp0"
if not defined MODKIT_ENGINE set "MODKIT_ENGINE=%~dp0..\Windows"
if not exist "%MODKIT_ENGINE%\Engine\Binaries\Win64\UnrealEditor.exe" (echo Engine not found at %MODKIT_ENGINE% - set MODKIT_ENGINE to the installed engine folder & pause & exit /b 1)
if not exist "%PROJ%ModkitLocal.ini" (echo Copy ModkitLocal.ini.example to ModkitLocal.ini and edit it first & pause & exit /b 1)
set "UE-LocalDataCachePath=%PROJ%DDC"
"%MODKIT_ENGINE%\Engine\Binaries\Win64\UnrealEditor.exe" "%PROJ%DBDMount.uproject" -log -d3d12 -sm5 %*
