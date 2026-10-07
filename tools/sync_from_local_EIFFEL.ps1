#requires -Version 5.1
<#!
Read-only discovery of a local EIFFEL project. No R code is executed.
Run from a separate repository checkout outside the source tree.
The manifest includes all discovered regular files, even excluded ones.
Directory links/junctions are not traversed; inaccessible paths cause failure.
!#>
[CmdletBinding()]
param(
    [string]$SourceRoot = 'D:\EIFFEL',
    [string]$RepositoryRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Get-Item -LiteralPath $SourceRoot -Force).FullName.TrimEnd('\', '/')
$repo = (Get-Item -LiteralPath $RepositoryRoot -Force).FullName.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'Source must be a directory.' }
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw 'Destination must be a Git checkout.' }
function Test-Within([string]$Child, [string]$Parent) {
    return $Child.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or
        $Child.StartsWith($Parent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
if ((Test-Within $repo $source) -or (Test-Within $source $repo)) {
    throw 'Source and repository must be separate, non-nested directories. Nothing was copied.'
}
# Reject linked ancestors as well as linked source/destination roots.
foreach ($root in @($source, $repo)) {
    $ancestor = Get-Item -LiteralPath $root -Force
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked root or ancestor is not supported: $($ancestor.FullName)"
        }
        $ancestor = $ancestor.Parent
    }
}
$destination = Join-Path $repo 'imported_local'
$manifest = Join-Path $repo 'local_manifest.csv'
if ((Test-Path -LiteralPath $destination) -or (Test-Path -LiteralPath $manifest)) {
    throw 'One-time import already exists. Refusing to overwrite imported_local/ or local_manifest.csv.'
}
$scriptExtensions = @('.r', '.rmd', '.qmd', '.md')
$tableExtensions = @('.txt', '.csv', '.csv2', '.tsv')
$scriptLimit = 1MB
$tableLimit = 256KB
$totalLimit = 20MB
# Broad data exclusions take precedence over summary names. All files in these
# directories are logged as excluded, including scripts; review omitted scripts later.
$excludedDirectoryPattern = '(?i)^(\.git|\.svn|\.hg|\.Rproj\.user|\.cache|__pycache__|node_modules|renv|packrat|tmp|temp|temporary|cache|caches|raw|data|raw[_-]?data|data[_-]?raw|input|inputs|hmsc|mcmc|mcmc[_-]?objects|model[_-]?objects|archive|archives|backup|backups)$'
$excludedFilePattern = '(?i)(^|[_ .-])(raw|observations?|records?|mcmc|samples?|chains?|draws?|cache|temp|temporary|backup)([_ .-]|$)'
$summaryPattern = '(?i)(^|[\\/_. -])(summary|summaries|results?[_-]?summary|model[_-]?fit|beta[_-]?effects|variance[_-]?partitioning|posterior[_-]?predictive[_-]?checks|species[_-]?dependencies|outer[_-]?cv|growth[_-]?models|population[_-]?lags|validation|metrics|coefficients|diagnostics|methods|readme|decisions)([\\/_. -]|$)'
$rows = New-Object 'System.Collections.Generic.List[object]'
$queue = New-Object 'System.Collections.Generic.Stack[object]'
$queue.Push([pscustomobject]@{ Path = $source; Reason = '' })
$linkDirectories = 0
Write-Host "Discovering lightweight material under $source (source is read-only)."
while ($queue.Count -gt 0) {
    $entry = $queue.Pop()
    foreach ($item in Get-ChildItem -LiteralPath $entry.Path -Force | Sort-Object Name) {
        $relative = $item.FullName.Substring($source.Length + 1)
        $reason = $entry.Reason
        $isLink = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
        if ($item.PSIsContainer) {
            if ($isLink) { $linkDirectories++; Write-Warning "Not traversing linked directory: $relative"; continue }
            if (-not $reason -and $item.Name -match $excludedDirectoryPattern) {
                $reason = "excluded directory: $relative"
            }
            $queue.Push([pscustomobject]@{ Path = $item.FullName; Reason = $reason })
            continue
        }
        $extension = $item.Extension.ToLowerInvariant()
        if ($isLink) { $reason = 'symbolic link/reparse point' }
        if (-not $reason -and $extension -notin ($scriptExtensions + $tableExtensions)) {
            $reason = 'extension not allowlisted (binary/GIS/archive/image/model objects excluded)'
        }
        if (-not $reason -and $item.BaseName -match $excludedFilePattern) {
            $reason = 'raw data/model object/temporary filename marker'
        }
        if (-not $reason -and $extension -in $scriptExtensions -and $item.Length -gt $scriptLimit) {
            $reason = 'script/document exceeds 1 MiB'
        }
        if (-not $reason -and $extension -in $tableExtensions) {
            if ($item.Length -gt $tableLimit) { $reason = 'text/table exceeds 256 KiB' }
            elseif ($relative -notmatch $summaryPattern) { $reason = 'text/table lacks recognized summary/document context; manual review required' }
        }
        $rows.Add([pscustomobject]@{
            source_path = $item.FullName
            relative_path = $relative
            extension = $extension
            size_bytes = $item.Length
            modified_timestamp_utc = $item.LastWriteTimeUtc.ToString('o')
            copied = 'no'
            exclusion_reason = $reason
        })
    }
}
# Discovery must finish successfully before any copies are attempted.
[long]$copiedBytes = 0
[int]$copiedCount = 0
[int]$copyErrors = 0
New-Item -ItemType Directory -Path $destination | Out-Null
foreach ($row in $rows | Sort-Object relative_path) {
    if ($row.exclusion_reason) { continue }
    if ($copiedBytes + $row.size_bytes -gt $totalLimit) {
        $row.exclusion_reason = 'aggregate copy limit of 20 MiB reached'
        continue
    }
    $target = Join-Path $destination $row.relative_path
    try {
        # A changing source is not a stable provenance snapshot.
        $current = Get-Item -LiteralPath $row.source_path -Force
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            $current.Length -ne $row.size_bytes -or
            $current.LastWriteTimeUtc.ToString('o') -ne $row.modified_timestamp_utc) {
            throw 'Source changed after discovery; skipped.'
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        # Copy without overwrite, even if another process has created the target.
        [IO.File]::Copy($row.source_path, $target, $false)
        $row.copied = 'yes'
        $copiedCount++
        $copiedBytes += $row.size_bytes
    } catch {
        $copyErrors++
        $row.exclusion_reason = "copy failed: $($_.Exception.Message)"
        Write-Warning "Copy failed: $($row.relative_path)"
    }
}
if ($rows.Count -gt 0) {
    $rows | Sort-Object relative_path | Export-Csv -LiteralPath $manifest -NoTypeInformation -Encoding UTF8
} else {
    '"source_path","relative_path","extension","size_bytes","modified_timestamp_utc","copied","exclusion_reason"' |
        Set-Content -LiteralPath $manifest -Encoding UTF8
}
Write-Host ''
Write-Host "Considered files: $($rows.Count)"
Write-Host "Copied: $copiedCount ($copiedBytes bytes)"
Write-Host "Not copied: $($rows.Count - $copiedCount)"
Write-Host "Linked directories not traversed: $linkDirectories"
Write-Host "Copy errors: $copyErrors"
Write-Host "Import: $destination"
Write-Host "Manifest: $manifest"
Write-Host 'Source originals were not modified. No R model was executed.'
Write-Host 'Review manifest and imported content for raw/sensitive data before staging or pushing.'
Write-Host 'Importing scripts does not establish active or authoritative status.'
if ($copyErrors -gt 0) { throw 'Import completed with copy errors. Review the manifest before committing.' }
