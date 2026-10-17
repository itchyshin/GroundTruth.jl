module GroundTruthLMM

using GroundTruth: FitResult
using MixedModels
using StatsModels: @formula
using Distributions: Normal, quantile
using LinearAlgebra: Symmetric, cholesky, rank, I, inv, norm, dot
using Logging

export lmm_ml

const ACCEPTED_STATUSES = (:SUCCESS, :STOPVAL_REACHED, :FTOL_REACHED, :XTOL_REACHED)
const LMM_FORMULA = @formula(y ~ 1 + x + (1 | group))
const INTERVAL_LEVELS = (.90, .95)

struct WarningRecorder{L<:AbstractLogger} <: AbstractLogger
    delegate::L
    messages::Vector{String}
end
Logging.min_enabled_level(logger::WarningRecorder) = min(Warn, Logging.min_enabled_level(logger.delegate))
Logging.shouldlog(logger::WarningRecorder, level, mod, group, id) =
    level >= Warn || Logging.shouldlog(logger.delegate, level, mod, group, id)
Logging.catch_exceptions(logger::WarningRecorder) = Logging.catch_exceptions(logger.delegate)
function Logging.handle_message(logger::WarningRecorder, level, message, mod, group, id, file, line; kwargs...)
    level >= Warn && push!(logger.messages, string(message))
    if level >= Logging.min_enabled_level(logger.delegate) && Logging.shouldlog(logger.delegate,level,mod,group,id)
        Logging.handle_message(logger.delegate,level,message,mod,group,id,file,line; kwargs...)
    end
end

function checked_data(d)
    hasproperty(d,:family) && d.family == :random_intercept ||
        throw(ArgumentError("lmm_ml requires random-intercept data"))
    all(hasproperty(d,name) for name in (:x,:y,:group)) ||
        throw(ArgumentError("x, y, and group are required"))
    d.x isa AbstractVector && d.y isa AbstractVector && d.group isa AbstractVector ||
        throw(ArgumentError("x, y, and group must be vectors"))
    n=length(d.y)
    n > 2 && length(d.x)==n && length(d.group)==n ||
        throw(ArgumentError("x, y, and group need equal lengths > 2"))
    all(v->v isa Real && isfinite(v),d.x) && all(v->v isa Real && isfinite(v),d.y) ||
        throw(ArgumentError("x and y must be finite real values"))
    x=Float64.(d.x); y=Float64.(d.y)
    all(isfinite,x) && all(isfinite,y) || throw(ArgumentError("x and y must be finite Float64 values"))
    rank(hcat(ones(n),x)) == 2 || throw(ArgumentError("fixed-effect design is rank deficient"))
    all(v->!ismissing(v),d.group) || throw(ArgumentError("group labels cannot be missing"))
    group=string.(d.group)
    length(unique(group))==length(unique(d.group)) ||
        throw(ArgumentError("distinct group labels collide after string conversion"))
    counts=[count(==(g),group) for g in unique(group)]
    length(counts)>=2 || throw(ArgumentError("at least two groups are required"))
    any(>(1),counts) || throw(ArgumentError("some within-group replication is required"))
    reject_residual_collapse(x,y,group)
    (; x,y,group)
end

"Reject a response lying in the fixed-plus-group span, up to floating-point backward error."
function reject_residual_collapse(x,y,group)
    # Demeaning removes arbitrary group intercepts. The remaining design is one
    # within-group slope; singletons contribute zero, without hiding replication.
    wx=copy(x); wy=copy(y)
    for label in unique(group)
        indices=findall(==(label),group)
        # Subtract a group anchor first: huge response origins or group means
        # must not set the tolerance for resolvable within-group residuals.
        dx=x[indices].-x[first(indices)]
        dy=y[indices].-y[first(indices)]
        wx[indices]=dx.-sum(dx)/length(indices)
        wy[indices]=dy.-sum(dy)/length(indices)
    end
    nx=norm(wx)
    slope=nx>0 ? dot(wx/nx,wy)/nx : 0.
    residual=wy-slope*wx
    scale=max(norm(wy),abs(slope)*nx)
    (scale==0 || norm(residual)/scale <= 64eps(Float64)) &&
        throw(ArgumentError("numerically residual-degenerate likelihood: y is in the fixed-plus-group span within floating-point tolerance; sigma2 may collapse to zero"))
    nothing
end

function optimizer_controls(o)
    (; maxfeval=o.maxfeval,ftol_rel=o.ftol_rel,ftol_abs=o.ftol_abs,
       xtol_rel=o.xtol_rel,xtol_abs=copy(o.xtol_abs),maxtime=o.maxtime,
       initial_step=copy(o.initial_step),lowerbd=copy(o.lowerbd),
       xtol_zero_abs=o.xtol_zero_abs,ftol_zero_abs=o.ftol_zero_abs,
       backend=o.backend,optimizer=o.optimizer)
end
function fit_diagnostics(m; observed_groups,warnings,boundary=missing,exact_zero=missing,near_boundary=missing)
    o=m.optsum
    (; objective=o.fmin/2,optimizer=o.optimizer,optimizer_status=o.returnvalue,
       evaluations=o.feval,optimizer_controls=optimizer_controls(o),accepted_statuses=ACCEPTED_STATUSES,
       criterion=:ML,formula="y ~ 1 + x + (1 | group)",engine="MixedModels",
       engine_version=string(Base.pkgversion(MixedModels)),boundary,issingular=boundary,
       exact_zero,near_boundary,near_boundary_threshold=1e-8,observed_groups,
       weak_group_information=observed_groups<5,warnings=copy(warnings),
       optimizer_message=string(o.returnvalue),interval_level=.95,interval_levels=INTERVAL_LEVELS,
       coefficient_interval_method=:plugin_normal_wald,variance_interval_reason=:not_expected,
       residual_degeneracy_detector="anchored within-group projection; residual/within-response-slope scale <= 64*eps(Float64)")
end

function coefficient_inference(table,estimates)
    n=length(table.y); X=hcat(ones(n),table.x)
    V=Matrix{Float64}(I,n,n).*estimates[:sigma2]
    for i in 1:n,j in 1:n
        table.group[i]==table.group[j] && (V[i,j]+=estimates[:tau2])
    end
    L=cholesky(Symmetric(V))
    C=Matrix(inv(Symmetric(X'*(L\X))))
    by_level=Dict(level=>Dict{Symbol,Tuple{Float64,Float64}}() for level in INTERVAL_LEVELS)
    failures=Dict{Tuple{Symbol,Float64},String}()
    for (target,column) in ((:alpha,1),(:beta,2)),level in INTERVAL_LEVELS
        variance=C[column,column]
        se=variance>0 ? sqrt(variance) : NaN
        q=quantile(Normal(),(1+level)/2)
        endpoints=(estimates[target]-q*se,estimates[target]+q*se)
        if isfinite(se) && se>0 && all(isfinite,endpoints)
            by_level[level][target]=endpoints
        else
            failures[(target,level)]="invalid fixed-effect covariance or nonfinite Wald endpoints"
        end
    end
    (; intervals_by_level=by_level,covariance=C,interval_failures=failures)
end

function result_with_intervals(estimates,diagnostics,build_intervals)
    by_level=Dict(level=>Dict{Symbol,Tuple{Float64,Float64}}() for level in INTERVAL_LEVELS)
    failure=nothing
    inference=(intervals_by_level=by_level,covariance=nothing,
               interval_failures=Dict{Tuple{Symbol,Float64},String}())
    try
        inference=build_intervals()
    catch e
        e isa InterruptException && rethrow()
        failure=sprint(showerror,e)
    end
    FitResult(estimates; intervals=inference.intervals_by_level[.95],
              diagnostics=merge(diagnostics,inference,(; interval_failure=failure)))
end

"""
    lmm_ml(data, rng; level=.95, maxfeval=10_000)

Gaussian ML for `y ~ 1 + x + (1 | group)`. Returns coefficient and variance
points, primary 95% coefficient Wald intervals, and both 90%/95% intervals in
`diagnostics.intervals_by_level`. Variance intervals are not expected. The fit is
deterministic and never reads truth fields. Only the declared 95% primary level
is accepted; the two coefficient levels use one fit and the same covariance.
"""
function lmm_ml(d,rng;level=.95,maxfeval=10_000)
    level==.95 || throw(ArgumentError("primary interval level must be .95; both .90 and .95 are returned"))
    maxfeval isa Integer && !(maxfeval isa Bool) && maxfeval>0 ||
        throw(ArgumentError("maxfeval must be a positive integer"))
    table=checked_data(d); observed_groups=length(unique(table.group))
    model=MixedModels.MixedModel(LMM_FORMULA,table;contrasts=Dict(:group=>MixedModels.Grouping()))
    model.optsum.maxfeval=maxfeval
    warnings=String[]
    with_logger(WarningRecorder(current_logger(),warnings)) do
        MixedModels.fit!(model;REML=false,progress=false)
    end
    diagnostics=fit_diagnostics(model;observed_groups,warnings)
    if model.optsum.returnvalue ∉ ACCEPTED_STATUSES
        return FitResult(Dict{Symbol,Float64}();converged=false,
                         message="optimizer status $(model.optsum.returnvalue)",diagnostics)
    end
    names=MixedModels.fixefnames(model)
    length(names)==2 && Set(names)==Set(("(Intercept)","x")) ||
        throw(ArgumentError("unexpected fixed-effect names or rank: $(names)"))
    beta=MixedModels.fixef(model)
    all(isfinite,beta) || throw(ArgumentError("nonfinite fixed-effect coefficients"))
    components=MixedModels.VarCorr(model).σρ
    keys(components)==(:group,) || throw(ArgumentError("unexpected random-effect grouping"))
    group_sd=only(values(only(values(components)).σ))
    sigma2=MixedModels.sdest(model)^2; tau2=group_sd^2
    isfinite(sigma2) && sigma2>0 && isfinite(tau2) && tau2>=0 ||
        throw(ArgumentError("invalid fitted variance components"))
    isfinite(diagnostics.objective) || throw(ArgumentError("nonfinite fitted objective"))
    estimates=Dict{Symbol,Float64}(:sigma2=>sigma2,:tau2=>tau2)
    for (name,target) in (("(Intercept)",:alpha),("x",:beta))
        estimates[target]=beta[only(findall(==(name),names))]
    end
    ratio=tau2/sigma2
    icc=ratio<=1 ? ratio/(1+ratio) : 1/(1+sigma2/tau2)
    diagnostics=fit_diagnostics(model;observed_groups,warnings,
                                boundary=MixedModels.issingular(model),exact_zero=iszero(tau2),
                                near_boundary=icc<=1e-8)
    result_with_intervals(estimates,diagnostics,()->coefficient_inference(table,estimates))
end

end # module GroundTruthLMM
