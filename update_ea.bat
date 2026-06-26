@echo off
REM ============================================================
REM  Update XAUUSD_EMA_EA.mq5 from GitHub
REM  
REM  Configure the MT5_EXPERTS_PATH below to match your local
REM  MetaTrader 5 Experts folder path.
REM ============================================================

REM --- CONFIGURATION ---
REM Set your local MT5 Experts folder path here:
SET MT5_EXPERTS_PATH=C:\Users\%USERNAME%\AppData\Roaming\MetaQuotes\Terminal\YOUR_TERMINAL_ID\MQL5\Experts

REM GitHub raw URL for the EA file (main branch)
SET EA_URL=https://raw.githubusercontent.com/gagandocx/AMA/main/Experts/XAUUSD_EMA_EA.mq5

REM Target filename
SET EA_FILE=XAUUSD_EMA_EA.mq5

REM --- END CONFIGURATION ---

echo.
echo ============================================================
echo   XAUUSD EMA EA Updater
echo ============================================================
echo.
echo Downloading latest %EA_FILE% ...
echo Source: %EA_URL%
echo Target: %MT5_EXPERTS_PATH%\%EA_FILE%
echo.

REM Check if target directory exists
IF NOT EXIST "%MT5_EXPERTS_PATH%" (
    echo [ERROR] Target directory does not exist:
    echo         %MT5_EXPERTS_PATH%
    echo.
    echo Please edit this script and set MT5_EXPERTS_PATH to your
    echo MetaTrader 5 Experts folder path.
    echo.
    pause
    exit /b 1
)

REM Download the file using curl
curl -s -o "%MT5_EXPERTS_PATH%\%EA_FILE%" -L "%EA_URL%"

IF %ERRORLEVEL% EQU 0 (
    echo [SUCCESS] %EA_FILE% has been updated successfully!
    echo           Location: %MT5_EXPERTS_PATH%\%EA_FILE%
) ELSE (
    echo [ERROR] Failed to download %EA_FILE%.
    echo         Please check your internet connection and try again.
    pause
    exit /b 1
)

echo.
echo Done. You can now refresh or restart MetaTrader 5 to load
echo the updated Expert Advisor.
echo.
pause
