@echo off
rem Registers this engine folder under the id "@ENGINE_ID@" for the current user, so .uproject files with that EngineAssociation open with it.
setlocal
for %%I in ("%~dp0.") do set "ENG=%%~fI"
if not exist "%ENG%\Engine\Binaries\Win64\UnrealEditor.exe" (echo Not an installed engine folder: %ENG% & pause & exit /b 1)
reg add "HKCU\Software\Epic Games\Unreal Engine\Builds" /v "@ENGINE_ID@" /t REG_SZ /d "%ENG%" /f
if errorlevel 1 (pause & exit /b 1)
echo Registered @ENGINE_ID@ = %ENG%
pause
