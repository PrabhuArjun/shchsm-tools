@echo off
chcp 65001 >nul
REM Транскрибатор ШЧСМ - распознать аудио в текст (Windows)
REM  Способ 1: перетащите аудиофайл(ы) на этот .bat.
REM  Способ 2 (обычный): положите аудио в папку "Положите аудио сюда"
REM  (Рабочий стол - "Транскрибатор ШЧСМ") и запустите этот файл двойным кликом.
REM  ⚠️ БЕТА: не проверено на живой Windows.
title Транскрибатор ШЧСМ
setlocal enabledelayedexpansion

set "ROOT=%USERPROFILE%\.transcriber-shchsm"
if "%SHCHSM_AUTOMATED%"=="1" if defined SHCHSM_TEST_ROOT set "ROOT=%SHCHSM_TEST_ROOT%"
set "MODEL=%ROOT%\models\ggml-large-v3-turbo.bin"
set "WCLI=%ROOT%\bin\whisper-cli.exe"
set "FFMPEG=%ROOT%\bin\ffmpeg.exe"
if not exist "%FFMPEG%" set "FFMPEG=ffmpeg"
REM Простые папки на Рабочем столе — вход и результат отдельно
for /f "usebackq delims=" %%D in (`powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[Text.UTF8Encoding]::new(); [Environment]::GetFolderPath('Desktop')"`) do set "TSH_DESKTOP=%%D"
if not defined TSH_DESKTOP set "TSH_DESKTOP=%USERPROFILE%\Desktop"
set "BASE_DIR=%TSH_DESKTOP%\Транскрибатор ШЧСМ"
set "INBOX=%BASE_DIR%\Положите аудио сюда"
set "OUTBOX=%BASE_DIR%\Готовые тексты"
if not exist "%INBOX%" mkdir "%INBOX%" >nul 2>&1
if not exist "%OUTBOX%" mkdir "%OUTBOX%" >nul 2>&1

REM Промпт-подсказка ИЗ единого glossary-файла (как mac) — НЕ хардкодим,
REM чтобы словарь не расходился с единым источником. Пропускаем #-комменты и пустые, первые 14.
REM ⚠️ 16 — не случайное число. Проверено на РЕАЛЬНОМ аудио лекций (20.07), не на синтетике.
REM    Первые ДВЕ строки словаря — ПАРА, разрывать нельзя:
REM    "Джай...Ки Джай" (произносимый возглас) + "Харе Кришна" (маха-мантра).
REM    Поодиночке они ИНТЕРФЕРИРУЮТ: возглас без маха-мантры превращает
REM    "Харе Кришна" в "Харина Кришна" - порча святого имени. Заданы ОБЕ - обе целы.
REM    Вредит не длина сама по себе, а непокрытая пара близких по звучанию форм:
REM    319 симв. с парой работают ЛУЧШЕ, чем 255 без неё. Но 430+ ломают пранаму в кашу.
REM ⚠️ РАЗДЕЛИТЕЛЬ «. » (точка+пробел), НЕ запятая: whisper копирует СТИЛЬ промпта.
REM    Через запятую расшифровка идёт сплошняком без точек и теряет слова. Менять — только с прогоном.
set "GLOSSARY=%ROOT%\glossary.txt"
set "PROMPT="
set /a GCOUNT=0
if exist "%GLOSSARY%" (
  for /f "usebackq tokens=* delims=" %%L in ("%GLOSSARY%") do (
    set "LINE=%%L"
    if !GCOUNT! lss 16 if not "!LINE:~0,1!"=="#" if not "!LINE!"=="" (
      if defined PROMPT (set "PROMPT=!PROMPT!. !LINE!") else (set "PROMPT=!LINE!")
      set /a GCOUNT+=1
    )
  )
)

if not exist "%MODEL%" (
  echo [!] Сначала запустите "1-Install.bat"
  call :wait & exit /b 1
)
REM Модель может быть недокачана - тогда движок падает с невнятной ошибкой
for %%A in ("%MODEL%") do set "MSIZE=%%~zA"
if !MSIZE! lss 1500000000 (
  echo [!] Языковая модель неполная ^(!MSIZE! байт^). Запустите "1-Install.bat" ещё раз.
  call :wait & exit /b 1
)
if not exist "%WCLI%" (
  echo [!] Движок не найден. Запустите "1-Install.bat"
  call :wait & exit /b 1
)
REM Без словаря имена ачарьев распознаются неверно - молчать об этом нельзя
if not defined PROMPT (
  echo [!] Не найден словарь имён и терминов.
  echo     Запустите "1-Install.bat" ещё раз - без словаря имена будут искажены.
  call :wait & exit /b 1
)

REM Собрать список: перетащенные файлы ИЛИ папка Входящие
set "COUNT=0"
set "FAILED=0"
set "SUCCEEDED=0"
set "TSH_RECOGNITION_LANGUAGE=ru"
if "%SHCHSM_AUTOMATED%"=="1" if "%SHCHSM_LANGUAGE%"=="en" set "TSH_RECOGNITION_LANGUAGE=en"
if not "%~1"=="" (
  for %%F in (%*) do call :one "%%~F"
) else (
  if not exist "%INBOX%" mkdir "%INBOX%"
  for %%F in ("%INBOX%\*.mp3" "%INBOX%\*.m4a" "%INBOX%\*.ogg" "%INBOX%\*.opus" "%INBOX%\*.wav" "%INBOX%\*.mp4" "%INBOX%\*.aac") do call :one "%%~F"
)
if "%COUNT%"=="0" (
  echo Пока нечего распознавать.
  echo Положите аудио в папку: Рабочий стол - "Транскрибатор ШЧСМ" - "Положите аудио сюда"
  if not "%SHCHSM_AUTOMATED%"=="1" start "" "%INBOX%"
  call :wait & exit /b 0
)
if not "%FAILED%"=="0" (
  echo [!] FAILED: %FAILED%. Successful: %SUCCEEDED%. Check errors above.
  call :wait
  exit /b 1
)
echo.
echo ══════════════════════════════════════════════
echo  Готово. Тексты - в папке "Готовые тексты"
echo  ^(Рабочий стол - "Транскрибатор ШЧСМ"^).
echo  Имя текста = имя аудио + пометка "(транскрипция)".
echo ══════════════════════════════════════════════
if not "%SHCHSM_AUTOMATED%"=="1" start "" "%OUTBOX%"
call :wait
exit /b 0

:one
if not exist "%~1" exit /b 0
if exist "%~1\" exit /b 0
set /a COUNT+=1
set "SRC=%~1"
set "STEM=%OUTBOX%\%~n1 (транскрипция)"
set "FINAL=%STEM%"
set "SUFFIX=1"
:choose_name
if exist "%FINAL%.txt" goto :next_name
if exist "%FINAL%.srt" goto :next_name
goto :name_ready
:next_name
set /a SUFFIX+=1
set "FINAL=%STEM% (%SUFFIX%)"
goto :choose_name
:name_ready
set "SRTOF=%TEMP%\tsh_%RANDOM%_%RANDOM%"
if exist "%SRTOF%.*" ( echo [!] Temporary filename collision & goto :failed )
set "TMP=%SRTOF%.wav"
set "OUT=%SRTOF%.txt"
echo -^> %~nx1 ...
"%FFMPEG%" -y -i "%SRC%" -ar 16000 -ac 1 -c:a pcm_s16le "%TMP%" > "%SRTOF%.decode.log" 2>&1
if not "!ERRORLEVEL!"=="0" ( echo [!] DECODE_FAILED & goto :failed )
REM Use the engine's text writer, not a possibly empty stdout stream.
"%WCLI%" -m "%MODEL%" -l %TSH_RECOGNITION_LANGUAGE% -mc 0 -np --prompt "%PROMPT%" -otxt -osrt -of "%SRTOF%" -f "%TMP%" > "%SRTOF%.raw" 2> "%SRTOF%.engine.log"
if not "!ERRORLEVEL!"=="0" ( echo [!] TRANSCRIBE_FAILED & goto :failed )
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { foreach ($ext in @('.txt','.srt')) { $f=$env:SRTOF+$ext; if (!(Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -eq 0) { throw 'MISSING_OUTPUT' } }; $text=[IO.File]::ReadAllText($env:OUT); if ($text -notmatch '\p{L}') { throw 'EMPTY_TRANSCRIPT' } } catch { Write-Host ('[!] '+$_.Exception.Message); exit 1 }"
if not "!ERRORLEVEL!"=="0" goto :failed

REM Машинные вставки: на тишине программа дописывает субтитровый мусор.
REM НЕ УДАЛЯЕМ - только ПОМЕЧАЕМ. На 47 реальных лекциях "Продолжение следует"
REM звучит 13 раз и часть из них - подлинная речь; повтор фразы - это киртан.
REM Пропущенный мусор вычитчик уберёт; молча удалённую речь - уже нет.
set "NOTES="
for %%J in ("Продолжение следует" "Спасибо за просмотр" "Подписывайтесь на канал" "Не забудьте подписаться" "Субтитры" "DimaTorzok" "KERCer" "Субтитры создавал" "Добро пожаловать в") do (
  findstr /i /c:%%~J "%OUT%" >nul 2>&1 && set "NOTES=!NOTES!  - %%~J!CRLF!"
)
if defined NOTES (
  >>"%OUT%" echo.
  >>"%OUT%" echo -----------------------------
  >>"%OUT%" echo [!] ПРОВЕРЬТЕ ЭТИ МЕСТА при вычитке ^(сам текст НЕ изменён^):
  for %%J in ("Продолжение следует" "Спасибо за просмотр" "Подписывайтесь на канал" "Не забудьте подписаться" "Субтитры" "DimaTorzok" "KERCer" "Субтитры создавал" "Добро пожаловать в") do (
    findstr /i /c:%%~J "%OUT%" >nul 2>&1 && >>"%OUT%" echo   - %%~J
  )
  >>"%OUT%" echo Чаще всего это музыка или киртан-интро в начале и конце - программа не
  >>"%OUT%" echo распознаёт пение и дописывает своё; настоящая лекция начинается после них.
  >>"%OUT%" echo Такие фразы программа иногда дописывает сама на тишине - но лектор мог
  >>"%OUT%" echo сказать это и по-настоящему. Решает человек, не программа.
  echo    [i] добавлена пометка о возможных машинных вставках
)
REM Never overwrite a user's previous transcript, including on a failed run.
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { [IO.File]::Copy($env:OUT,$env:FINAL+'.txt',$false); [IO.File]::Copy($env:SRTOF+'.srt',$env:FINAL+'.srt',$false) } catch { Write-Host ('[!] '+$_.Exception.Message); exit 1 }"
if not "!ERRORLEVEL!"=="0" goto :failed
del "%TMP%" "%SRTOF%.txt" "%SRTOF%.srt" "%SRTOF%.raw" "%SRTOF%.decode.log" "%SRTOF%.engine.log" >nul 2>&1
set /a SUCCEEDED+=1
echo    [OK] %FINAL%.txt
exit /b 0

:failed
set /a FAILED+=1
REM Inputs and existing results are never deleted. Keep diagnostics/partial output.
echo [!] Not completed. Diagnostic files: %SRTOF%.*
exit /b 1

:wait
if not "%SHCHSM_AUTOMATED%"=="1" pause
exit /b 0
