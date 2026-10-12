param(
  [ValidateSet('inspect','build')]
  [string]$Mode = 'inspect',
  [string]$Script = (Join-Path $PSScriptRoot '..\R\build_six_species_annual_v3.R'),
  [string]$DataRoot = 'D:\EIFFEL\data',
  [string]$RuntimeRoot = 'D:\EIFFEL_runtime',
  [string]$Rscript = 'D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe'
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
$vol = Get-PSDrive -Name D -ErrorAction Stop
if ($vol.Free -lt 50GB) { throw 'D:-asemalla alle 50 GB vapaana, ajo pysäytetty.' }
Write-Host "R temp: $temp"
Write-Host "Input data: $DataRoot"
Write-Host "Build outputs: $out"
& $Rscript --vanilla -e 'cat(tempdir(),"\n"); t <- normalizePath(tempdir(),winslash="/"); p <- normalizePath(Sys.getenv("TMPDIR"),winslash="/"); if(!startsWith(t,paste0(p,"/"))) stop("R temp folder is outside D: runtime root")'
if ($LASTEXITCODE -ne 0) { throw 'Temp-ympäristön R-tarkistus epäonnistui.' }
Push-Location (Split-Path -Parent $Script)
try {
  & $Rscript --vanilla $Script "--$Mode"
  if ($LASTEXITCODE -ne 0) { throw "R-skripti epäonnistui, exit code $LASTEXITCODE" }
} finally { Pop-Location }