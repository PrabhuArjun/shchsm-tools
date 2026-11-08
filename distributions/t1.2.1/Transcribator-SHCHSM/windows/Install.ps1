# Транскрибатор ШЧСМ - установщик (Windows PowerShell 5.1).
# Запускается из 1-Install.bat через ScriptBlock.Create; путь пакета - в $env:TSH_PACKAGE_ROOT.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false) } catch {}
Add-Type -AssemblyName System.IO.Compression.FileSystem

$PackageRoot = $env:TSH_PACKAGE_ROOT
if ([string]::IsNullOrWhiteSpace($PackageRoot)) { Write-Host '[!] TSH_PACKAGE_ROOT is not set'; exit 1 }
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$Automated = ($env:SHCHSM_AUTOMATED -eq '1')

$FfmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$EngineUrl = 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-bin-x64.zip'
$EngineSha256 = 'b1514ebc099765e39fa37eb780b92a140a94c86bb0b3b3d98226b38825979732'
$ModelUrl = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin'
$ModelSize = 1624555275
$ModelSha256 = '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69'

# Helpers (same ScriptBlock route as this script: no -File policy involved).
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $PackageRoot 'Ensure-Runtime.ps1'))))

function Get-TshRoot {
  if ($Automated -and -not [string]::IsNullOrWhiteSpace($env:SHCHSM_TEST_ROOT)) { return $env:SHCHSM_TEST_ROOT }
  return (Join-Path $env:USERPROFILE '.transcriber-shchsm')
}

function Expand-ZipEntry {
  param($Entry, [string]$Destination)
  $in = $Entry.Open()
  try {
    $out = [IO.File]::Create($Destination)
    try { $in.CopyTo($out) } finally { $out.Dispose() }
  } finally { $in.Dispose() }
}

function Install-Ffmpeg {
  param([string]$Root, [string]$BinDir)
  if (Test-Path -LiteralPath (Join-Path $BinDir 'ffmpeg.exe') -PathType Leaf) { Write-Host '[OK] ffmpeg уже установлен'; return }
  Write-Host '-> Скачиваю ffmpeg ~105 МБ, один раз, несколько минут...'
  $stage = Join-Path $Root ('stage_ffmpeg_' + [guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($stage)
  try {
    $zipPath = Join-Path $stage 'ffmpeg.zip'
    Save-Download $FfmpegUrl $zipPath
    Write-Host '-> Распаковываю...'
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
        $entry = @($zip.Entries | Where-Object { $_.Name -ieq $name } | Select-Object -First 1)
        if ($entry.Count -eq 0) {
          if ($name -eq 'ffmpeg.exe') { throw 'ffmpeg.exe не найден в архиве' }
          continue
        }
        Expand-ZipEntry $entry[0] (Join-Path $stage $name)
      }
    } finally { $zip.Dispose() }
    foreach ($name in @('ffprobe.exe', 'ffmpeg.exe')) {
      $f = Join-Path $stage $name
      if (Test-Path -LiteralPath $f -PathType Leaf) { Copy-Item -LiteralPath $f -Destination (Join-Path $BinDir $name) -Force }
    }
  } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  if (-not (Test-Path -LiteralPath (Join-Path $BinDir 'ffmpeg.exe') -PathType Leaf)) { throw 'ffmpeg.exe не найден после распаковки' }
  Write-Host '[OK] ffmpeg установлен'
}

function Install-Engine {
  param([string]$Root, [string]$BinDir)
  if (Test-Path -LiteralPath (Join-Path $BinDir 'whisper-cli.exe') -PathType Leaf) { Write-Host '[OK] Движок уже установлен'; return }
  Write-Host '-> Скачиваю движок whisper.cpp v1.8.2...'
  $stage = Join-Path $Root ('stage_engine_' + [guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($stage)
  try {
    $zipPath = Join-Path $stage 'engine.zip'
    Save-Download $EngineUrl $zipPath
    # SHA-256 is checked BEFORE anything is extracted.
    if ((Get-FileSha256 $zipPath) -ne $EngineSha256) { throw 'ENGINE_SHA256_MISMATCH' }
    $unpacked = Join-Path $stage 'unpacked'
    [void][IO.Directory]::CreateDirectory($unpacked)
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      $exes = @($zip.Entries | Where-Object { $_.Name -ieq 'whisper-cli.exe' })
      if ($exes.Count -ne 1) { throw 'ENGINE_EXE_MISSING_OR_AMBIGUOUS' }
      $prefix = $exes[0].FullName.Substring(0, $exes[0].FullName.Length - $exes[0].Name.Length)
      $dlls = @($zip.Entries | Where-Object {
        $_.Name -like '*.dll' -and $_.FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -and
        $_.FullName.Substring($prefix.Length).IndexOf('/') -lt 0
      })
      if ($dlls.Count -eq 0) { throw 'ENGINE_DLL_MISSING' }
      # Only leaf names are used for destinations, so archive paths cannot escape the staging folder.
      foreach ($d in $dlls) { Expand-ZipEntry $d (Join-Path $unpacked $d.Name) }
      Expand-ZipEntry $exes[0] (Join-Path $unpacked 'whisper-cli.exe')
    } finally { $zip.Dispose() }
    foreach ($f in @(Get-ChildItem -LiteralPath $unpacked -Filter '*.dll' -File)) { Copy-Item -LiteralPath $f.FullName -Destination $BinDir -Force }
    Copy-Item -LiteralPath (Join-Path $unpacked 'whisper-cli.exe') -Destination $BinDir -Force
  } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
  Write-Host '[OK] Движок установлен'
}

function Test-ModelFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  if ((Get-Item -LiteralPath $Path).Length -ne $ModelSize) { return $false }
  return ((Get-FileSha256 $Path) -eq $ModelSha256)
}

function Install-Model {
  param([string]$ModelsDir)
  $model = Join-Path $ModelsDir 'ggml-large-v3-turbo.bin'
  if (Test-ModelFile $model) { Write-Host '[OK] Модель уже скачана'; return }
  if (Test-Path -LiteralPath $model) { Write-Host '[!] Найденная модель неполная или повреждена - скачиваю заново.' }
  Write-Host '-> Скачиваю модель ~1,5 ГБ, один раз, несколько минут...'
  $part = Join-Path $ModelsDir ('model_' + [guid]::NewGuid().ToString('N') + '.part')
  try {
    Save-Download $ModelUrl $part
    $got = (Get-Item -LiteralPath $part).Length
    if ($got -ne $ModelSize) { throw "Модель скачалась не полностью ($got байт из $ModelSize)" }
    if ((Get-FileSha256 $part) -ne $ModelSha256) { throw 'MODEL_SHA256_MISMATCH' }
    # The previous file is replaced only now that the new one is fully validated.
    if (Test-Path -LiteralPath $model) { [IO.File]::Replace($part, $model, $null) } else { [IO.File]::Move($part, $model) }
  } finally { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
  Write-Host '[OK] Модель скачана'
}

function Write-Utf8Bom {
  param([string]$Source, [string]$Destination)
  $text = [IO.File]::ReadAllText($Source)
  [IO.File]::WriteAllText($Destination, $text, (New-Object Text.UTF8Encoding($true)))
}

function Install-Main {
  $root = Get-TshRoot
  $bin = Join-Path $root 'bin'
  $models = Join-Path $root 'models'
  [void][IO.Directory]::CreateDirectory($bin)
  [void][IO.Directory]::CreateDirectory($models)

  Write-Host '=============================================='
  Write-Host '   Транскрибатор ШЧСМ - установка (Windows)'
  Write-Host '=============================================='
  Write-Host ''

  Install-Ffmpeg $root $bin
  Install-Engine $root $bin
  Ensure-Runtime $root $bin
  Write-Host '[OK] Движок запускается'
  Install-Model $models

  # Glossary: failing silently would distort the names.
  $glossary = Join-Path (Split-Path -Parent $PackageRoot) 'glossary.txt'
  if (-not (Test-Path -LiteralPath $glossary -PathType Leaf)) { $glossary = Join-Path $PackageRoot 'glossary.txt' }
  if (-not (Test-Path -LiteralPath $glossary -PathType Leaf)) {
    throw 'Не найден словарь имён (glossary.txt). Распакуйте архив целиком и запустите установщик из папки "windows".'
  }
  Copy-Item -LiteralPath $glossary -Destination (Join-Path $root 'glossary.txt') -Force
  Write-Host '[OK] Словарь установлен'

  # Helpers: written as new local files (UTF-8 with BOM, no inherited Mark-of-the-Web).
  foreach ($name in @('Transcribe.ps1', 'Ensure-Runtime.ps1')) {
    $src = Join-Path $PackageRoot $name
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Не найден файл пакета: $name" }
    Write-Utf8Bom $src (Join-Path $root $name)
  }
  if (-not (Test-Path -LiteralPath (Join-Path $root 'Transcribe.ps1') -PathType Leaf)) { throw 'Transcribe.ps1 не установлен' }
  Write-Host '[OK] Скрипты установлены'

  # Desktop (native known folder: follows OneDrive redirection).
  $desktop = [Environment]::GetFolderPath('Desktop')
  if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = Join-Path $env:USERPROFILE 'Desktop' }
  $base = Join-Path $desktop 'Транскрибатор ШЧСМ'
  [void][IO.Directory]::CreateDirectory((Join-Path $base 'Положите аудио сюда'))
  [void][IO.Directory]::CreateDirectory((Join-Path $base 'Готовые тексты'))
  $launcherSrc = Join-Path $PackageRoot '2-Transcribe.bat'
  if (-not (Test-Path -LiteralPath $launcherSrc -PathType Leaf)) { throw 'Не найден 2-Transcribe.bat' }
  $launcher = Join-Path $base 'ТРАНСКРИБИРОВАТЬ.bat'
  Copy-Item -LiteralPath $launcherSrc -Destination $launcher -Force
  if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Не удалось создать кнопку "ТРАНСКРИБИРОВАТЬ" на Рабочем столе.' }
  Write-Host '[OK] Папка "Транскрибатор ШЧСМ" создана на Рабочем столе'

  Write-Host ''
  Write-Host '=============================================='
  Write-Host ' ГОТОВО. Как пользоваться (три шага):'
  Write-Host ''
  Write-Host '   На Рабочем столе появилась папка "Транскрибатор ШЧСМ".'
  Write-Host '   Внутри неё:'
  Write-Host '     1. "Положите аудио сюда"  - киньте туда лекцию или голосовое'
  Write-Host '     2. "ТРАНСКРИБИРОВАТЬ"     - дважды щёлкните по нему'
  Write-Host '     3. "Готовые тексты"       - заберите готовый текст'
  Write-Host ''
  Write-Host '   Имя текста = имя вашего аудио + пометка "(транскрипция)".'
  Write-Host '   Например:  Лекция 5 июля.mp3  ->  Лекция 5 июля (транскрипция).txt'
  Write-Host '=============================================='
  if (-not $Automated) { Start-Process -FilePath 'explorer.exe' -ArgumentList (ConvertTo-WinArg $base) }
}

try {
  Install-Main
} catch {
  Write-Host ('[!] ' + $_.Exception.Message)
  Write-Host '    Проверьте интернет и запустите установку снова.'
  exit 1
}
exit 0
