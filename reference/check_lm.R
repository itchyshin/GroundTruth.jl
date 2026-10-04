# Run from package root: Rscript --vanilla reference/check_lm.R
args <- commandArgs(trailingOnly=TRUE)
out <- if(length(args)) args[1] else "results/linear"
d <- read.csv(file.path(out,"rep1-data.csv"))
j <- read.csv(file.path(out,"rep1-julia.csv"))
m <- lm(y ~ x, data=d)
r <- data.frame(target=c("alpha","beta"),estimate=unname(coef(m)),
                lower=confint(m)[,1],upper=confint(m)[,2])
stopifnot(identical(j$target,r$target))
err <- max(abs(as.matrix(j[,2:4])-as.matrix(r[,2:4])))
stopifnot(err < 1e-10)
write.csv(r,file.path(out,"rep1-r-lm.csv"),row.names=FALSE)
writeLines(c(R.version.string,paste("maximum absolute discrepancy",format(err,digits=17)),
             "PASS: coefficients and exact t interval endpoints on identical data"),
           file.path(out,"r-lm-check.txt"))
cat("PASS: R lm maximum absolute discrepancy",err,"\n")
