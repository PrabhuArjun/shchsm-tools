@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
title Transcribator SHCHSM
REM Thin launcher (also copied to the Desktop as the transcribe button).
REM Drag audio files onto it, or double-click to process the inbox folder.
set "TSH_ROOT=%USERPROFILE%\.transcriber-shchsm"
if "%SHCHSM_AUTOMATED%"=="1" if defined SHCHSM_TEST_ROOT set "TSH_ROOT=%SHCHSM_TEST_ROOT%"
if not exist "%TSH_ROOT%\Transcribe.ps1" goto :missing
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%TSH_ROOT%\Transcribe.ps1" %*
set "RC=%ERRORLEVEL%"
goto :finish

:missing
echo [!] Сначала запустите "1-Install.bat" (Transcribe.ps1 не найден).
set "RC=1"

:finish
if not "%SHCHSM_AUTOMATED%"=="1" pause
exit /b %RC%
