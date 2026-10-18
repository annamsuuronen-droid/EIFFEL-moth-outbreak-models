# No real data access, no process launches and no scientific calculations.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcher = Join-Path $repo 'tools\run_eiffel_local_workflow.ps1'
$tasksFile = Join-Path $repo '.vscode\tasks.json'
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $launcher, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$source = Get-Content -LiteralPath $launcher -Raw
if (-not $source.Contains("[string]`$Mode = 'PopulationStatus'")) {
    throw 'The safe read-only status mode must be the launcher default'
}
foreach ($name in @('PopulationStatus','PopulationHistory')) {
    if (-not $source.Contains("'$name'")) {
        throw "Required mode missing from launcher: $name"
    }
}
if (-not (Test-Path -LiteralPath $tasksFile)) { throw 'Missing VS Code tasks' }
$tasks = (Get-Content -LiteralPath $tasksFile -Raw | ConvertFrom-Json).tasks
$default = @($tasks | Where-Object { $_.group.isDefault -eq $true })
if ($default.Count -ne 1 -or $default[0].label -ne 'EIFFEL: Tila (ei uusia laskentoja)') {
    throw 'Exactly one read-only status task must be the VS Code default'
}
if ($default[0].args[-1] -cne 'PopulationStatus' -or $default[0].dependsOn -or
    $default[0].runOptions.runOn -eq 'folderOpen') {
    throw 'Default task must dispatch status directly, without dependencies or auto-run'
}
if (@($tasks | Where-Object { $_.label -eq 'EIFFEL: Muodosta vain puuttuva populaatiohistoria' }).Count -ne 1) {
    throw 'Missing explicit population-history task'
}
$history = @($tasks | Where-Object { $_.label -eq 'EIFFEL: Muodosta vain puuttuva populaatiohistoria' })[0]
if ($history.args[-1] -cne 'PopulationHistory' -or $history.dependsOn -or
    $history.runOptions.runOn -eq 'folderOpen') {
    throw 'Population task must be explicit, without upstream dependencies'
}
if (@($tasks | Where-Object { $_.label -eq 'EIFFEL: 2 Muodosta Saa+Frost ja validoi' }).Count -ne 1) {
    throw 'Historical annual build task was removed'
}
Write-Host 'PASS: PowerShell parser + one status-default / explicit derived-stage task.'
Write-Host 'Only synthetic/static checks; no annual source, model, CV or protected files read.'
