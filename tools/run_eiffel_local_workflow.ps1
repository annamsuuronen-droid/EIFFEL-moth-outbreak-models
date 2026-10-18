<#
.SYNOPSIS
  EIFFEL local VS Code workflow: one task instead of manual chat commands.
.DESCRIPTION
  D:-drive R launcher, new timestamped outputs, QA. No Hmsc fits.
  Git pull is a separate prerequisite in VS Code tasks.
#>
param(
  [ValidateSet('PopulationStatus','PopulationHistory','BuildAndVerify','VerifyLatest','Audit','LockedWeather','Inspect')]
  [string]$Mode = 'PopulationStatus',
  [string]$DataRoot = 'D:\EIFFEL\data',
  [string]$RuntimeRoot = 'D:\EIFFEL_runtime',
  [string]$Rscript = '',
  [ValidateRange(0, 10000)] [int]$MinFreeGB = 50
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $repo 'tools\run_eiffel_build.ps1'
$runtimeOptions = @{ MinFreeGB = $MinFreeGB }
if (-not [string]::IsNullOrWhiteSpace($Rscript)) { $runtimeOptions.Rscript = $Rscript }
$root = Join-Path $RuntimeRoot 'annual_pipeline_v3'
$verifyScript = Join-Path $repo 'R\validation\VERIFY_BUILT_ANNUAL_v1.R'
$lockedScript = Join-Path $repo 'R\validation\AUDIT_REUSE_LOCKED_WEATHER_v1.R'
$populationScript = Join-Path $repo 'R\population_dynamics\BUILD_POPULATION_HISTORY_v1.R'
$populationModule = Join-Path $repo 'R\population_dynamics\POPULATION_HISTORY_v1.R'
$populationRoot = Join-Path $root 'population_history_v1'
$logs = Join-Path $RuntimeRoot 'logs'
# The default status mode is genuinely read-only: no logs or output folders.
$logFile = $null
$transcript = $false
if ($Mode -ne 'PopulationStatus') {
  New-Item -ItemType Directory -Force -Path $logs | Out-Null
  $logFile = Join-Path $logs ("EIFFEL_{0}_{1}_{2}_{3}.log" -f $Mode,(Get-Date -Format 'yyyyMMdd_HHmmss'),$PID,([guid]::NewGuid().ToString('N')))
  try {
    Start-Transcript -Path $logFile -ErrorAction Stop | Out-Null
    $transcript = $true
  } catch {
    Write-Warning 'PowerShell transcript could not start; output remains visible in VS Code.'
  }
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
    throw "BLOCKED: No completed build in $root. No upstream computation started."
  }
  return $folders[0]
}
function Verify-Build([string]$path) {
  Write-Host ([Environment]::NewLine + "EIFFEL QA target: $path") -ForegroundColor Cyan
  $env:EIFFEL_AUDIT_BUILD_DIR = $path.Replace('\','/')
  & $launcher -Mode inspect -Script $verifyScript -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions
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
# No raw study source is opened in status mode: only folder names/QA presence.
function Show-PopulationStatus {
  $folders = @(Get-BuildFolders | Where-Object {
    (Test-Path (Join-Path $_.FullName 'annual_site_species_flight_year.csv')) -and
    (Test-Path (Join-Path $_.FullName 'QA_SUMMARY.csv'))
  } | Sort-Object LastWriteTime -Descending)
  if ($folders.Count -eq 0) {
    Write-Host 'BLOCKED: No existing complete six-species annual build. No rebuild started.'
    return
  }
  $latest = $folders[0].FullName
  $qaFile = Join-Path $latest 'LOCAL_VALIDATION_REPORT.csv'
  Write-Host "Existing annual build: $latest"
  if (-not (Test-Path -LiteralPath $qaFile -PathType Leaf)) {
    Write-Host 'BLOCKED: Local annual validation report missing. No QA rerun started.'
    return
  }
  try { Assert-ApprovedAnnual $latest } catch {
    Write-Host ("BLOCKED: {0} No QA rerun started." -f $_.Exception.Message)
    return
  }
  Write-Host 'REUSE: Existing annual arithmetic/zero/effort QA gates passed (not scientific approval).'
  if (-not (Test-Path -LiteralPath $populationRoot -PathType Container)) {
    Write-Host 'NEW: Population-history output not present; run PopulationHistory explicitly if needed.'
    return
  }
  $derived = @(Get-ChildItem -LiteralPath $populationRoot -Directory -Filter 'history_*' |
     Where-Object { Test-Path (Join-Path $_.FullName 'COMPLETE.txt') })
  Write-Host ("Population-history completed output folders: {0}; source/hash reuse verified only in explicit PopulationHistory mode." -f $derived.Count)
}
function Assert-ApprovedAnnual([string]$path) {
  $qa = Join-Path $path 'LOCAL_VALIDATION_REPORT.csv'
  if (-not (Test-Path -LiteralPath $qa -PathType Leaf)) {
    throw 'Saved annual QA is missing. Do not auto-run VerifyLatest or BuildAndVerify.'
  }
  $checks = @(Import-Csv -LiteralPath $qa)
  if ($checks.Count -eq 0 -or
      $checks[0].PSObject.Properties.Name -notcontains 'check' -or
      $checks[0].PSObject.Properties.Name -notcontains 'status' -or
      @($checks | Where-Object { [string]::IsNullOrWhiteSpace($_.check) -or
        @('PASS','REVIEW','FAIL') -cnotcontains $_.status }).Count -gt 0) {
    throw 'Saved annual QA has an invalid schema or status; stopped.'
  }
  if ($checks.status -contains 'FAIL') { throw 'Existing annual QA contains FAIL; stopped.' }
  foreach ($key in @('annual_counts_reconcile_after_exact_dedup',
                       'true_observed_zeros', 'unknown_effort_is_not_invented')) {
    $gate = @($checks | Where-Object { $_.check -ceq $key })
    if ($gate.Count -ne 1 -or $gate[0].status -cne 'PASS') {
      throw "Missing/ambiguous mandatory PASS gate: $key"
    }
  }
}
function File-Md5([string]$path) {
  (Get-FileHash -LiteralPath $path -Algorithm MD5).Hash.ToLowerInvariant()
}
function Find-ReusablePopulationHistory([string]$annualSource) {
  if (-not (Test-Path -LiteralPath $populationRoot -PathType Container)) { return $null }
  $annualHash = File-Md5 $annualSource
  $qaHash = File-Md5 (Join-Path (Split-Path -Parent $annualSource) 'LOCAL_VALIDATION_REPORT.csv')
  $moduleHash = File-Md5 $populationModule
  $runnerHash = File-Md5 $populationScript
  foreach ($folder in @(Get-ChildItem -LiteralPath $populationRoot -Directory -Filter 'history_*' |
                       Sort-Object LastWriteTime -Descending)) {
    $manifestFile = Join-Path $folder.FullName 'POPULATION_HISTORY_MANIFEST.csv'
    $hashFile = Join-Path $folder.FullName 'OUTPUT_HASHES.csv'
    $complete = Join-Path $folder.FullName 'COMPLETE.txt'
    if (-not ((Test-Path $manifestFile) -and (Test-Path $hashFile) -and
               (Test-Path $complete))) { continue }
    $marker = @(Get-Content -LiteralPath $complete)
    if ($marker.Count -ne 1 -or $marker[0] -cne
        'COMPLETE_DERIVED_ONLY_NOT_SCIENTIFIC_MODEL_APPROVAL') { continue }
    $manifest = @{}
    $entries = @(Import-Csv -LiteralPath $manifestFile)
    if (@($entries | Group-Object item | Where-Object Count -ne 1).Count -gt 0) { continue }
    foreach ($entry in $entries) {
      $manifest[$entry.item] = $entry.value
    }
    if (($manifest['annual_source_md5'] -ne $annualHash) -or
        ($manifest['annual_qa_md5'] -ne $qaHash) -or
        ($manifest['population_module_md5'] -ne $moduleHash) -or
        ($manifest['population_runner_md5'] -ne $runnerHash) -or
        ($manifest['status'] -cne 'DERIVED_ONLY_LOCAL_QA_NOT_MODEL_VALIDATION')) { continue }
    $hashes = @(Import-Csv -LiteralPath $hashFile)
    if ($hashes.Count -ne 3) { continue }
    $expectedNames = @('population_history_lag1to3_LOCAL.csv',
                       'population_lag_coverage_LOCAL.csv',
                       'POPULATION_HISTORY_MANIFEST.csv')
    $uniqueNames = @($hashes | Select-Object -ExpandProperty filename -Unique)
    if ($uniqueNames.Count -ne 3 -or
        @($hashes | Where-Object { $expectedNames -cnotcontains $_.filename }).Count -gt 0) { continue }
    $valid = $true
    foreach ($h in $hashes) {
      $path = Join-Path $folder.FullName $h.filename
      if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
          $h.md5 -notmatch '^[0-9a-fA-F]{32}$' -or
          (File-Md5 $path) -ne $h.md5) {
        $valid = $false
        break
      }
    }
    if ($valid) { return $folder.FullName }
  }
  return $null
}
function Build-PopulationHistory {
  $build = Get-CompleteBuild
  Assert-ApprovedAnnual $build.FullName
  if (-not (Test-Path -LiteralPath $populationScript -PathType Leaf) -or
      -not (Test-Path -LiteralPath $populationModule -PathType Leaf)) {
    throw 'Population history R modules are missing; do not rebuild upstream annual data.'
  }
  $annual = Join-Path $build.FullName 'annual_site_species_flight_year.csv'
  $reused = Find-ReusablePopulationHistory $annual
  if ($reused) {
    Write-Host "REUSE: Verified population-history output unchanged: $reused" -ForegroundColor Green
    return
  }
  # Explicit new lightweight DERIVED stage, never R/build_six_species_annual_v3.R.
  # R wrapper enforces D:-temp guard and runs only the selected population script.
  $destination = Join-Path $populationRoot ("history_{0}_{1}_{2}" -f
      (Get-Date -Format 'yyyyMMdd_HHmmss'),$PID,([guid]::NewGuid().ToString('N')))
  if (Test-Path -LiteralPath $destination) { throw 'Output exists; refusing overwrite.' }
  $previousBuild = $env:EIFFEL_AUDIT_BUILD_DIR
  $previousOutput = $env:EIFFEL_POP_HISTORY_OUT
  try {
    $env:EIFFEL_AUDIT_BUILD_DIR = $build.FullName.Replace('\','/')
    $env:EIFFEL_POP_HISTORY_OUT = $destination.Replace('\','/')
    & $launcher -Mode build -Script $populationScript -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions
    if ((Find-ReusablePopulationHistory $annual) -ne $destination) {
      throw 'Population-history output failed completion/hash verification.'
    }
  } finally {
    $env:EIFFEL_AUDIT_BUILD_DIR = $previousBuild
    $env:EIFFEL_POP_HISTORY_OUT = $previousOutput
  }
  Write-Host "DONE: Population history only: $destination" -ForegroundColor Green
  Write-Host 'No Hmsc, old CV, source catches or existing annual build was rerun.'
}

Push-Location $repo
try {
  switch ($Mode) {
    'PopulationStatus' { Show-PopulationStatus }
    'PopulationHistory' { Build-PopulationHistory }
    'BuildAndVerify' {
      $before = @(Get-BuildFolders | ForEach-Object FullName)
      Write-Host "Starting local EIFFEL WEATHER + optional FROST build; no Hmsc fits." -ForegroundColor Cyan
      & $launcher -Mode build -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions
      $after = @(Get-BuildFolders | Where-Object { $before -notcontains $_.FullName })
      if ($after.Count -ne 1) {
        throw "Expected exactly one new build; found $($after.Count). Verify output directories before continuing."
      }
      Verify-Build $after[0].FullName
    }
    'VerifyLatest' { $last = Get-CompleteBuild; Verify-Build $last.FullName }
    'Audit' { & $launcher -Mode audit -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions }
    'LockedWeather' {
      & $launcher -Mode inspect -Script $lockedScript -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions
    }
    'Inspect' { & $launcher -Mode inspect -DataRoot $DataRoot -RuntimeRoot $RuntimeRoot @runtimeOptions }
  }
  if ($Mode -ne 'PopulationStatus') {
    Write-Host "EIFFEL task finished: $Mode. No Hmsc fitted." -ForegroundColor Green
  }
} finally {
  Pop-Location
  if($transcript) { Stop-Transcript | Out-Null }
  if ($logFile) { Write-Host "Task log: $logFile" }
}
