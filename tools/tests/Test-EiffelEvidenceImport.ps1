#requires -Version 5.1
# Synthetic tests only. Never accesses D:\EIFFEL or runs R.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'import_local_evidence.ps1'
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw ($parseErrors | Out-String) }
. $scriptPath
$allowOriginal = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'project_state\audit_v1\LOCAL_EVIDENCE_REQUEST.csv'
$inventory = @(Read-EiffelAllowList $allowOriginal)
$workspace = Join-Path ([IO.Path]::GetTempPath()) ('eiffel-synthetic-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($workspace)
$utf8 = New-Object Text.UTF8Encoding $false
$testCount = 0
$junctions = New-Object 'System.Collections.Generic.List[string]'

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "TEST FAILED: $Message" }
}
function Write-Fixture([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, $utf8)
}
function Get-Snapshot([string]$Root) {
    return (@(Get-ChildItem -LiteralPath $Root -File -Recurse | Sort-Object FullName | ForEach-Object {
        $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}
function New-Fixture([string]$Name) {
    $base = Join-Path $workspace $Name
    $source = Join-Path $base 'source'
    $repo = Join-Path $base 'repo'
    [void][IO.Directory]::CreateDirectory($source)
    [void][IO.Directory]::CreateDirectory($repo)
    $allow = Join-Path $repo 'project_state\audit_v1\LOCAL_EVIDENCE_REQUEST.csv'
    Write-Fixture $allow ([IO.File]::ReadAllText($allowOriginal))
    foreach ($row in $inventory) {
        $file = Join-Path $source $row.relative_path.Replace('/', '\')
        if ($row.relative_path.EndsWith('/S5_sample_summary.csv2')) {
            $text = 'species;n_original;n_with_exact_previous_year;n_matched_dynamic;proportion_retained' + "`n"
            foreach ($species in @('Epirrita_autumnata','Operophtera_brumata','Operophtera_fagata')) {
                $text += $species + ';2;2;1;0,5' + "`n"
            }
        } elseif ($file.EndsWith('.csv2')) {
            $text = 'metric;value' + "`n" + 'synthetic;1' + "`n"
        } else { $text = 'SYNTHETIC TEST FIXTURE ONLY' + "`n" }
        $length = $utf8.GetByteCount($text)
        Assert-Test ($length -le [int]$row.size_bytes) 'Fixture is too long.'
        $text += (' ' * ([int]$row.size_bytes - $length))
        Write-Fixture $file $text
    }
    Write-Fixture (Join-Path $source 'raw_observations.csv') "SYNTHETIC UNLISTED;DO NOT COPY`n"
    Write-Fixture (Join-Path $repo 'imported_local\existing.txt') 'existing snapshot sentinel'
    return [pscustomobject]@{ Source=$source; Repo=$repo; Allow=$allow; Target=(Join-Path $repo 'imported_local_evidence_v1') }
}
function Invoke-Refusal($Fixture, [string]$Pattern, [bool]$ExpectNoTarget = $true) {
    $before = Get-Snapshot $Fixture.Source
    $repoBefore = Get-Snapshot $Fixture.Repo
    $refused = $false
    try { Invoke-EiffelEvidenceImport $Fixture.Source $Fixture.Repo } catch {
        $refused = $true
        Assert-Test ($_.Exception.Message -match $Pattern) ("Wrong refusal: " + $_.Exception.Message)
    }
    Assert-Test $refused 'Unsafe import was accepted.'
    Assert-Test ((Get-Snapshot $Fixture.Source) -ceq $before) 'Source changed during refusal.'
    Assert-Test ((Get-Snapshot $Fixture.Repo) -ceq $repoBefore) 'Preflight refusal wrote repository files.'
    if ($ExpectNoTarget) { Assert-Test (-not (Test-Path -LiteralPath $Fixture.Target)) 'Preflight created target.' }
    $script:testCount++
}
function Alter-Allow($Fixture, [scriptblock]$Change) {
    $rows = @(Import-Csv -LiteralPath $Fixture.Allow)
    & $Change $rows
    $rows | Export-Csv -LiteralPath $Fixture.Allow -NoTypeInformation -Encoding UTF8
}
try {
    $f = New-Fixture 'success'
    $before = Get-Snapshot $f.Source
    Invoke-EiffelEvidenceImport $f.Source $f.Repo
    Assert-Test ((Get-Snapshot $f.Source) -ceq $before) 'Success changed source files/timestamps.'
    $manifest = @(Import-Csv -LiteralPath (Join-Path $f.Target 'evidence_manifest.csv'))
    Assert-Test ($manifest.Count -eq 51) 'Manifest row count.'
    Assert-Test (@(Get-ChildItem -LiteralPath $f.Target -File -Recurse).Count -eq 52) 'Only 51 requested files plus manifest.'
    foreach ($row in $manifest) {
        Assert-Test ($row.status -ceq 'VERIFIED') 'Non-verified success status.'
        Assert-Test ($row.expected_size -eq $row.actual_size) 'Manifest size mismatch.'
        Assert-Test ($row.sha256 -ceq (Get-FileHash -LiteralPath $row.destination_path -Algorithm SHA256).Hash.ToLowerInvariant()) 'Destination SHA256 mismatch.'
        $original = Join-Path $f.Source $row.source_relative_path.Replace('/', '\')
        Assert-Test ($row.sha256 -ceq (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant()) 'Source SHA256 mismatch.'
    }
    Assert-Test (([IO.File]::ReadAllText((Join-Path $f.Repo 'imported_local\existing.txt'))) -ceq 'existing snapshot sentinel') 'Existing snapshot changed.'
    $testCount++
    Invoke-Refusal $f 'Destination already exists' $false

    $f = New-Fixture 'missing'
    [IO.File]::Delete((Join-Path $f.Source $inventory[0].relative_path.Replace('/', '\')))
    Invoke-Refusal $f 'not find|cannot find|could not find'

    $f = New-Fixture 'size'
    [IO.File]::AppendAllText((Join-Path $f.Source $inventory[0].relative_path.Replace('/', '\')), 'X')
    Invoke-Refusal $f 'Size mismatch'

    $f = New-Fixture 'traversal'
    Alter-Allow $f { param($r) $r[0].relative_path = 'hmsc_outputs/../outside.csv2' }
    Invoke-Refusal $f 'Unsafe path segment'

    $f = New-Fixture 'absolute'
    Alter-Allow $f { param($r) $r[0].relative_path = 'D:\EIFFEL\unexpected.csv2' }
    Invoke-Refusal $f 'Unexpected source path'

    $f = New-Fixture 'extension'
    Alter-Allow $f { param($r) $r[0].relative_path = 'hmsc_outputs/model.rds' }
    Invoke-Refusal $f 'Unexpected extension'

    $f = New-Fixture 'duplicate'
    Alter-Allow $f { param($r) $r[1].relative_path = $r[0].relative_path }
    Invoke-Refusal $f 'Duplicate allow-list'

    $f = New-Fixture 'changed-size-inventory'
    Alter-Allow $f { param($r) $r[0].size_bytes = '73' }
    Invoke-Refusal $f 'differs from the reviewed'

    $f = New-Fixture 'unreviewed-path'
    Alter-Allow $f { param($r) $r[0].relative_path = 'hmsc_outputs/raw_observations.csv2' }
    Invoke-Refusal $f 'differs from the reviewed'

    $f = New-Fixture 'missing-entry'
    @(Import-Csv -LiteralPath $f.Allow)[0..49] | Export-Csv -LiteralPath $f.Allow -NoTypeInformation -Encoding UTF8
    Invoke-Refusal $f 'exactly the 51'

    $f = New-Fixture 'destination-file'
    Write-Fixture $f.Target 'existing destination sentinel'
    Invoke-Refusal $f 'Destination already exists' $false

    $f = New-Fixture 'binary'
    $path = Join-Path $f.Source $inventory[0].relative_path.Replace('/', '\')
    $bytes = [IO.File]::ReadAllBytes($path); $bytes[0] = 0; [IO.File]::WriteAllBytes($path,$bytes)
    Invoke-Refusal $f 'Binary content forbidden'

    $f = New-Fixture 'observation-table'
    $path = Join-Path $f.Source $inventory[0].relative_path.Replace('/', '\')
    $text = "site;year;abundance`nSYNTHETIC;2000;1`n"
    Write-Fixture $path ($text + (' ' * ([int]$inventory[0].size_bytes - $utf8.GetByteCount($text))))
    Invoke-Refusal $f 'Observation-level schema forbidden'

    $f = New-Fixture 'nonaggregate-sample-summary'
    $row = @($inventory | Where-Object { $_.relative_path.EndsWith('/S5_sample_summary.csv2') })[0]
    $text = "species;individual_count`nSYNTHETIC;1`n"
    Write-Fixture (Join-Path $f.Source $row.relative_path.Replace('/', '\')) ($text + (' ' * ([int]$row.size_bytes - $utf8.GetByteCount($text))))
    Invoke-Refusal $f 'NOT an approved aggregate schema'

    $f = New-Fixture 'source-junction'
    $outside = Join-Path $workspace 'outside-source'
    [IO.Directory]::Move((Join-Path $f.Source 'hmsc_outputs'), $outside)
    $junction = Join-Path $f.Source 'hmsc_outputs'
    [void](New-Item -ItemType Junction -Path $junction -Target $outside)
    $junctions.Add($junction)
    Invoke-Refusal $f 'reparse points forbidden'

    $f = New-Fixture 'repository-junction'
    $outside = Join-Path $workspace 'outside-repo'
    [IO.Directory]::Move($f.Repo, $outside)
    [void](New-Item -ItemType Junction -Path $f.Repo -Target $outside)
    $junctions.Add($f.Repo)
    Invoke-Refusal $f 'reparse points forbidden'

    $f = New-Fixture 'allow-list-symlink'
    $outside = Join-Path $workspace 'outside-allow.csv'
    [IO.File]::Move($f.Allow, $outside)
    [void](New-Item -ItemType SymbolicLink -Path $f.Allow -Target $outside)
    $junctions.Add($f.Allow)
    Invoke-Refusal $f 'Source must be an ordinary file'

    $f = New-Fixture 'source-file-symlink'
    $path = Join-Path $f.Source $inventory[0].relative_path.Replace('/', '\')
    $outside = Join-Path $workspace 'outside-evidence.csv2'
    [IO.File]::Move($path,$outside)
    [void](New-Item -ItemType SymbolicLink -Path $path -Target $outside)
    $junctions.Add($path)
    Invoke-Refusal $f 'Source must be an ordinary file'

    foreach ($bad in @('hmsc_outputs/a:ads.txt','hmsc_outputs//a.txt','hmsc_outputs/./a.txt','hmsc_outputs/CON.txt','hmsc_outputs/a./b.txt','hmsc_outputs/a\b.txt','\\server\share\a.txt')) {
        $refused = $false
        try { Assert-EiffelRelativePath $bad } catch { $refused = $true }
        Assert-Test $refused "Unsafe path accepted: $bad"
        $testCount++
    }
    $f = New-Fixture 'overlapping-roots'
    $refused = $false
    try { Invoke-EiffelEvidenceImport $f.Source (Join-Path $f.Source 'repo') } catch {
        $refused = $_.Exception.Message -match 'non-overlapping'
    }
    Assert-Test $refused 'Overlapping roots accepted.'
    $testCount++

    # Production entry point cannot accept alternative roots, even from a synthetic test.
    $exe = (Get-Process -Id $PID).Path
    $ErrorActionPreference = 'Continue'
    $output = @(& $exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath arbitrary 2>&1)
    $ErrorActionPreference = 'Stop'
    Assert-Test ($LASTEXITCODE -ne 0) 'Production accepted arguments.'
    Assert-Test (($output -join "`n") -match 'No arguments accepted') 'Unexpected production refusal.'
    $testCount++
    Write-Host "PASS: syntax parser and $testCount synthetic safety cases on $($PSVersionTable.PSVersion). No local scientific project accessed."
} finally {
    # Test-generated links only; remove links themselves before deleting this unique temp fixture.
    foreach ($path in $junctions) {
        if ([IO.File]::Exists($path) -and -not [IO.Directory]::Exists($path)) { [IO.File]::Delete($path) }
        elseif ([IO.Directory]::Exists($path)) { [IO.Directory]::Delete($path) }
    }
    if ([IO.Directory]::Exists($workspace)) { [IO.Directory]::Delete($workspace, $true) }
}
