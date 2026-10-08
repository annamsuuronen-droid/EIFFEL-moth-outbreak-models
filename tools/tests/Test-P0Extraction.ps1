#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script=Join-Path $repo 'tools\extract_p0_existing_evidence.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$testP0RuntimePath='C:\SYNTHETIC_ONLY\Rscript.exe'
. $script -RscriptPath $testP0RuntimePath
if($RscriptPath -cne $testP0RuntimePath) {throw 'Explicit Rscript path lost when loading shared helpers.'}
$workspace=Join-Path ([IO.Path]::GetTempPath()) ('eiffel-p0-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
function Assert($ok,$message){if(-not $ok){throw $message}}
function Reject([scriptblock]$x){$failed=$false;try{&$x}catch{$failed=$true};Assert $failed 'Expected refusal'}
try {
 $original=Join-Path $repo 'project_state\p0_investigation_v1\LOCAL_EXTRACTION_ALLOWLIST.csv'
 $rows=@(Read-P0AllowList $original);Assert ($rows.Count-eq 36) 'Missing reviewed rows'
 $allow=Join-Path $workspace 'allow.csv'
 foreach($bad in @('../raw.csv','hmsc_outputs/../raw.csv','hmsc_outputs/x.rds:ads','hmsc_outputs/CON.rds','hmsc_outputs/x./a.rds','hmsc_outputs/conifer_species/x.rds','data/x.csv','D:/raw.csv')) {
  [IO.File]::WriteAllText($allow,([IO.File]::ReadAllText($original).Replace($rows[0].relative_path,$bad)))
  Reject {Read-P0AllowList $allow}
 }
 [IO.File]::WriteAllText($allow,([IO.File]::ReadAllText($original).Replace('169986680','169986681')));Reject {Read-P0AllowList $allow}
 $source=Join-Path $workspace 'source';$checkout=Join-Path $workspace 'repo'
 [void][IO.Directory]::CreateDirectory($source);[void][IO.Directory]::CreateDirectory($checkout)
 $a=Join-Path $checkout 'project_state\p0_investigation_v1\LOCAL_EXTRACTION_ALLOWLIST.csv'
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($a));[IO.File]::WriteAllText($a,[IO.File]::ReadAllText($original))
 $mock={param($s,$t,$a) Write-Fold5CsvNew ([pscustomobject]@{status='SYNTHETIC_ONLY'}) (Join-Path $t 'STATUS.csv');Write-Fold5CsvNew ([pscustomobject]@{status='SYNTHETIC_ONLY'}) (Join-Path $t 'recovery_status.csv')}
 Reject {Invoke-P0Extraction $source $checkout $mock}
 foreach($r in $rows){$p=Join-Path $source $r.relative_path.Replace('/','\');[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p));$f=[IO.File]::Open($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write);try{$f.SetLength([long]$r.expected_size)}finally{$f.Dispose()}}
 $raw=Join-Path $source $rows[3].relative_path.Replace('/','\');$f=[IO.File]::OpenWrite($raw);try{$f.SetLength(1)}finally{$f.Dispose()}
 Reject {Invoke-P0Extraction $source $checkout $mock}
 $f=[IO.File]::OpenWrite($raw);try{$f.SetLength([long]$rows[3].expected_size)}finally{$f.Dispose()}
 $before=@(foreach($r in $rows){(Get-FileHash -LiteralPath (Join-Path $source $r.relative_path.Replace('/','\'))).Hash})
 $target=Invoke-P0Extraction $source $checkout $mock
 $after=@(foreach($r in $rows){(Get-FileHash -LiteralPath (Join-Path $source $r.relative_path.Replace('/','\'))).Hash})
 Assert (($before-join '|')-ceq ($after-join '|')) 'Source content changed'
 Assert (@(Get-ChildItem -LiteralPath $target -Filter '*.rds').Count-eq 0) 'Source binary copied'
 Assert (@(Import-Csv -LiteralPath (Join-Path $target 'source_manifest.csv')).Count-eq 36) 'Missing source manifest'
 Assert (@(Get-ChildItem -LiteralPath $target -Filter '*.txt').Count-eq 32) 'Diagnostic copy count'
 Reject {Invoke-P0Extraction $source $checkout $mock}
 Reject {Invoke-P0Extraction $source $source $mock}
 $outside=Join-Path $workspace 'outside';[void][IO.Directory]::CreateDirectory($outside)
 $link=Join-Path $workspace 'link';New-Item -ItemType Junction -Path $link -Target $outside|Out-Null
 try{Reject {Invoke-P0Extraction $link $checkout $mock}}finally{[IO.Directory]::Delete($link)}
 Write-Host 'PASS: P0 PowerShell parser, exact allow-list, traversal/ADS/reserved/unexpected/conifer paths, missing/size/overwrite/root/junction refusals and unchanged-source success. Synthetic fixtures only.'
} finally {[IO.Directory]::Delete($workspace,$true)}
