import argparse,csv,hashlib,importlib.util,json,math,re
from pathlib import Path
r=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Read-only P0 inventory/code/evidence investigation; no R/model objects.')
parser.add_argument('--output',type=Path,required=True)
out=parser.parse_args().output
if out.exists():raise ValueError('Refusing existing investigation output')
out.mkdir(parents=True,exist_ok=False)
s=importlib.util.spec_from_file_location('a',r/'tools/audit_imported_lightweight.py');a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
tracked=set()
def read(p):
 tracked.add(p);h,rows,bad=a.table(r/p);assert not bad,p;return rows
def write(name,rows):
 p=out/name
 if p.exists():raise ValueError('Refusing existing P0 output '+name)
 with p.open('x',newline='',encoding='utf-8') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]),lineterminator='\n');w.writeheader();w.writerows(rows)
tracked.add('local_manifest.csv')
manifest=list(csv.DictReader((r/'local_manifest.csv').open(encoding='utf-8-sig',newline='')))
inventory=[]
for x in manifest:
 p=x['relative_path'].replace('\\','/')
 if 'conifer' in p.lower() or 'PREDICTIVE' not in p or x['extension'].lower() not in ['.rds','.rdata','.rda']:continue
 role=('DIRECT_HMSC_MODEL_CANDIDATE' if p.endswith('_Hmsc_model.rds') else
       'FITTED_SESSION_CONTAINER_UNINSPECTED' if p.endswith('_fitted.RData') else
       'SELECTION_CACHE_NOT_ESTABLISHED_AS_SAVED_CHAINS' if '/cache/' in p else
       'COMPLETION_OR_METADATA_NOT_ESTABLISHED_AS_SAVED_CHAINS')
 inventory.append(dict(source_relative_path=p,recorded_bytes=x['size_bytes'],role=role,source_evidence='Phase1 manifest; runtime filesystem not accessible',cloud_object_inspected=False))
assert len(inventory)==2478
write('PREDICTIVE_BINARY_INVENTORY.csv',inventory)
existing=[]
for x in manifest:
 p=x['relative_path'].replace(chr(92),'/')
 if 'PREDICTIVE' not in p:continue
 m=re.search(r'_(Beta|Gamma|V|Sigma)_(ESS|gelman)\.txt$',p)
 if not m:continue
 scope=('current_weather' if 'WEATHER_ONLY_MATCHED_' in p else 'current_environment' if 'WEATHER_PLUS_ENVIRONMENT_MATCHED_' in p else 'legacy_primary' if 'PRIMARY_PREDICTIVE_' in p else 'sensitivity')
 existing.append(dict(source_relative_path=p,size=x['size_bytes'],scope=scope,type=m[2],status='LOCATED_IN_MANIFEST_NOT_IMPORTED_VALUES_UNKNOWN'))
assert len(existing)==32
write('EXISTING_DIAGNOSTICS_INVENTORY.csv',existing)
fold2='imported_local/hmsc_outputs/S3_HMSC_NESTED_OUTER_CV_PREDICTIVE_v2/outer_year/fold_02/outer_test_predictions.csv2'
ext=[x for x in read(fold2) if x['species']=='Epirrita autumnata' and a.number(x['observed'])==379332]
assert len(ext)==2 and {x['sample_id'] for x in ext}=={'1308__2004'}
write('EXTREME_TRACE.csv',[dict(stage='VERIFIED_HELD_OUT_OBSERVATION',site=x['site'],year=x['year'],species=x['species'],value=x['observed'],model=x['model_type'],source=fold2,original_raw_source_verified=False) for x in ext])
supp='imported_local_evidence_v1/hmsc_outputs/';pred='HMSC_ANNUAL_PREDICTIVE_ONE_BUFFER_MATCHED_ENVIRONMENT_SELECTION_v2/04_final_models/'
zero=[]
for name in ['FINAL_ANNUAL_WEATHER_ONLY_MATCHED_PPC_offset_corrected.csv2','FINAL_ANNUAL_WEATHER_PLUS_ENVIRONMENT_MATCHED_PPC_offset_corrected.csv2']:
 p=supp+pred+name;g=next(x for x in read(p) if x['species']=='Operophtera fagata')
 n=int(g['n']);observed=a.number(g['observed_zero_proportion']);count=round(n*observed)
 assert abs(n*observed-count)<1e-8 and g['zero_covered_95']=='FALSE'
 zero.append(dict(source=p,model=g['model'],n=n,observed_zero_count=count,observed_zero_fraction=observed,
  predicted_zero_fraction_q025=a.number(g['predicted_zero_q025']),predicted_zero_fraction_median=a.number(g['predicted_zero_median']),predicted_zero_fraction_q975=a.number(g['predicted_zero_q975']),
  observed_minus_median_zero_count=n*(observed-a.number(g['predicted_zero_median'])),ppc_p=a.number(g['zero_ppc_p']),
  check='VERIFIED_PPC_DISCREPANCY_CAUSE_UNRESOLVED'))
write('FAGATA_ZERO_INVESTIGATION.csv',zero)
v=[x for x in read('project_state/model_diagnostics_v1/CONVERGENCE_REVIEW.csv') if x['component']=='V']
assert len(v)==9 and all(x['diagnostic_pass']=='False' and x['recorded_policy_accept']=='True' for x in v)
write('V_POLICY_REVIEW.csv',v)
expl='HMSC_ANNUAL_SPECIES_SPECIFIC_FINAL_FITS_v4_INFERENCE_GATE/results/'
generic=read(supp+expl+'S4_ALL_SPECIES_explanatory_fit.csv2')
ppc=read(supp+expl+'S4_ALL_SPECIES_PPC.csv2')
occ=read('imported_local/hmsc_outputs/'+expl+'S4_ALL_SPECIES_occurrence_metrics.csv2')
reconcile=[]
for x in generic:
 p=next(z for z in ppc if z['species']==x['species']);o=next(z for z in occ if z['species']==x['species'])
 expected=math.sqrt(a.number(p['observed_zero']))
 assert abs(a.number(x['O.RMSE'])-expected)<1e-12 and a.number(x['O.AUC'])==.5 and a.number(x['O.TjurR2'])==0
 reconcile.append(dict(branch='explanatory_v4',species=x['species'],generic_O_RMSE=a.number(x['O.RMSE']),sqrt_observed_zero_fraction=expected,
  generic_O_AUC=a.number(x['O.AUC']),dedicated_realized_O_AUC=a.number(o['O.AUC']),generic_O_TjurR2=a.number(x['O.TjurR2']),dedicated_realized_O_TjurR2=a.number(o['O.TjurR2']),
  reconciliation='Expected-count positivity explains degeneracy; exact v4 producer absent; use dedicated occurrence columns with correct scope'))
write('OCCURRENCE_RECONCILIATION.csv',reconcile)
sources={
 'upstream':'imported_local/R/moth_species_balance_corrected.R',
 'primary':'imported_local/R/S1_S2_a_PREDICTIVE_variable_selection_with_variance_partitioning.R',
 'final':'imported_local/R/S1_S2_c_d_PREDICTIVE_environment_selection_with_blocked_CV.R',
 'S5':'imported_local/R/S5_HMSC_annual_species_abundance_dependencies.R'}
findings=[
 ('upstream',37, 'RAW_SOURCE','data/Eiffel_1993_2024.csv; positive species records are expanded to observed sampling events; all-zero/unsampled-event distinction cannot be recovered from this table alone','PROVENANCE_REQUIRED'),
 ('upstream',155,'EFFORT','pmax(end-start,1) clamps nonpositive durations; primary requirespositive interval_days but cannot detect a previously clamped date error','CODE_RISK_ACTUAL_ROWS_UNVERIFIED'),
 ('upstream',189,'MISSING_COUNTS','sum(count) without na.rm can yield NA; later replace_na(count,0) collapses present missing sums into zero','CODE_RISK_ACTUAL_ROWS_UNVERIFIED'),
 ('upstream',218,'YEAR_ASSIGNMENT','Jan-Mar brumata/fagata flight_year is previous year; HMSC uses prepared year; active calendar/flight-year mapping is unproven','PROVENANCE_REQUIRED'),
 ('primary',2992,'BUFFER_DEDUPLICATION','count is taken once per sample/species after checking consistent finitebuffer counts, not summed across buffers','DEFENSE_RETAIN'),
 ('primary',3024,'ABSENT_VS_MISSING','Only absent sample/species rows zero-filled here; present missing counts remain missing','DEFENSE_RETAIN_UPSTREAM_LOSS_POSSIBLE'),
 ('primary',3068,'ANNUAL_AGGREGATION','Annual raw count and effort sum finite-count intervals; >=4 intervals and>=28days; count is not annual_index/log1p response','CODE_DEFINITION_NOT_EXECUTION_PROOF'),
 ('primary',3176,'OFFSET','Loff=log(effort_days/7); missing Y getsneutral offset;7d rate is interpretation, not divided count fedto likelihood','CODE_DEFINITION_NOT_EXECUTION_PROOF'),
 ('primary',92,'EXTREME_VERIFICATION','extreme_annual_counts_verified=TRUE bypasses confirmation gate; no actual source-check record is supplied','NOT_SOURCE_VERIFICATION'),
 ('final',596,'PPC_OFFSET','predict(...Loff=model$Loff,expected=FALSE) supplies realized PPC/occurrence draws; expected=TRUE count fit evaluated separately','PPC_NOT_DISMISSED_AS_GENERIC_METRIC_BUG'),
 ('final',628,'REALIZED_OCCURRENCE','1-mean(realized==0) supplies presence probability; generic occurrence columns replaced for finalmodels','SEMANTICS_ESTABLISHED_FOR_RETAINED_CD_SOURCE'),
 ('final',1145,'DIAGNOSTIC_EXPORT','Conditional helper is implemented in primary S1/S2a;32existingESS/Gelman text exports located in originalmanifest butnotimported; actualvalues and executedhelperrevision unverified','VALUES_MISSING_NOT_EXPORT_ABSENCE'),
 ('primary',1321,'OLD_CLASSIC_DIAGNOSTIC_METHOD','Helper uses convertToCodaObject then gelman.diag(multivariate=FALSE) withdefaultautoburnin and coda effectiveSize; comparewith newlycomputedall-retained-draw PSRF without conflating modernRhat','IMPLEMENTATION_LOCATED_NOT_EXECUTION_PROOF'),
 ('S5',97,'V_POLICY','V has1.10 PSRFupper/200ESS limits but blocks_inference=FALSE; acceptance intentionally differs from diagnostic_pass','GENUINE_UNRESOLVED_POLICY_ISSUE1'),
 ('S5',586,'EXPECTED_COUNT_OCCURRENCE','expected=TRUE predictions go into evaluateModelFit without dedicated realized-occurrence replacement','GENERIC_OCCURRENCE_ESTIMAND_ERROR_NOT_FITTING_ERROR')]
rows=[]
for key,line,topic,finding,status in findings:
 p=sources[key];tracked.add(p)
 rows.append(dict(source=p,line=line,topic=topic,finding=finding,status=status))
write('SOURCE_CODE_FINDINGS_v2.csv',rows)
write('INPUT_FINGERPRINTS.csv',[dict(path=p,sha256=hashlib.sha256((r/p).read_bytes()).hexdigest(),size=(r/p).stat().st_size) for p in sorted(tracked)])
status=dict(base_commit='f12268156cd9360dbb8683a75c2d9f96aaf1cbbb',historical_predictive_binary_inventory=2478,
 existing_diagnostic_text_paths_located=32,current_full_data_diagnostic_text_paths=16,existing_diagnostic_values_recovered=0,full_data_current_direct_model_paths=2,other_primary_sensitivity_direct_model_paths=2,cloud_posterior_objects_opened=0,
 newly_recovered_actual_predictive_Rhat_ESS_traces=0,predictive_convergence_proven=False,verified_extreme_site='1308',verified_extreme_year=2004,extreme_original_source_verified=False,
 fagata_observed_zero_count=560,fagata_zero_PPC_cause_resolved=False,V_failed_nonblocking_components=9,
 verified_generic_occurrence_constant_comparisons=3,observation_preparation_errors_proven_in_executed_data=False,
 preparation_code_risks_identified=True,model_runs=0,refitting_currently_justified=False,local_extraction_executed=False)
(out/'CHECK_STATUS_v2.json').write_text(json.dumps(status,indent=2)+'\n')
print(json.dumps(status,indent=2))
