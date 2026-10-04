# Optional local MLE reference; requires installed TMB and a C++ toolchain.
# Run from package root. Compiles a copy inside results, never edits source template.
library(TMB)
args <- commandArgs(trailingOnly=TRUE)
out <- normalizePath(if(length(args)) args[1] else "results/linear")
template <- normalizePath("reference/linear.cpp")
d <- read.csv(file.path(out,"rep1-data.csv"))
build <- file.path(out,"tmb-build"); dir.create(build,showWarnings=FALSE)
file.copy(template,file.path(build,"linear.cpp"),overwrite=TRUE)
setwd(build)
compile("linear.cpp",flags="-O0")
dyn.load(dynlib("linear"))
obj <- MakeADFun(list(x=d$x,y=d$y),list(alpha=0,beta=0,log_sigma=0),silent=TRUE)
fit <- optim(obj$par,obj$fn,obj$gr,method="BFGS",control=list(reltol=1e-12,maxit=500))
stopifnot(fit$convergence==0L,max(abs(obj$gr(fit$par)))<1e-4)
j <- read.csv(file.path(out,"rep1-julia.csv"))
err <- max(abs(unname(fit$par[c("alpha","beta")])-j$estimate))
stopifnot(err<1e-6)
# Independent normalized Gaussian log likelihood check at a fixed parameter point.
p <- c(alpha=.2,beta=.4,log_sigma=log(1.3))
expected <- -sum(dnorm(d$y,.2+.4*d$x,1.3,log=TRUE))
stopifnot(abs(obj$fn(p)-expected)<1e-9)
write.csv(data.frame(target=names(fit$par),estimate=fit$par),file.path(out,"rep1-tmb.csv"),row.names=FALSE)
writeLines(c(R.version.string,paste("TMB",packageVersion("TMB")),
  paste("maximum coefficient discrepancy",format(err,digits=17)),
  "PASS: convergence, score, coefficients and fixed-point normalized log likelihood",
  "Intervals not compared: ML residual variance uses N, OLS unbiased variance uses N-2."),
  file.path(out,"tmb-check.txt"))
cat("PASS: TMB MLE coefficient discrepancy",err,"\n")
