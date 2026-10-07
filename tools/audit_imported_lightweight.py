"""Read-only lightweight audit; never imports R code or runs scientific models.

Usage: python tools/audit_imported_lightweight.py --output work/audit_checks
Outputs are new audit tables. Existing output directories are refused.
"""
import argparse
import csv
import hashlib
import json
import math
import statistics
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def number(value):
    try:
        return float(str(value).replace(',', '.'))
    except ValueError:
        return math.nan

def table(path):
    text = path.read_text(encoding='utf-8-sig')
    first = text.splitlines()[0] if text.splitlines() else ''
    delim = ';' if ';' in first else '\t' if '\t' in first else ','
    raw = list(csv.reader(text.splitlines(), delimiter=delim))
    if not raw:
        return [], [], 0
    header = raw[0]
    bad = sum(len(r) != len(header) for r in raw[1:] if r)
    return header, [dict(zip(header, r)) for r in raw[1:] if r], bad

def write(path, rows, fields):
    with path.open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)

def ranks(values):
    order = sorted(range(len(values)), key=values.__getitem__)
    result = [0.] * len(values)
    i = 0
    while i < len(order):
        j = i + 1
        while j < len(order) and values[order[j]] == values[order[i]]:
            j += 1
        for k in order[i:j]:
            result[k] = (i + 1 + j) / 2
        i = j
    return result

def sr2(x, y):
    if len(x) < 3:
        return math.nan
    x, y = ranks(x), ranks(y)
    mx, my = statistics.mean(x), statistics.mean(y)
    denom = math.sqrt(sum((v-mx)**2 for v in x) * sum((v-my)**2 for v in y))
    if denom == 0:
        return math.nan
    rho = sum((a-mx)*(b-my) for a,b in zip(x,y)) / denom
    return math.copysign(rho*rho, rho)

def metrics(rows):
    y = [number(r['observed']) for r in rows]
    pred = [number(r['predicted_median']) for r in rows]
    prob = [number(r['presence_probability']) for r in rows]
    positive = [i for i,v in enumerate(y) if v > 0]
    absent = [i for i,v in enumerate(y) if v == 0]
    auc = math.nan
    tjur = math.nan
    if positive and absent:
        ranked = ranks(prob)
        auc = (sum(ranked[i] for i in positive) - len(positive)*(len(positive)+1)/2) / (len(positive)*len(absent))
        tjur = statistics.mean(prob[i] for i in positive) - statistics.mean(prob[i] for i in absent)
    rmse = lambda a,b: math.sqrt(statistics.mean((v-w)**2 for v,w in zip(a,b)))
    cy = [y[i] for i in positive]
    cp = [pred[i] for i in positive]
    return {'n':len(y), 'RMSE':rmse(y,pred), 'SR2':sr2(y,pred),
            'O.RMSE':rmse([float(v>0) for v in y],prob), 'O.AUC':auc, 'O.TjurR2':tjur,
            'C.RMSE':rmse(cy,cp) if cy else math.nan, 'C.SR2':sr2(cy,cp)}

def audit(output):
    if output.exists():
        raise SystemExit('Refusing to overwrite an existing audit output directory.')
    output.mkdir(parents=True)
    manifest = list(csv.DictReader((ROOT/'local_manifest.csv').open(encoding='utf-8-sig')))
    copied = {r['relative_path'].replace('\\','/') for r in manifest if r['copied']=='yes'}
    files = sorted(p for p in (ROOT/'imported_local').rglob('*') if p.is_file())
    present = {p.relative_to(ROOT/'imported_local').as_posix() for p in files}
    inventory, convergence, problems = [], [], []
    for path in files:
        content = path.read_bytes()
        rel = path.relative_to(ROOT).as_posix()
        header, rows, malformed = [], [], 0
        if path.suffix.lower() in {'.csv','.csv2','.tsv','.txt'}:
            header, rows, malformed = table(path)
        flags = Counter(r.get(k,'') for r in rows for k in ['status','ppc_status','accepted','diagnostic_accepted'] if r.get(k,''))
        inventory.append({'file_path':rel, 'bytes_decoded':len(content), 'sha256_decoded':hashlib.sha256(content).hexdigest(),
                          'rows':len(rows), 'columns':'|'.join(header), 'malformed_rows':malformed,
                          'flags':json.dumps(dict(flags),sort_keys=True)})
        if malformed:
            problems.append({'file_path':rel,'issue':'ragged_table','count':malformed})
        if 'maximum_PSRF_upper' in header and 'accepted' in header:
            for i,r in enumerate(rows,2):
                psrf, ess = number(r['maximum_PSRF_upper']), number(r['minimum_ESS'])
                diagnostic = math.isfinite(psrf) and math.isfinite(ess) and psrf<=number(r['PSRF_limit']) and ess>=number(r['ESS_limit'])
                blocks = r.get('blocks_inference','TRUE')=='TRUE'
                accepted = diagnostic or not blocks
                matches = accepted == (r['accepted']=='TRUE')
                convergence.append({'file_path':rel,'line':i,'species':r.get('species',''), 'model':r.get('model',''),
                                    'component':r['component'],'random_level':r.get('random_level',''),
                                    'diagnostic_pass':diagnostic,'blocks_inference':blocks,'reported_accepted':r['accepted'],
                                    'policy_recalculation_matches':matches})
                if not matches:
                    problems.append({'file_path':rel,'issue':'convergence_policy_mismatch','count':1})
    checks, coverage, selections = [], [], []
    outer = ROOT/'imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year'
    partition = {r['block_value']:int(r['fold']) for r in table(outer/'outer_partition_blocks.csv2')[1]}
    for fold_dir in sorted(outer.glob('fold_*')):
        fold = int(fold_dir.name.split('_')[1])
        cov = {r['label']:int(r['n_site_years']) for r in table(fold_dir/'outer_fold_coverage.csv2')[1]}
        has_predictions = (fold_dir/'outer_test_predictions.csv2').exists()
        coverage.append({'fold':fold,'all_test_rows':cov['outer_test_all'],'complete_test_rows':cov['outer_test_final_complete'],
                         'excluded_test_rows':cov['outer_test_all']-cov['outer_test_final_complete'],'predictions_present':has_predictions})
        for kind in ['weather','environment']:
            path = fold_dir/('01_weather_selection/selected_weather_variables.csv2' if kind=='weather' else '02_environment_selection/selected_environment_variables.csv2')
            for row in table(path)[1]:
                selections.append({'fold':fold,'kind':kind,'variable':row['variable']})
        if not has_predictions:
            continue
        pred_rows = table(fold_dir/'outer_test_predictions.csv2')[1]
        groups = defaultdict(list)
        for r in pred_rows:
            assert partition[r['year']]==fold, 'Prediction assigned to wrong outer fold'
            groups[(r['model_type'],r['species'])].append(r)
        for species in {r['species'] for r in pred_rows}:
            ref = {r['sample_id']:r['observed'] for r in groups[('WEATHER_ONLY',species)]}
            cand = {r['sample_id']:r['observed'] for r in groups[('WEATHER_PLUS_ENVIRONMENT',species)]}
            assert ref==cand and len(ref)==cov['outer_test_final_complete'], 'Unmatched final outer samples'
            assert len(ref)==len(groups[('WEATHER_ONLY',species)]), 'Duplicate prediction sample'
        for row in table(fold_dir/'outer_test_metrics.csv2')[1]:
            computed = metrics(groups[(row['model_type'],row['species'])])
            for name,value in computed.items():
                reported = number(row[name])
                agrees = (math.isnan(value) and math.isnan(reported)) or math.isclose(value,reported,abs_tol=1e-8,rel_tol=1e-9)
                checks.append({'fold':fold,'model':row['model_type'],'species':row['species'],'metric':name,
                               'reported':row[name],'recomputed':value,'matches':agrees})
                if not agrees:
                    problems.append({'file_path':(fold_dir/'outer_test_metrics.csv2').relative_to(ROOT).as_posix(),'issue':f'metric_mismatch:{name}','count':1})
    write(output/'FILE_AUDIT.csv',inventory,list(inventory[0]))
    write(output/'CONVERGENCE_POLICY_CHECKS.csv',convergence,list(convergence[0]))
    write(output/'OUTER_FOLD_METRIC_CHECKS.csv',checks,list(checks[0]))
    write(output/'OUTER_FOLD_COVERAGE.csv',coverage,list(coverage[0]))
    write(output/'OUTER_FOLD_PREDICTORS.csv',selections,list(selections[0]))
    write(output/'AUDIT_CHECK_ISSUES.csv',problems,['file_path','issue','count'])
    summary={'manifest_rows':len(manifest),'imported_files':len(files),'scripts':sum(p.suffix.lower()=='.r' for p in files),
             'summaries':sum(p.suffix.lower()!='.r' for p in files),'missing_copied_files':sorted(copied-present),
             'unmanifested_imports':sorted(present-copied),'convergence_checks':len(convergence),'metric_checks':len(checks),
             'check_issues':len(problems),'models_run':0}
    (output/'CHECK_SUMMARY.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
    return bool(problems or copied!=present)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    raise SystemExit(int(audit(args.output)))
