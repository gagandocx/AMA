@echo off
REM ============================================================
REM  Update XAUUSD_EMA_EA.mq5 from GitHub
REM
REM  Place this file in: D:\Automation\EA Testing\EMA\
REM  Run it to download the latest EA into the same folder.
REM ============================================================

REM GitHub raw URL for the EA file (main branch)
SET EA_URL=https://raw.githubusercontent.com/gagandocx/AMA/main/Experts/XAUUSD_EMA_EA.mq5

REM Target filename
SET EA_FILE=XAUUSD_EMA_EA.mq5

echo.
echo ============================================================
echo   XAUUSD EMA EA Updater
echo ============================================================
echo.
echo Downloading latest %EA_FILE% ...
echo Source: %EA_URL%
echo.

curl -s -o "%~dp0%EA_FILE%" -L "%EA_URL%"

IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to download %EA_FILE%.
    echo         Please check your internet connection and try again.
    pause
    exit /b 1
)

echo [SUCCESS] %EA_FILE% has been updated!
echo           Location: %~dp0%EA_FILE%
echo.
pause
