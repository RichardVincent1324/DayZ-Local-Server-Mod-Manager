@echo off
setlocal

:: ============================================================
:: DayZ Local Server - Example Launcher
:: ============================================================
::
:: This file is a template for the DayZ Local Server Mod Manager.
::
:: Before using it:
::   1. Set "serverDirectory" to your DayZ Server folder.
::   2. Configure the remaining server settings if necessary.
::
:: The Mod Manager automatically updates the "modList" variable.
:: Do not manually edit the modList line after configuring the
:: Mod Manager, as your changes may be overwritten.
::
:: ============================================================


:: ------------------------------------------------------------
:: Server name
:: ------------------------------------------------------------
set "serverName=LocalServer"


:: ------------------------------------------------------------
:: DayZ Server installation directory
:: IMPORTANT: Change this to your actual DayZ Server folder.
:: Example:
::   D:\DayZServer
:: ------------------------------------------------------------
set "serverDirectory=C:\Path\To\DayZServer"


:: ------------------------------------------------------------
:: Server port
:: ------------------------------------------------------------
set "serverPort=2302"


:: ------------------------------------------------------------
:: Server configuration file
:: ------------------------------------------------------------
set "serverConfig=serverDZ.cfg"


:: ------------------------------------------------------------
:: Server profile directory
::
:: The Mod Manager can automatically change this when switching
:: maps. Leave this setting enabled if you use map profiles.
:: ------------------------------------------------------------
set "serverProfile=map_profiles\chernarusplus"


:: ------------------------------------------------------------
:: Number of CPU threads assigned to the server
:: ------------------------------------------------------------
set "serverCPU=4"


:: ------------------------------------------------------------
:: DayZ mod list
::
:: IMPORTANT:
:: This line is automatically managed by the DayZ Local Server
:: Mod Manager. Do not manually edit it.
:: ------------------------------------------------------------
set "modList=-mod=;"


:: ============================================================
:: DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE
:: DOING.
:: ============================================================


:: Set the Command Prompt window title
title %serverName%


:: Change to the DayZ Server directory
cd /D "%serverDirectory%" || (
    echo.
    echo [ERROR] DayZ Server directory not found:
    echo %serverDirectory%
    echo.
    pause
    exit /b 1
)


:: Verify that the DayZ Server executable exists
if not exist "DayZServer_x64.exe" (
    echo.
    echo [ERROR] DayZServer_x64.exe was not found.
    echo Server directory:
    echo %serverDirectory%
    echo.
    pause
    exit /b 1
)


:: Create the server profile directory if necessary
if not exist "%serverProfile%" (
    mkdir "%serverProfile%" >nul 2>&1
)


:: ============================================================
:: Start DayZ Server
:: ============================================================

echo.
echo Starting DayZ Server...
echo.

start "%serverName%" /min "DayZServer_x64.exe" ^
    -config=%serverConfig% ^
    -port=%serverPort% ^
    -profiles=%serverProfile% ^
    %modList% ^
    -cpuCount=%serverCPU% ^
    -noBattlEye ^
    -nosplash


:: ============================================================
:: Check whether Steam is running
:: ============================================================

tasklist /FI "IMAGENAME eq steam.exe" 2>NUL | find /I "steam.exe" >NUL

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Steam is running.
    echo Launching DayZ...
    echo.
    
    start "" "steam://rungameid/221100"
) else (
    echo.
    echo [WARNING] Steam is not running.
    echo.
    echo The DayZ server has been started,
    echo but the DayZ client was not launched.
    echo.
    echo Please start Steam and launch DayZ manually.
    echo.
)


echo Server startup command completed.
echo This window can now be closed.
echo.

endlocal
exit /b 0
