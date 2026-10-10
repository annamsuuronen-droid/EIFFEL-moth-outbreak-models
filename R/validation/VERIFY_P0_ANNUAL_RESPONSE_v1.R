# Read-only annual-response reconstruction; never sources or executes model producers.
annual_species <- c('Epirrita autumnata','Operophtera brumata','Operophtera fagata')
annual_numeric <- function(x) {
 if(is.numeric(x)) return(x)
 x<-trimws(as.character(x));x[x %in% c('', 'NA','NaN','NULL')]<-NA_character_
 suppressWarnings(as.numeric(gsub(',', '.', x, fixed=TRUE)))
}
annual_reconstruct <- function(dat) {
 required<-c('sample_id','site','year','species','count','interval_days','buffer_m')
 if(!all(required %in% names(dat)))stop('Final GIS input lacks required producer columns')
 d<-dat[,required,drop=FALSE]
 for(n in c('sample_id','site','species'))d[[n]]<-as.character(d[[n]])
 d$year<-suppressWarnings(as.integer(as.character(d$year)))
 for(n in c('count','interval_days','buffer_m'))d[[n]]<-annual_numeric(d[[n]])
 if(any(!is.finite(d$year)) || any(d$count<0,na.rm=TRUE) || any(!is.finite(d$buffer_m)) || any(!is.finite(d$interval_days)) || any(d$interval_days<=0))stop('Original producer input validation failed')
 if(anyNA(d$sample_id) || anyNA(d$site) || any(!nzchar(d$sample_id)) || any(!nzchar(d$site)))stop('Ambiguous/missing sample or site identifier')
 names_found<-unique(d$species);norm<-function(x)gsub('[^a-z]','',tolower(trimws(x)))
 sp<-vapply(norm(annual_species),function(p){hit<-names_found[norm(names_found)==p & !is.na(names_found)];if(length(hit)!=1L)stop('Target species not uniquely identified');hit},character(1))
 d<-d[d$species %in% sp,,drop=FALSE]
 # Repeated GIS buffer rows are representations of one sampling event, not repeated catches.
 groups<-split(seq_len(nrow(d)),match(d$sample_id,unique(d$sample_id)))
 meta<-do.call(rbind,lapply(groups,function(ix){z<-d[ix,,drop=FALSE];for(n in c('site','year','interval_days'))if(length(unique(z[[n]]))!=1L)stop('Conflicting interval metadata');z[1,c('sample_id','site','year','interval_days'),drop=FALSE]}))
 rownames(meta)<-NULL
 ci<-match(d$sample_id,meta$sample_id);sj<-match(d$species,sp)
 key<-ci+(sj-1L)*nrow(meta)
 counts<-rep(0,nrow(meta)*3L);present<-rep(FALSE,length(counts));mixed<-0L
 for(ix in split(seq_len(nrow(d)),key)) {
  vals<-unique(d$count[ix][is.finite(d$count[ix])]);if(length(vals)>1L)stop('Conflicting counts across buffer rows')
  k<-key[ix[1]];present[k]<-TRUE;counts[k]<-if(length(vals))vals else NA_real_
  if(length(vals) && any(!is.finite(d$count[ix])))mixed<-mixed+1L
 }
 long<-meta[rep(seq_len(nrow(meta)),3L),,drop=FALSE];long$species<-rep(sp,each=nrow(meta));long$count<-counts;long$present<-present
 ids<-paste(long$site,long$year,sep='__')
 # Reject ambiguous site-year keys rather than guessing how to align saved models.
 meta_ids<-unique(meta[,c('site','year'),drop=FALSE]);if(anyDuplicated(paste(meta_ids$site,meta_ids$year,sep='__')))stop('Ambiguous site-year identity')
 valid<-which(is.finite(long$count));annual_keys<-paste(match(ids,unique(ids)),match(long$species,sp),sep=':')
 ann<-do.call(rbind,lapply(split(valid,annual_keys[valid]),function(ix) {
  z<-long[ix,,drop=FALSE];data.frame(sample_id=ids[ix[1]],species=z$species[1],site=z$site[1],year=z$year[1],total_count=sum(z$count),total_effort_days=sum(z$interval_days),n_intervals=nrow(z))
 }))
 if(is.null(ann))stop('No finite annual observations')
 ann$used<-ann$n_intervals>=4L & ann$total_effort_days>=28
 used<-ann[ann$used,,drop=FALSE];if(!nrow(used))stop('No annual observations pass original coverage limits')
 if(any(abs(used$total_count-round(used$total_count))>1e-8))stop('Noninteger annual Poisson response')
 row_ids<-unique(used$sample_id);Y<-matrix(NA_real_,length(row_ids),3L,dimnames=list(row_ids,unname(sp)))
 effort<-Y;index<-cbind(match(used$sample_id,row_ids),match(used$species,sp))
 Y[index]<-round(used$total_count);effort[index]<-used$total_effort_days
 Loff<-matrix(0,nrow(Y),3L,dimnames=dimnames(Y));good<-is.finite(effort)&effort>0;Loff[good]<-log(effort[good]/7)
 audit<-do.call(rbind,lapply(sp,function(s){z<-long[long$species==s,];a<-ann[ann$species==s,];data.frame(species=s,intervals=nrow(z),absent_rows_zero_filled=sum(!z$present),present_missing_counts=sum(z$present & !is.finite(z$count)),annual_groups=nrow(a),coverage_excluded=sum(!a$used))}))
 # Only aggregate extreme provenance is exported; individual count/abundance records remain private.
 extreme<-long[long$site=='1308' & long$year==2004L & norm(long$species)=='epirritaautumnata',,drop=FALSE]
 e<-data.frame(site='1308',year=2004,intervals=nrow(extreme),finite_count_intervals=sum(is.finite(extreme$count)),missing_counts=sum(!is.finite(extreme$count)),zero_filled_intervals=sum(!extreme$present),total_count=sum(extreme$count[is.finite(extreme$count)]),total_effort_days=sum(extreme$interval_days[is.finite(extreme$count)]),maximum_interval_count=if(any(is.finite(extreme$count)))max(extreme$count,na.rm=TRUE)else NA_real_)
 list(Y=Y,Loff=Loff,effort=effort,audit=audit,extreme=e,preparation=data.frame(target_buffer_rows=nrow(d),unique_interval_species=sum(present),repeated_interval_species_rows=nrow(d)-sum(present),exact_projected_duplicates=sum(duplicated(d)),mixed_missing_finite_buffer_groups=mixed,year_rule='Uses prepared year verbatim; no calendar/flight-year reassignment',coverage='>=4 intervals and >=28 days per site/year/species',offset='log(total_effort_days / 7)',response='annual total_count; not annual_index or count_per_7d'))
}
annual_compare <- function(m,r,id) {
 y<-m$Y;o<-m$Loff
 if(!is.matrix(y)||!is.matrix(o)||!identical(dimnames(y),dimnames(o))||!identical(dim(y),dim(o))||anyDuplicated(rownames(y))||is.null(rownames(y))||is.null(colnames(y))||anyDuplicated(colnames(y))||!setequal(colnames(y),colnames(r$Y)))stop('Invalid saved Y/Loff identity')
 if(any(!is.finite(o))||any(!is.finite(y)&!is.na(y))||any(y[is.finite(y)]<0)||any(abs(y[is.finite(y)]-round(y[is.finite(y)]))>1e-8))stop('Invalid saved observation/offset')
 rows<-match(rownames(y),rownames(r$Y));cols<-match(colnames(y),colnames(r$Y));a<-r$Y[rows,cols,drop=FALSE];b<-r$Loff[rows,cols,drop=FALSE]
 missing<-is.na(y)!=is.na(a);finite<-is.finite(y)&is.finite(a);count_bad<-finite & y!=a
 off_valid<-is.finite(y)&is.finite(b);delta<-abs(o-b)
 data.frame(model=id,saved_rows=nrow(y),reconstructed_rows=nrow(r$Y),missing_saved_row_ids=sum(is.na(rows)),missingness_mismatches=sum(missing),count_mismatches=sum(count_bad),observed_offset_mismatches=sum(off_valid & delta>1e-10),maximum_observed_offset_difference=if(any(off_valid))max(delta[off_valid])else NA_real_,unobserved_offset_mismatches=sum(!is.finite(y)&is.finite(b)&delta>1e-10),response_and_observed_offset_match=all(!is.na(rows)) && !any(missing) && !any(count_bad) && all(is.finite(b[is.finite(y)])) && !any(delta[is.finite(y)]>1e-10),historical_input_byte_identity='UNVERIFIED: numerical agreement is not historical file identity')
}
annual_timing <- function(dat) {
 fields<-intersect(c('flight_year','calendar_year','PvmAlku','PvmLoppu','start_date','end_date'),names(dat));out<-list()
 for(n in fields) {
  v<-dat[[n]];derived<-rep(NA_integer_,length(v));jan_march<-rep(FALSE,length(v))
  if(n %in% c('flight_year','calendar_year'))derived<-suppressWarnings(as.integer(as.character(v)))else {
   dates<-as.Date(rep(NA_character_,length(v)));text<-trimws(as.character(v))
   for(fmt in c('%Y-%m-%d','%d.%m.%Y','%d/%m/%Y','%Y/%m/%d')) {
    take<-is.na(dates);parsed<-suppressWarnings(as.Date(text[take],format=fmt));good<-!is.na(parsed) & format(parsed,fmt)==text[take];ix<-which(take)[good];dates[ix]<-parsed[good]
   }
   derived<-suppressWarnings(as.integer(format(dates,'%Y')));jan_march<-!is.na(dates)&as.integer(format(dates,'%m'))<=3
  }
  year<-suppressWarnings(as.integer(as.character(dat$year)));valid<-is.finite(derived)&is.finite(year)
  out[[n]]<-data.frame(field=n,buffer_rows=nrow(dat),unparsed_or_missing=sum(!is.finite(derived)),year_disagreements=sum(valid & year!=derived),prepared_previous_year=sum(valid & year==derived-1L),jan_march_previous_year=sum(valid & jan_march & year==derived-1L),interpretation='Buffer-row diagnostics, not unique sampling events; disagreements are not proven errors; no year reassignment')
 }
 if(length(out))do.call(rbind,out)else data.frame(field='NO_REVIEWED_DATE_OR_FLIGHT_YEAR_FIELDS',buffer_rows=nrow(dat),unparsed_or_missing=NA,year_disagreements=NA,prepared_previous_year=NA,jan_march_previous_year=NA,interpretation='Underlying date/year assignment remains unverified')
}
annual_extract <- function(source,output,allow,helper) {
 base::source(helper,local=TRUE) # Reviewed arithmetic definitions only; guarded main does not run.
 if(!requireNamespace('Hmsc',quietly=TRUE)||!requireNamespace('coda',quietly=TRUE))stop('Existing installed Hmsc/coda required; no installation permitted')
 rows<-read.csv(allow,stringsAsFactors=FALSE);path<-function(row)file.path(source,row$relative_path)
 input<-rows[rows$action=='ANNUAL_INPUT',,drop=FALSE];if(nrow(input)!=1L)stop('Exactly one scientifically identified final input required')
 header<-names(read.csv(path(input),nrows=0,check.names=FALSE));if(anyDuplicated(header))stop('Duplicated input column names refused')
 classes<-rep('NULL',length(header));classes[header %in% c('sample_id','site','year','species','count','interval_days','buffer_m','flight_year','calendar_year','PvmAlku','PvmLoppu','start_date','end_date')]<-'character'
 dat<-read.csv(path(input),sep=',',dec='.',stringsAsFactors=FALSE,check.names=FALSE,colClasses=classes)
 r<-annual_reconstruct(dat)
 p0_write(annual_timing(dat),file.path(output,'timing_field_audit.csv'))
 p0_write(r$audit,file.path(output,'zero_and_coverage_audit.csv'));p0_write(r$extreme,file.path(output,'extreme_final_input_aggregate.csv'));p0_write(r$preparation,file.path(output,'preparation_summary.csv'))
 timing_names<-grep('date|pvm|flight|calendar|year',header,ignore.case=TRUE,value=TRUE)
 p0_write(data.frame(available_timing_fields=paste(timing_names,collapse='|'),year_semantics='Prepared year used unchanged; underlying date-to-year mapping not established by annual reconstruction'),file.path(output,'year_assignment_status.csv'))
 rm(dat);gc()
 comparisons<-execution<-statuses<-list()
 for(i in which(rows$action=='COPY_DIAGNOSTIC')) {
  row<-rows[i,,drop=FALSE];kind<-if(grepl('_ESS$',row$id))'ESS' else 'gelman'
  summary<-tryCatch(p0_existing_diagnostic(path(row),kind),error=function(e)e)
  if(inherits(summary,'error'))statuses[[length(statuses)+1L]]<-data.frame(id=row$id,component=kind,status='EXISTING_EXPORT_PARSE_UNRECOVERED',detail=conditionMessage(summary))else p0_write(summary,file.path(output,paste0(row$id,'_summary.csv')))
 }
 for(i in which(rows$action=='MODEL_DIAGNOSTICS')) {
  row<-rows[i,,drop=FALSE];id<-row$id;m<-readRDS(path(row));if(!identical(class(m),'Hmsc'))stop('Expected direct saved Hmsc object')
  if(id %in% c('weather','environment')){p0_identity(m,id);p0_write(p0_model_observations(m),file.path(output,paste0(id,'_observation_summary.csv')))}
  comparisons[[id]]<-annual_compare(m,r,id)
  stored<-function(x)if(is.null(x)||!length(x))'MISSING_IN_OBJECT'else paste(as.vector(x),collapse='|')
  execution[[id]]<-data.frame(id=id,source=row$relative_path,saved_chains=length(m$postList),chain_lengths=stored(vapply(m$postList,length,integer(1))),thin=stored(m$thin),samples=stored(m$samples),transient=stored(m$transient),distribution=stored(m$distr),YScale=stored(m$YScale),covariates=stored(m$covNames),input_path=stored(m$data_file),input_sha256=stored(m$input_sha256),interpretation='Stored fields only; absent provenance not inferred')
  converter<-getExportedValue('Hmsc','convertToCodaObject');options<-list(Beta=FALSE,Gamma=FALSE,V=FALSE,Sigma=FALSE,rho=FALSE,Eta=FALSE,Lambda=FALSE,alpha=FALSE,Omega=FALSE,Psi=FALSE,Delta=FALSE)
  for(component in c('Beta','Gamma','V','Sigma','rho','Omega','Lambda','alpha')) {
   opt<-options;opt[[component]]<-TRUE;if(component=='Omega')opt$Lambda<-TRUE
   result<-tryCatch({if(length(setdiff(names(opt),names(formals(converter)))))stop('Installed converter differs from reviewed API');do.call(converter,c(list(m),opt))},error=function(e)e)
   pieces<-list();flatten<-function(x,n){if(inherits(x,'mcmc.list')){pieces[[n]]<<-x;return(invisible(NULL))};if(is.list(x))for(j in seq_along(x))flatten(x[[j]],paste(n,j,sep='_'))}
   if(!inherits(result,'error')){x<-result[[component]];if(is.null(x)&&component=='rho')x<-result$Rho;flatten(x,component)}
   if(!length(pieces)){statuses[[length(statuses)+1L]]<-data.frame(id=id,component=component,status='UNRECOVERED_OR_NOT_APPLICABLE',detail=if(inherits(result,'error'))conditionMessage(result)else 'No separate saved chains returned');next}
   for(n in names(pieces)) {
    d<-tryCatch(p0_diagnose(pieces[[n]],n),error=function(e)e)
    if(inherits(d,'error')){statuses[[length(statuses)+1L]]<-data.frame(id=id,component=n,status='UNRECOVERED',detail=conditionMessage(d));next}
    p0_write(d,file.path(output,paste0(id,'_',n,'_diagnostics.csv')))
    z<-p0_chains(pieces[[n]]);blocks<-list()
    for(k in seq_along(z))for(b in 1:10){ix<-which(ceiling(seq_len(nrow(z[[k]]))*10/nrow(z[[k]]))==b);if(length(ix))blocks[[length(blocks)+1L]]<-data.frame(chain=k,block=b,parameter=d$parameter,mean=colMeans(z[[k]][ix,,drop=FALSE]),sd=apply(z[[k]][ix,,drop=FALSE],2,sd))}
    p0_write(do.call(rbind,blocks),file.path(output,paste0(id,'_',n,'_mixing_blocks.csv')))
    trace_path<-file.path(output,paste0(id,'_',n,'_traces.pdf'));if(file.exists(trace_path))stop('Trace overwrite refused')
    pdf(trace_path);tryCatch({for(j in head(order(d$rank_normalized_split_Rhat,decreasing=TRUE,na.last=TRUE),6))matplot(vapply(z,function(q)q[,j],numeric(nrow(z[[1]]))),type='l',lty=1,xlab='Retained draw index',ylab=d$parameter[j],main=paste(id,n,'actual saved chains'))},finally=dev.off())
    statuses[[length(statuses)+1L]]<-data.frame(id=id,component=n,status='RECOVERED_ARITHMETIC',detail='No convergence certification; assess all parameters and trace limitations')
   }
  }
  rm(m);gc()
 }
 p0_write(do.call(rbind,comparisons),file.path(output,'response_offset_comparison.csv'))
 p0_write(do.call(rbind,execution),file.path(output,'execution_metadata.csv'));p0_write(do.call(rbind,statuses),file.path(output,'recovery_status.csv'))
 primary<-readRDS(path(rows[rows$action=='PREPARATION_METADATA',,drop=FALSE]))
 if(!is.list(primary))stop('Unexpected primary metadata object')
 for(n in c('zero_fill_audit','response_distribution','extreme_count_flags')){x<-primary[[n]];if(is.data.frame(x)&&'species'%in%names(x)&&all(x$species %in% annual_species))p0_write(x,file.path(output,paste0('primary_',n,'.csv')))}
 fields<-c('role','script_revision','n_samples','response_definition','offset_definition','distribution','analysis_version','data_file','input_sha256','primary_rdata_file')
 p0_write(data.frame(field=fields,value=vapply(fields,function(n)if(is.null(primary[[n]]))'NOT_RECORDED'else paste(primary[[n]],collapse='|'),character(1))),file.path(output,'primary_provenance_fields.csv'))
 p0_write(data.frame(status='EXTRACTION_FINISHED_REVIEW_REQUIRED',response_match_all=all(vapply(comparisons,function(x)x$response_and_observed_offset_match,logical(1))),historical_input_byte_identity='UNVERIFIED_UNLESS_EXECUTION_HASH_RECOVERED',model_fits=0,MCMC_runs=0,CV_runs=0,abundance_rows_exported=0),file.path(output,'STATUS.csv'))
}
if(sys.nframe()==0L){a<-commandArgs(trailingOnly=TRUE);if(length(a)!=3L)stop('Use guarded PowerShell wrapper');helper<-file.path(dirname(normalizePath(a[3])),'..','..','R','validation','EXTRACT_P0_EXISTING_POSTERIORS_v1.R');annual_extract(a[1],a[2],a[3],helper)}
