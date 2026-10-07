# Reconstructed final-profile contract for nested outer CV v2

## Status

This contract authorizes only a **reconstructed compatibility continuation** of
outer-year fold 5. It does **not** claim that the missing historical v2 producer
used byte-for-byte identical Hmsc, RNG, MCMC or random-level settings.

## Evidence supporting the contract

The retained v1 nested-CV producer defines the final outer-fold model as:

- distribution: `lognormal poisson`
- random levels: site and year, with units taken from all metadata levels
- outer-final MCMC: 5000 samples, 10000 transient, thin 20, 4 chains, 4 parallel workers
- maximum posterior draws for prediction: 1000
- year-fold seed logic based on outer-year seed 20260818 and fold-specific offsets

The imported v2 evidence independently fixes the following:

- the outer-year partition and fold numbering
- complete fold 1-4 selections, coverage, predictions and metrics
- fold-5 weather and environmental selections
- fold-5 matched coverage: 916 final TRAIN site-years and 222 final TEST site-years
- output schemas and metric semantics
- all 166 frozen lightweight evidence files

The local dry-run on 2026-10-07 verified that the current primary RData reproduces
the stored v2 partition, fold coverage and selected predictors, and that folds 1-4
are immutable/complete while fold 5 is selection-complete and final-fit pending.

The local runtime check on 2026-10-07 reported:

- R 4.5.2
- Hmsc 3.3-7
- coda 0.19-4.1
- RNGkind: Mersenne-Twister / Inversion / Rejection
- 20 detected CPU cores

The retained sessionInfo files for the predictive primary workflow and later Hmsc
stages also report R 4.5.2 and Hmsc 3.3-7.

## Reconstruction decision

Because the exact historical v2 producer is unavailable, fold 5 will not be
represented as a continuation of a proven historical executable. Instead, any
future run must be labelled and versioned as a **reconstructed compatibility run**.

The reconstructed execution profile deliberately adopts the retained v1
outer-final settings because they are the closest surviving producer settings and
are compatible with the observed v2 outputs. The profile is accepted only after a
local preflight verifies the runtime, primary data, frozen v2 evidence, fold-5
partition/coverage, selections and absence of conflicting final outputs.

## Uncertainty that remains

The lightweight v2 outputs cannot prove the exact historical v2:

- RNG state or RNGkind
- Hmsc call details beyond what is inferable from v1 and output schemas
- MCMC settings
- random-level construction

Therefore reconstructed fold-5 predictions are scientifically usable only as the
missing fold completed under this documented reconstruction contract. They must not
be described as bitwise reproduction of the lost historical v2 execution.

Outer-site CV remains disabled and is outside this contract.
