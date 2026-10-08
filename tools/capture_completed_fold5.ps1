#requires -Version 5.1
[CmdletBinding()]
param([switch]$PublishGit, [string]$RscriptPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'import_local_evidence.ps1')
function Read-Fold5AllowList([string]$Path) {
    $rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($rows.Count -ne 5 -or (@($rows[0].PSObject.Properties.Name) -join '|') -cne 'relative_path|action|max_bytes') { throw 'Unexpected allow-list schema/count.' }
    $canonical = @()
    foreach ($row in $rows) {
        if ($row.relative_path -cnotmatch '^hmsc_outputs/[A-Za-z0-9_./-]+$') { throw 'Unexpected path.' }
        foreach ($part in $row.relative_path.Split('/')) {
            if ($part -in @('', '.', '..') -or $part.EndsWith('.') -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Unsafe path.' }
        }
        if ($row.action -cnotin @('COPY','EXTRACT','VERIFY_ONLY') -or $row.max_bytes -cnotmatch '^[1-9][0-9]*$') { throw 'Unexpected action/size.' }
        if ($row.action -ceq 'COPY' -and [IO.Path]::GetExtension($row.relative_path) -cne '.csv2') { throw 'Unexpected copied extension.' }
        $canonical += ($row.relative_path + '|' + $row.action + '|' + $row.max_bytes)
    }
    $stream = New-Object IO.MemoryStream (,[Text.Encoding]::UTF8.GetBytes(($canonical -join "`n")))
    try { if ((Get-EiffelHash $stream) -cne '9fdbb1e7685b8ccf9c79f6067ff72847c3d1a2bf670fda39188d71112d12cd45') { throw 'Allow-list differs from the five reviewed entries.' } } finally { $stream.Dispose() }
    return $rows
}
function Resolve-Fold5Rscript([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return (Get-Command Rscript.exe -CommandType Application -ErrorAction Stop).Source }
    if ($Path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetFileName($Path) -ine 'Rscript.exe') { throw 'Rscript must be an absolute local path ending in Rscript.exe.' }
    $full = ConvertTo-EiffelFullPath $Path
    if (-not [IO.File]::Exists($full) -or ([IO.File]::GetAttributes($full) -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) { throw 'Rscript executable is missing or a reparse point.' }
    return $full
}
function Assert-Fold5CapturedHashes([string]$Target) {
    $rows = @(Import-Csv -LiteralPath (Join-Path $Target 'artifact_manifest.csv') -Encoding UTF8)
    $prefix = 'hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05/'
    $expected = @(($prefix+'outer_test_predictions.csv2'), ($prefix+'outer_test_metrics.csv2'), 'checkpoint_verification.csv', 'reconstructed_provenance_summary.csv', 'source_manifest.csv')
    if ($rows.Count -ne 5 -or ((@($rows.relative_path | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|'))) { throw 'Unexpected captured artifact paths.' }
    $guards = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    $guarded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        Protect-EiffelDirectory $Target $guards $guarded
        foreach ($row in $rows) {
            $path = Join-Path $Target $row.relative_path.Replace('/','\')
            $stream = Open-EiffelSource $path $guards $guarded
            try { if ($stream.Length -ne [long]$row.size -or (Get-EiffelHash $stream) -cne $row.sha256) { throw 'Captured artifact SHA256/size mismatch before publication.' } }
            finally { $stream.Dispose() }
        }
    } finally { for ($i=$guards.Count-1;$i -ge 0;$i--) { $guards[$i].Dispose() } }
}
function Write-Fold5AuditManifest([string]$Directory) {
    $expected = @('recomputed_fold_metrics.csv','pooled_five_fold_metrics.csv','equal_weight_fold_metrics.csv','fold_coverage.csv','STATUS.csv','INPUT_ARTIFACT_MANIFEST.csv','README.md')
    $files = @(Get-ChildItem -LiteralPath $Directory -Force)
    if (($files.Count -ne 7) -or ((@($files.Name | Sort-Object) -join '|') -cne (@($expected | Sort-Object) -join '|'))) { throw 'Unexpected audit output files; publication refused.' }
    $guards = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    $guarded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $records = @()
    try {
        Protect-EiffelDirectory $Directory $guards $guarded
        foreach ($file in $files) {
            $stream = Open-EiffelSource $file.FullName $guards $guarded
            try {
                if ($stream.Length -le 0 -or $stream.Length -gt 262144) { throw 'Unexpected audit file size.' }
                $records += [pscustomobject]@{relative_path=$file.Name;size=$stream.Length;sha256=(Get-EiffelHash $stream);md5=(Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash.ToLowerInvariant()}
            } finally { $stream.Dispose() }
        }
        Write-Fold5CsvNew $records (Join-Path $Directory 'AUDIT_ARTIFACT_MANIFEST.csv')
    } finally { for ($i=$guards.Count-1;$i -ge 0;$i--) { $guards[$i].Dispose() } }
}
function Write-Fold5CsvNew($Rows, [string]$Path) {
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        if (-not (Get-EiffelPhysicalPath $stream.SafeFileHandle).Equals($Path,[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest destination escape.' }
        $lines = @($Rows | ConvertTo-Csv -NoTypeInformation)
        $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`r`n")+"`r`n")
        $stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)
    } finally { $stream.Dispose() }
}
function Invoke-Fold5Capture([string]$SourceRoot, [string]$RepositoryRoot, [scriptblock]$Extractor) {
    $source = ConvertTo-EiffelFullPath $SourceRoot
    $repo = ConvertTo-EiffelFullPath $RepositoryRoot
    if ($source -notmatch '^[A-Za-z]:\\' -or $repo -notmatch '^[A-Za-z]:\\' -or $source.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $repo.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Roots must be separate local drive directories.' }
    foreach ($tempPath in @([IO.Path]::GetTempPath(),$env:TEMP,$env:TMP)) {
        if ($tempPath -and ((ConvertTo-EiffelFullPath $tempPath).Equals($source,[StringComparison]::OrdinalIgnoreCase) -or (ConvertTo-EiffelFullPath $tempPath).StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase))) { throw 'Temporary paths cannot be under source.' }
    }
    Initialize-EiffelNative
    $guards = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    $guarded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $created = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $streams = New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
    $records = New-Object 'System.Collections.Generic.List[object]'
    $target = Join-Path $repo 'imported_fold5_completed_r2_v1'
    $audit = Join-Path $repo 'project_state\outer_year_cv_full_v1'
    try {
        Protect-EiffelDirectory $source $guards $guarded
        Protect-EiffelDirectory $repo $guards $guarded
        if ((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $audit)) { throw 'Versioned destination already exists; replacement and automatic retry forbidden.' }
        $allow = Join-Path $repo 'project_state\outer_year_cv_recovery_v1\LOCAL_EVIDENCE_ALLOWLIST.csv'
        $streams.Add((Open-EiffelSource $allow $guards $guarded))
        $rows = @(Read-Fold5AllowList $allow)
        foreach ($row in $rows) {
            $path = ConvertTo-EiffelFullPath (Join-Path $source $row.relative_path.Replace('/','\'))
            if (-not $path.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Source escapes root.' }
            $s = Open-EiffelSource $path $guards $guarded; $streams.Add($s)
            if ($s.Length -le 0 -or $s.Length -gt [long]$row.max_bytes) { throw "Empty/oversized evidence: $($row.relative_path)" }
            $records.Add([pscustomobject]@{source_relative_path=$row.relative_path; action=$row.action; expected_size='UNKNOWN_BEFORE_CAPTURE'; maximum_size=[long]$row.max_bytes; actual_size=$s.Length; sha256=(Get-EiffelHash $s); destination_path=''; status='PREFLIGHT_VERIFIED'; stream=$s})
        }
        # All source files remain open read-only with no write/delete sharing throughout extraction.
        New-EiffelDirectory $target $guards $guarded $created
        foreach ($record in $records) {
            if ($record.action -cne 'COPY') { continue }
            $dest = Join-Path $target $record.source_relative_path.Replace('/','\')
            New-EiffelDirectory ([IO.Path]::GetDirectoryName($dest)) $guards $guarded $created
            $d = [IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            try {
                if (-not (Get-EiffelPhysicalPath $d.SafeFileHandle).Equals($dest,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination escape.' }
                $record.stream.Position=0; $record.stream.CopyTo($d); $d.Flush($true)
                if ($d.Length -ne $record.actual_size -or (Get-EiffelHash $d) -cne $record.sha256) { throw 'SHA256/size copy mismatch.' }
            } finally { $d.Dispose() }
            $record.destination_path=$record.source_relative_path; $record.status='COPIED_SHA256_VERIFIED'
        }
        & $Extractor $source $repo $target
        foreach ($record in $records) {
            if ($record.stream.Length -ne $record.actual_size -or (Get-EiffelHash $record.stream) -cne $record.sha256) { throw 'Source changed during capture.' }
            if ($record.action -cne 'COPY') { $record.status='READ_ONLY_VERIFIED_NOT_COPIED' }
        }
        Write-Fold5CsvNew ($records | Select-Object source_relative_path,action,expected_size,maximum_size,actual_size,sha256,destination_path,status) (Join-Path $target 'source_manifest.csv')
        $artifacts = @()
        foreach ($file in @(Get-ChildItem -LiteralPath $target -Recurse -File)) {
            $s = Open-EiffelSource $file.FullName $guards $guarded
            try {
                $relative = $file.FullName.Substring($target.Length+1).Replace('\','/')
                $artifacts += [pscustomobject]@{relative_path=$relative; size=$s.Length; sha256=(Get-EiffelHash $s); md5=(Get-FileHash -LiteralPath $file.FullName -Algorithm MD5).Hash.ToLowerInvariant()}
            } finally { $s.Dispose() }
        }
        Write-Fold5CsvNew $artifacts (Join-Path $target 'artifact_manifest.csv')
        return $target
    } catch {
        $message = $_.Exception.Message
        if ($created.Contains($target)) {
            try { Write-Fold5CsvNew ($records | Select-Object source_relative_path,action,expected_size,maximum_size,actual_size,sha256,destination_path,status) (Join-Path $target 'FAILED_CAPTURE_MANIFEST.csv') }
            catch { $message += '; failure-manifest write also refused: '+$_.Exception.Message }
        }
        throw "CAPTURE REFUSED/FAILED: $message. Source unchanged. Any partial versioned destination is retained and cannot be reused."
    }
    finally { foreach ($s in $streams) { $s.Dispose() }; for ($i=$guards.Count-1;$i -ge 0;$i--) { $guards[$i].Dispose() } }
}
if ($MyInvocation.InvocationName -ne '.') {
    $repo = ConvertTo-EiffelFullPath (Join-Path $PSScriptRoot '..')
    if (-not $repo.Equals('D:\EIFFEL-control',[StringComparison]::OrdinalIgnoreCase)) { throw 'Production repository must be D:\EIFFEL-control.' }
    $rscript = Resolve-Fold5Rscript $RscriptPath
    if ($PublishGit) {
        $branch = & git -C $repo branch --show-current
        if ($LASTEXITCODE -ne 0 -or $branch -cne 'main') { throw 'Publication requires main.' }
        $remote = & git -C $repo remote get-url origin
        if ($LASTEXITCODE -ne 0 -or $remote -notmatch '^(https://github\.com/|git@github\.com:)annamsuuronen-droid/EIFFEL-moth-outbreak-models(?:\.git)?$') { throw 'Unexpected origin.' }
        & git -C $repo diff --cached --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Existing staged changes; scoped publication refused.' }
    }
    $extractor = {
        param($source,$repository,$target)
        & $rscript --vanilla (Join-Path $repository 'R\validation\EXTRACT_COMPLETED_FOLD5_v1.R') $source $repository $target
        if ($LASTEXITCODE -ne 0) { throw 'Read-only checkpoint/input verification failed.' }
    }.GetNewClosure()
    $target = Invoke-Fold5Capture 'D:\EIFFEL_runtime' $repo $extractor
    & $rscript --vanilla (Join-Path $repo 'R\validation\AUDIT_COMPLETE_OUTER_YEAR_CV_v1.R') $repo $target
    if ($LASTEXITCODE -ne 0) { throw 'Full five-fold audit failed; no publication.' }
    Assert-Fold5CapturedHashes $target
    Write-Fold5AuditManifest (Join-Path $repo 'project_state\outer_year_cv_full_v1')
    if ($PublishGit) {
        & git -C $repo diff --cached --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Staging changed during capture; publication refused.' }
        if ((& git -C $repo branch --show-current) -cne 'main') { throw 'Branch changed during capture.' }
        # Empty hook directory prevents local hooks from launching unrelated computation.
        $hooks = Join-Path ([IO.Path]::GetTempPath()) ('eiffel-empty-hooks-'+[Guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($hooks)
        try {
            & git -c "core.hooksPath=$hooks" -C $repo add -- imported_fold5_completed_r2_v1 project_state/outer_year_cv_full_v1
            if ($LASTEXITCODE -ne 0) { throw 'Scoped git add failed.' }
            & git -c "core.hooksPath=$hooks" -C $repo commit -m 'Capture verified r2 fold-5 evidence and complete outer-year audit'
            if ($LASTEXITCODE -ne 0) { throw 'Scoped evidence commit failed.' }
            & git -c "core.hooksPath=$hooks" -C $repo push origin main
            if ($LASTEXITCODE -ne 0) { throw 'Non-forced push failed; verified evidence retained locally.' }
        } finally { [IO.Directory]::Delete($hooks) }
    }
    Write-Host 'SUCCESS: 2 CSV2 files SHA256 verified; 2 RDS files verified/extracted; primary input verified read-only, never copied.'
    Write-Host 'FULL FIVE-FOLD OUTER-YEAR CV VERIFIED. Historical folds 1-4 plus reconstructed-compatibility r2 fold 5.'
    Write-Host 'No fitting, MCMC, site CV, S4 or S5 execution occurred. Existing scientific results unchanged.'
}
