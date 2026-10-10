#requires -Version 5.1
[CmdletBinding()]
param([string]$RscriptPath='D:\ProgramFiles\R\R-4.5.2\bin\x64\Rscript.exe')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Dot-sourced capture helper declares a same-named parameter; preserve the caller's executable.
$requestedP0RscriptPath=$RscriptPath
. (Join-Path $PSScriptRoot 'capture_completed_fold5.ps1')
$RscriptPath=$requestedP0RscriptPath
function Read-AnnualAllowList([string]$Path) {
    $rows=@(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($rows.Count -ne 21 -or (@($rows[0].PSObject.Properties.Name)-join '|') -cne 'id|relative_path|expected_size|action') { throw 'Unexpected P0 allow-list schema/count.' }
    $canonical=@()
    foreach($r in $rows) {
        if ($r.id -cnotmatch '^[A-Za-z_]+$' -or $r.relative_path -cnotmatch '^(hmsc_outputs|EIFFELgis)/[A-Za-z0-9_./-]+$' -or $r.expected_size -cnotmatch '^(UNRECORDED|[1-9][0-9]*)$') { throw 'Unexpected path/size/id.' }
        foreach($part in $r.relative_path.Split('/')) {
            if($part -in @('','.','..') -or $part.EndsWith('.') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Unsafe path.' }
        }
        if($r.action -cnotin @('MODEL_DIAGNOSTICS','PREPARATION_METADATA','ANNUAL_INPUT','COPY_DIAGNOSTIC')) { throw 'Unexpected extraction action.' }
        if($r.action -ceq 'COPY_DIAGNOSTIC' -and ([IO.Path]::GetExtension($r.relative_path) -cne '.txt' -or [long]$r.expected_size -gt 8192)) {throw 'Unexpected diagnostic extension/size.'}
        $canonical+=($r.id+'|'+$r.relative_path+'|'+$r.expected_size+'|'+$r.action)
    }
    $s=New-Object IO.MemoryStream (,[Text.Encoding]::UTF8.GetBytes(($canonical-join "`n")))
    try { if((Get-EiffelHash $s) -cne '3d1802fdcb63cb866600236745f0f7069092f32d754390190d7089def3143c92') { throw 'Allow-list differs from the 21 reviewed exact paths/sizes/actions.' } } finally {$s.Dispose()}
    return $rows
}
function Invoke-AnnualExtraction([string]$SourceRoot,[string]$RepositoryRoot,[scriptblock]$Extractor) {
    $source=ConvertTo-EiffelFullPath $SourceRoot;$repo=ConvertTo-EiffelFullPath $RepositoryRoot
    if($source -notmatch '^[A-Za-z]:\\' -or $repo -notmatch '^[A-Za-z]:\\' -or $source.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $repo.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Separate local drive roots required.'}
    # D:\EIFFEL is never a permitted runtime/source/output root in the production entry point.
    foreach($tmp in @([IO.Path]::GetTempPath(),$env:TEMP,$env:TMP)) {
        if($tmp -and ((ConvertTo-EiffelFullPath $tmp).Equals($source,[StringComparison]::OrdinalIgnoreCase) -or (ConvertTo-EiffelFullPath $tmp).StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or (ConvertTo-EiffelFullPath $tmp) -match '^(?i:D:\\EIFFEL)(\\|$)')) {throw 'Temporary paths cannot be under protected source roots.'}
    }
    Initialize-EiffelNative
    $guards=New-Object 'System.Collections.Generic.List[System.IDisposable]'
    $guarded=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $created=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $streams=New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
    $records=New-Object 'System.Collections.Generic.List[object]'
    $target=Join-Path $repo 'local_p0_count_effort_v1'
    try {
        Protect-EiffelDirectory $source $guards $guarded;Protect-EiffelDirectory $repo $guards $guarded
        if(Test-Path -LiteralPath $target) {throw 'Versioned destination already exists; no overwrite/retry permitted.'}
        $allow=Join-Path $repo 'project_state\p0_count_effort_v1\LOCAL_EXTRACTION_ALLOWLIST.csv'
        $streams.Add((Open-EiffelSource $allow $guards $guarded))
        $rows=@(Read-AnnualAllowList $allow)
        foreach($r in $rows) {
            $path=ConvertTo-EiffelFullPath (Join-Path $source $r.relative_path.Replace('/','\'))
            if(-not $path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Source escape.'}
            $s=Open-EiffelSource $path $guards $guarded;$streams.Add($s)
            if($r.expected_size -ceq 'UNRECORDED' -and ($r.id -cne 'final_input' -or $s.Length -le 0 -or $s.Length -gt 2147483648)) {throw 'Final input empty/above 2 GiB read-only cap.'}
            if($r.expected_size -cne 'UNRECORDED' -and $s.Length -ne [long]$r.expected_size) {throw "Exact source size mismatch: $($r.relative_path); recover new metadata instead of editing the allow-list."}
            $records.Add([pscustomobject]@{id=$r.id;source_relative_path=$r.relative_path;expected_size=$r.expected_size;actual_size=$s.Length;sha256=(Get-EiffelHash $s);action=$r.action;destination_path='';status='READ_ONLY_PREFLIGHT';stream=$s})
        }
        New-EiffelDirectory $target $guards $guarded $created
        foreach($r in $records) {
            if($r.action -cne 'COPY_DIAGNOSTIC') {continue}
            $name=$r.id+'.txt';$dest=Join-Path $target $name
            $d=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            try {
                if(-not (Get-EiffelPhysicalPath $d.SafeFileHandle).Equals($dest,[StringComparison]::OrdinalIgnoreCase)) {throw 'Diagnostic destination escape.'}
                $r.stream.Position=0;$r.stream.CopyTo($d);$d.Flush($true)
                if($d.Length -ne $r.actual_size -or (Get-EiffelHash $d)-cne $r.sha256){throw 'Diagnostic copy hash mismatch.'}
                $r.destination_path=$name
            } finally {$d.Dispose()}
        }
        & $Extractor $source $target $allow
        foreach($r in $records) {
            if($r.stream.Length -ne $r.actual_size -or (Get-EiffelHash $r.stream) -cne $r.sha256) {throw 'Source changed during extraction.'}
            $r.status=if($r.action -ceq 'COPY_DIAGNOSTIC'){'COPIED_DIAGNOSTIC_SHA256_VERIFIED_SOURCE_UNCHANGED'}else{'READ_ONLY_SHA256_UNCHANGED_NOT_COPIED'}
        }
        $files=@(Get-ChildItem -LiteralPath $target -Force)
        $diagnosticNames=@($records|Where-Object action -ceq 'COPY_DIAGNOSTIC'|ForEach-Object {$_.id+'.txt'})
        if(-not ($files.Name -ccontains 'STATUS.csv') -or -not ($files.Name -ccontains 'recovery_status.csv') -or $files.Count -gt 160) {throw 'Missing/unexpected extraction outputs.'}
        $artifacts=@()
        foreach($f in $files) {
            if($f.PSIsContainer -or $f.Name -cnotmatch '^[A-Za-z0-9_-]+\.(csv|pdf|txt)$') {throw 'Unexpected output path/extension.'}
            if([IO.Path]::GetExtension($f.Name) -ceq '.txt' -and $diagnosticNames -cnotcontains $f.Name) {throw 'Unexpected diagnostic text output.'}
            $s=Open-EiffelSource $f.FullName $guards $guarded
            try {
                if($s.Length -le 0 -or $s.Length -gt 4194304) {throw 'Empty/oversized output; do not publish.'}
                if([IO.Path]::GetExtension($f.Name) -ceq '.txt') {
                    $original=@($records|Where-Object destination_path -ceq $f.Name)
                    if($original.Count-ne 1 -or $s.Length-ne $original[0].actual_size -or (Get-EiffelHash $s)-cne $original[0].sha256){throw 'Copied diagnostic changed after extraction.'}
                }
                $artifacts+=[pscustomobject]@{relative_path=$f.Name;size=$s.Length;sha256=(Get-EiffelHash $s);md5=(Get-FileHash -LiteralPath $f.FullName -Algorithm MD5).Hash.ToLowerInvariant()}
            } finally {$s.Dispose()}
        }
        Write-Fold5CsvNew ($records|Select-Object id,source_relative_path,expected_size,actual_size,sha256,action,destination_path,status) (Join-Path $target 'source_manifest.csv')
        $mf=Join-Path $target 'source_manifest.csv';$s=Open-EiffelSource $mf $guards $guarded
        try {$artifacts+=[pscustomobject]@{relative_path='source_manifest.csv';size=$s.Length;sha256=(Get-EiffelHash $s);md5=(Get-FileHash -LiteralPath $mf -Algorithm MD5).Hash.ToLowerInvariant()}} finally {$s.Dispose()}
        Write-Fold5CsvNew $artifacts (Join-Path $target 'artifact_manifest.csv')
        Write-Host 'SUCCESS: 21 source files SHA256 unchanged; 16 existing diagnostic texts copied and verified; five input/posterior/preparation sources read only, never copied.'
        Write-Host 'EXTRACTION COMPLETE; convergence and preparation are NOT certified. Review recovery_status.csv and diagnostics; local evidence remains unpublished.'
        Write-Host "Output: $target. No fitting, MCMC, prediction, CV, S4 or S5; source/results/snapshots/conifer job unchanged."
        return $target
    } catch {
        if($created.Contains($target)) {
            try {Write-Fold5CsvNew ([pscustomobject]@{status='FAILED_NOT_PUBLISHABLE';message=$_.Exception.Message}) (Join-Path $target 'FAILED.csv')} catch {}
        }
        throw
    } finally {
        foreach($s in $streams) {$s.Dispose()}
        for($i=$guards.Count-1;$i-ge 0;$i--) {$guards[$i].Dispose()}
    }
}
if($MyInvocation.InvocationName -ne '.') {
    $repo=ConvertTo-EiffelFullPath (Split-Path $PSScriptRoot -Parent)
    if(-not $repo.Equals('D:\EIFFEL-control',[StringComparison]::OrdinalIgnoreCase)) {throw 'Production repository must be D:\EIFFEL-control.'}
    $exe=Resolve-Fold5Rscript $RscriptPath
    $code=Join-Path $repo 'R\validation\VERIFY_P0_ANNUAL_RESPONSE_v1.R'
    $extractor={param($source,$target,$allow)
        $codeGuards=New-Object 'System.Collections.Generic.List[System.IDisposable]'
        $codeGuarded=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $codeStreams=@()
        try {
            foreach($p in @($exe,$code,(Join-Path $repo 'tools\verify_p0_annual_response.ps1'),(Join-Path $repo 'tools\capture_completed_fold5.ps1'),(Join-Path $repo 'tools\import_local_evidence.ps1'),(Join-Path $repo 'R\validation\EXTRACT_P0_EXISTING_POSTERIORS_v1.R'))) {$codeStreams+=(Open-EiffelSource $p $codeGuards $codeGuarded)}
            $hashes=@($codeStreams|ForEach-Object {Get-EiffelHash $_})
            & $exe --vanilla $code $source $target $allow
            if($LASTEXITCODE -ne 0) {throw 'Read-only R extraction failed; evidence is not publishable.'}
            for($j=0;$j-lt $codeStreams.Count;$j++) {if((Get-EiffelHash $codeStreams[$j])-cne $hashes[$j]) {throw 'Extractor/runtime changed.'}}
            Write-Fold5CsvNew @([pscustomobject]@{role='Rscript';sha256=$hashes[0]},[pscustomobject]@{role='reviewed_R_extractor';sha256=$hashes[1]},[pscustomobject]@{role='P0_PowerShell_wrapper';sha256=$hashes[2]},[pscustomobject]@{role='capture_guard_dependency';sha256=$hashes[3]},[pscustomobject]@{role='native_import_guard_dependency';sha256=$hashes[4]},[pscustomobject]@{role='diagnostic_arithmetic_dependency';sha256=$hashes[5]}) (Join-Path $target 'tool_manifest.csv')
        } finally {foreach($s in $codeStreams){$s.Dispose()};for($j=$codeGuards.Count-1;$j-ge 0;$j--){$codeGuards[$j].Dispose()}}
    }.GetNewClosure()
    Invoke-AnnualExtraction 'D:\EIFFEL_runtime' $repo $extractor
}
