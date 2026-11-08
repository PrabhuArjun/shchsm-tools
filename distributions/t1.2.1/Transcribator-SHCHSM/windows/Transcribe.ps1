# Транскрибатор ШЧСМ - распознать аудио в текст (Windows PowerShell 5.1).
# Аргументы: пути к аудиофайлам (перетаскивание) ИЛИ без аргументов - папка "Положите аудио сюда".
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch {}

$Automated = ($env:SHCHSM_AUTOMATED -eq '1')
$Root = Join-Path $env:USERPROFILE '.transcriber-shchsm'
if ($Automated -and -not [string]::IsNullOrWhiteSpace($env:SHCHSM_TEST_ROOT)) { $Root = $env:SHCHSM_TEST_ROOT }
$ErrorLog = Join-Path $Root 'transcribe-errors.log'
$ModelSize = 1624555275
$Model = Join-Path $Root 'models\ggml-large-v3-turbo.bin'
$Wcli = Join-Path $Root 'bin\whisper-cli.exe'
$Language = 'ru'
if ($Automated -and $env:SHCHSM_LANGUAGE -eq 'en') { $Language = 'en' }

function Write-Failure {
  param([string]$Message)
  Write-Host ('[!] ' + $Message)
  try { Add-Content -LiteralPath $ErrorLog -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8 } catch {}
}

function ConvertTo-WinArg {
  param([string]$Value)
  if ($Value -eq '') { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

# argv array -> process, no shell. Redirected streams: stderr text never becomes a PowerShell error.
function Invoke-Native {
  param([string]$FilePath, [string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath)
  $argLine = (@($Arguments) | ForEach-Object { ConvertTo-WinArg $_ }) -join ' '
  $proc = Start-Process -FilePath $FilePath -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
  $proc.WaitForExit()
  if ($null -eq $proc.ExitCode) { return -1 }
  return [int]$proc.ExitCode
}

# Phrases whisper tends to invent on silence. They are only MARKED, never removed.
$SuspectPhrases = @('Продолжение следует', 'Спасибо за просмотр', 'Подписывайтесь на канал', 'Не забудьте подписаться',
  'Субтитры', 'DimaTorzok', 'KERCer', 'Субтитры создавал', 'Добро пожаловать в')

function Add-SuspectNote {
  param([string]$TxtPath)
  $text = [IO.File]::ReadAllText($TxtPath)
  $found = @($SuspectPhrases | Where-Object { $text.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
  if ($found.Count -eq 0) { return }
  $nl = [Environment]::NewLine
  $note = $nl + '-----------------------------' + $nl +
    '[!] ПРОВЕРЬТЕ ЭТИ МЕСТА при вычитке (сам текст НЕ изменён):' + $nl
  foreach ($p in $found) { $note += '  - ' + $p + $nl }
  $note += 'Чаще всего это музыка или киртан-интро в начале и конце - программа не' + $nl +
    'распознаёт пение и дописывает своё; настоящая лекция начинается после них.' + $nl +
    'Такие фразы программа иногда дописывает сама на тишине - но лектор мог' + $nl +
    'сказать это и по-настоящему. Решает человек, не программа.' + $nl
  [IO.File]::AppendAllText($TxtPath, $note, (New-Object Text.UTF8Encoding($false)))
  Write-Host '   [i] добавлена пометка о возможных машинных вставках'
}

# Never overwrites an earlier result: picks a free name and copies with overwrite = $false.
function Save-Result {
  param([string]$Outbox, [string]$Stem, [string]$TxtSource, [string]$SrtSource)
  for ($n = 1; $n -le 1000; $n++) {
    $final = Join-Path $Outbox $Stem
    if ($n -gt 1) { $final = $final + " ($n)" }
    $txt = $final + '.txt'
    $srt = $final + '.srt'
    if ((Test-Path -LiteralPath $txt) -or (Test-Path -LiteralPath $srt)) { continue }
    try { [IO.File]::Copy($TxtSource, $txt, $false) } catch [IO.IOException] { continue }
    try { [IO.File]::Copy($SrtSource, $srt, $false) } catch [IO.IOException] {
      Remove-Item -LiteralPath $txt -Force -ErrorAction SilentlyContinue
      continue
    }
    return $txt
  }
  throw 'Не удалось подобрать свободное имя результата'
}

function Convert-One {
  param([string]$Source)
  $name = [IO.Path]::GetFileName($Source)
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsh_' + [guid]::NewGuid().ToString('N'))
  $wav = $tmp + '.wav'
  Write-Host ('-> ' + $name + ' ...')
  try {
    $code = Invoke-Native $script:Ffmpeg @('-y', '-nostdin', '-i', $Source, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', $wav) ($tmp + '.decode.log') ($tmp + '.decode.err.log')
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $wav) -or (Get-Item -LiteralPath $wav).Length -eq 0) {
      throw ('DECODE_FAILED (код ' + $code + '). Журнал: ' + $tmp + '.decode.err.log')
    }
    # The engine writes the .txt/.srt itself (-of is the output base name).
    $code = Invoke-Native $Wcli @('-m', $Model, '-l', $Language, '-mc', '0', '-np', '--prompt', $script:Prompt, '-otxt', '-osrt', '-of', $tmp, '-f', $wav) ($tmp + '.raw') ($tmp + '.engine.log')
    if ($code -ne 0) { throw ('TRANSCRIBE_FAILED (код ' + $code + '). Журнал: ' + $tmp + '.engine.log') }
    foreach ($ext in @('.txt', '.srt')) {
      $f = $tmp + $ext
      if (-not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -eq 0) { throw ('MISSING_OUTPUT ' + $ext + '. Журнал: ' + $tmp + '.engine.log') }
    }
    if ([IO.File]::ReadAllText($tmp + '.txt') -notmatch '\p{L}') { throw 'EMPTY_TRANSCRIPT' }
    Add-SuspectNote ($tmp + '.txt')
    $saved = Save-Result $script:Outbox ([IO.Path]::GetFileNameWithoutExtension($name) + ' (транскрипция)') ($tmp + '.txt') ($tmp + '.srt')
    foreach ($ext in @('.wav', '.txt', '.srt', '.raw', '.decode.log', '.decode.err.log', '.engine.log')) {
      Remove-Item -LiteralPath ($tmp + $ext) -Force -ErrorAction SilentlyContinue
    }
    Write-Host ('   [OK] ' + $saved)
    return $true
  } catch {
    # Inputs and earlier results are never deleted; diagnostics stay in %TEMP%.
    Write-Failure ($name + ': ' + $_.Exception.Message)
    return $false
  }
}

function Start-Main {
  if (-not (Test-Path -LiteralPath $Model -PathType Leaf)) { Write-Failure 'Сначала запустите "1-Install.bat" (нет модели).'; return 1 }
  $size = (Get-Item -LiteralPath $Model).Length
  if ($size -ne $ModelSize) { Write-Failure ('Языковая модель неполная (' + $size + ' байт). Запустите "1-Install.bat" ещё раз.'); return 1 }
  if (-not (Test-Path -LiteralPath $Wcli -PathType Leaf)) { Write-Failure 'Движок не найден. Запустите "1-Install.bat".'; return 1 }

  $script:Ffmpeg = Join-Path $Root 'bin\ffmpeg.exe'
  if (-not (Test-Path -LiteralPath $script:Ffmpeg -PathType Leaf)) {
    $cmd = Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { Write-Failure 'ffmpeg не найден. Запустите "1-Install.bat".'; return 1 }
    $script:Ffmpeg = $cmd.Source
  }

  # First 16 non-comment glossary lines, joined with ". " (whisper copies the prompt's style).
  $glossary = Join-Path $Root 'glossary.txt'
  $lines = @()
  if (Test-Path -LiteralPath $glossary -PathType Leaf) {
    $lines = @([IO.File]::ReadAllLines($glossary) | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') } | Select-Object -First 16)
  }
  if ($lines.Count -eq 0) { Write-Failure 'Не найден словарь имён и терминов. Запустите "1-Install.bat" ещё раз.'; return 1 }
  $script:Prompt = $lines -join '. '

  $desktop = [Environment]::GetFolderPath('Desktop')
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
  $base = Join-Path $desktop 'Транскрибатор ШЧСМ'
  $inbox = Join-Path $base 'Положите аудио сюда'
  $script:Outbox = Join-Path $base 'Готовые тексты'
  [void][IO.Directory]::CreateDirectory($inbox)
  [void][IO.Directory]::CreateDirectory($script:Outbox)

  $count = 0; $failed = 0; $succeeded = 0
  if ($args.Count -gt 0) {
    foreach ($a in $args) {
      $count++
      $path = $null
      try {
        $path = [string]$a
        if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path (Get-Location).ProviderPath $path }
        $path = [IO.Path]::GetFullPath($path)
      } catch { $path = $null }
      if ($null -eq $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Failure ('FILE_NOT_FOUND: ' + $a)
        $failed++
        continue
      }
      if (Convert-One $path) { $succeeded++ } else { $failed++ }
    }
  } else {
    $exts = @('.mp3', '.m4a', '.ogg', '.opus', '.wav', '.mp4', '.aac')
    $files = @(Get-ChildItem -LiteralPath $inbox -File | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object Name)
    foreach ($f in $files) {
      $count++
      if (Convert-One $f.FullName) { $succeeded++ } else { $failed++ }
    }
  }

  if ($count -eq 0) {
    Write-Host 'Пока нечего распознавать.'
    Write-Host 'Положите аудио в папку: Рабочий стол - "Транскрибатор ШЧСМ" - "Положите аудио сюда"'
    if (-not $Automated) { Start-Process -FilePath 'explorer.exe' -ArgumentList (ConvertTo-WinArg $inbox) }
    return 0
  }
  if ($failed -gt 0) {
    Write-Failure ('FAILED: ' + $failed + '. Успешно: ' + $succeeded + '. См. ошибки выше (журнал: ' + $ErrorLog + ').')
    return 1
  }
  Write-Host ''
  Write-Host '=============================================='
  Write-Host ' Готово. Тексты - в папке "Готовые тексты"'
  Write-Host ' (Рабочий стол - "Транскрибатор ШЧСМ").'
  Write-Host ' Имя текста = имя аудио + пометка "(транскрипция)".'
  Write-Host '=============================================='
  if (-not $Automated) { Start-Process -FilePath 'explorer.exe' -ArgumentList (ConvertTo-WinArg $script:Outbox) }
  return 0
}

try {
  $rc = Start-Main @args
} catch {
  Write-Failure $_.Exception.Message
  $rc = 1
}
exit $rc
