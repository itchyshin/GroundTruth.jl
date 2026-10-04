# Symbolic contract (written before implementation)

Gaussian: x_i ~ N(0,1), y_i = alpha + beta*x_i + sigma*epsilon_i,
epsilon_i ~ N(0,1) independently. Targets alpha, beta; sigma is DGP truth
but is not a coefficient target in this first slice. OLS uses an intercept and x;
intervals use Student t with n-2 degrees of freedom and estimated residual variance.

Logistic: x_i ~ N(0,1), y_i ~ Bernoulli(logistic(alpha+beta*x_i)).
Targets alpha and beta are conditional log-odds coefficients, not risk differences.
MLE uses Newton iteration; intervals are asymptotic normal Wald intervals.

Random intercept: y_ij = alpha + beta*x_ij + u_j + sigma*epsilon_ij,
u_j ~ N(0,tau²). Targets alpha,beta. The first comparison uses GLS with KNOWN
sigma,tau; it is an oracle benchmark, not a variance-component estimator.

| Symbol | Generator | Fit | Truth |
|---|---|---|---|
| alpha | intercept contribution | coefficient 1 | scenario.alpha |
| beta | beta*x | coefficient 2 | scenario.beta |
| sigma | independent normal noise scale | OLS estimated; oracle GLS known | scenario.sigma |
| tau | independent group draw scale | oracle covariance block tau² | scenario.tau |

Fitting receives data only, never the scenario/truth. Oracle covariance is supplied
explicitly in adapter settings. Reference Stan LM uses the same likelihood and
coefficient targets with explicit priors, thus a different inferential procedure
from OLS. No claim that a Bayesian posterior and an MLE are interchangeable.
