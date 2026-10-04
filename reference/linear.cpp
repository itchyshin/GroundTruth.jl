#include <TMB.hpp>
template<class Type>
Type objective_function<Type>::operator() () {
  DATA_VECTOR(x);
  DATA_VECTOR(y);
  PARAMETER(alpha);
  PARAMETER(beta);
  PARAMETER(log_sigma);
  Type nll = 0;
  for(int i=0; i<y.size(); i++)
    nll -= dnorm(y(i), alpha + beta*x(i), exp(log_sigma), true);
  ADREPORT(alpha); ADREPORT(beta); ADREPORT(log_sigma);
  return nll;
}
