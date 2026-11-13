@echo off
cd /d N:\DBD-UEEditor-BuildSrc
echo START %DATE% %TIME% > N:\DBD-UEEditor\buildlogs\installed_build8.time
call Engine\Build\BatchFiles\RunUAT.bat BuildGraph -target="Make Installed Build Win64" -script=Engine/Build/InstalledEngineBuild.xml -set:HostPlatformOnly=true -set:WithWin64=true -set:WithClient=true -set:WithServer=true "-set:GameConfigurations=Development;Shipping" -set:WithDDC=false -set:WithFullDebugInfo=true -set:IncludeDocs=true -set:BuiltDirectory=N:/DBD-UEEditor-Installed "-set:ExtraCompileArgs=-UBA -UBAHost=<build-helper-ip> -UBAPort=1345 -UBAPrintSummary" -WaitMutex -NoP4 > N:\DBD-UEEditor\buildlogs\installed_build8.log 2>&1
echo EXIT %ERRORLEVEL% >> N:\DBD-UEEditor\buildlogs\installed_build8.time
echo END %DATE% %TIME% >> N:\DBD-UEEditor\buildlogs\installed_build8.time
