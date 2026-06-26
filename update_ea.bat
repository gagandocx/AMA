@echo off
REM ============================================================
REM  Update XAUUSD_EMA_EA.mq5 from GitHub
REM
REM  Downloads the EA into a version-specific subfolder under
REM  the configured base path, preserving older versions.
REM
REM  Example structure:
REM    D:\Automation\EA Testing\EMA\v1.00\XAUUSD_EMA_EA.mq5
REM    D:\Automation\EA Testing\EMA\v1.01\XAUUSD_EMA_EA.mq5
REM ============================================================

REM --- CONFIGURATION ---
REM Base folder where version subfolders will be created:
SET BASE_PATH=D:\Automation\EA Testing\EMA

REM GitHub raw URL for the EA file (main branch)
SET EA_URL=https://raw.githubusercontent.com/gagandocx/AMA/main/Experts/XAUUSD_EMA_EA.mq5

REM Target filename
SET EA_FILE=XAUUSD_EMA_EA.mq5

REM --- END CONFIGURATION ---

echo.
echo ============================================================
echo   XAUUSD EMA EA Updater (Versioned)
echo ============================================================
echo.

REM Create base directory if it does not exist
IF NOT EXIST "%BASE_PATH%" (
    echo Creating base directory: %BASE_PATH%
    mkdir "%BASE_PATH%"
    IF %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to create base directory.
        pause
        exit /b 1
    )
)

REM Download the file to a temporary location first
SET TEMP_FILE=%TEMP%\%EA_FILE%
echo Downloading latest %EA_FILE% ...
echo Source: %EA_URL%
echo.

curl -s -o "%TEMP_FILE%" -L "%EA_URL%"

IF %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to download %EA_FILE%.
    echo         Please check your internet connection and try again.
    pause
    exit /b 1
)

REM Extract version from the downloaded file
SET EA_VERSION=
FOR /F "tokens=2 delims=^\"" %%A IN ('findstr /C:"#property version" "%TEMP_FILE%"') DO (
    SET EA_VERSION=%%A
)

IF "%EA_VERSION%"=="" (
    echo [ERROR] Could not extract version from downloaded file.
    del "%TEMP_FILE%" >nul 2>&1
    pause
    exit /b 1
)

echo Detected version: %EA_VERSION%

REM Create versioned subfolder
SET VERSION_PATH=%BASE_PATH%\v%EA_VERSION%

IF NOT EXIST "%VERSION_PATH%" (
    echo Creating version folder: %VERSION_PATH%
    mkdir "%VERSION_PATH%"
    IF %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to create version directory.
        del "%TEMP_FILE%" >nul 2>&1
        pause
        exit /b 1
    )
)

REM Move the downloaded file to the versioned folder
copy /Y "%TEMP_FILE%" "%VERSION_PATH%\%EA_FILE%" >nul

IF %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] %EA_FILE% v%EA_VERSION% has been saved!
    echo           Location: %VERSION_PATH%\%EA_FILE%
) ELSE (
    echo [ERROR] Failed to copy file to version folder.
    del "%TEMP_FILE%" >nul 2>&1
    pause
    exit /b 1
)

REM Clean up temp file
del "%TEMP_FILE%" >nul 2>&1

echo.
echo Done. Each version is preserved in its own folder under:
echo   %BASE_PATH%
echo.
pause
