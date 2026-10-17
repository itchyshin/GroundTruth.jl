"""Exact balanced-group intercept control only; no candidate model/engine fit."""
import csv,json,math
from pathlib import Path
from statistics import mean,stdev,NormalDist
ROOT=Path(__file__).resolve().parent
rows=list(csv.DictReader((ROOT/'fixtures/balanced_interior.csv').open()))
groups={g:[r for r in rows if r['group']==g] for g in sorted({r['group'] for r in rows})}
assert len({len(v) for v in groups.values()})==1
assert all(abs(sum(float(r['x']) for r in v))<1e-14 for v in groups.values())
y=[mean(float(r['y']) for r in v) for v in groups.values()]
df=len(y)-1
# Integrate Student density from0 to t by deterministic Simpson quadrature.
# This oracle does not call R qt or Julia Distributions.
c=math.exp(math.lgamma((df+1)/2)-math.lgamma(df/2))/math.sqrt(df*math.pi)
def cdf(t):
    n=2048;h=t/n
    f=lambda z:c*(1+z*z/df)**(-(df+1)/2)
    return .5+h/3*(f(0)+f(t)+sum((4 if k%2 else 2)*f(k*h) for k in range(1,n)))
def quantile(p):
    lo,hi=0.,16.
    assert cdf(hi)>p
    for _ in range(70):
        m=(lo+hi)/2
        if cdf(m)<p:lo=m
        else:hi=m
    return (lo+hi)/2
se=stdev(y)/math.sqrt(len(y));out={}
for level in (.9,.95):
    q=quantile((1+level)/2)
    assert q>NormalDist().inv_cdf((1+level)/2)
    out[str(level)]={'df':df,'critical':q,'mean':mean(y),'se':se,'lower':mean(y)-q*se,'upper':mean(y)+q*se}
assert abs(out['0.95']['critical']-2.570581835636314)<1e-10
if __name__=='__main__':print(json.dumps(out));print('GROUP_MEAN_T_CONTROL_OK')
