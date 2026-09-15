@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo   SABONG ROOSTERS - 1-CLICK WEB (HTML5) EXPORTER
echo ===================================================

cd /d "%~dp0"

:: 1. Locate Godot Executable
set "GODOT_BIN="
if exist "D:\Downloads\Godot_v4.7.1-stable_win64_console.exe" (
    set "GODOT_BIN=D:\Downloads\Godot_v4.7.1-stable_win64_console.exe"
) else if exist "D:\Downloads\Godot_v4.7.1-stable_win64.exe" (
    set "GODOT_BIN=D:\Downloads\Godot_v4.7.1-stable_win64.exe"
) else (
    where godot >nul 2>&1
    if not errorlevel 1 (
        for /f "delims=" %%i in ('where godot') do set "GODOT_BIN=%%i"
    )
)

if "%GODOT_BIN%"=="" (
    echo [ERROR] Godot 4 executable could not be found automatically.
    echo Please ensure Godot is in your PATH or at D:\Downloads\Godot_v4.7.1-stable_win64_console.exe
    pause
    exit /b 1
)

echo [1/3] Using Godot engine: "%GODOT_BIN%"

:: Ensure target exports/web folder exists
if not exist "exports\web" mkdir "exports\web"

:: 2. Import all new assets into Godot
echo [2/3] Importing project assets and verifying scripts...
"%GODOT_BIN%" --headless --import
if errorlevel 1 (
    echo [WARNING] Import finished with exit code %errorlevel%. Continuing export...
)

:: 3. Export to Web
echo [3/4] Exporting to Web (HTML5) via preset 'Web'...
"%GODOT_BIN%" --headless --export-release "Web" "exports/web/index.html"

if errorlevel 1 (
    echo [ERROR] Export failed with error code %errorlevel%.
    pause
    exit /b %errorlevel%
)

:: 4. Pre-compress Assets (Gzip) for Fast HTTP Delivery
echo [4/4] Generating pre-compressed Gzip assets (.wasm.gz, .pck.gz)...
python scratch\compress_assets.py

echo.
echo ===================================================
echo [SUCCESS] Web export completed with Gzip compression!
echo Output folder: %~dp0exports\web\
echo Test URL:     http://localhost:8060
echo ===================================================
echo.

:: Check if server is running
curl -s http://localhost:8060 >nul 2>&1
if errorlevel 1 (
    echo [INFO] Local web server is not running. You can start it with: python run_web_server.py
) else (
    echo [INFO] Local web server is active! Refresh your browser at http://localhost:8060
)

echo.
