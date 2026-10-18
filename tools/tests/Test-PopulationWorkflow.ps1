# Synthetic execution tests of the existing entrypoint, never study data.
# Default: mock only the platform-specific temp wrapper, execute the real R stage.
# -UseRealWrapper (Windows CI): also execute the unchanged D:/temp-style wrapper.
param(
  [string]$Rscript = 'Rscript',
  [switch]$UseRealWrapper
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('eiffel_population_fixture_' + [guid]::NewGuid().ToString('N'))
$fixtureRepo = Join-Path $scratch 'repo'
$runtime = Join-Path $scratch 'runtime'
$data = Join-Path $scratch 'empty_data'
$root = Join-Path $runtime 'annual_pipeline_v3'
$build = Join-Path $root 'build_synthetic'
$derived = Join-Path $root 'population_history_v1'
$checks = 0
function Assert([bool]$condition, [string]$message) {
  if (-not $condition) { throw $message }
  $script:checks++
}
function Refuse([scriptblock]$action, [string]$message) {
  $failed = $false
  try { & $action *> $null } catch { $failed = $true }
  Assert $failed $message
}
function Snapshot([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  return (@(Get-ChildItem -LiteralPath $path -Recurse -Force | Sort-Object FullName | ForEach-Object {
    $hash = if ($_.PSIsContainer) { '' } else { (Get-FileHash -LiteralPath $_.FullName).Hash }
    '{0}|{1}|{2}' -f $_.FullName,$_.LastWriteTimeUtc.Ticks,$hash
  }) -join "`n")
}
function Histories { return @(Get-ChildItem -LiteralPath $derived -Directory -Filter 'history_*') }
$savedEnv = @{}
foreach ($name in @('EIFFEL_AUDIT_BUILD_DIR','EIFFEL_POP_HISTORY_OUT','EIFFEL_BUILD_OUT',
                     'EIFFEL_DATA','EIFFEL_EXPECTED_TEMP','TEMP','TMP','TMPDIR','EIFFEL_FROST_FILE')) {
  $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
  foreach ($relative in @('tools','R/population_dynamics','R/validation')) {
    New-Item -ItemType Directory -Path (Join-Path $fixtureRepo $relative) -Force | Out-Null
  }
  foreach ($relative in @('tools/run_eiffel_local_workflow.ps1',
                          'R/population_dynamics/POPULATION_HISTORY_v1.R',
                          'R/population_dynamics/BUILD_POPULATION_HISTORY_v1.R',
                          'R/validation/VERIFY_LOCAL_TEMP_ROOT_v1.R')) {
    Copy-Item -LiteralPath (Join-Path $repo $relative) -Destination (Join-Path $fixtureRepo $relative)
  }
  $workflow = Join-Path $fixtureRepo 'tools/run_eiffel_local_workflow.ps1'
  $runner = Join-Path $fixtureRepo 'R/population_dynamics/BUILD_POPULATION_HISTORY_v1.R'
  $module = Join-Path $fixtureRepo 'R/population_dynamics/POPULATION_HISTORY_v1.R'
  # A forgotten -Script must fail here; the upstream builder is NEVER copied.
  Set-Content -LiteralPath (Join-Path $fixtureRepo 'R/build_six_species_annual_v3.R') -Value 'stop("FORBIDDEN annual build")'
  if ($UseRealWrapper) {
    Copy-Item -LiteralPath (Join-Path $repo 'tools/run_eiffel_build.ps1') -Destination (Join-Path $fixtureRepo 'tools/run_eiffel_build.ps1')
  } else {
    @'
param($Mode, $Script = 'FORBIDDEN_DEFAULT_ANNUAL', $DataRoot, $RuntimeRoot, $Rscript, $MinFreeGB)
$ErrorActionPreference = 'Stop'
if ($Mode -cne 'build' -or (Split-Path -Leaf $Script) -cne 'BUILD_POPULATION_HISTORY_v1.R') {
  throw 'FORBIDDEN: omitted population script or unexpected upstream mode'
}
$env:EIFFEL_BUILD_OUT = (Join-Path $RuntimeRoot 'annual_pipeline_v3').Replace('\','/')
& $Rscript --vanilla $Script --build
if ($LASTEXITCODE -ne 0) { throw 'Synthetic population R stage failed' }
'@ | Set-Content -LiteralPath (Join-Path $fixtureRepo 'tools/run_eiffel_build.ps1')
  }
  $options = @{ RuntimeRoot = $runtime; DataRoot = $data; Rscript = $Rscript; MinFreeGB = 0 }
  & $workflow @options *> $null
  Assert (-not (Test-Path -LiteralPath $runtime)) 'Default status created runtime/logs or called R'
  New-Item -ItemType Directory -Path $build,$data -Force | Out-Null
  $fixture = Join-Path $scratch 'make_fixture.R'
  @'
args <- commandArgs(TRUE)
source(args[1])
a <- expand.grid(site = c('SYNTHETIC_A', 'SYNTHETIC_B'), year = 2020:2023,
                 species = unname(population_species_v1), stringsAsFactors = FALSE)
a$annual_count <- rep(0:7, length.out = nrow(a))
a$n_sampling_intervals <- 4L
a$n_unknown_effort_intervals <- 0L
a$effort_days <- 28
a$annual_count_per_7d <- a$annual_count / 4
a$n_unknown_effort_intervals[2] <- 1L
a$effort_days[2] <- a$annual_count_per_7d[2] <- NA_real_
write.csv(a, file.path(args[2], 'annual_site_species_flight_year.csv'), row.names = FALSE)
write.csv(data.frame(check='synthetic', value=1), file.path(args[2], 'QA_SUMMARY.csv'), row.names=FALSE)
qa <- data.frame(check=c('annual_counts_reconcile_after_exact_dedup','true_observed_zeros',
                         'unknown_effort_is_not_invented','scientific_qa_pending'),
                 status=c('PASS','PASS','PASS','REVIEW'))
write.csv(qa, file.path(args[2], 'LOCAL_VALIDATION_REPORT.csv'), row.names=FALSE)
'@ | Set-Content -LiteralPath $fixture
  & $Rscript --vanilla $fixture $module $build
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic fixture setup failed' }
  $qaFile = Join-Path $build 'LOCAL_VALIDATION_REPORT.csv'
  $annual = Join-Path $build 'annual_site_species_flight_year.csv'
  $qaOriginal = [IO.File]::ReadAllText($qaFile)
  $annualOriginal = [IO.File]::ReadAllText($annual)
  $before = Snapshot $runtime
  & $workflow @options *> $null
  $afterStatus = Snapshot $runtime
  if ($afterStatus -cne $before) {
    # Synthetic fixture only: identify the changed path or timestamp on Windows CI.
    $originalLines = @($before -split "`n")
    $currentLines = @($afterStatus -split "`n")
    Write-Host ("STATUS SNAPSHOT DIAGNOSTIC: before={0} entries; after={1} entries" -f $originalLines.Count,$currentLines.Count)
    @(Compare-Object -ReferenceObject $originalLines -DifferenceObject $currentLines) |
      Select-Object -First 20 | ForEach-Object {
        Write-Host ("STATUS SNAPSHOT DIFF {0}: {1}" -f $_.SideIndicator,$_.InputObject)
      }
  }
  Assert ($afterStatus -ceq $before) 'Status wrote files or logs'
  # Status must not parse the annual data, even if it is deliberately unreadable as CSV.
  [IO.File]::WriteAllText($annual, 'NOT_AN_ANNUAL_CSV')
  $before = Snapshot $runtime
  & $workflow @options *> $null
  Assert ((Snapshot $runtime) -ceq $before) 'Status touched annual content'
  [IO.File]::WriteAllText($annual, $annualOriginal)
  foreach ($badQa in @($qaOriginal.Replace('PASS','FAIL'),
                       $qaOriginal.Replace('PASS','UNKNOWN'),
                       ($qaOriginal + '"true_observed_zeros","REVIEW"' + "`n"),
                       'wrong,schema')) {
    [IO.File]::WriteAllText($qaFile, $badQa)
    $before = Snapshot $runtime
    & $workflow @options *> $null
    Assert ((Snapshot $runtime) -ceq $before) 'Blocked status wrote files'
    Refuse { & $workflow -Mode PopulationHistory @options } 'Missing/failed/ambiguous QA did not block derivation'
    Assert (-not (Test-Path -LiteralPath $derived)) 'Blocked QA launched R or created history'
  }
  Remove-Item -LiteralPath $qaFile
  Refuse { & $workflow -Mode PopulationHistory @options } 'Absent QA did not block'
  [IO.File]::WriteAllText($qaFile, $qaOriginal)
  $sourceBefore = Snapshot $build
  & $workflow -Mode PopulationHistory @options *> $null
  $first = @(Histories)
  Assert ($first.Count -eq 1) 'Explicit mode failed to create exactly one history'
  Assert ((Snapshot $build) -ceq $sourceBefore) 'Annual source or QA was modified'
  $firstSnapshot = Snapshot $first[0].FullName
  $before = Snapshot $runtime
  & $workflow @options *> $null
  Assert ((Snapshot $runtime) -ceq $before) 'Status of a completed output wrote files'
  # Prove reuse does not launch even the selected R script.
  $noR = @{} + $options
  $noR.Rscript = Join-Path $scratch 'FORBIDDEN_R_EXECUTABLE'
  & $workflow -Mode PopulationHistory @noR *> $null
  Assert (@(Histories).Count -eq 1) 'Identical output was not reused'
  Assert ((Snapshot $first[0].FullName) -ceq $firstSnapshot) 'Reuse overwrote completed output'
  # MD5 hex comparisons must work with the uppercase form returned by Get-FileHash.
  $hashFile = Join-Path $first[0].FullName 'OUTPUT_HASHES.csv'
  $hashes = @(Import-Csv -LiteralPath $hashFile)
  $hashes | ForEach-Object { $_.md5 = $_.md5.ToUpperInvariant() }
  $hashes | Export-Csv -LiteralPath $hashFile -NoTypeInformation
  & $workflow -Mode PopulationHistory @noR *> $null
  Assert (@(Histories).Count -eq 1) 'Case-insensitive MD5 reuse failed'
  # Changed QA (still arithmetically PASS) invalidates the cached provenance.
  Add-Content -LiteralPath $qaFile -Value '"additional_synthetic_review","REVIEW"'
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 2) 'Changed QA did not create a new version'
  # Changed module and runner, unchanged prior outputs.
  Add-Content -LiteralPath $module -Value '# synthetic cache invalidation'
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 3) 'Changed module did not invalidate cache'
  Add-Content -LiteralPath $runner -Value '# synthetic cache invalidation'
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 4) 'Changed runner did not invalidate cache'
  $change = Join-Path $scratch 'change_synthetic_input.R'
  @'
p <- commandArgs(TRUE)[1]
a <- read.csv(p, stringsAsFactors=FALSE)
a$annual_count[1] <- a$annual_count[1] + 1L
a$annual_count_per_7d[1] <- 7 * a$annual_count[1] / a$effort_days[1]
write.csv(a, p, row.names=FALSE)
'@ | Set-Content -LiteralPath $change
  & $Rscript --vanilla $change $annual
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic input update failed' }
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 5) 'Changed annual source did not invalidate cache'
  $latest = @(Histories | Sort-Object LastWriteTime -Descending)[0]
  $tampered = Join-Path $latest.FullName 'population_lag_coverage_LOCAL.csv'
  Add-Content -LiteralPath $tampered -Value '# synthetic corrupt output'
  $tamperedSnapshot = Snapshot $latest.FullName
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 6) 'Corrupt output was incorrectly reused'
  Assert ((Snapshot $latest.FullName) -ceq $tamperedSnapshot) 'Corrupt prior artifact was overwritten'
  $latest = @(Histories | Sort-Object LastWriteTime -Descending)[0]
  Remove-Item -LiteralPath (Join-Path $latest.FullName 'COMPLETE.txt')
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 7) 'Missing completion marker was accepted'
  $latest = @(Histories | Sort-Object LastWriteTime -Descending)[0]
  $hashFile = Join-Path $latest.FullName 'OUTPUT_HASHES.csv'
  $hashes = @(Import-Csv -LiteralPath $hashFile)
  $hashes[0].filename = '../FORBIDDEN.csv'
  $hashes | Export-Csv -LiteralPath $hashFile -NoTypeInformation
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 8) 'Non-allowlisted cache filename was accepted'
  $latest = @(Histories | Sort-Object LastWriteTime -Descending)[0]
  Set-Content -LiteralPath (Join-Path $latest.FullName 'COMPLETE.txt') -Value 'complete_derived_only_not_scientific_model_approval'
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 9) 'Incorrect completion marker was accepted'
  # Exercise runner refusal without the PowerShell QA precheck, with synthetic data only.
  $env:EIFFEL_AUDIT_BUILD_DIR = $build.Replace('\','/')
  $env:EIFFEL_BUILD_OUT = $root.Replace('\','/')
  $env:EIFFEL_POP_HISTORY_OUT = $first[0].FullName.Replace('\','/')
  function Refuse-R([string[]]$arguments) {
    $failed = $false
    try { & $Rscript --vanilla $runner @arguments *> $null; $failed = $LASTEXITCODE -ne 0 }
    catch { $failed = $true }
    Assert $failed 'R runner failed to refuse unsafe invocation'
  }
  Refuse-R @() # Missing explicit --build
  Refuse-R @('--build') # Existing destination
  $env:EIFFEL_POP_HISTORY_OUT = (Join-Path $scratch 'history_OUTSIDE_RUNTIME').Replace('\','/')
  Refuse-R @('--build')
  $env:EIFFEL_POP_HISTORY_OUT = (Join-Path $derived 'history_bad_qa').Replace('\','/')
  [IO.File]::WriteAllText($qaFile, $qaOriginal + '"true_observed_zeros","REVIEW"' + "`n")
  Refuse-R @('--build')
  Assert (-not (Test-Path -LiteralPath $env:EIFFEL_POP_HISTORY_OUT)) 'R QA refusal left output'
  Assert (-not (Test-Path -LiteralPath (Join-Path $scratch 'history_OUTSIDE_RUNTIME'))) 'R wrote outside runtime'
  [IO.File]::WriteAllText($qaFile, $qaOriginal)
  $allUnknown = Join-Path $scratch 'all_unknown_effort.R'
  @'
p <- commandArgs(TRUE)[1]
a <- read.csv(p, stringsAsFactors=FALSE)
a$n_unknown_effort_intervals <- 1L
a$effort_days <- a$annual_count_per_7d <- NA_real_
write.csv(a, p, row.names=FALSE)
'@ | Set-Content -LiteralPath $allUnknown
  & $Rscript --vanilla $allUnknown $annual
  if ($LASTEXITCODE -ne 0) { throw 'Synthetic all-unknown fixture failed' }
  & $workflow -Mode PopulationHistory @options *> $null
  Assert (@(Histories).Count -eq 10) 'All-NA effort/rate CSV was not parsed with numeric types'
  $latest = @(Histories | Sort-Object LastWriteTime -Descending)[0]
  $localHistory = @(Import-Csv -LiteralPath (Join-Path $latest.FullName 'population_history_lag1to3_LOCAL.csv'))
  Assert (@($localHistory | Where-Object { $_.annual_count -eq '' }).Count -eq 0) 'Unknown effort discarded observed counts'
  Assert (@($localHistory | Where-Object { $_.annual_count_per_7d -ne '' }).Count -eq 0) 'Unknown effort created comparable rates'
  Write-Host "PASS: $checks synthetic workflow assertions; real R stage; real temp wrapper=$UseRealWrapper. No study data or models."
} finally {
  foreach ($name in $savedEnv.Keys) {
    [Environment]::SetEnvironmentVariable($name, $savedEnv[$name], 'Process')
  }
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
