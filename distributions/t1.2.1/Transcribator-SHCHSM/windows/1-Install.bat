@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
title Transcribator SHCHSM - install
REM All logic lives in Install.ps1. It is run as text through ScriptBlock.Create,
REM so the downloaded unsigned .ps1 is not subject to -File policy (no policy is changed).
REM The package path travels in an environment variable; no user input is placed in code.
set "TSH_PACKAGE_ROOT=%~dp0"
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; & ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $env:TSH_PACKAGE_ROOT 'Install.ps1'))))"
set "RC=%ERRORLEVEL%"
if not "%SHCHSM_AUTOMATED%"=="1" pause
exit /b %RC%
