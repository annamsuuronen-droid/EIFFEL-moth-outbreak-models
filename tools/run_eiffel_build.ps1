param(
  [ValidateSet('inspect','build')]
  [string]$Mode = 'inspect',
  [string]$Script = (Join-Path $PSScriptRoot '..\R\build_six_species_annual_v3.R'),
  [string]$DataRoot = 'D:\EIFFEL\data',
  [string]$RuntimeRoot = 'D:\EIFFEL_runtime',
  [string]$Rscript = 'D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe',
  [string]$FrostFile = '',
  [ValidateRange(0, 10000)] [int]$MinFreeGB = 50,
  [switch]$TempCheckOnly
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Rscript -PathType Leaf)) { throw "Rscript puuttuu: $Rscript" }
if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw "R-skripti puuttuu: $Script" }
if (-not (Test-Path -LiteralPath $DataRoot -PathType Container)) { throw "Datakansio puuttuu: $DataRoot" }
$temp = Join-Path $RuntimeRoot 'temp\R'
$out = Join-Path $RuntimeRoot 'annual_pipeline_v3'
foreach ($dir in @($temp, $out, (Join-Path $RuntimeRoot 'logs'))) {
  New-Item -Path $dir -ItemType Directory -Force | Out-Null
}
$env:TEMP = $temp
$env:TMP = $temp
$env:TMPDIR = $temp
$env:EIFFEL_DATA = $DataRoot.Replace('\','/')
$env:EIFFEL_BUILD_OUT = $out.Replace('\','/')
if (-not [string]::IsNullOrWhiteSpace($FrostFile)) {
  if (-not (Test-Path -LiteralPath $FrostFile -PathType Leaf)) {
    throw "Frost source file missing: $FrostFile"
  }
  $env:EIFFEL_FROST_FILE = ([System.IO.Path]::GetFullPath($FrostFile)).Replace('\','/')
}
$runtimeDrive = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($RuntimeRoot)).Substring(0,1)
$vol = Get-PSDrive -Name $runtimeDrive -ErrorAction Stop
if ($MinFreeGB -gt 0 -and $vol.Free -lt ($MinFreeGB * 1GB)) {
  throw ("Ajolevylla {0}: on alle {1} GB vapaana, ajo pysaytetty." -f $runtimeDrive, $MinFreeGB)
}
Write-Host "R temp: $temp"
Write-Host "Input data: $DataRoot"
Write-Host "Build outputs: $out"
$env:EIFFEL_EXPECTED_TEMP = $temp.Replace('\','/')
$verify = Join-Path $PSScriptRoot '..\R\validation\VERIFY_LOCAL_TEMP_ROOT_v1.R'
if (-not (Test-Path -LiteralPath $verify -PathType Leaf)) { throw "R temp guard missing: $verify" }
& $Rscript --vanilla $verify
if ($LASTEXITCODE -ne 0) { throw 'Temp-ympariston R-tarkistus epaonnistui.' }
if ($TempCheckOnly) {
  Write-Host 'PASS: TempCheckOnly complete; no source data read and no Hmsc run.'
  return
}
Push-Location (Split-Path -Parent $Script)
try {
  & $Rscript --vanilla $Script "--$Mode"
  if ($LASTEXITCODE -ne 0) { throw "R-skripti epäonnistui, exit code $LASTEXITCODE" }
} finally { Pop-Location }