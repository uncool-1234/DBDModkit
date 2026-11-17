@echo off
rem BuildGraph command that produces the installed engine build from a copy of the game/dbd engine tree.
rem   BUILD_SRC  engine source copy to build (required)
rem   OUT_DIR    BuiltDirectory (default %MODKIT_ROOT%\..\DBD-UEEditor-Installed)
rem   LOG_DIR    log folder (default %MODKIT_ROOT%\logs)
rem   UBA_HOST   optional: LAN IP of this PC, enables UBA helpers on port 1345
rem   WITH_FULL_DEBUG_INFO  true (default) or false: BuildGraph WithFullDebugInfo
if not defined MODKIT_ROOT call "%~dp0..\..\tools\env\modkit-env.cmd"
if not defined BUILD_SRC (echo set BUILD_SRC to the engine source copy & exit /b 1)
if not defined OUT_DIR for %%I in ("%MODKIT_ROOT%\..\DBD-UEEditor-Installed") do set "OUT_DIR=%%~fI"
if not defined LOG_DIR set "LOG_DIR=%MODKIT_ROOT%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not defined WITH_FULL_DEBUG_INFO set "WITH_FULL_DEBUG_INFO=true"
set "UBA_ARGS="
if defined UBA_HOST set "UBA_ARGS=-UBA -UBAHost=%UBA_HOST% -UBAPort=1345 -UBAPrintSummary"
cd /d "%BUILD_SRC%"
echo START %DATE% %TIME% > "%LOG_DIR%\installed_build.time"
call Engine\Build\BatchFiles\RunUAT.bat BuildGraph -target="Make Installed Build Win64" -script=Engine/Build/InstalledEngineBuild.xml -set:HostPlatformOnly=true -set:WithWin64=true -set:WithClient=true -set:WithServer=true "-set:GameConfigurations=Development;Shipping" -set:WithDDC=false -set:WithFullDebugInfo=%WITH_FULL_DEBUG_INFO% -set:IncludeDocs=true "-set:BuiltDirectory=%OUT_DIR%" "-set:ExtraCompileArgs=%UBA_ARGS%" -WaitMutex -NoP4 > "%LOG_DIR%\installed_build.log" 2>&1
set "RC=%ERRORLEVEL%"
echo EXIT %RC% >> "%LOG_DIR%\installed_build.time"
echo END %DATE% %TIME% >> "%LOG_DIR%\installed_build.time"
exit /b %RC%
