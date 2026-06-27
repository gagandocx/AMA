@echo off
REM ============================================================
REM  Update & Compile XAUUSD_EMA_EA.mq5 from GitHub
REM
REM  This script:
REM    1. Downloads the latest EA from GitHub
REM    2. Copies it to the MT5 Experts/Advisors folder
REM    3. Compiles it using MetaEditor
REM ============================================================

REM GitHub raw URL for the EA file (feature branch)
SET EA_URL=https://raw.githubusercontent.com/gagandocx/AMA/feature/xauusd-ema-ea/Experts/XAUUSD_EMA_EA.mq5

REM Target filename
SET EA_FILE=XAUUSD_EMA_EA.mq5

REM MT5 Experts/Advisors folder
SET MT5_DEST=C:\Users\gagan\AppData\Roaming\MetaQuotes\Terminal\930119AA53207C8778B41171FBFFB46F\MQL5\Experts\Advisors

echo.
echo ============================================================
echo   XAUUSD EMA EA Updater + Compiler
echo ============================================================
echo.

REM --- Step 1: Download the latest EA ---
echo [1/3] Downloading latest %EA_FILE% ...
echo       Source: %EA_URL%
echo.

curl -s -o "%MT5_DEST%\%EA_FILE%" -L "%EA_URL%"

IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to download %EA_FILE%.
    echo         Please check your internet connection and try again.
    pause
    exit /b 1
)

echo [OK] Downloaded %EA_FILE% successfully.
echo      Saved to: %MT5_DEST%\%EA_FILE%
echo.

REM --- Step 2: Locate MetaEditor ---
echo [2/3] Locating MetaEditor...

SET METAEDITOR=

REM Check common MetaEditor locations
IF EXIST "C:\Program Files\MetaTrader 5\metaeditor64.exe" (
    SET "METAEDITOR=C:\Program Files\MetaTrader 5\metaeditor64.exe"
    GOTO :found_editor
)

IF EXIST "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe" (
    SET "METAEDITOR=C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
    GOTO :found_editor
)

IF EXIST "D:\Program Files\MetaTrader 5\metaeditor64.exe" (
    SET "METAEDITOR=D:\Program Files\MetaTrader 5\metaeditor64.exe"
    GOTO :found_editor
)

IF EXIST "D:\MetaTrader 5\metaeditor64.exe" (
    SET "METAEDITOR=D:\MetaTrader 5\metaeditor64.exe"
    GOTO :found_editor
)

REM Search in the terminal data folder's parent installation
FOR /F "tokens=*" %%i IN ('where /R "C:\Program Files" metaeditor64.exe 2^>nul') DO (
    SET "METAEDITOR=%%i"
    GOTO :found_editor
)

FOR /F "tokens=*" %%i IN ('where /R "D:\Program Files" metaeditor64.exe 2^>nul') DO (
    SET "METAEDITOR=%%i"
    GOTO :found_editor
)

echo [ERROR] Could not find metaeditor64.exe
echo         Please install MetaTrader 5 or set the METAEDITOR path manually in this script.
pause
exit /b 1

:found_editor
echo [OK] Found MetaEditor: %METAEDITOR%
echo.

REM --- Step 3: Compile the EA ---
echo [3/3] Compiling %EA_FILE% ...
echo.

"%METAEDITOR%" /compile:"%MT5_DEST%\%EA_FILE%" /log

IF %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Compilation failed! Check the log for details.
    echo         Log file: %MT5_DEST%\%~n0.log
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   [SUCCESS] EA updated and compiled!
echo   File: %MT5_DEST%\%EA_FILE%
echo ============================================================
echo.
pause
