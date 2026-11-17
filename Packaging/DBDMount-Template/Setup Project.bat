@echo off
rem Writes ModkitData\ModkitLocal.ini: finds the engine, the profile, the game install and the files in ModkitData, and asks for what it cannot find.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ModkitProject.ps1" -Action setup
if errorlevel 1 (pause & exit /b 1)
pause
