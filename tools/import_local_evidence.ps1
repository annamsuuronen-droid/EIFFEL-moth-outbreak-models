#requires -Version 5.1
<#
Production entry point: fixed D:\EIFFEL -> D:\EIFFEL-control. No R invocation.
Dot-sourcing defines the same engine for synthetic Windows tests; it never imports.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-EiffelNative {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This importer requires Windows.'
    }
    if ($null -eq ('EiffelEvidence.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace EiffelEvidence {
    public static class Native {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern SafeFileHandle CreateFileW(string name, uint access,
            uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle,
            StringBuilder path, uint length, uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool CreateDirectoryW(string path, IntPtr security);
    }
}
'@
    }
}

function ConvertTo-EiffelFullPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }
    return $full
}

function Get-EiffelPhysicalPath($Handle) {
    $buffer = New-Object System.Text.StringBuilder 32768
    $length = [EiffelEvidence.Native]::GetFinalPathNameByHandleW($Handle, $buffer, 32768, 0)
    if ($length -eq 0 -or $length -ge 32768) { throw 'Cannot resolve opened handle.' }
    $path = $buffer.ToString()
    if ($path.StartsWith('\\?\UNC\')) { throw 'UNC paths are forbidden.' }
    if ($path.StartsWith('\\?\')) { $path = $path.Substring(4) }
    return ConvertTo-EiffelFullPath $path
}

function Assert-EiffelRelativePath([string]$RelativePath) {
    # Slash-only canonical paths: no drives, ADS, UNC, wildcards or ambiguous names.
    if ($RelativePath -cnotmatch '^hmsc_outputs/[A-Za-z0-9_.\-/]+$') {
        throw "Unexpected source path: $RelativePath"
    }
    foreach ($segment in $RelativePath.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..' -or
            $segment.EndsWith('.') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
            throw "Unsafe path segment: $RelativePath"
        }
    }
    if ([IO.Path]::GetExtension($RelativePath) -cnotin @('.txt', '.csv2')) {
        throw "Unexpected extension: $RelativePath"
    }
}

function Get-EiffelHash($Stream) {
    $Stream.Position = 0
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $Stream.Position = 0; $sha.Dispose() }
}

function Read-EiffelAllowList([string]$Path) {
    $rows = @(Import-Csv -LiteralPath $Path -Encoding UTF8)
    if ($rows.Count -ne 51) { throw 'Allow-list must contain exactly the 51 reviewed entries.' }
    $headers = @($rows[0].PSObject.Properties.Name)
    if (($headers -join '|') -cne 'relative_path|size_bytes|exclusion_reason|purpose') {
        throw 'Unexpected allow-list headers.'
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $canonical = New-Object 'System.Collections.Generic.List[string]'
    foreach ($row in $rows) {
        Assert-EiffelRelativePath $row.relative_path
        if (-not $seen.Add($row.relative_path)) { throw 'Duplicate allow-list path.' }
        if ($row.size_bytes -cnotmatch '^[1-9][0-9]*$' -or [long]$row.size_bytes -gt 262144) {
            throw "Invalid or excessive expected size: $($row.relative_path)"
        }
        $canonical.Add($row.relative_path + '|' + $row.size_bytes)
    }
    # Independent of BOM/CRLF, but pins exact ordered paths and byte sizes reviewed at 757b78c.
    $bytes = [Text.Encoding]::UTF8.GetBytes(($canonical -join "`n"))
    $stream = New-Object IO.MemoryStream (,$bytes)
    try { $digest = Get-EiffelHash $stream } finally { $stream.Dispose() }
    if ($digest -cne '972501464c135ddaf50e0bb355dce0afe40772bee65bf0b874d928683a430b31') {
        throw 'Allow-list differs from the reviewed 757b78c path/size inventory.'
    }
    return $rows
}

function Protect-EiffelDirectory([string]$Path, $Guards, $Guarded) {
    $full = ConvertTo-EiffelFullPath $Path
    if ($Guarded.Contains($full)) { return }
    $parent = [IO.Directory]::GetParent($full)
    if ($null -ne $parent) { Protect-EiffelDirectory $parent.FullName $Guards $Guarded }
    $attributes = [IO.File]::GetAttributes($full)
    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($attributes -band [IO.FileAttributes]::Directory) -eq 0) {
        throw "Not an ordinary directory (reparse points forbidden): $full"
    }
    # No FILE_SHARE_DELETE: pin ancestors against concurrent rename/replacement on Windows.
    $handle = [EiffelEvidence.Native]::CreateFileW($full, 0, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
    if ($handle.IsInvalid) { $handle.Dispose(); throw "Cannot guard directory: $full" }
    $Guards.Add($handle)
    if (-not (Get-EiffelPhysicalPath $handle).Equals($full, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Directory resolves unexpectedly: $full"
    }
    if (([IO.File]::GetAttributes($full) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Directory became a reparse point: $full"
    }
    [void]$Guarded.Add($full)
}

function New-EiffelDirectory([string]$Path, $Guards, $Guarded, $Created) {
    if ($Created.Contains($Path)) { return }
    $parent = [IO.Directory]::GetParent($Path).FullName
    if (-not $Guarded.Contains($parent)) { New-EiffelDirectory $parent $Guards $Guarded $Created }
    # Unlike Directory.CreateDirectory, native creation fails if another run created this path.
    if (-not [EiffelEvidence.Native]::CreateDirectoryW($Path, [IntPtr]::Zero)) {
        throw "Refusing existing/uncreatable destination directory: $Path"
    }
    [void]$Created.Add($Path)
    Protect-EiffelDirectory $Path $Guards $Guarded
}

function Open-EiffelSource([string]$Path, $Guards, $Guarded) {
    Protect-EiffelDirectory ([IO.Path]::GetDirectoryName($Path)) $Guards $Guarded
    $attributes = [IO.File]::GetAttributes($Path) # Missing files fail here, never skipped.
    if (($attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) -ne 0) {
        throw "Source must be an ordinary file: $Path"
    }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if (-not (Get-EiffelPhysicalPath $stream.SafeFileHandle).Equals($Path, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Source handle resolves unexpectedly: $Path"
        }
        if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Source became a reparse point: $Path"
        }
        return $stream
    } catch { $stream.Dispose(); throw }
}

function Assert-EiffelSummaryContent([string]$RelativePath, $Stream) {
    $Stream.Position = 0
    $bytes = New-Object byte[] ([int]$Stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -eq 0) { throw 'Short read during content inspection.' }
        $offset += $read
    }
    $Stream.Position = 0
    $utf8 = New-Object Text.UTF8Encoding ($false, $true)
    $text = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
    if ($text.IndexOf([char]0) -ge 0) { throw "Binary content forbidden: $RelativePath" }
    if ([IO.Path]::GetExtension($RelativePath) -eq '.csv2') {
        $lines = @($text -split '\r?\n' | Where-Object { $_.Trim().Length -gt 0 })
        if ($lines.Count -eq 0) { throw "Empty table: $RelativePath" }
        $columns = @($lines[0].Split(';') | ForEach-Object { $_.Trim().Trim('"') })
        if (@($columns | Where-Object { $_ -match '^(?i:site|site_id|year|sample|sample_id|observation|observation_id|row|row_id|abundance|count|observed|observed_count|trap|trap_id|station|date|latitude|longitude)$' }).Count -gt 0) {
            throw "Observation-level schema forbidden: $RelativePath"
        }
        if ($RelativePath.EndsWith('/S5_sample_summary.csv2')) {
            if (($columns -join '|') -cne 'species|n_original|n_with_exact_previous_year|n_matched_dynamic|proportion_retained') {
                throw 'S5_sample_summary is NOT an approved aggregate schema; DO NOT import it.'
            }
            $data = @($text | ConvertFrom-Csv -Delimiter ';')
            if ($data.Count -ne 3) { throw 'S5_sample_summary must contain exactly three aggregate species rows.' }
            $expected = @('Epirrita_autumnata', 'Operophtera_brumata', 'Operophtera_fagata')
            if ((@($data.species | Sort-Object) -join '|') -cne ($expected -join '|')) {
                throw 'Unexpected or duplicate species in S5_sample_summary.'
            }
            foreach ($row in $data) {
                foreach ($field in @('n_original','n_with_exact_previous_year','n_matched_dynamic')) {
                    if ($row.$field -cnotmatch '^[0-9]+$') { throw 'Invalid aggregate sample count.' }
                }
                $n = [long]$row.n_original; $previous = [long]$row.n_with_exact_previous_year
                $matched = [long]$row.n_matched_dynamic
                $ratio = [double]::Parse($row.proportion_retained.Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture)
                if ($n -le 0 -or $previous -gt $n -or $matched -gt $previous -or
                    [double]::IsNaN($ratio) -or [double]::IsInfinity($ratio) -or
                    [Math]::Abs($ratio - $matched / [double]$n) -gt 0.00001) {
                    throw 'Inconsistent aggregate sample counts/proportion.'
                }
            }
        }
    }
}

function Invoke-EiffelEvidenceImport([string]$SourceRoot, [string]$RepositoryRoot) {
    Initialize-EiffelNative
    $source = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $repo = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    if ($source -notmatch '^[A-Za-z]:\\' -or $repo -notmatch '^[A-Za-z]:\\' -or
        $source.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
        $repo.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $source.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source and repository must be separate, non-overlapping local drive directories.'
    }
    $target = [IO.Path]::Combine($repo, 'imported_local_evidence_v1')
    $allowPath = [IO.Path]::Combine($repo, 'project_state\audit_v1\LOCAL_EVIDENCE_REQUEST.csv')
    $guards = New-Object 'System.Collections.Generic.List[System.IDisposable]'
    $guarded = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $created = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $opened = New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
    $records = New-Object 'System.Collections.Generic.List[object]'
    $manifestStream = $null
    $failure = $null
    try {
        Protect-EiffelDirectory $source $guards $guarded
        Protect-EiffelDirectory $repo $guards $guarded
        if (Test-Path -LiteralPath $target) { throw 'Destination already exists. No overwrites or automatic retries.' }
        $allowStream = Open-EiffelSource $allowPath $guards $guarded
        $opened.Add($allowStream)
        $rows = @(Read-EiffelAllowList $allowPath)
        foreach ($row in $rows) {
            $relative = $row.relative_path
            $path = [IO.Path]::GetFullPath([IO.Path]::Combine($source, $relative.Replace('/', '\')))
            if (-not $path.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Source escapes root.' }
            $stream = Open-EiffelSource $path $guards $guarded
            $opened.Add($stream)
            if ($stream.Length -ne [long]$row.size_bytes) { throw "Size mismatch: $relative; expected $($row.size_bytes), actual $($stream.Length)" }
            Assert-EiffelSummaryContent $relative $stream
            $records.Add([pscustomobject]@{
                source_relative_path = $relative
                expected_size = [long]$row.size_bytes
                actual_size = $stream.Length
                sha256 = Get-EiffelHash $stream
                destination_path = [IO.Path]::Combine($target, $relative.Replace('/', '\'))
                status = 'NOT_COPIED'
                source_modified_utc = [IO.File]::GetLastWriteTimeUtc($path).ToString('o')
                stream = $stream
            })
        }
        # Nothing under the repository is written until ALL 51 pass preflight.
        New-EiffelDirectory $target $guards $guarded $created
        $manifestPath = [IO.Path]::Combine($target, 'evidence_manifest.csv')
        $manifestStream = [IO.File]::Open($manifestPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        foreach ($record in $records) {
            $record.status = 'FAILED'
            New-EiffelDirectory ([IO.Path]::GetDirectoryName($record.destination_path)) $guards $guarded $created
            $destination = [IO.File]::Open($record.destination_path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            try {
                if (-not (Get-EiffelPhysicalPath $destination.SafeFileHandle).Equals($record.destination_path, [StringComparison]::OrdinalIgnoreCase)) { throw 'Destination handle escapes expected location.' }
                $record.stream.Position = 0
                $record.stream.CopyTo($destination)
                $destination.Flush($true)
                if ($destination.Length -ne $record.expected_size -or
                    (Get-EiffelHash $destination) -cne $record.sha256 -or
                    (Get-EiffelHash $record.stream) -cne $record.sha256) { throw 'Copied bytes failed SHA256/size verification.' }
                $record.status = 'VERIFIED'
            } finally { $destination.Dispose() }
        }
    } catch { $failure = $_ }
    finally {
        if ($null -ne $manifestStream) {
            try {
                $csv = @($records | Select-Object source_relative_path,expected_size,actual_size,sha256,destination_path,status,source_modified_utc | ConvertTo-Csv -NoTypeInformation)
                $bytes = [Text.Encoding]::UTF8.GetBytes(($csv -join "`r`n") + "`r`n")
                $manifestStream.Write($bytes, 0, $bytes.Length)
                $manifestStream.Flush($true)
            } catch { $failure = $_ }
            finally { $manifestStream.Dispose() }
        }
        foreach ($stream in $opened) { $stream.Dispose() }
        for ($i = $guards.Count - 1; $i -ge 0; $i--) { $guards[$i].Dispose() }
    }
    if ($null -ne $failure) {
        throw "IMPORT REFUSED/FAILED: $($failure.Exception.Message). No source files were changed. Any partial destination is retained; do not reuse it."
    }
    Write-Host 'SUCCESS: 51/51 allow-listed files copied and SHA256 verified (50,918 bytes).'
    Write-Host "Destination: $target"
    Write-Host "Manifest: $manifestPath (51 VERIFIED rows)"
    Write-Host 'Source opened read-only. No R or models executed. Existing snapshots/results untouched.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ($args.Count -ne 0) { throw 'No arguments accepted: production roots and allow-list are fixed.' }
        $expectedTools = 'D:\EIFFEL-control\tools'
        if (-not [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\').Equals($expectedTools, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Run the repository script from D:\EIFFEL-control\tools.'
        }
        Invoke-EiffelEvidenceImport -SourceRoot 'D:\EIFFEL' -RepositoryRoot 'D:\EIFFEL-control'
    } catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}
