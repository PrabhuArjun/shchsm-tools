@echo off
chcp 65001 >nul
REM Транскрибатор ШЧСМ — установка для Windows 10/11
REM  ⚠️ БЕТА: собрано без проверки на живой Windows. Если что-то не скачалось —
REM     сообщите Арджуне, поправим ссылку (2 минуты). Логика та же, что на Mac.
title Транскрибатор ШЧСМ - установка
setlocal enabledelayedexpansion
set "MODEL_MIN=1500000000"
echo ==============================================
echo    Транскрибатор ШЧСМ - установка (Windows)
echo ==============================================
echo.

set "ROOT=%USERPROFILE%\.transcriber-shchsm"
if "%SHCHSM_AUTOMATED%"=="1" if defined SHCHSM_TEST_ROOT set "ROOT=%SHCHSM_TEST_ROOT%"
set "BIN=%ROOT%\bin"
set "MODELS=%ROOT%\models"
set "MODEL=%MODELS%\ggml-large-v3-turbo.bin"
if not exist "%BIN%" mkdir "%BIN%"
if not exist "%MODELS%" mkdir "%MODELS%"

REM 1. ffmpeg (конвертер аудио) — качаем НАПРЯМУЮ в свою папку %BIN%, БЕЗ winget.
REM    У winget бывает "Access denied" при копировании в системную папку (тест 24.07).
REM    Прямая загрузка надёжнее и ничего в системе не трогает.
if exist "%BIN%\ffmpeg.exe" ( echo [OK] ffmpeg уже установлен & goto :ff_done )
where ffmpeg >nul 2>&1
if not errorlevel 1 ( echo [OK] ffmpeg уже есть в системе & goto :ff_done )
echo -^> Скачиваю ffmpeg ~105 МБ, один раз, несколько минут...
curl -L --fail -o "%ROOT%\ffmpeg.zip" "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
if not "!ERRORLEVEL!"=="0" ( echo [!] Не скачался ffmpeg - проверьте интернет и запустите снова. & call :wait & exit /b 1 )
echo -^> Распаковываю...
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { Expand-Archive -Force -LiteralPath (Join-Path $env:ROOT 'ffmpeg.zip') -DestinationPath (Join-Path $env:ROOT 'ffmpeg-tmp') } catch { Write-Host $_; exit 1 }"
if not "!ERRORLEVEL!"=="0" ( echo [!] ffmpeg extraction failed & call :wait & exit /b 1 )
for /r "%ROOT%\ffmpeg-tmp" %%F in (ffmpeg.exe)  do copy /Y "%%F" "%BIN%\ffmpeg.exe"  >nul
for /r "%ROOT%\ffmpeg-tmp" %%F in (ffprobe.exe) do copy /Y "%%F" "%BIN%\ffprobe.exe" >nul
rmdir /s /q "%ROOT%\ffmpeg-tmp" >nul 2>&1
del "%ROOT%\ffmpeg.zip" >nul 2>&1
if not exist "%BIN%\ffmpeg.exe" ( echo [!] ffmpeg скачан, но ffmpeg.exe не найден после распаковки. & call :wait & exit /b 1 )
echo [OK] ffmpeg установлен
:ff_done

REM 2. Pinned engine. Validate SHA256 BEFORE extraction, keep adjacent DLLs.
if not exist "%BIN%\whisper-cli.exe" (
  set "ENGINE_STAGE=%TEMP%\tsh_engine_%RANDOM%_%RANDOM%"
  if exist "!ENGINE_STAGE!" ( echo [!] Engine staging collision & call :wait & exit /b 1 )
  mkdir "!ENGINE_STAGE!"
  if not "!ERRORLEVEL!"=="0" ( echo [!] Cannot create engine staging & call :wait & exit /b 1 )
  echo -^> Downloading whisper.cpp v1.8.2...
  curl.exe -L --fail --retry 2 -o "!ENGINE_STAGE!\engine.zip" "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-bin-x64.zip"
  if not "!ERRORLEVEL!"=="0" ( echo [!] Engine download failed & call :wait & exit /b 1 )
  powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $zip=Join-Path $env:ENGINE_STAGE 'engine.zip'; $hash=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($zip))).Replace('-','').ToLowerInvariant(); if ($hash -ne 'b1514ebc099765e39fa37eb780b92a140a94c86bb0b3b3d98226b38825979732') { throw 'ENGINE_SHA256_MISMATCH' }; $stage=Join-Path $env:ENGINE_STAGE 'unpacked'; Expand-Archive -LiteralPath $zip -DestinationPath $stage; $exe=@(Get-ChildItem -LiteralPath $stage -Filter whisper-cli.exe -Recurse -File); if ($exe.Count -ne 1) { throw 'ENGINE_EXE_MISSING_OR_AMBIGUOUS' }; $dll=@(Get-ChildItem -LiteralPath $exe[0].DirectoryName -Filter *.dll -File); if ($dll.Count -eq 0) { throw 'ENGINE_DLL_MISSING' }; foreach ($f in $dll) { Copy-Item -LiteralPath $f.FullName -Destination $env:BIN -Force }; Copy-Item -LiteralPath $exe[0].FullName -Destination $env:BIN -Force } catch { Write-Host ('[!] '+$_.Exception.Message); exit 1 }"
  if not "!ERRORLEVEL!"=="0" ( echo [!] Engine verification or installation failed & call :wait & exit /b 1 )
  rmdir /s /q "!ENGINE_STAGE!" >nul 2>&1
  echo [OK] Engine installed
) else (
  echo [OK] Engine already installed
)

REM Start the engine; install signed Microsoft runtime if it is missing.
"%BIN%\whisper-cli.exe" --help > "%ROOT%\engine-preflight.log" 2>&1
if not "!ERRORLEVEL!"=="0" (
  powershell.exe -NoProfile -Command "$ErrorActionPreference = 'Stop' $runtimePath = Join-Path $env:ROOT 'vc_redist.x64.exe' try {   Write-Host 'Installing the Microsoft runtime. Confirm the Windows prompt if shown.'   Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $runtimePath   $signature = Get-AuthenticodeSignature -LiteralPath $runtimePath   if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Microsoft signature validation failed' }   $process = Start-Process -FilePath $runtimePath -ArgumentList '/install','/passive','/norestart' -Wait -PassThru   if ($process.ExitCode -notin @(0, 1638, 3010)) { throw ('Runtime installation failed: '+$process.ExitCode) }   Remove-Item -LiteralPath $runtimePath -Force   exit 0 } catch {   Write-Host $_.Exception.Message   exit 1 }"
  if not "!ERRORLEVEL!"=="0" ( echo [!] Не удалось установить необходимые библиотеки. & call :wait & exit /b 1 )
  "%BIN%\whisper-cli.exe" --help > "%ROOT%\engine-preflight.log" 2>&1
  if not "!ERRORLEVEL!"=="0" ( echo [!] Движок не запустился. Установка остановлена. & call :wait & exit /b 1 )
)

REM 3. Языковая модель (~1,5 ГБ, один раз)
REM    Проверяем РАЗМЕР, а не факт существования: оборванная закачка иначе
REM    останется битым файлом и при следующем запуске будет принята за готовую.
set "MODEL_OK="
if exist "%MODEL%" (
  for %%A in ("%MODEL%") do set "MSIZE=%%~zA"
  if !MSIZE! geq %MODEL_MIN% set "MODEL_OK=1"
  if not defined MODEL_OK (
    echo [!] Найдена неполная модель - скачиваю заново.
    REM Keep the old model until its replacement has downloaded successfully.
  )
)
if defined MODEL_OK (
  echo [OK] Модель уже скачана
) else (
  echo -^> Скачиваю модель ~1,5 ГБ, один раз, несколько минут...
  curl -L --fail -o "%MODELS%\model.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
  if not "!ERRORLEVEL!"=="0" (
    del /f /q "%MODELS%\model.part" >nul 2>&1
    echo [!] Модель не скачалась - проверьте интернет и запустите снова
    call :wait & exit /b 1
  )
  for %%A in ("%MODELS%\model.part") do set "GOT=%%~zA"
  if !GOT! lss %MODEL_MIN% (
    del /f /q "%MODELS%\model.part" >nul 2>&1
    echo [!] Модель скачалась не полностью - запустите установку снова
    call :wait & exit /b 1
  )
  move /y "%MODELS%\model.part" "%MODEL%" >nul
  if not "!ERRORLEVEL!"=="0" ( echo [!] Cannot save model & call :wait & exit /b 1 )
  echo [OK] Модель скачана
)

REM 4. Словарь имён и терминов ШЧСМ.
REM    Без словаря имена ачарьев распознаются неверно - о провале молчать нельзя.
copy /Y "%~dp0..\glossary.txt" "%ROOT%\glossary.txt" >nul
if not "!ERRORLEVEL!"=="0" (
  echo [!] Не удалось установить словарь имён.
  echo     Распакуйте архив целиком и запустите установщик из папки "windows".
  call :wait & exit /b 1
)
echo [OK] Словарь установлен

REM 5. Простые папки на Рабочем столе + кнопка запуска рядом (всё в одном месте)
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); [Environment]::GetFolderPath('Desktop')"`) do set "TSH_DESKTOP=%%D"
if not defined TSH_DESKTOP set "TSH_DESKTOP=%USERPROFILE%\Desktop"
set "BASE_DIR=%TSH_DESKTOP%\Транскрибатор ШЧСМ"
if not exist "%BASE_DIR%\Положите аудио сюда" mkdir "%BASE_DIR%\Положите аудио сюда"
if not exist "%BASE_DIR%\Готовые тексты" mkdir "%BASE_DIR%\Готовые тексты"
copy /Y "%~dp02-Transcribe.bat" "%BASE_DIR%\ТРАНСКРИБИРОВАТЬ.bat" >nul 2>&1
if not exist "%BASE_DIR%\ТРАНСКРИБИРОВАТЬ.bat" (
  echo [!] Не удалось создать кнопку "ТРАНСКРИБИРОВАТЬ" на Рабочем столе.
  call :wait & exit /b 1
)
echo [OK] Папка "Транскрибатор ШЧСМ" создана на Рабочем столе

echo.
echo ==============================================
echo  ГОТОВО. Как пользоваться (три шага):
echo.
echo   На Рабочем столе появилась папка "Транскрибатор ШЧСМ".
echo   Внутри неё:
echo     1. "Положите аудио сюда"  - киньте туда лекцию или голосовое
echo     2. "ТРАНСКРИБИРОВАТЬ"     - дважды щёлкните по нему
echo     3. "Готовые тексты"       - заберите готовый текст
echo.
echo   Имя текста = имя вашего аудио + пометка "(транскрипция)".
echo   Например:  Лекция 5 июля.mp3  -^>  Лекция 5 июля (транскрипция).txt
echo ==============================================
if not "%SHCHSM_AUTOMATED%"=="1" start "" "%BASE_DIR%"
call :wait

exit /b 0

:wait
if not "%SHCHSM_AUTOMATED%"=="1" pause
exit /b 0
