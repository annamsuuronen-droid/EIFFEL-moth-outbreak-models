#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repository=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script=Join-Path $repository 'tools\capture_completed_fold5.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
. $script
$allowOriginal=Join-Path $repository 'project_state\outer_year_cv_recovery_v1\LOCAL_EVIDENCE_ALLOWLIST.csv'
$rows=@(Read-Fold5AllowList $allowOriginal)
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('eiffel-f5-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
$count=0
function Assert([bool]$ok,[string]$message) { if (-not $ok) { throw "TEST FAILED: $message" } }
function Write-TestFile($path,$text) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path));[IO.File]::WriteAllText($path,$text) }
function Fixture($name) {
 $base=Join-Path $workspace $name;$src=Join-Path $base 'source';$repo=Join-Path $base 'repo'
 [void][IO.Directory]::CreateDirectory($src);[void][IO.Directory]::CreateDirectory($repo)
 $allow=Join-Path $repo 'project_state\outer_year_cv_recovery_v1\LOCAL_EVIDENCE_ALLOWLIST.csv'
 Write-TestFile $allow ([IO.File]::ReadAllText($allowOriginal))
 foreach($row in $rows) { Write-TestFile (Join-Path $src $row.relative_path.Replace('/','\')) 'SYNTHETIC FIXTURE ONLY' }
 Write-TestFile (Join-Path $src 'raw.csv') 'NEVER COPY'
 Write-TestFile (Join-Path $src 'hmsc_outputs\S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2\outer_year\fold_05\RECONSTRUCTED_r2\WEATHER_ONLY_FINAL_FIT.rds') 'NEVER READ/COPY'
 Write-TestFile (Join-Path $repo 'imported_local\sentinel') 'UNCHANGED'
 [pscustomobject]@{Source=$src;Repo=$repo;Allow=$allow;Target=(Join-Path $repo 'imported_fold5_completed_r2_v1')}
}
function Snapshot($path) { (@(Get-ChildItem -LiteralPath $path -File -Recurse | Sort-Object FullName | ForEach-Object { $_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks+'|'+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n") }
$mock={ param($source,$repo,$target)
 Write-TestFile (Join-Path $target 'checkpoint_verification.csv') "check,status`nsynthetic,PASS"
 Write-TestFile (Join-Path $target 'reconstructed_provenance_summary.csv') "field,value`nsynthetic,TEST_ONLY"
}
function Refuse($f,$pattern,$extractor=$mock) {
 $before=Snapshot $f.Source;$failed=$false
 try { Invoke-Fold5Capture $f.Source $f.Repo $extractor } catch { $failed=$true;Assert ($_.Exception.Message -match $pattern) $_.Exception.Message }
 Assert $failed 'Expected refusal';Assert ((Snapshot $f.Source)-ceq $before) 'Source changed';$script:count++
}
try {
 $f=Fixture 'success';$before=Snapshot $f.Source
 $target=Invoke-Fold5Capture $f.Source $f.Repo $mock
 Assert ((Snapshot $f.Source)-ceq $before) 'Success changed source'
 $manifest=@(Import-Csv -LiteralPath (Join-Path $target 'source_manifest.csv'))
 Assert ($manifest.Count-eq 5) 'Source manifest count'
 Assert (@(Get-ChildItem -LiteralPath $target -Recurse -Filter '*.rds').Count-eq 0) 'Binary RDS copied'
 Assert (@(Get-ChildItem -LiteralPath $target -Recurse -Filter '*.RData').Count-eq 0) 'Primary RData copied'
 Assert (@($manifest|Where-Object status -ceq 'COPIED_SHA256_VERIFIED').Count-eq 2) 'Copied count'
 foreach($row in @($manifest|Where-Object action -ceq 'COPY')) { Assert ((Get-FileHash -LiteralPath (Join-Path $target $row.destination_path.Replace('/','\')) -Algorithm SHA256).Hash.ToLowerInvariant()-ceq $row.sha256) 'Hash mismatch' }
 $count++
 Refuse $f 'already exists'
 $f=Fixture 'missing';[IO.File]::Delete((Join-Path $f.Source $rows[0].relative_path.Replace('/','\')));Refuse $f 'find|exist|Exception calling'
 $f=Fixture 'oversize';$path=Join-Path $f.Source $rows[1].relative_path.Replace('/','\');[IO.File]::WriteAllBytes($path,(New-Object byte[] 65537));Refuse $f 'oversized'
 $f=Fixture 'empty';[IO.File]::WriteAllText((Join-Path $f.Source $rows[0].relative_path.Replace('/','\')),'');Refuse $f 'Empty'
 foreach($bad in @('../raw.csv','hmsc_outputs/../raw.csv','D:/bad.csv','hmsc_outputs/x.rds','hmsc_outputs/x.csv2:ads','hmsc_outputs/CON.csv2','hmsc_outputs/x./z.csv2','hmsc_outputs/x\z.csv2')) {
  $f=Fixture ('bad-'+$count);$text=[IO.File]::ReadAllText($f.Allow).Replace($rows[0].relative_path,$bad);[IO.File]::WriteAllText($f.Allow,$text);Refuse $f 'path|extension|reviewed'
 }
 $f=Fixture 'allow-size';[IO.File]::WriteAllText($f.Allow,([IO.File]::ReadAllText($f.Allow).Replace('2097152','2097153')));Refuse $f 'reviewed'
 $f=Fixture 'allow-action';[IO.File]::WriteAllText($f.Allow,([IO.File]::ReadAllText($f.Allow).Replace('COPY','EXTRACT')));Refuse $f 'reviewed'
 $f=Fixture 'extraction-failure';Refuse $f 'synthetic extraction refusal' { throw 'synthetic extraction refusal' };Assert (Test-Path -LiteralPath (Join-Path $f.Target 'FAILED_CAPTURE_MANIFEST.csv')) 'Failure manifest absent';Refuse $f 'already exists'
 $f=Fixture 'junction';$outside=Join-Path $workspace 'outside';[void][IO.Directory]::CreateDirectory($outside)
 $hmsc=Join-Path $f.Source 'hmsc_outputs';$original=Join-Path $f.Source 'original'
 [IO.Directory]::Move($hmsc,$original)
 New-Item -ItemType Junction -Path $hmsc -Target $outside | Out-Null
 try { Refuse $f 'reparse' } finally { [IO.Directory]::Delete($hmsc) }
 Write-Host "PASS: $count synthetic capture cases; no R or scientific models executed."
} finally { [IO.Directory]::Delete($workspace,$true) }
