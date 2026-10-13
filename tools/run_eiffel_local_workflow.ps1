<#
.SYNOPSIS
  EIFFEL local VS Code workflow: one task instead of manual chat commands.
.DESCRIPTION
  D:-drive R launcher, new timestamped outputs, QA. No Hmsc fits.
  Git pull is a separate prerequisite in VS Code tasks.
#>
param(
  [ValidateSet('BuildAndVerify','VerifyLatest','Audit','LockedWeather','Inspect')]
  [string]$Mode = 'VerifyLatest',
  [string]$DataRoot = 'D:\EIFFEL\data',
  [string]$RuntimeRoot = 'D:\EIFFEL_runtime'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $repo 'tools\run_eiffel_build.ps1'
$root = Join-Path $RuntimeRoot 'annual_pipeline_v3'
$verifyScript = Join-Path $repo 'R\validation\VERIFY_BUILT_ANNUAL_v1.R'
$lockedScript = Join-Path $repo 'R\validation\AUDIT_REUSE_LOCKED_WEATHER_v1.R'
$logs = Join-Path $RuntimeRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$logFile = Join-Path $logs ("EIFFEL_{0}_{1}_{2}.log" -f $Mode,(Get-Date -Format 'yyyyMMdd_HHmmss'),$PID)
$transcript = $false
try {
  Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
  $transcript = $true
} catch {
  Write-Warning 'PowerShell transcript could not start; output remains visible in VS Code.'
}
function Get-BuildFolders {
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $root -Directory -Filter 'build_*')
}
function Get-CompleteBuild {
  $folders = @(Get-BuildFolders | Where-Object {
     (Test-Path (Join-Path $_.FullName 'annual_site_species_flight_year.csv')) -and
     (Test-Path (Join-Path $_.FullName 'QA_SUMMARY.csv'))
  } | Sort-Object LastWriteTime -Descending)
  if ($folders.Count -eq 0) {
    throw "No completed build in $root. First run BuildAndVerify."
  }
  return $folders[0]
}
function Verify-Build([string]$path) {
  Write-Host ([Environment]::NewLine + "EIFFEL QA target: $path") -ForegroundColor Cyan
  $env:EIFFEL_AUDIT_BUILD_DIR = $path.Replace('\','/')
  & $launcher -Mode inspect -Script $verifyScript -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot
  if (-not (Test-Path (Join-Path $path 'LOCAL_VALIDATION_REPORT.csv'))) {
    throw "Expected QA report not written in $path"
  }
  $errors = @(Import-Csv (Join-Path $path 'LOCAL_VALIDATION_REPORT.csv') |
    Where-Object status -eq 'FAIL')
  if ($errors.Count -gt 0) {
    throw "$($errors.Count) validation checks failed; see LOCAL_VALIDATION_REPORT.md"
  }
  Write-Host "PASS: QA checks completed. Reports in: $path" -ForegroundColor Green
}
Push-Location $repo
try {
  switch ($Mode) {
    'BuildAndVerify' {
      $before = @(Get-BuildFolders | ForEach-Object FullName)
      Write-Host "Starting local EIFFEL WEATHER + optional FROST build; no Hmsc fits." -ForegroundColor Cyan
      & $launcher -Mode build -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot
      $after = @(Get-BuildFolders | Where-Object { $before -notcontains $_.FullName })
      if ($after.Count -ne 1) {
        throw "Expected exactly one new build; found $($after.Count). Verify output directories before continuing."
      }
      Verify-Build $after[0].FullName
    }
    'VerifyLatest' { $last = Get-CompleteBuild; Verify-Build $last.FullName }
    'Audit' { & $launcher -Mode audit -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot }
    'LockedWeather' {
      & $launcher -Mode inspect -Script $lockedScript -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot
    }
    'Inspect' { & $launcher -Mode inspect -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot }
  }
  Write-Host "EIFFEL task finished: $Mode. No Hmsc fitted." -ForegroundColor Green
} finally {
  Pop-Location
  if($transcript) { Stop-Transcript | Out-Null }
  Write-Host "Task log: $logFile"
}
