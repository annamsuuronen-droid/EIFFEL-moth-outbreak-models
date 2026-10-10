# Cross-platform parser/exact-path contract tests; Windows native guards tested separately.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script=Join-Path $repo 'tools/verify_p0_annual_response.ps1'
$tokens=$null;$errors=$null
foreach($p in @($script,(Join-Path $repo 'tools/tests/Test-P0AnnualResponse.ps1'))) {
 [void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ($errors|Out-String)}
}
$sentinel='SYNTHETIC_RSCRIPT_PATH'
. $script -RscriptPath $sentinel
if($RscriptPath -cne $sentinel){throw 'Caller Rscript path lost'}
$allow=Join-Path $repo 'project_state/p0_count_effort_v1/LOCAL_EXTRACTION_ALLOWLIST.csv'
if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){Initialize-EiffelNative} # Native APIs remain Windows-only.
$rows=@(Read-AnnualAllowList $allow)
if($rows.Count-ne 21){throw 'Unexpected source count'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('eiffel-contract-'+[Guid]::NewGuid().ToString('N')+'.csv')
$checks=0
try {
 foreach($bad in @('Olddata/model_data_environment_nearly_constant_years_filled.csv','EIFFELgis/../source.csv','EIFFELgis/CON.csv','EIFFELgis/a.csv:ads','EIFFELgis/a./source.csv','D:/unexpected.csv','hmsc_outputs/conifer_species/model.rds','data/Eiffel_1993_2024.csv')) {
  [IO.File]::WriteAllText($fixture,([IO.File]::ReadAllText($allow).Replace($rows[0].relative_path,$bad)))
  $refused=$false;try{Read-AnnualAllowList $fixture|Out-Null}catch{$refused=$true}
  if(-not $refused){throw "Unexpected accepted path: $bad"};$checks++
 }
 foreach($replacement in @('211358134','UNRECORDED','0')) {
  [IO.File]::WriteAllText($fixture,([IO.File]::ReadAllText($allow).Replace('211358133',$replacement)))
  $refused=$false;try{Read-AnnualAllowList $fixture|Out-Null}catch{$refused=$true}
  if(-not $refused){throw 'Changed source-size contract accepted'};$checks++
 }
 Write-Host "PASS: PowerShell parser, explicit Rscript preservation, exact21-source digest and $checks contract mutation refusals. Native Windows execution not simulated."
} finally {if([IO.File]::Exists($fixture)){[IO.File]::Delete($fixture)}}
