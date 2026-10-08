# Read-only existing-posterior arithmetic. No prediction, sampling, CV or producer sourcing.
p0_species <- c("Epirrita autumnata", "Operophtera brumata", "Operophtera fagata")
p0_weather <- c("lag1_summer_mean_Tmin","lag1_summer_mean_Tmax","lag1_summer_max_Tmax","lag1_growing_sum_precipitation","lag1_autumn_mean_Tmax")
p0_identity <- function(m,id) {
  expected<-c(p0_weather,if(id=="environment") c("NDVI_mean__b100m","NDVI_median__b100m","NDVI_max__b100m"))
  actual<-m$covNames;if(is.null(actual) && is.matrix(m$X))actual<-colnames(m$X)
  if(!id%in%c("weather","environment") || nrow(m$Y)!=1277L ||
     is.null(actual) || !setequal(setdiff(actual,"(Intercept)"),expected)) stop("Saved model differs from frozen full-data row/predictor contract")
  paste(actual,collapse="|")
}
p0_write <- function(x, path) {
  if (file.exists(path)) stop("Refusing existing output: ", path)
  con <- file(path, open="wx"); on.exit(close(con))
  write.csv(x, con, row.names=FALSE, na="NA")
}
p0_chains <- function(x) {
  if (!inherits(x,"mcmc.list") || length(x)<2L) stop("At least two separate saved chains required")
  z <- lapply(x, as.matrix)
  if (!ncol(z[[1]]) || length(unique(vapply(z,nrow,integer(1))))!=1L ||
      length(unique(vapply(z,ncol,integer(1))))!=1L || nrow(z[[1]])<8L) stop("Incompatible/short chains")
  if (!all(vapply(z,function(a) identical(colnames(a),colnames(z[[1]])),logical(1)))) stop("Parameter order differs")
  if (!all(vapply(z,function(a) all(is.finite(a)),logical(1)))) stop("Nonfinite saved draws")
  z
}
p0_diagnose <- function(x, component, modern=requireNamespace("posterior",quietly=TRUE)) {
  z<-p0_chains(x); n<-nrow(z[[1]]); p<-ncol(z[[1]]); k<-length(z)
  if (p>20000L) stop("Component exceeds reviewed parameter cap")
  nm<-colnames(z[[1]]); if (is.null(nm)) nm<-paste0("parameter_",seq_len(p))
  ps<-tryCatch(coda::gelman.diag(x,multivariate=FALSE,autoburnin=FALSE)$psrf,error=function(e) NULL)
  ess<-tryCatch(coda::effectiveSize(x),error=function(e) NULL)
  rows<-lapply(seq_len(p),function(j) {
    a<-vapply(z,function(m)m[,j],numeric(n))
    constant<-all(apply(a,2,sd)==0)
    scalar<-function(fun) if (constant || !modern) NA_real_ else tryCatch(as.numeric(fun(a)),error=function(e) NA_real_)
    data.frame(component=component,parameter=nm[j],chains=k,retained_draws_per_chain=n,
      classic_PSRF_point=if(is.null(ps)) NA_real_ else ps[j,1],
      classic_PSRF_upper=if(is.null(ps)) NA_real_ else ps[j,2],
      coda_ESS=if(is.null(ess)) NA_real_ else as.numeric(ess[j]),
      rank_normalized_split_Rhat=scalar(function(a)posterior::rhat(a)),
      bulk_ESS=scalar(function(a)posterior::ess_bulk(a)),tail_ESS=scalar(function(a)posterior::ess_tail(a)),
      mcse_mean=scalar(function(a)posterior::mcse_mean(a)),
      constant_chains=constant,modern_package_available=modern,
      interpretation=if(constant) "CONSTANT_DRAWS_REQUIRE_PARAMETER_SEMANTICS_REVIEW" else "DIAGNOSTIC_NOT_SCIENTIFIC_ACCEPTANCE",
      stringsAsFactors=FALSE)
  })
  do.call(rbind,rows)
}
p0_model_observations <- function(model) {
  y<-model$Y; off<-model$Loff
  if (!is.matrix(y) || !is.matrix(off) || !identical(dim(y),dim(off)) || !identical(dimnames(y),dimnames(off)) ||
      !setequal(colnames(y),p0_species) || is.null(rownames(y)) || anyDuplicated(rownames(y))) stop("Unexpected Y/Loff/species/row alignment schema")
  if (any(y[is.finite(y)]<0) || any(abs(y[is.finite(y)]-round(y[is.finite(y)]))>1e-8) || any(!is.finite(off))) stop("Invalid count/offset")
  do.call(rbind,lapply(seq_len(ncol(y)),function(j) {
    keep<-is.finite(y[,j]); effort<-7*exp(off[keep,j])
    if(!any(keep) || any(!is.finite(effort)) || any(effort<=0)) stop("Missing observations or invalid inferred effort")
    reference_zero<-c("Epirrita autumnata"=2,"Operophtera brumata"=150,"Operophtera fagata"=560)[colnames(y)[j]]
    reference_max<-c("Epirrita autumnata"=379332,"Operophtera brumata"=2051,"Operophtera fagata"=3171)[colnames(y)[j]]
    data.frame(species=colnames(y)[j],rows=nrow(y),finite_observations=sum(keep),missing_observations=sum(!keep),
      zeros=sum(y[keep,j]==0),zero_fraction=mean(y[keep,j]==0),maximum=max(y[keep,j]),
      saved_PPC_reference_zeros=unname(reference_zero),saved_PPC_reference_maximum=unname(reference_max),
      matches_saved_PPC_observation_counts=(sum(keep)==1277L && sum(y[keep,j]==0)==reference_zero && max(y[keep,j])==reference_max),
      inferred_effort_days_min=min(effort),inferred_effort_days_median=median(effort),inferred_effort_days_max=max(effort),
      effort_inference="7*exp(Loff); verify against primary preparation metadata",stringsAsFactors=FALSE)
  }))
}
p0_raw_extreme <- function(raw) {
  need<-c("site","year","species","KokMaara")
  if (!all(need %in% names(raw))) stop("Raw-source schema differs; no guessed column mapping")
  s<-trimws(gsub("[[:space:]]+"," ",as.character(raw$species)))
  g<-raw[as.character(raw$site)=="1308" & as.character(raw$year)=="2004" & s=="Epirrita autumnata",,drop=FALSE]
  if (!nrow(g)) stop("Extreme source group missing; calendar/flight-year provenance unresolved")
  d<-unique(g); v<-suppressWarnings(as.numeric(as.character(d$KokMaara)))
  valid<-all(is.finite(v)) && all(v>=0) && all(abs(v-round(v))<1e-8)
  total<-if(valid) sum(v) else NA_real_
  missing_dates<-nonpositive<-events<-effort<-NA_real_; date_status<-"DATE_COLUMNS_UNAVAILABLE"
  if(all(c("PvmAlku","PvmLoppu")%in%names(raw))) {
    q<-raw[as.character(raw$site)=="1308" & as.character(raw$year)=="2004",c("PvmAlku","PvmLoppu"),drop=FALSE]
    q<-unique(q)
    parse_date<-function(x) {
      text<-trimws(as.character(x));ans<-as.Date(rep(NA_character_,length(x)))
      for(fmt in c("%Y-%m-%d","%d.%m.%Y","%d/%m/%Y","%d-%m-%Y")) {
        idx<-which(is.na(ans));if(length(idx))ans[idx]<-as.Date(text[idx],format=fmt)
      }
      ans
    }
    days<-as.numeric(parse_date(q$PvmLoppu)-parse_date(q$PvmAlku))
    missing_dates<-sum(!is.finite(days));nonpositive<-sum(days<=0,na.rm=TRUE);events<-length(days)
    effort<-if(all(is.finite(days)) && all(days>0))sum(days) else NA_real_
    date_status<-"RAW_YEAR_ALL_SPECIES_DISTINCT_DATEPAIR_SUM_NOT_VERIFIED_ACTIVE_JOIN"
  }
  data.frame(site="1308",year=2004,species="Epirrita autumnata",raw_rows=nrow(g),exact_distinct_rows=nrow(d),
    exact_duplicate_rows=nrow(g)-nrow(d),missing_or_invalid_counts=sum(!is.finite(v)|v<0),
    original_sum=if(valid)sum(as.numeric(as.character(g$KokMaara))) else NA_real_,
    exact_distinct_sum=total,model_extreme_reference=379332,sum_matches_reference=isTRUE(total==379332),
    raw_site_year_distinct_datepairs=events,unparsed_datepairs=missing_dates,nonpositive_date_durations=nonpositive,
    raw_distinct_datepair_effort_days=effort,date_provenance_status=date_status,
    provenance_status="AGGREGATE_RAW_COMPARISON_NOT_EXECUTED_GIS_JOIN_PROOF",stringsAsFactors=FALSE)
}
p0_extract <- function(source, output, allow) {
  if (!dir.exists(output) || length(list.files(output,all.files=TRUE,no..=TRUE))) stop("Output must be a fresh empty guarded directory")
  if (!requireNamespace("Hmsc",quietly=TRUE) || !requireNamespace("coda",quietly=TRUE)) stop("Existing Hmsc and coda installations required; no automatic installation")
  rows<-read.csv(allow,colClasses="character",check.names=FALSE)
  statuses<-list(); executions<-list();reference<-NULL
  path<-function(r) file.path(source,r$relative_path)
  for (i in which(rows$action=="MODEL_DIAGNOSTICS")) {
    r<-rows[i,,drop=FALSE]; id<-r$id
    m<-readRDS(path(r))
    if (!identical(class(m),"Hmsc")) stop("Expected direct Hmsc object; nested/other schema refused: ",id)
    covariates<-p0_identity(m,id)
    p0_write(p0_model_observations(m),file.path(output,paste0(id,"_observation_summary.csv")))
    if(is.null(reference)) reference<-list(Y=m$Y,Loff=m$Loff) else {
      same<-identical(m$Y,reference$Y) && identical(m$Loff,reference$Loff)
      p0_write(data.frame(Y_and_Loff_identical_between_models=same,
        interpretation=if(same) "MATCHED_MODEL_OBSERVATIONS_AND_OFFSETS" else "DISCREPANCY_DO_NOT_DECLARE_COMPARABLE"),file.path(output,"matched_observation_check.csv"))
    }
    chains<-if(is.list(m$postList))length(m$postList) else 0L
    lengths<-if(chains)vapply(m$postList,length,integer(1)) else integer()
    stored<-function(x) if(is.null(x) || !length(x)) "MISSING_IN_OBJECT" else paste(as.vector(x),collapse="|")
    executions[[length(executions)+1L]]<-data.frame(id=id,source=r$relative_path,class="Hmsc",saved_chains=chains,
      saved_chain_lengths=stored(lengths),stored_samples=stored(m$samples),
      stored_thin=stored(m$thin),stored_transient=stored(m$transient),covariates=covariates,
      stored_distribution_codes=stored(m$distr),stored_YScale=stored(m$YScale),
      offset_present=!is.null(m$Loff),Hmsc=as.character(packageVersion("Hmsc")),coda=as.character(packageVersion("coda")),
      posterior=if(requireNamespace("posterior",quietly=TRUE))as.character(packageVersion("posterior")) else "NOT_INSTALLED",
      stringsAsFactors=FALSE)
    y<-m$Y; hit<-which(y[,"Epirrita autumnata"]==379332)
    extreme<-data.frame(id=id,occurrences=length(hit),sample_ids=if(length(hit))paste(rownames(y)[hit],collapse="|") else "NOT_PRESENT",
      Loff=if(length(hit))paste(m$Loff[hit,"Epirrita autumnata"],collapse="|") else "NOT_PRESENT",stringsAsFactors=FALSE)
    p0_write(extreme,file.path(output,paste0(id,"_extreme_link.csv")))
    converter<-getExportedValue("Hmsc","convertToCodaObject")
    options<-list(Beta=TRUE,Gamma=TRUE,V=TRUE,Sigma=TRUE,rho=TRUE,Eta=FALSE,Lambda=TRUE,alpha=TRUE,Omega=TRUE,Psi=FALSE,Delta=FALSE)
    unknown<-setdiff(names(options),names(formals(converter)))
    converted<-list()
    for(requested in c("Beta","Gamma","V","Sigma","rho","Omega","Lambda","alpha")) {
      opt<-options; opt[]<-FALSE;opt[[requested]]<-TRUE
      if(requested=="Omega") opt$Lambda<-TRUE
      block<-if(length(unknown)) simpleError(paste("Reviewed converter options unavailable:",paste(unknown,collapse=","))) else
        tryCatch(do.call(converter,c(list(m),opt)),error=function(e)e)
      if(inherits(block,"error")) {
        statuses[[length(statuses)+1L]]<-data.frame(id=id,component=requested,status="UNRECOVERED",detail=conditionMessage(block))
      } else {
        candidate<-block[[requested]]
        if(is.null(candidate) && requested=="rho") candidate<-block$Rho
        if(is.null(candidate)) {
          statuses[[length(statuses)+1L]]<-data.frame(id=id,component=requested,status="NOT_RETURNED",detail="Component absent/not applicable or unsupported; inspect execution/model structure")
        } else converted[[requested]]<-candidate
      }
    }
    pieces<-list()
    flatten<-function(x,n) {
      if(inherits(x,"mcmc.list")) {pieces[[n]]<<-x;return(invisible(NULL))}
      if(is.list(x)) for(j in seq_along(x)) flatten(x[[j]],paste0(n,"/",if(!is.null(names(x)) && nzchar(names(x)[j]))names(x)[j] else j))
    }
    {
      for(n in names(converted)) flatten(converted[[n]],n)
      if(!length(pieces)) statuses[[length(statuses)+1L]]<-data.frame(id=id,component="ALL",status="UNRECOVERED",detail="No separate coda chains returned")
      for(n in names(pieces)) {
        d<-tryCatch(p0_diagnose(pieces[[n]],n),error=function(e)e)
        if(inherits(d,"error")) {
          statuses[[length(statuses)+1L]]<-data.frame(id=id,component=n,status="UNRECOVERED",detail=conditionMessage(d));next
        }
        safe<-gsub("[^A-Za-z0-9_-]","_",n)
        p0_write(d,file.path(output,paste0(id,"_",safe,"_diagnostics.csv")))
        # Bounded block summaries for every monitored parameter/chain, not chain draws.
        z<-p0_chains(pieces[[n]]); blocks<-list()
        for(k in seq_along(z)) for(b in 1:10) {
          idx<-which(ceiling(seq_len(nrow(z[[k]]))*10/nrow(z[[k]]))==b)
          if(!length(idx)) next
          blocks[[length(blocks)+1L]]<-data.frame(chain=k,block=b,parameter=d$parameter,
            mean=colMeans(z[[k]][idx,,drop=FALSE]),sd=apply(z[[k]][idx,,drop=FALSE],2,sd),stringsAsFactors=FALSE)
        }
        p0_write(do.call(rbind,blocks),file.path(output,paste0(id,"_",safe,"_chain_blocks.csv")))
        # Actual saved-draw trace plots only for the six worst finite modern R-hats (or first6 if unavailable).
        ix<-head(order(d$rank_normalized_split_Rhat,decreasing=TRUE,na.last=TRUE),6)
        trace_path<-file.path(output,paste0(id,"_",safe,"_selected_traces.pdf"))
        if(file.exists(trace_path)) stop("Refusing trace overwrite")
        pdf(trace_path,width=10,height=7)
        tryCatch({for(j in ix) {
          a<-vapply(z,function(q)q[,j],numeric(nrow(z[[1]])))
          matplot(a,type="l",lty=1,xlab="Retained draw index (not sampler iteration)",ylab=d$parameter[j],main=paste(id,n,"saved-chain trace"))
        }},finally=dev.off())
        statuses[[length(statuses)+1L]]<-data.frame(id=id,component=n,status="RECOVERED_ARITHMETIC",detail="Saved-chain diagnostics; selected actual traces only; no blanket convergence certification")
      }
    }
    rm(m,converted,pieces);gc()
  }
  primary<-readRDS(path(rows[rows$action=="PREPARATION_METADATA",,drop=FALSE]))
  if (!is.list(primary)) stop("Unexpected preparation metadata schema")
  for(n in c("response_distribution","zero_fill_audit","extreme_count_flags")) {
    a<-primary[[n]]
    if(is.data.frame(a) && all(a$species %in% p0_species)) p0_write(a,file.path(output,paste0("primary_",n,".csv")))
    else statuses[[length(statuses)+1L]]<-data.frame(id="primary",component=n,status="UNRECOVERED",detail="Missing/unexpected three-species aggregate schema")
  }
  a<-primary$extreme_count_audit
  if(is.data.frame(a) && all(c("site","year","species","total_count")%in%names(a))) {
    a<-a[as.character(a$site)=="1308" & a$year==2004 & a$species=="Epirrita autumnata",,drop=FALSE]
    keep<-intersect(names(a),c("species","site","year","total_count","total_effort_days","n_intervals","annual_index","log_annual_index"))
    p0_write(a[,keep,drop=FALSE],file.path(output,"primary_extreme_link.csv"))
  }
  interval<-primary$extreme_interval_audit
  if(is.data.frame(interval) && all(c("site","year","species","count","interval_days")%in%names(interval))) {
    g<-interval[as.character(interval$site)=="1308" & interval$year==2004 & interval$species=="Epirrita autumnata",,drop=FALSE]
    if(nrow(g))p0_write(data.frame(n_intervals=nrow(g),missing_counts=sum(!is.finite(g$count)),
      total_count=if(all(is.finite(g$count)))sum(g$count) else NA_real_,total_effort_days=sum(g$interval_days),
      maximum_interval_count=max(g$count),nonpositive_effort=sum(g$interval_days<=0)),file.path(output,"primary_extreme_interval_aggregate.csv"))
  }
  raw<-read.csv(path(rows[rows$action=="RAW_EXTREME_AGGREGATE",,drop=FALSE]),sep=";",dec=".",check.names=FALSE,stringsAsFactors=FALSE)
  p0_write(p0_raw_extreme(raw),file.path(output,"raw_extreme_aggregate.csv"))
  p0_write(do.call(rbind,executions),file.path(output,"execution_metadata.csv"))
  p0_write(do.call(rbind,statuses),file.path(output,"recovery_status.csv"))
  p0_write(data.frame(R=R.version.string,Hmsc=as.character(packageVersion("Hmsc")),coda=as.character(packageVersion("coda"))),file.path(output,"runtime.csv"))
  p0_write(data.frame(status="EXTRACTION_FINISHED_NOT_MODEL_CONVERGENCE",model_fits=0,MCMC_runs=0,CV_runs=0,primary_raw_rows_exported=0),file.path(output,"STATUS.csv"))
}
if (sys.nframe()==0L) {
  a<-commandArgs(trailingOnly=TRUE)
  if(length(a)!=3L) stop("Run through guarded PowerShell wrapper: source output allowlist")
  p0_extract(a[1],a[2],a[3])
}
