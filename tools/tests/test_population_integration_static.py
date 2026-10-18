#!/usr/bin/env python3
"""Strictly static candidate-package checks. No dataset or external commands."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
runner = (ROOT / 'tools/run_eiffel_local_workflow.ps1').read_text(encoding='utf-8')
existing = (ROOT / 'R/population_dynamics/BUILD_POPULATION_HISTORY_v1.R').read_text()
tasks = json.loads((ROOT / '.vscode/tasks.json').read_text())['tasks']
checks = []

def ok(condition, name):
    assert condition, name
    checks.append(name)

ok("[string]$Mode = 'PopulationStatus'" in runner, 'read-only safe default')
ok("if ($Mode -ne 'PopulationStatus')" in runner, 'status avoids logs')
ok("'PopulationStatus' { Show-PopulationStatus }" in runner, 'status dispatch')
ok("'PopulationHistory' { Build-PopulationHistory }" in runner, 'explicit derived stage')
ok('Find-ReusablePopulationHistory $annual' in runner, 'hash reuse')
ok('Assert-ApprovedAnnual $build.FullName' in runner, 'QA gate')
ok('& $launcher -Mode build -Script $populationScript' in runner,
   'derived script explicit to existing guarded runner')
ok('if (!identical(args, \'--build\'))' in existing, 'R requires explicit --build')
ok('population_make_history(x)' in existing, 'reuse population module')
ok('if (file.exists(output))' in existing, 'no output overwrite')
ok('file.rename(stage, output)' in existing, 'atomic derived publish')
ok(all('Hmsc' not in line for line in runner.splitlines()
       if ('& $launcher ' in line)), 'no Hmsc executable path')
labels = [t['label'] for t in tasks]
ok(len(labels) == len(set(labels)), 'unique task names')
defaults = [t for t in tasks if isinstance(t.get('group'), dict) and t['group'].get('isDefault')]
ok(len(defaults) == 1 and defaults[0]['label'] == 'EIFFEL: Tila (ei uusia laskentoja)',
   'safe VS Code default')
ok('EIFFEL: Paivita + muodosta + validoi (YKSI TEHTAVA)' in labels,
   'legacy intentional full build preserved')
ok('EIFFEL: Muodosta vain puuttuva populaatiohistoria' in labels,
   'explicit population history task')
ok((ROOT / 'tools/tests/Test-PopulationLauncherSyntax.ps1').exists(),
   'PowerShell syntax/contract check')
print('PASS:', len(checks), 'static checks only (NOT a PowerShell or R execution)')
