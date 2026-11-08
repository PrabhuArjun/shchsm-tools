$ErrorActionPreference = 'Stop'
$runtimePath = Join-Path $env:ROOT 'vc_redist.x64.exe'
try {
  Write-Host 'Installing the Microsoft runtime. Confirm the Windows prompt if shown.'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $runtimePath
  $signature = Get-AuthenticodeSignature -LiteralPath $runtimePath
  if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Microsoft signature validation failed' }
  $process = Start-Process -FilePath $runtimePath -ArgumentList '/install','/passive','/norestart' -Wait -PassThru
  if ($process.ExitCode -notin @(0, 1638, 3010)) { throw "Runtime installation failed: $($process.ExitCode)" }
  Remove-Item -LiteralPath $runtimePath -Force
  exit 0
} catch {
  Write-Host $_.Exception.Message
  exit 1
}
