@echo off
setlocal

:: ============================================================
:: DayZ Local Server - Example Launcher for v2.1.0
:: ============================================================
::
:: This file is a template for the DayZ Local Server Mod Manager.
::
:: Before using it:
::   1. Set "serverDirectory" to your DayZ Server folder.
::   2. Configure the remaining server settings if necessary.
::
:: The Mod Manager automatically updates the "modList",
:: "serverProfile" and "serverConfig" variables when you Apply.
:: Do not manually edit those lines after configuring the
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
::   D:\...\DayZServer
:: ------------------------------------------------------------
set "serverDirectory=C:\Path\To\DayZServer"


:: ------------------------------------------------------------
:: Server port
:: ------------------------------------------------------------
set "serverPort=2302"


:: ------------------------------------------------------------
:: Server configuration file
::
:: Managed by the Mod Manager: on Apply this is rewritten to the
:: active preset's serverDZ.cfg. The value below is only the
:: fallback used before the first Apply.
:: ------------------------------------------------------------
set "serverConfig=serverDZ.cfg"


:: ------------------------------------------------------------
:: Server profile directory
::
:: Managed by the Mod Manager: on Apply this is rewritten to the
:: active preset's profiles folder. The value below is only the
:: fallback used before the first Apply.
:: ------------------------------------------------------------
set "serverProfile=DayZ-Mod-Manager-V2\Presets\dayzOffline.chernarusplus\__default_preset__\profiles"


:: ------------------------------------------------------------
:: Number of CPU threads assigned to the server
:: ------------------------------------------------------------
set "serverCPU=4"


:: ------------------------------------------------------------
:: DayZ mod list
::
:: IMPORTANT:
:: This line is automatically managed by the DayZ Local Server
:: Mod Manager V2. Do not manually edit it.
:: ------------------------------------------------------------
set "modList=-mod="


:: ------------------------------------------------------------
:: Server-side mod list (-serverMod=)
::
:: NOT managed by the Mod Manager. For advanced users only.
:: IMPORTANT: DZMMV2 does NOT create junctions for these mods.
:: You MUST copy physical @‑prefixed mod folders into your
:: DayZServer root directory. Referencing Steam !Workshop will not work.
:: Example: set "serverMod=-serverMod=@ServerMod1;@ServerMod2"
:: Separate multiple mods with semicolon ;
:: This line will NEVER be overwritten by Mod Manager.
:: ------------------------------------------------------------
set "serverMod=-serverMod="


:: ============================================================
:: DO NOT MODIFY BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE
:: DOING.
:: ============================================================


:: Set the Command Prompt window title
title "%serverName%"


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
    "%modList%" ^
    "%serverMod%" ^
    -cpuCount=%serverCPU% ^
    -nosplash

:: ============================================================
::  Launch the DayZ client through Steam
:: ============================================================

:: tasklist /FI "IMAGENAME eq steam.exe" 2>NUL | find /I "steam.exe" >NUL
:: 
:: if %ERRORLEVEL% EQU 0 (
::     echo.
::     echo Steam is running.
::     echo Launching DayZ...
::     echo.
::     start "" "steam://rungameid/221100"
:: ) else (
::     echo.
::     echo [WARNING] Steam is not running.
::     echo.
::     echo The DayZ server has been started,
::     echo but the DayZ client was not launched.
::     echo.
::     echo Please start Steam and launch DayZ manually.
::     echo.
:: )


echo Server startup command completed.
echo This window can now be closed.
echo.

endlocal
exit /b 0
