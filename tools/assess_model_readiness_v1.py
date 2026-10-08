"""Read-only arithmetic/diagnostic assessment of existing evidence. Never loads model objects."""
import argparse
import csv
import hashlib
import importlib.util
import json
import math
from collections import defaultdict
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('historical_audit', ROOT/'tools/audit_imported_lightweight.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
spec = importlib.util.spec_from_file_location('capture_hashes', ROOT/'tools/verify_fold5_capture.py')
hashes = importlib.util.module_from_spec(spec); spec.loader.exec_module(hashes)
SPECIES = ('Epirrita autumnata','Operophtera brumata','Operophtera fagata')
MODELS = ('WEATHER_ONLY','WEATHER_PLUS_ENVIRONMENT')
PREPARED_SPECIES = ('Lymantria monacha','Bupalus piniarius','Panolis flammea',*SPECIES)
CV = 'imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2'
PRED = 'imported_local/hmsc_outputs/HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2'
SUPP = 'imported_local_evidence_v1/hmsc_outputs/'
EXPL = 'HMSC_ANNUAL_SPECIES_SPECIFIC_FINAL_FITS_v4_INFERENCE_GATE'
S5 = 'HMSC_ANNUAL_SPECIES_ABUNDANCE_DEPENDENCIES_v2_RANDOMLEVEL_REBUILT'


def close(a,b):
    a,b=base.number(a),base.number(b)
    return (math.isnan(a) and math.isnan(b)) or (math.isfinite(a) and math.isfinite(b) and abs(a-b)<=1e-8+1e-9*abs(b))


def diagnostics(rows):
    assert rows and all(math.isfinite(base.number(r['observed'])) for r in rows), 'Nonfinite outcomes need explicit metric handling'
    m=base.metrics(rows)
    y=[base.number(r['observed']) for r in rows]
    p=[base.number(r['predicted_median']) for r in rows]
    errors=[(a-b)**2 for a,b in zip(y,p)]
    sse=sum(errors)
    m.update(zeros=sum(v==0 for v in y),positive=sum(v>0 for v in y),observed_max=max(y),
             log1p_RMSE=math.sqrt(statistics.mean((math.log1p(a)-math.log1p(b))**2 for a,b in zip(y,p))),
             largest_error_SSE_fraction=max(errors)/sse if sse else 0,
             five_largest_errors_SSE_fraction=sum(sorted(errors,reverse=True)[:5])/sse if sse else 0,
             always_present_O_RMSE=math.sqrt(sum(v==0 for v in y)/len(y)),
             observed_mean=statistics.mean(y),mean_of_predicted_medians=statistics.mean(p))
    return m


def assess(output, root=ROOT):
    root=Path(root)
    if Path(output).exists(): raise ValueError('Refusing existing diagnostic output directory')
    tracked=set()
    def read(path):
        p=root/path;tracked.add(path)
        header,rows,bad=base.table(p)
        assert not bad, 'Malformed rows: '+path
        return rows
    snapshot=root/'imported_fold5_completed_r2_v1';full=root/'project_state/outer_year_cv_full_v1'
    transport=[]
    hashes.verify(snapshot,True,transport);hashes.verify_audit(full,True,transport)
    assert (snapshot/'artifact_manifest.csv').read_bytes().replace(b'\r\n',b'\n')==(full/'INPUT_ARTIFACT_MANIFEST.csv').read_bytes().replace(b'\r\n',b'\n'), 'Input manifest archive disagreement'
    captured=read('imported_fold5_completed_r2_v1/checkpoint_verification.csv')
    required_checks=['checkpoint_schema','predictions_metrics','primary_partition_and_matched_ids','primary_observed_values','coverage','selected_predictors','r2_provenance','profile_compatibility_not_historical_identity','historical_folds_primary_observations','all_folds_exact_primary_matched_test_ids']
    assert [r['check'] for r in captured]==required_checks and all(r['status']=='PASS' for r in captured)
    inventory=read('project_state/nested_cv_reconstruction_v1/EVIDENCE_INVENTORY.csv')
    for r in inventory:
        path=root/CV/r['relative_path'];tracked.add(str(Path(CV)/r['relative_path']))
        data=path.read_bytes().replace(b'\r\n',b'\n')
        assert hashlib.md5(data).hexdigest()==r['md5'] and hashlib.sha256(data).hexdigest()==r['sha256']
    partition=read(CV+'/outer_year/outer_partition_blocks.csv2')
    year_folds={r['block_value']:int(r['fold']) for r in partition}
    coverage=read('project_state/outer_year_cv_full_v1/fold_coverage.csv')
    coverage_map={(int(r['outer_fold']),r['label']):r for r in coverage}
    all_groups=defaultdict(list); per_fold=[];metric_checks=[];selections=[];all_ids=[]
    locked=read('project_state/audit_v1/LOCKED_PREDICTORS.csv')
    locked_weather=[r['variable'] for r in locked if r['branch']=='predictive_weather']
    locked_env=[r['variable'] for r in locked if r['branch']=='predictive_environment']
    assert len(locked_weather)==5 and locked_env==['NDVI_mean__b100m','NDVI_median__b100m','NDVI_max__b100m']
    for fold in range(1,6):
        prefix=(f'imported_fold5_completed_r2_v1/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_05' if fold==5 else f'{CV}/outer_year/fold_{fold:02}')
        rows=read(prefix+'/outer_test_predictions.csv2');saved=read(prefix+'/outer_test_metrics.csv2')
        expected_columns=['evaluation','model_type','sample_id','site','year','species','observed','predicted_median','presence_probability','outer_fold','scheme']
        assert list(rows[0])==expected_columns
        assert {r['species'] for r in rows}==set(SPECIES) and {r['model_type'] for r in rows}==set(MODELS)
        groups=defaultdict(list)
        for r in rows:
            assert r['sample_id']==r['site']+'__'+r['year'] and year_folds[r['year']]==fold and int(r['outer_fold'])==fold
            assert r['scheme']=='year' and r['evaluation']=='outer_year'
            assert 0<=base.number(r['presence_probability'])<=1 and base.number(r['predicted_median'])>=0
            groups[(r['model_type'],r['species'])].append(r)
        reference=None
        for key,g in groups.items():
            ids=[r['sample_id'] for r in g]
            assert len(ids)==len(set(ids))==int(coverage_map[(fold,'outer_test_final_complete')]['n_site_years'])
            if reference is None:reference=ids;all_ids+=ids
            assert ids==reference
            ref=groups[('WEATHER_ONLY',key[1])]
            assert [r['observed'] for r in g]==[r['observed'] for r in ref]
            computed=diagnostics(g)
            saved_row=next(r for r in saved if (r['model_type'],r['species'])==key)
            for metric in ('n','RMSE','SR2','O.RMSE','O.AUC','O.TjurR2','C.RMSE','C.SR2'):
                assert close(computed[metric],saved_row[metric]), (fold,key,metric)
                metric_checks.append(dict(scope='fold',fold=fold,model=key[0],species=key[1],metric=metric,saved=saved_row[metric],recomputed=computed[metric],status='PASS'))
            per_fold.append(dict(fold=fold,model=key[0],species=key[1],producer_class='RECONSTRUCTED_COMPATIBILITY_R2' if fold==5 else 'HISTORICAL_V2',**computed))
            all_groups[key]+=g
        spath=f'{CV}/outer_year/fold_{fold:02}'
        weather=[r['variable'] for r in read(spath+'/01_weather_selection/selected_weather_variables.csv2')]
        env=[r['variable'] for r in read(spath+'/02_environment_selection/selected_environment_variables.csv2')]
        wg=[r['group'] for r in read(spath+'/01_weather_selection/selected_weather_groups.csv2')]
        eg=[r['group'] for r in read(spath+'/02_environment_selection/selected_environment_groups.csv2')]
        identical_models=all([(a['predicted_median'],a['presence_probability']) for a in groups[(MODELS[0],sp)]]==[(a['predicted_median'],a['presence_probability']) for a in groups[(MODELS[1],sp)]] for sp in SPECIES)
        assert bool(not env)==bool(identical_models), 'Check unexplained duplicate model predictions'
        selections.append(dict(fold=fold,weather_variables='|'.join(weather),environment_variables='|'.join(env),weather_groups='|'.join(wg),environment_groups='|'.join(eg),n_weather=len(weather),n_environment=len(env),full_data_weather_variables_retained=len(set(weather)&set(locked_weather)),full_data_environment_variables_retained=len(set(env)&set(locked_env)),identical_model_predictions=identical_models))
    assert len(all_ids)==len(set(all_ids))==1229 and len(year_folds)==32
    saved_pool=read('project_state/outer_year_cv_full_v1/pooled_five_fold_metrics.csv')
    pool=[]
    for key,g in all_groups.items():
        computed=diagnostics(g);saved=next(r for r in saved_pool if (r['model_type'],r['species'])==key)
        for metric in ('n','RMSE','SR2','O.RMSE','O.AUC','O.TjurR2','C.RMSE','C.SR2'):
            assert close(computed[metric],saved[metric]),(key,metric)
            metric_checks.append(dict(scope='pooled',fold='ALL',model=key[0],species=key[1],metric=metric,saved=saved[metric],recomputed=computed[metric],status='PASS'))
        pool.append(dict(model=key[0],species=key[1],**computed))
    deltas=[]
    for sp in SPECIES:
        w=next(r for r in pool if r['species']==sp and r['model']==MODELS[0]);e=next(r for r in pool if r['species']==sp and r['model']==MODELS[1])
        wfold=[r for r in per_fold if r['species']==sp and r['model']==MODELS[0]]
        efold=[r for r in per_fold if r['species']==sp and r['model']==MODELS[1]]
        ds=[b['SR2']-a['SR2'] for a,b in zip(wfold,efold)]
        deltas.append(dict(species=sp,delta_RMSE=e['RMSE']-w['RMSE'],relative_RMSE_reduction=(w['RMSE']-e['RMSE'])/w['RMSE'],delta_SR2=e['SR2']-w['SR2'],delta_O_AUC=e['O.AUC']-w['O.AUC'],delta_O_RMSE=e['O.RMSE']-w['O.RMSE'],fold_SR2_positive=sum(d>1e-12 for d in ds),fold_SR2_negative=sum(d < -1e-12 for d in ds),fold_SR2_tied=sum(abs(d)<=1e-12 for d in ds)))
    ppc_checks=[]
    for branch,paths in [('predictive_full_data',[SUPP+'HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2/04_final_models/'+name for name in ['FINAL_ANNUAL_WEATHER_ONLY_MATCHED_PPC_offset_corrected.csv2','FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_PPC_offset_corrected.csv2']]),('explanatory_v4',[SUPP+EXPL+'/results/S4_ALL_SPECIES_PPC.csv2'])]:
        for path in paths:
            for r in read(path):
                for label in ('mean','zero','q95','q99','maximum'):
                    if branch=='predictive_full_data':
                        obs='observed_zero_proportion' if label=='zero' else 'observed_'+label
                        lower='predicted_'+label+'_q025';upper='predicted_'+label+'_q975';flag=label+'_covered_95'
                    else:
                        l='max' if label=='maximum' else label
                        obs='observed_'+l;lower=l+'_q025';upper=l+'_q975';flag=l+'_covered'
                    inside=base.number(r[lower])<=base.number(r[obs])<=base.number(r[upper])
                    assert inside==(r[flag]=='TRUE')
                    ppc_checks.append(dict(branch=branch,model=r.get('model','SPECIES_SPECIFIC_FINAL_V4'),species=r['species'],statistic=label,observed=r[obs],lower=r[lower],upper=r[upper],covered=inside,ppc_status=r['ppc_status'],check='PASS'))
    convergence=[]
    for branch,path in [('explanatory_v4',f'imported_local/hmsc_outputs/{EXPL}/results/S4_ALL_SPECIES_final_convergence_summary.csv2'),('species_association_S5',f'imported_local/hmsc_outputs/{S5}/results/S5_ALL_SPECIES_convergence_summary.csv2')]:
        for r in read(path):
            diagnostic=base.number(r['maximum_PSRF_upper'])<=base.number(r['PSRF_limit']) and base.number(r['minimum_ESS'])>=base.number(r['ESS_limit'])
            accepted=diagnostic or r['blocks_inference']=='FALSE'
            assert diagnostic==(r['diagnostic_accepted']=='TRUE') and accepted==(r['accepted']=='TRUE')
            convergence.append(dict(branch=branch,model=r.get('model','SPECIES_SPECIFIC_FINAL_V4'),species=r['species'],component=r['component'],random_level=r['random_level'],maximum_PSRF_upper=r['maximum_PSRF_upper'],minimum_ESS=r['minimum_ESS'],recorded_PSRF_limit=r['PSRF_limit'],recorded_ESS_limit=r['ESS_limit'],diagnostic_pass=diagnostic,recorded_policy_accept=accepted,status='RECORDED_POLICY_PASS_WITH_FAILED_NONBLOCKING_COMPONENT' if accepted and not diagnostic else 'RECORDED_DIAGNOSTIC_PASS_NOT_RANK_NORMALIZED_RHAT_CERTIFICATION'))
    for model in MODELS:
        convergence.append(dict(branch='predictive_full_data',model=model,species='|'.join(SPECIES),component='NOT_EXPORTED',random_level='',maximum_PSRF_upper='',minimum_ESS='',recorded_PSRF_limit='',recorded_ESS_limit='',diagnostic_pass='',recorded_policy_accept='',status='MISSING_PREDICTIVE_CONVERGENCE_EVIDENCE'))
    vp=read(PRED+'/04_final_models/FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_variance_partitioning.csv2')
    for sp in SPECIES:
        assert close(sum(base.number(r['variance_proportion']) for r in vp if r['species']==sp),1)
    legacy=read(PRED+'/04_final_models/FINAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_metrics.csv2')
    optimism=[]
    for sp in SPECIES:
        ins=next(r for r in legacy if r['species']==sp and r['evaluation']=='explanatory_offset_corrected')
        out=next(r for r in pool if r['species']==sp and r['model']==MODELS[1])
        optimism.append(dict(species=sp,in_sample_SR2=ins['SR2'],nested_pooled_SR2=out['SR2'],descriptive_SR2_gap=base.number(ins['SR2'])-out['SR2'],different_panels_and_estimands=True,overfitting_test='NOT_FORMAL_OVERFITTING_PROOF'))
    dedicated=read(f'imported_local/hmsc_outputs/{EXPL}/results/S4_ALL_SPECIES_occurrence_metrics.csv2')
    generic=read(SUPP+EXPL+'/results/S4_ALL_SPECIES_explanatory_fit.csv2');inconsistencies=[]
    for r in generic:
        good=next(z for z in dedicated if z['species']==r['species'])
        assert base.number(r['O.AUC'])==.5 and base.number(r['O.TjurR2'])==0
        inconsistencies.append(dict(branch='explanatory_v4',species=r['species'],generic_O_AUC=r['O.AUC'],dedicated_O_AUC=good['O.AUC'],generic_O_TjurR2=r['O.TjurR2'],dedicated_O_TjurR2=good['O.TjurR2'],status='CONTRADICTORY_EXPORTS_DO_NOT_USE_GENERIC_OCCURRENCE_COLUMNS'))
    targets=[dict(species=sp,prepared_in_six_species_code=True,verified_nested_CV_evidence=sp in SPECIES,readiness='THREE_SPECIES_EVIDENCE_ONLY' if sp in SPECIES else 'NO_IMPORTED_MODEL_VALIDATION_EVIDENCE_DO_NOT_INSPECT_ACTIVE_CONIFER_JOB') for sp in PREPARED_SPECIES]
    tables={'CV_METRIC_CHECKS.csv':metric_checks,'POOLED_PERFORMANCE.csv':pool,'FOLD_PERFORMANCE.csv':per_fold,'ENVIRONMENT_DELTAS.csv':deltas,'SELECTION_STABILITY.csv':selections,'PPC_INTERVAL_CHECKS.csv':ppc_checks,'CONVERGENCE_REVIEW.csv':convergence,'VARIANCE_PARTITION_REVIEW.csv':vp,'IN_SAMPLE_VS_NESTED.csv':optimism,'OCCURRENCE_EXPORT_INCONSISTENCIES.csv':inconsistencies,'SPECIES_COVERAGE.csv':targets,'EXPLORATORY_FIXED_PREDICTOR_CV.csv':legacy}
    # Output only after all real-evidence checks have passed. No source outputs modified.
    output=Path(output);output.mkdir(parents=True,exist_ok=False)
    for name,rows in tables.items():base.write(output/name,rows,list(rows[0]))
    for r in transport:r['path']=str(Path(r['path']).relative_to(root))
    base.write(output/'TRANSPORT_HASH_CHECKS.csv',transport,list(transport[0]))
    for prefix,manifest in [('imported_fold5_completed_r2_v1','artifact_manifest.csv'),('project_state/outer_year_cv_full_v1','AUDIT_ARTIFACT_MANIFEST.csv')]:
        tracked.add(prefix+'/'+manifest)
        tracked.update(prefix+'/'+r['relative_path'] for r in read(prefix+'/'+manifest))
    source_hashes=[dict(path=p,sha256_git_or_local_bytes=hashlib.sha256((root/p).read_bytes()).hexdigest(),bytes=(root/p).stat().st_size) for p in sorted(tracked)]
    base.write(output/'INPUT_FINGERPRINTS.csv',source_hashes,list(source_hashes[0]))
    status=dict(five_fold_metric_cells_verified=len(metric_checks),real_prediction_rows=sum(len(g) for g in all_groups.values()),matched_site_years=len(all_ids),available_years=len(year_folds),evaluated_years=len({r['year'] for g in all_groups.values() for r in g}),species_verified=list(SPECIES),six_species_verified=False,source_byte_hash_checks=len(transport),transport_restorations=sum(r['transport_status']!='EXACT_GIT_BYTES' for r in transport),PPC_interval_flags_verified=len(ppc_checks),convergence_policy_rows_verified=len(convergence)-2,predictive_convergence_available=False,publication_of_final_ecological_claims_ready=False,spatial_prediction_ready=False,model_runs=0)
    (output/'CHECK_STATUS.json').write_text(json.dumps(status,indent=2)+'\n')
    return status

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path,required=True)
    print(json.dumps(assess(parser.parse_args().output),indent=2))
