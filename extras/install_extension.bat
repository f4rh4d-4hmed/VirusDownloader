@echo off
setlocal enabledelayedexpansion
title VirusDownloader Browser Extension Installer

echo ==========================================================
echo        VirusDownloader Browser Extension Helper
echo ==========================================================
echo.

set "EXT_DIR=%~dp0extension"
echo Extension directory:
echo   "%EXT_DIR%"
echo.

echo Select an option:
echo   [1] Launch Google Chrome with VirusDownloader Extension
echo   [2] Launch Microsoft Edge with VirusDownloader Extension
echo   [3] Launch Brave Browser with VirusDownloader Extension
echo   [4] Open Extension Folder in File Explorer
echo   [5] Copy Extension Path to Clipboard
echo   [6] Exit
echo.

set /p choice="Enter choice [1-6]: "

if "%choice%"=="1" (
    echo Launching Google Chrome...
    start "" chrome.exe --load-extension="%EXT_DIR%" "chrome://extensions"
    goto done
)
if "%choice%"=="2" (
    echo Launching Microsoft Edge...
    start "" msedge.exe --load-extension="%EXT_DIR%" "edge://extensions"
    goto done
)
if "%choice%"=="3" (
    echo Launching Brave Browser...
    start "" brave.exe --load-extension="%EXT_DIR%" "brave://extensions"
    goto done
)
if "%choice%"=="4" (
    explorer.exe "%EXT_DIR%"
    goto done
)
if "%choice%"=="5" (
    echo | set /p="%EXT_DIR%" | clip
    echo.
    echo Path copied to clipboard!
    echo In your browser, go to Extensions -> Turn on 'Developer mode' -> Click 'Load unpacked' and paste the path.
    pause
    goto done
)

:done
echo.
echo Operation completed.

