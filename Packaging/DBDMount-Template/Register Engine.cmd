@echo off
rem Registers the installed engine under the id "DBDModkit-5.7.4" for the current user (needed to double click the .uproject / right click Switch Engine version).
rem Usage: "Register Engine.cmd" [path of the installed engine folder, default ..\Windows]
setlocal
set "ENG=%~1"
if "%ENG%"=="" set "ENG=%~dp0..\Windows"
for %%I in ("%ENG%") do set "ENG=%%~fI"
if not exist "%ENG%\Engine\Binaries\Win64\UnrealEditor.exe" (echo Not an installed engine folder: %ENG% & exit /b 1)
reg add "HKCU\Software\Epic Games\Unreal Engine\Builds" /v "DBDModkit-5.7.4" /t REG_SZ /d "%ENG%" /f
echo Registered DBDModkit-5.7.4 = %ENG%
