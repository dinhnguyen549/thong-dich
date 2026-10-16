@echo off
chcp 65001 >nul
title Thong Dich - model downloader
echo.
echo   ============================================================
echo    Thong Dich - download the AI models (one time, on this PC)
echo   ============================================================
echo.
echo   Needed:   speech recognition + voice detector + Gemma 4 E2B   (about 4.2 GB)
echo   Optional: TranslateGemma 4B  (+2.2 GB, recommended)
echo   Optional: Gemma 4 E4B        (+5.2 GB, only for iPhone Air / 12 GB iPhones)
echo.
echo   When finished, copy the .tdpack files from the ThongDich-Transfer folder
echo   to the iPhone app (Apple Devices app ^> your iPhone ^> Files ^> Thong Dich).
echo.
set "ARGS="
set /p TG="  Include TranslateGemma? (Y/N, default Y): "
if /I "%TG%"=="N" set "ARGS=%ARGS% -SkipTranslateGemma"
set /p E4B="  Include Gemma 4 E4B for iPhone Air? (Y/N, default N): "
if /I "%E4B%"=="Y" set "ARGS=%ARGS% -IncludeE4B"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0get-models.ps1" %ARGS%
echo.
pause
