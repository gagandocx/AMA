@echo off
REM ============================================================
REM  Update & Compile EMATrendScalper.mq5 from GitHub
REM
REM  This script:
REM    1. Downloads the latest EA from GitHub
REM    2. Copies it to the MT5 Experts/Advisors folder
REM    3. Compiles it using MetaEditor
REM ============================================================

REM GitHub raw URL for the EA file (feature branch)
SET EA_URL=https://raw.githubusercontent.com/gagandocx/AMA/feature/xauusd-ema-ea/Experts/EMATrendScalper.mq5

REM Target filename
SET EA_FILE=EMATrendScalper.mq5

REM MT5 Experts/Advisors folder
SET MT5_DEST=C:\Users\gagan\AppData\Roaming\MetaQuotes\Terminal\930119AA53207C8778B41171FBFFB46F\MQL5\Experts\Advisors

echo.
echo ============================================================
echo   EMATrendScalper EA Updater + Compiler
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

REM --- Step 2.5: Cleanup old EA name if present ---
IF EXIST "%MT5_DEST%\XAUUSD_EMA_EA.mq5" (
    echo [CLEANUP] Removing old XAUUSD_EMA_EA.mq5 ...
    del "%MT5_DEST%\XAUUSD_EMA_EA.mq5"
)
IF EXIST "%MT5_DEST%\XAUUSD_EMA_EA.ex5" (
    echo [CLEANUP] Removing old XAUUSD_EMA_EA.ex5 ...
    del "%MT5_DEST%\XAUUSD_EMA_EA.ex5"
)

REM --- Step 3: Compile the EA ---
echo [3/3] Compiling %EA_FILE% ...
echo.

SET "LOG_FILE=%MT5_DEST%\EMATrendScalper.log"

REM Delete old log file if it exists
IF EXIST "%LOG_FILE%" del "%LOG_FILE%"

REM Run MetaEditor compile (ignore ERRORLEVEL - MetaEditor returns non-zero even on success)
"%METAEDITOR%" /compile:"%MT5_DEST%\%EA_FILE%" /log

REM Wait a moment for the log file to be written
timeout /t 2 /nobreak >nul

REM Check if log file was created
IF NOT EXIST "%LOG_FILE%" (
    echo.
    echo [ERROR] Compilation log file not found!
    echo         Expected: %LOG_FILE%
    echo         MetaEditor may not have run correctly.
    pause
    exit /b 1
)

REM Display the compilation log
echo --- Compilation Log ---
type "%LOG_FILE%"
echo --- End of Log ---
echo.

REM Check for successful compilation by looking for "0 error(s)" in the log
findstr /C:"0 error(s)" "%LOG_FILE%" >nul 2>&1
IF %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================================
    echo   [SUCCESS] EA updated and compiled!
    echo   File: %MT5_DEST%\%EA_FILE%
    echo ============================================================
    echo.
    pause
    exit /b 0
)

REM If we get here, there were compilation errors
echo.
echo [ERROR] Compilation failed! Errors found in log:
echo.
findstr /I "error" "%LOG_FILE%"
echo.
echo         Log file: %LOG_FILE%
pause
exit /b 1
