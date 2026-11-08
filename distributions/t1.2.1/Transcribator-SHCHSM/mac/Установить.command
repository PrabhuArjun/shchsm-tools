#!/bin/bash
# Транскрибатор ШЧСМ — установка для macOS (двойной клик, один раз)
cd "$(dirname "$0")"
clear
echo "══════════════════════════════════════════════"
echo "   🎙  Транскрибатор ШЧСМ — установка (macOS)"
echo "══════════════════════════════════════════════"
echo ""

# PATH при двойном клике из Finder урезан — добавляем оба пути Homebrew явно
# (/opt/homebrew — Apple Silicon, /usr/local — Intel), иначе brew «не найден» на ровном месте.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

HOME_DIR="$HOME/.transcriber-shchsm"
MODEL_DIR="$HOME_DIR/models"
MODEL="$MODEL_DIR/ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
MODEL_MIN=1500000000   # ~1,5 ГБ. Реальная модель 1,62 ГБ; недокачанный файл ДОЛЖЕН отбраковываться
mkdir -p "$MODEL_DIR"

# 1. Homebrew (менеджер программ для Mac)
if ! command -v brew >/dev/null 2>&1; then
  echo "⚠️  Нужен Homebrew (бесплатный менеджер программ)."
  echo "   Открываю сайт установки — поставьте по инструкции и запустите этот файл снова."
  open "https://brew.sh" 2>/dev/null
  read -p "Enter — закрыть..." _; exit 0
fi
echo "✅ Homebrew есть"

# 2. Движок распознавания речи + конвертер аудио
echo "→ Ставлю движок (whisper) и конвертер (ffmpeg)…"
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp
brew list ffmpeg      >/dev/null 2>&1 || brew install ffmpeg
# Проверяем РЕЗУЛЬТАТ, а не факт запуска: молчаливый провал brew иначе даёт ложное «готово»
if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "❌ Движок распознавания не установился."
  echo "   Попробуйте выполнить вручную:  brew install whisper-cpp"
  read -p "Enter…" _; exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "❌ Конвертер аудио не установился."
  echo "   Попробуйте выполнить вручную:  brew install ffmpeg"
  read -p "Enter…" _; exit 1
fi
echo "✅ Движок и конвертер готовы"

# 3. Языковая модель (~1,5 ГБ, скачивается один раз)
# stat -L — идём ПО ССЫЛКЕ: у части машин модель — симлинк на общую копию,
# и без -L размер симлинка (~57 байт) выглядел бы как «модели нет» → перекачка поверх чужого файла.
CUR_SIZE=$(stat -Lf%z "$MODEL" 2>/dev/null || echo 0)
if [ -e "$MODEL" ] && [ "$CUR_SIZE" -ge "$MODEL_MIN" ]; then
  echo "✅ Модель уже скачана"
else
  if [ -e "$MODEL" ] && [ ! -L "$MODEL" ]; then
    echo "⚠️  Найдена неполная модель ($CUR_SIZE байт) — скачиваю заново."
    rm -f "$MODEL"
  fi
  echo "→ Скачиваю модель (~1,5 ГБ, один раз, может занять несколько минут)…"
  # Качаем во временный файл и переносим только целую — иначе обрыв связи оставит
  # битый файл, который при следующем запуске примут за готовый.
  TMP_MODEL="$MODEL_DIR/.model.part"
  rm -f "$TMP_MODEL"
  curl -L --fail -o "$TMP_MODEL" "$MODEL_URL" || {
    rm -f "$TMP_MODEL"
    echo "❌ Не скачалась модель — проверьте интернет и запустите снова"; read -p "Enter…" _; exit 1; }
  GOT=$(stat -Lf%z "$TMP_MODEL" 2>/dev/null || echo 0)
  if [ "$GOT" -lt "$MODEL_MIN" ]; then
    rm -f "$TMP_MODEL"
    echo "❌ Модель скачалась не полностью ($GOT байт) — запустите установку снова"
    read -p "Enter…" _; exit 1
  fi
  mv -f "$TMP_MODEL" "$MODEL"
  echo "✅ Модель скачана"
fi

# 4. Глоссарий имён и терминов ШЧСМ (без него имена ачарьев распознаются неверно —
#    молчать о провале нельзя, иначе преданный получит текст с искажёнными именами)
if ! cp "../glossary.txt" "$HOME_DIR/glossary.txt" 2>/dev/null; then
  echo "❌ Не удалось установить словарь имён (нет файла glossary.txt рядом с установщиком)."
  echo "   Распакуйте архив целиком и запустите установщик из папки «mac»."
  read -p "Enter…" _; exit 1
fi
echo "✅ Словарь имён и терминов установлен"

# 5. Простые папки на Рабочем столе + кнопка запуска рядом (всё в одном месте)
BASE_DIR="$HOME/Desktop/Транскрибатор ШЧСМ"
mkdir -p "$BASE_DIR/Положите аудио сюда" "$BASE_DIR/Готовые тексты"
if ! cp "Транскрибировать.command" "$BASE_DIR/ТРАНСКРИБИРОВАТЬ.command" 2>/dev/null; then
  echo "❌ Не удалось создать кнопку «ТРАНСКРИБИРОВАТЬ» на Рабочем столе."
  read -p "Enter…" _; exit 1
fi
chmod +x "$BASE_DIR/ТРАНСКРИБИРОВАТЬ.command" || {
  echo "❌ Кнопка создана, но не запускается (не удалось выдать права)."; read -p "Enter…" _; exit 1; }
echo "✅ Папка «Транскрибатор ШЧСМ» создана на Рабочем столе"
echo ""
echo "══════════════════════════════════════════════"
echo " ✅ ГОТОВО. Как пользоваться (три шага):"
echo ""
echo "   На Рабочем столе появилась папка «Транскрибатор ШЧСМ»."
echo "   Внутри неё:"
echo "     1. «Положите аудио сюда»  — киньте туда лекцию/голосовое/запись"
echo "     2. «ТРАНСКРИБИРОВАТЬ»     — дважды щёлкните по нему"
echo "     3. «Готовые тексты»       — заберите готовый текст"
echo ""
echo "   Имя текста = имя вашего аудио + пометка «(транскрипция)»."
echo "   Например:  Лекция 5 июля.mp3  →  Лекция 5 июля (транскрипция).txt"
echo "══════════════════════════════════════════════"
open "$BASE_DIR" 2>/dev/null
read -p "Enter — закрыть…" _
