#!/usr/bin/env Rscript
# Base R preflight for Windows and Linux. Run as a FILE, never through -e:
# PowerShell 5.1 can strip embedded quotes when invoking native Rscript.exe.
expected <- Sys.getenv("EIFFEL_EXPECTED_TEMP", unset = "")
if (!nzchar(expected)) stop("EIFFEL_EXPECTED_TEMP is not configured")
expected <- normalizePath(expected, winslash = "/", mustWork = TRUE)
actual <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
clean <- function(s) tolower(sub("/+$", "", s))
base <- clean(expected)
tmp <- clean(actual)
if (!startsWith(tmp, paste0(base, "/"))) {
  stop(sprintf("R temp is outside expected root. expected=%s; actual=%s", expected, actual))
}
cat("PASS: R temp directory:", actual, "\n")
