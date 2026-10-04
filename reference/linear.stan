data { int<lower=1> N; vector[N] x; vector[N] y; }
parameters { real alpha; real beta; real log_sigma; }
model {
  alpha ~ normal(0, 5);
  beta ~ normal(0, 2);
  log_sigma ~ normal(0, 0.5);
  y ~ normal(alpha + beta * x, exp(log_sigma));
}
