# Independent R checks on exactly the exported data; no new R packages required.
out <- "results/extensions"
d <- read.csv(file.path(out,"logistic-rep1-data.csv"))
j <- read.csv(file.path(out,"logistic-rep1-julia.csv"))
m <- glm(y~x,data=d,family=binomial(),control=glm.control(epsilon=1e-12,maxit=100))
stopifnot(m$converged)
b <- unname(coef(m))
# glm's cached IRLS covariance uses the previous iteration's weights. Evaluate
# the Fisher information at final fitted probabilities to match the stated target.
X <- model.matrix(m); p <- fitted(m)
se <- sqrt(diag(solve(crossprod(X,X*(p*(1-p))))))
r <- cbind(b,b-qnorm(.975)*se,b+qnorm(.975)*se)
logistic_error <- max(abs(r-as.matrix(j[,2:4])))
stopifnot(logistic_error<1e-7)
d <- read.csv(file.path(out,"random-intercept-rep1-data.csv"))
j <- read.csv(file.path(out,"random-intercept-rep1-julia.csv"))
X <- cbind(1,d$x)
V <- diag(1.2^2,nrow(d)) + outer(d$group,d$group,"==")*.7^2
C <- solve(crossprod(X,solve(V,X)))
b <- drop(C%*%crossprod(X,solve(V,d$y))); se <- sqrt(diag(C))
r <- cbind(b,b-qnorm(.975)*se,b+qnorm(.975)*se)
ri_error <- max(abs(r-as.matrix(j[,2:4])))
stopifnot(ri_error<1e-10)
writeLines(c(R.version.string,paste("logistic estimate/interval max error",format(logistic_error,digits=17)),
 paste("known-covariance GLS estimate/interval max error",format(ri_error,digits=17)),
 "PASS: same data and coefficient targets; random-intercept check uses KNOWN variance components"),
 file.path(out,"r-check.txt"))
cat("PASS: logistic discrepancy",logistic_error," oracle GLS discrepancy",ri_error,"\n")
