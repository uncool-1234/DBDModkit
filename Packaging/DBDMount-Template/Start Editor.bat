@echo off
rem Starts the editor with the paths from ModkitData\ModkitLocal.ini (run "Setup Project.bat" first). Arguments are passed to the editor.
setlocal
set "MODKIT_EDITOR_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ModkitProject.ps1" -Action start
if errorlevel 1 (pause & exit /b 1)
