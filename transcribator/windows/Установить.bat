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
set "BIN=%ROOT%\bin"
set "MODELS=%ROOT%\models"
set "MODEL=%MODELS%\ggml-large-v3-turbo.bin"
if not exist "%BIN%" mkdir "%BIN%"
if not exist "%MODELS%" mkdir "%MODELS%"

REM 1. ffmpeg (конвертер аудио) через встроенный winget
where ffmpeg >nul 2>&1
if errorlevel 1 (
  echo -^> Ставлю ffmpeg через winget...
  winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
  REM После winget PATH в ТЕКУЩЕМ окне не обновляется — это нормально, нужен перезапуск.
  where ffmpeg >nul 2>&1
  if errorlevel 1 (
    echo.
    echo [!] ffmpeg установлен, но ещё не виден в этом окне.
    echo     Закройте это окно и запустите "Установить.bat" ещё раз - этого достаточно.
    pause & exit /b 1
  )
) else (
  echo [OK] ffmpeg уже есть
)

REM 2. Движок whisper.cpp (Windows-сборка). При смене версии — обновить ссылку.
if not exist "%BIN%\whisper-cli.exe" (
  echo -^> Скачиваю движок whisper.cpp...
  curl -L --fail -o "%ROOT%\whisper-bin.zip" "https://github.com/ggml-org/whisper.cpp/releases/latest/download/whisper-bin-x64.zip"
  if errorlevel 1 (
    echo [!] Не скачался движок. Скачайте whisper-bin-x64.zip со страницы
    echo     github.com/ggml-org/whisper.cpp/releases и распакуйте в "%BIN%"
    pause & exit /b 1
  ) else (
    powershell -command "Expand-Archive -Force '%ROOT%\whisper-bin.zip' '%BIN%'"
    del "%ROOT%\whisper-bin.zip"
  )
  REM Проверяем РЕЗУЛЬТАТ распаковки: иначе установка "успешна", а движка нет.
  if not exist "%BIN%\whisper-cli.exe" (
    echo [!] Движок скачан, но whisper-cli.exe не найден после распаковки.
    echo     Распакуйте whisper-bin-x64.zip вручную в "%BIN%" и запустите снова.
    pause & exit /b 1
  )
) else (
  echo [OK] Движок уже установлен
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
    del /f /q "%MODEL%" >nul 2>&1
  )
)
if defined MODEL_OK (
  echo [OK] Модель уже скачана
) else (
  echo -^> Скачиваю модель ~1,5 ГБ, один раз, несколько минут...
  curl -L --fail -o "%MODELS%\model.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
  if errorlevel 1 (
    del /f /q "%MODELS%\model.part" >nul 2>&1
    echo [!] Модель не скачалась - проверьте интернет и запустите снова
    pause & exit /b 1
  )
  for %%A in ("%MODELS%\model.part") do set "GOT=%%~zA"
  if !GOT! lss %MODEL_MIN% (
    del /f /q "%MODELS%\model.part" >nul 2>&1
    echo [!] Модель скачалась не полностью - запустите установку снова
    pause & exit /b 1
  )
  move /y "%MODELS%\model.part" "%MODEL%" >nul
  echo [OK] Модель скачана
)

REM 4. Словарь имён и терминов ШЧСМ.
REM    Без словаря имена ачарьев распознаются неверно - о провале молчать нельзя.
copy /Y "%~dp0..\glossary.txt" "%ROOT%\glossary.txt" >nul
if errorlevel 1 (
  echo [!] Не удалось установить словарь имён.
  echo     Распакуйте архив целиком и запустите установщик из папки "windows".
  pause & exit /b 1
)
echo [OK] Словарь установлен

REM 5. Простые папки на Рабочем столе + кнопка запуска рядом (всё в одном месте)
set "BASE_DIR=%USERPROFILE%\Desktop\Транскрибатор ШЧСМ"
if not exist "%BASE_DIR%\Положите аудио сюда" mkdir "%BASE_DIR%\Положите аудио сюда"
if not exist "%BASE_DIR%\Готовые тексты" mkdir "%BASE_DIR%\Готовые тексты"
copy /Y "%~dp0Транскрибировать.bat" "%BASE_DIR%\ТРАНСКРИБИРОВАТЬ.bat" >nul 2>&1
if not exist "%BASE_DIR%\ТРАНСКРИБИРОВАТЬ.bat" (
  echo [!] Не удалось создать кнопку "ТРАНСКРИБИРОВАТЬ" на Рабочем столе.
  pause & exit /b 1
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
start "" "%BASE_DIR%"
pause
