# Shared helpers: safe native process launch, downloads, hashing, Microsoft runtime check.
# Loaded by Install.ps1 through ScriptBlock.Create (no -File execution policy involved).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ProgressPreference = 'SilentlyContinue'

function ConvertTo-WinArg {
  param([string]$Value)
  if ($Value -eq '') { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

# Runs an executable with an argv array (no shell, no eval). Returns the exit code.
# Start-Process with redirected streams never raises NativeCommandError on stderr output.
function Invoke-Native {
  param([string]$FilePath, [string[]]$Arguments, [string]$StdoutPath, [string]$StderrPath)
  $argLine = (@($Arguments) | ForEach-Object { ConvertTo-WinArg $_ }) -join ' '
  $proc = Start-Process -FilePath $FilePath -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
  $proc.WaitForExit()
  if ($null -eq $proc.ExitCode) { return -1 }
  return [int]$proc.ExitCode
}

function Get-FileSha256 {
  param([string]$Path)
  $sha = [Security.Cryptography.SHA256]::Create()
  $stream = [IO.File]::OpenRead($Path)
  try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
  finally { $stream.Dispose(); $sha.Dispose() }
}

function Save-Download {
  param([string]$Url, [string]$Path)
  for ($i = 1; $i -le 3; $i++) {
    $wc = New-Object Net.WebClient
    try {
      $wc.Headers['User-Agent'] = 'TranscribatorSHCHSM-Installer'
      $wc.DownloadFile($Url, $Path)
      return
    } catch {
      Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
      if ($i -eq 3) { throw }
      Start-Sleep -Seconds 3
    } finally { $wc.Dispose() }
  }
}

function Test-Engine {
  param([string]$Root, [string]$BinDir)
  $exe = Join-Path $BinDir 'whisper-cli.exe'
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
  try {
    $code = Invoke-Native $exe @('--help') (Join-Path $Root 'engine-preflight.log') (Join-Path $Root 'engine-preflight.err.log')
    return ($code -eq 0)
  } catch {
    Write-Host ('[!] ' + $_.Exception.Message)
    return $false
  }
}

function Install-MicrosoftRuntime {
  param([string]$Root)
  $path = Join-Path $Root ('vc_redist_' + [guid]::NewGuid().ToString('N') + '.exe')
  try {
    Write-Host 'Устанавливаю библиотеки Microsoft. Если появится запрос Windows - подтвердите.'
    Save-Download 'https://aka.ms/vs/17/release/vc_redist.x64.exe' $path
    $sig = Get-AuthenticodeSignature -LiteralPath $path
    if ($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
      throw 'Microsoft signature validation failed'
    }
    $proc = Start-Process -FilePath $path -ArgumentList '/install', '/passive', '/norestart' -Wait -PassThru
    if (@(0, 1638, 3010) -notcontains $proc.ExitCode) { throw ('Runtime installation failed: ' + $proc.ExitCode) }
  } finally {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }
}

# Engine must start; if not, install the signed Microsoft runtime and re-check.
function Ensure-Runtime {
  param([string]$Root, [string]$BinDir)
  if (Test-Engine $Root $BinDir) { return }
  Install-MicrosoftRuntime $Root
  if (-not (Test-Engine $Root $BinDir)) { throw 'Движок не запустился после установки библиотек (см. engine-preflight.err.log).' }
}
