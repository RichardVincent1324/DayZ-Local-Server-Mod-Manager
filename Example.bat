@echo off
::Server name
set serverName=LocalServer
::Server files location 【必填修改】
set serverDirectory="<你的DayZServer完整根目录>"
::Server Port
set serverPort=2302
::Server config
set serverConfig=serverDZ.cfg
::Server profile location 工具会自动根据地图切换，可留空
set serverProfile=map_profiles\chernarusplus
::Logical CPU cores
set serverCPU=4
::modlist 由 ModManager.ps1 工具自动改写，无需手动填写
set modList="-mod=;"
::Sets title
title %serverName% batch
cd /D "%serverDirectory%"
if not exist "%serverProfile%" ( 
mkdir %serverProfile% > nul
) 
tasklist /fi "imagename eq steam.exe" | findstr steam.exe >nul
if %errorlevel% equ 0 (
    start "" "steam://rungameid/221100"
start "DayZ Server" /min DayZServer_x64.exe -config=%serverConfig% -port=%serverPort% -profiles=%serverProfile% %modList% -cpuCount=4 -noBattlEye -maxMem=4096 -malloc=tbb4malloc_bi -nosplash -filePatching -exThreads=4
) else (
    echo Steam Not Running in the background
	pause
)