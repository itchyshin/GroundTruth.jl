#!/usr/bin/env python3
"""Stdlib-only deterministic Gaussian RI oracle. No GroundTruth/lme4/MixedModels imports.

Block Sherman-Morrison calculations and an independently coded dense Cholesky
route check each other. Optimization is scalar concentrated likelihood, not a
second call to the engine under test. A bounded search never proves an infinite CI.
"""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
from statistics import NormalDist
import time

HERE = Path(__file__).resolve().parent
FIXTURES = HERE.parent / "fixtures"
LOG2PI = math.log(2 * math.pi)


def read_data(path):
    with open(path, newline="") as handle:
        rows = list(csv.DictReader(handle))
    return ([float(r["x"]) for r in rows], [float(r["y"]) for r in rows],
            [r["group"] for r in rows])


def dot(a, b):
    return math.fsum(x * y for x, y in zip(a, b))


def chol(a):
    n = len(a)
    out = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            value = a[i][j] - math.fsum(out[i][k] * out[j][k] for k in range(j))
            if i == j:
                if value <= 0:
                    raise ValueError("non-positive-definite matrix")
                out[i][j] = math.sqrt(value)
            else:
                out[i][j] = value / out[j][j]
    return out


def solve_chol(l, b):
    n = len(b)
    z, x = [0.0] * n, [0.0] * n
    for i in range(n):
        z[i] = (b[i] - math.fsum(l[i][k] * z[k] for k in range(i))) / l[i][i]
    for i in reversed(range(n)):
        x[i] = (z[i] - math.fsum(l[k][i] * x[k] for k in range(i + 1, n))) / l[i][i]
    return x


def inverse_chol(l):
    n = len(l)
    columns = [solve_chol(l, [float(i == j) for i in range(n)]) for j in range(n)]
    return [[columns[j][i] for j in range(n)] for i in range(n)]


def dense_reference(data, sigma2, tau2, beta=None, criterion="ML"):
    x, y, groups = data
    n = len(y)
    v = [[sigma2 * (i == j) + tau2 * (groups[i] == groups[j])
          for j in range(n)] for i in range(n)]
    lv = chol(v)
    columns = [[1.0] * n, x]
    vx = [solve_chol(lv, c) for c in columns]
    information = [[dot(c, solved) for solved in vx] for c in columns]
    li = chol(information)
    covariance = inverse_chol(li)
    vy = solve_chol(lv, y)
    bhat = solve_chol(li, [dot(c, vy) for c in columns])
    b = bhat if beta is None else beta
    residual = [yi - b[0] - b[1] * xi for xi, yi in zip(x, y)]
    q = dot(residual, solve_chol(lv, residual))
    value = n * LOG2PI + 2 * sum(math.log(lv[i][i]) for i in range(n)) + q
    if criterion == "REML":
        if beta is not None:
            raise ValueError("REML oracle is variance likelihood, not constrained fixed effect")
        value += 2 * sum(math.log(li[i][i]) for i in range(2)) - 2 * LOG2PI
    return dict(nll=value / 2, coefficients=bhat, covariance=covariance)


class BlockModel:
    def __init__(self, data):
        self.x, self.y, self.groups = data
        self.n = len(self.y)
        self.columns = [[1.0] * self.n, self.x]
        self.indices = [[i for i, g in enumerate(self.groups) if g == group]
                        for group in dict.fromkeys(self.groups)]
        if self.n <= 2 or len(self.indices) < 2:
            raise ValueError("insufficient observations/groups")
        if not any(len(ii) > 1 for ii in self.indices):
            raise ValueError("no replicated group")
        # Independent full rank condition (two-column Gram determinant).
        gram = self.n * dot(self.x, self.x) - sum(self.x) ** 2
        if gram <= 1e-13 * max(1, self.n * dot(self.x, self.x)):
            raise ValueError("rank deficient design")

    def inner(self, a, b, rho):
        # Sherman-Morrison in group-mean/within form avoids cancellation at
        # large rho: within crossproduct + n*mean(a)*mean(b)/(1+n*rho).
        pieces=[]
        for ii in self.indices:
            ma=math.fsum(a[i] for i in ii)/len(ii)
            mb=math.fsum(b[i] for i in ii)/len(ii)
            pieces.append(math.fsum((a[i]-ma)*(b[i]-mb) for i in ii) +
                          len(ii)*ma*mb/(1+len(ii)*rho))
        return math.fsum(pieces)

    def evaluate(self, rho, criterion="ML", constraint=None):
        if rho < 0 or not math.isfinite(rho):
            raise ValueError("rho must be finite and nonnegative")
        columns = self.columns
        response = self.y
        if constraint is not None:
            if criterion != "ML":
                raise ValueError("fixed coefficient profiling is ML only")
            j, value = constraint
            response = [y - value * x for y, x in zip(response, columns[j])]
            columns = [columns[1 - j]]
        info = [[self.inner(c, d, rho) for d in columns] for c in columns]
        li = chol(info)
        coefficients = solve_chol(li, [self.inner(c, response, rho) for c in columns])
        residual = [response[i] - sum(c[i] * b for c, b in zip(columns, coefficients))
                    for i in range(self.n)]
        q = self.inner(residual, residual, rho)
        if q <= 0:
            raise ValueError("residual-degenerate likelihood")
        df = self.n - (2 if criterion == "REML" else 0)
        sigma2 = q / df
        logdet = sum(math.log1p(len(ii) * rho) for ii in self.indices)
        nll = (df * (LOG2PI + math.log(sigma2) + 1) + logdet) / 2
        if criterion == "REML":
            nll += sum(math.log(li[i][i]) for i in range(2))
        covariance = [[sigma2 * v for v in row] for row in inverse_chol(li)]
        if constraint is not None:
            b = [None, None]
            b[constraint[0]] = constraint[1]
            b[1 - constraint[0]] = coefficients[0]
            coefficients = b
        return dict(nll=nll, sigma2=sigma2, tau2=rho * sigma2,
                    rho=rho, coefficients=coefficients, covariance=covariance)

    def fixed_variances(self, sigma2, tau2, criterion="ML", beta=None):
        if sigma2 <= 0 or tau2 < 0:
            raise ValueError("invalid variances")
        if criterion == "REML" and beta is not None:
            raise ValueError("REML eliminates fixed effects")
        rho=tau2/sigma2
        gls=self.evaluate(rho,criterion)
        b=gls["coefficients"] if beta is None else beta
        residual=[yi-b[0]-b[1]*xi for xi,yi in zip(self.x,self.y)]
        q=self.inner(residual,residual,rho)
        df=self.n-(2 if criterion=="REML" else 0)
        logdet=sum(math.log1p(len(ii)*rho) for ii in self.indices)
        value=(df*(LOG2PI+math.log(sigma2))+logdet+q/sigma2)/2
        if criterion=="REML":
            li=chol([[self.inner(c,d,rho) for d in self.columns] for c in self.columns])
            value+=sum(math.log(li[i][i]) for i in range(2))
        return dict(nll=value,coefficients=gls["coefficients"],
                    covariance=[[v*sigma2/gls["sigma2"] for v in row] for row in gls["covariance"]])

    def optimize(self, criterion="ML", constraint=None):
        if (criterion == "REML" and len(self.indices) == 2 and
            all(all(self.x[i] == self.x[ii[0]] for i in ii) for ii in self.indices)):
            # Algebraic ridge: choose a labelled representative, never optimize
            # floating-point noise along an unidentified variance direction.
            representative=self.evaluate(0.0,criterion)
            representative["variance_information"]="tau2_unidentified; rho=0 is a representative only"
            return representative
        # Search multiple local basins in t=log1p(rho), include boundary exactly.
        # Upper search cap is explicit and checked, never silently called infinity.
        def evaluate(t):
            return self.evaluate(math.expm1(t), criterion, constraint)
        grid = [i / 4 for i in range(129)]
        values = [evaluate(t) for t in grid]
        candidates = [values[0]]
        for k in range(1, len(grid) - 1):
            if values[k]["nll"] <= values[k-1]["nll"] and values[k]["nll"] <= values[k+1]["nll"]:
                lo, hi = grid[k-1], grid[k+1]
                ratio = (math.sqrt(5) - 1) / 2
                a, b = hi - ratio * (hi-lo), lo + ratio * (hi-lo)
                fa, fb = evaluate(a), evaluate(b)
                for _ in range(70):
                    if fa["nll"] < fb["nll"]:
                        hi, b, fb = b, a, fa
                        a = hi - ratio * (hi-lo)
                        fa = evaluate(a)
                    else:
                        lo, a, fa = a, b, fb
                        b = lo + ratio * (hi-lo)
                        fb = evaluate(b)
                candidates.extend([fa, fb])
        best = min(candidates, key=lambda d: d["nll"])
        if values[-1]["nll"] < best["nll"] - 1e-7:
            raise ValueError("scalar variance search incomplete at upper cap")
        best["search_t_cap"] = grid[-1]
        return best

    def profile_endpoint(self, base, coefficient, level, side):
        cutoff = NormalDist().inv_cdf((1 + level) / 2)
        center = base["coefficients"][coefficient]
        se = math.sqrt(base["covariance"][coefficient][coefficient])
        def lr(value):
            fit = self.optimize(constraint=(coefficient, value))
            delta = 2 * (fit["nll"] - base["nll"])
            if delta < -1e-7:
                raise ValueError("constrained NLL below base optimum")
            return math.sqrt(max(0, delta)) - cutoff
        inner, outer = center, center + side * se
        for _ in range(25):
            if lr(outer) >= 0:
                break
            outer = center + 2 * (outer - center)
        else:
            raise ValueError("profile bracket incomplete; no unboundedness claim")
        for _ in range(45):
            middle = (inner + outer) / 2
            if lr(middle) >= 0:
                outer = middle
            else:
                inner = middle
        endpoint = (inner + outer) / 2
        residual=lr(endpoint)
        assert abs(residual)<1e-8, ("independent profile root failed",endpoint,residual)
        return dict(endpoint=endpoint, root_lr_residual=residual)


def close(a, b, tol=1e-8):
    assert abs(a-b) <= tol * (1+abs(b)), (a, b, tol)


def inspect_fixture(path, profiles=False):
    data = read_data(path)
    model = BlockModel(data)
    checks = 0
    # Fixed positive variances test objectives and covariance independently of optimization.
    for sigma2, tau2 in ((.7, 0), (.7, .4), (2.0, 3.0)):
        rho = tau2 / sigma2
        for criterion in ("ML", "REML"):
            block = model.fixed_variances(sigma2,tau2,criterion)
            dense = dense_reference(data,sigma2,tau2,criterion=criterion)
            close(block["nll"], dense["nll"])
            for i in range(2):
                close(block["coefficients"][i], dense["coefficients"][i])
                for j in range(2):
                    close(block["covariance"][i][j], dense["covariance"][i][j])
            checks += 1
        block=model.fixed_variances(sigma2,tau2,beta=[1.1,-.4])
        dense=dense_reference(data,sigma2,tau2,beta=[1.1,-.4])
        close(block["nll"],dense["nll"])
        checks+=1
    fits = {criterion: model.optimize(criterion) for criterion in ("ML", "REML")}
    for criterion, fit in fits.items():
        fit["normal_intervals"] = {}
        for j, target in enumerate(("alpha", "beta")):
            se = math.sqrt(fit["covariance"][j][j])
            for level in (.9, .95):
                q = NormalDist().inv_cdf((1+level)/2)
                fit["normal_intervals"][f"{target}:{level}"] = [fit["coefficients"][j]-q*se,
                                                                    fit["coefficients"][j]+q*se]
    if profiles:
        fits["ML"]["profile_intervals"] = {
            f"{target}:{level}": [model.profile_endpoint(fits["ML"], j, level, side)
                                   for side in (-1, 1)]
            for j, target in enumerate(("alpha", "beta")) for level in (.9, .95)}
    return dict(checks=checks, fits=fits)


def verify(manifest, profiles=False):
    results = {}
    for entry in manifest["fixtures"]:
        path = FIXTURES / entry["file"]
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]
        if entry.get("invalid"):
            # Schema/rank rejection is tested here; anchored residual-collapse is
            # checked separately by exact within-group construction, not native fits.
            if entry["invalid"] == "rank":
                try:
                    BlockModel(read_data(path))
                except ValueError:
                    results[path.stem] = dict(expected_rejection="rank")
                else:
                    raise AssertionError("rank deficient fixture accepted")
            else:
                x,y,g=read_data(path)
                for group in set(g):
                    ii=[i for i,v in enumerate(g) if v==group]
                    for i in ii:
                        close(y[i]-y[ii[0]], 2*(x[i]-x[ii[0]]),1e-13)
                results[path.stem] = dict(expected_rejection="residual collapse")
            continue
        results[path.stem] = inspect_fixture(path, profiles and entry.get("profile_validation", False))
    limited = BlockModel(read_data(FIXTURES / "two_group_group_x.csv"))
    reml = [dense_reference((limited.x, limited.y, limited.groups), .8, tau, criterion="REML")["nll"]
            for tau in (0, .1, 1, 10, 100)]
    for value in reml:
        close(value, reml[0])
    results["two_group_group_x"]["tau2_unidentified_REML"] = dict(fixed_sigma2=.8,tau2=[0,.1,1,10,100],nll=reml)
    # Analytic no-RE limit: both scalar fits at rho=0 equal OLS, REML sigma2 uses n-p.
    boundary = BlockModel(read_data(FIXTURES / "boundary_zero.csv"))
    ml, remlfit = boundary.optimize("ML"), boundary.optimize("REML")
    assert ml["rho"] == 0 and remlfit["rho"] == 0
    close(remlfit["sigma2"]/ml["sigma2"],boundary.n/(boundary.n-2))
    # Affine transformations independently constrain all coefficient/covariance
    # entries, both variances and the objective's determinant convention.
    for criterion in ("ML","REML"):
        base=results["balanced_interior"]["fits"][criterion]
        sx=results["predictor_shift_rescale"]["fits"][criterion]
        sy=results["response_shift_rescale"]["fits"][criterion]
        close(sx["coefficients"][0],base["coefficients"][0]+.03*base["coefficients"][1])
        close(sx["coefficients"][1],-.01*base["coefficients"][1])
        close(sy["coefficients"][0],2+.01*base["coefficients"][0])
        close(sy["coefficients"][1],.01*base["coefficients"][1])
        a=[[1,.03],[0,-.01]]
        for i in range(2):
            for j in range(2):
                expected=sum(a[i][k]*base["covariance"][k][l]*a[j][l] for k in range(2) for l in range(2))
                close(sx["covariance"][i][j],expected)
                close(sy["covariance"][i][j],.0001*base["covariance"][i][j])
        for variance in ("sigma2","tau2"):
            close(sx[variance],base[variance],1e-5)
            close(sy[variance],.0001*base[variance],1e-5)
        close(sx["nll"],base["nll"]+(math.log(100) if criterion=="REML" else 0))
        close(sy["nll"],base["nll"]+(24-(2 if criterion=="REML" else 0))*math.log(.01))
    results["predictor_shift_rescale"]["transformation_checks"]="all coefficients, full covariance, variances, ML/REML objective"
    results["response_shift_rescale"]["transformation_checks"]="all coefficients, full covariance, variances, ML/REML objective"
    return results


if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--profiles",action="store_true")
    parser.add_argument("--output",type=Path)
    args=parser.parse_args()
    start=time.monotonic()
    manifest=json.loads((FIXTURES/"manifest.json").read_text())
    results=verify(manifest,args.profiles)
    payload=dict(independence="stdlib block + dense Cholesky; no fitted native engine",results=results,
                 elapsed_seconds=time.monotonic()-start,profile_endpoints=args.profiles)
    if args.output:
        args.output.write_text(json.dumps(payload,indent=2,allow_nan=False)+"\n")
    print("INDEPENDENT_GAUSSIAN_ORACLE_OK",len(results),f"{payload['elapsed_seconds']:.3f}s")
