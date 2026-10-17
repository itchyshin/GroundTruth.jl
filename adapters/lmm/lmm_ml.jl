module GroundTruthLMM

using GroundTruth: FitResult
using MixedModels
using StatsModels: @formula
using Distributions: Normal, quantile
using LinearAlgebra: Symmetric, cholesky, rank, I, inv, norm, dot
using Logging
using Serialization

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

# Uniform internal stopping precision for base fits and profile-helper refits.
# Keep evaluation limits and all other native optimizer controls unchanged.
function configure_optimizer_precision!(o)
    o.ftol_rel=1e-12
    o.ftol_abs=1e-12
    o
end

function optimizer_controls(o)
    (; maxfeval=o.maxfeval,ftol_rel=o.ftol_rel,ftol_abs=o.ftol_abs,
       xtol_rel=o.xtol_rel,xtol_abs=copy(o.xtol_abs),maxtime=o.maxtime,
       initial_step=copy(o.initial_step),lowerbd=copy(o.lowerbd),
       xtol_zero_abs=o.xtol_zero_abs,ftol_zero_abs=o.ftol_zero_abs,
       backend=o.backend,optimizer=o.optimizer)
end
function fit_diagnostics(m; observed_groups,warnings,criterion,boundary=missing,exact_zero=missing,near_boundary=missing)
    o=m.optsum
    (; objective=o.fmin/2,optimizer=o.optimizer,optimizer_status=o.returnvalue,
       evaluations=o.feval,optimizer_controls=optimizer_controls(o),accepted_statuses=ACCEPTED_STATUSES,
       criterion,objective_convention=criterion==:ML ? :gaussian_ml_nll : :explicit_restricted_gaussian_nll,
       formula="y ~ 1 + x + (1 | group)",engine="MixedModels",
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

"""Whether the design gives REML residual degrees of freedom for group means."""
function information_limit(d)
    labels=string.(d.group)
    groups=unique(labels)
    group_constant_x=all(g->begin
        indices=findall(==(g),labels)
        all(==(first(d.x[indices])),d.x[indices])
    end,groups)
    limited=length(groups)==2 && group_constant_x
    message=limited ?
        "two groups with group-constant x have zero residual group-mean degrees of freedom; REML tau2 is not identified" :
        nothing
    (; reml_tau2_identified=!limited,message)
end

function empty_profile_result()
    levels=Dict(level=>Dict{Symbol,Tuple{Float64,Float64}}() for level in INTERVAL_LEVELS)
    keys=Tuple{Symbol,Float64}[(target,level) for target in (:alpha,:beta) for level in INTERVAL_LEVELS]
    (; intervals_by_level=levels,
       inference_status=Dict(key=>:incomplete for key in keys),
       profile_residuals=Dict{Tuple{Symbol,Float64},Union{Missing,Float64}}(key=>missing for key in keys),
       profile_endpoint_distances=Dict{Tuple{Symbol,Float64},Union{Missing,Float64}}(key=>missing for key in keys),
       profile_message=Dict(key=>"profile did not produce a validated endpoint" for key in keys))
end

"Apply terminal or partial native helper output without discarding accepted pairs."
function apply_profile_payload!(result,status,message,result_data)
    processed=result_data===nothing ? Set{Tuple{Symbol,Float64}}() : Set(result_data.processed)
    for key in keys(result.inference_status)
        if key in processed
            result.inference_status[key]=get(result_data.inference_status,key,:error)
            result.profile_message[key]=get(result_data.profile_message,key,message)
            if haskey(result_data.intervals,key)
                result.intervals_by_level[key[2]][key[1]]=result_data.intervals[key]
                result.profile_residuals[key]=get(result_data.profile_residuals,key,missing)
            end
        else
            state=status==:timeout ? :timeout : status==:invalid ? :invalid : :error
            result.inference_status[key]=state
            result.profile_message[key]=message
        end
    end
    result
end

function run_profile_helper(table,estimates,maxfeval,timeout)
    Sys.isunix() || return merge(empty_profile_result(),(; profile_elapsed=0.,profile_elapsed_seconds=0.,profile_timeout=timeout,
        profile_message=Dict(key=>"hard profile timeout is unsupported on this platform" for key in keys(empty_profile_result().inference_status)),
        inference_messages=Dict(key=>"hard profile timeout is unsupported on this platform" for key in keys(empty_profile_result().inference_status)),
        inference_status=Dict(key=>:error for key in keys(empty_profile_result().inference_status)),
        profile_endpoint_distances=Dict(key=>missing for key in keys(empty_profile_result().inference_status))))
    started=time()
    result=empty_profile_result()
    workdir=mktempdir()
    input=joinpath(workdir,"input.bin"); output=joinpath(workdir,"output.bin")
    stdout_path=joinpath(workdir,"stdout.log"); stderr_path=joinpath(workdir,"stderr.log")
    open(input,"w") do io
        Serialization.serialize(io,(x=table.x,y=table.y,group=table.group,expected=estimates,maxfeval))
    end
    project=normpath(joinpath(@__DIR__,"..",".."))
    adapter_project=joinpath(@__DIR__)
    julia=Base.julia_cmd()
    inherited_loadpath=get(ENV,"JULIA_LOAD_PATH","@")
    loadpath=string(inherited_loadpath,Sys.iswindows() ? ';' : ':',adapter_project)
    cmd=addenv(`$julia --startup-file=no --compiled-modules=no --compile=min -O0 --threads=1 --project=$project $(@__DIR__)/inference_profile_helper.jl $input $output`,
             "JULIA_LOAD_PATH"=>loadpath,
             "JULIA_NUM_THREADS"=>"1","JULIA_PKG_OFFLINE"=>"true",
             "JULIA_PKG_PRECOMPILE_AUTO"=>"0","JULIA_SCRATCH_TRACK_ACCESS"=>"0",
             "OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1",
             "MKL_NUM_THREADS"=>"1","VECLIB_MAXIMUM_THREADS"=>"1")
    proc=nothing
    status=:error; message="profile helper failed"; result_data=nothing
    helper_stdout=""; helper_stderr=""
    try
        proc=run(pipeline(cmd,stdout=stdout_path,stderr=stderr_path);wait=false)
        deadline=started+timeout
        while process_running(proc) && time()<deadline
            sleep(.02)
        end
        if process_running(proc)
            kill(proc,Base.SIGKILL)
            wait(proc)
            status=:timeout; message="profile helper exceeded wall deadline"
            isfile(output) && (result_data=open(Serialization.deserialize,output))
        else
            wait(proc)
            helper_stdout=isfile(stdout_path) ? read(stdout_path,String) : ""
            helper_stderr=isfile(stderr_path) ? read(stderr_path,String) : ""
            length(helper_stdout)>8192 && (helper_stdout=last(helper_stdout,8192))
            length(helper_stderr)>8192 && (helper_stderr=last(helper_stderr,8192))
            if isfile(output)
                result_data=open(Serialization.deserialize,output)
                status=success(proc) ? result_data.status : :error
                message=success(proc) ? result_data.message : "profile helper exited unsuccessfully: "*result_data.message
                if status!=:ok && !isempty(helper_stderr)
                    message *= "\nhelper stderr: "*helper_stderr
                end
            else
                status=:error
                message=isempty(helper_stderr) ? "profile helper exited without a result" : helper_stderr
            end
        end
    catch e
        e isa InterruptException && rethrow()
        status=:error; message=sprint(showerror,e)
        if proc!==nothing && process_running(proc)
            kill(proc,Base.SIGKILL); wait(proc)
        end
    finally
        proc!==nothing && process_running(proc) && (kill(proc,Base.SIGKILL);wait(proc))
        if isfile(stdout_path)
            helper_stdout=read(stdout_path,String)
            length(helper_stdout)>8192 && (helper_stdout=last(helper_stdout,8192))
        end
        if isfile(stderr_path)
            helper_stderr=read(stderr_path,String)
            length(helper_stderr)>8192 && (helper_stderr=last(helper_stderr,8192))
        end
        rm(workdir;recursive=true,force=true)
    end
    elapsed=time()-started
    apply_profile_payload!(result,status,message,result_data)
    merge(result,(profile_elapsed=elapsed,profile_elapsed_seconds=elapsed,profile_timeout=timeout,
                  profile_helper_status=status,profile_helper_message=message,
                  profile_helper_stdout=helper_stdout,profile_helper_stderr=helper_stderr,
                  profile_endpoint_distances=Dict(key=>missing for key in keys(result.inference_status)),
                  inference_messages=result.profile_message))
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

Gaussian ML or REML for `y ~ 1 + x + (1 | group)`. Returns coefficient and variance
points, primary 95% coefficient intervals, and both 90%/95% intervals in
`diagnostics.intervals_by_level`. Fixed-effect profiles are ML-only and run in a
killable helper after the accepted base fit. Variance intervals are not expected.
The fit is deterministic and never reads truth fields. Both levels use one fit.
"""
function lmm_ml(data,rng;level=.95,maxfeval=10_000,criterion=:ML,interval_method=:normal,profile_timeout=60.0)
    level==.95 || throw(ArgumentError("primary interval level must be .95; both .90 and .95 are returned"))
    criterion in (:ML,:REML) || throw(ArgumentError("criterion must be :ML or :REML"))
    interval_method in (:normal,:profile) || throw(ArgumentError("interval_method must be :normal or :profile"))
    profile_timeout isa Real && !(profile_timeout isa Bool) && isfinite(profile_timeout) && profile_timeout>0 ||
        throw(ArgumentError("profile_timeout must be positive and finite"))
    criterion==:REML && interval_method==:profile &&
        throw(ArgumentError("fixed-effect profile intervals are available only with criterion=:ML"))
    maxfeval isa Integer && !(maxfeval isa Bool) && maxfeval>0 ||
        throw(ArgumentError("maxfeval must be a positive integer"))
    d=data
    table=checked_data(d); observed_groups=length(unique(table.group))
    model=MixedModels.MixedModel(LMM_FORMULA,table;contrasts=Dict(:group=>MixedModels.Grouping()))
    model.optsum.maxfeval=maxfeval
    configure_optimizer_precision!(model.optsum)
    warnings=String[]
    with_logger(WarningRecorder(current_logger(),warnings)) do
        MixedModels.fit!(model;REML=criterion==:REML,progress=false)
    end
    diagnostics=merge(fit_diagnostics(model;observed_groups,warnings,criterion),
        (;interval_method,profile_timeout,interval_levels=INTERVAL_LEVELS,
          information_limit=information_limit(d)))
    if model.optsum.returnvalue ∉ ACCEPTED_STATUSES
        failed_keys=[(target,level) for target in (:alpha,:beta) for level in INTERVAL_LEVELS]
        diagnostics=merge(diagnostics,(;
            inference_status=Dict(key=>:error for key in failed_keys),
            profile_residuals=Dict(key=>missing for key in failed_keys),
            profile_endpoint_distances=Dict(key=>missing for key in failed_keys),
            profile_elapsed=0.,profile_elapsed_seconds=0.,
            profile_message=Dict(key=>"base fit was not accepted" for key in failed_keys),
            inference_messages=Dict(key=>"base fit was not accepted" for key in failed_keys)))
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
    diagnostics=fit_diagnostics(model;observed_groups,warnings,criterion,
                                boundary=MixedModels.issingular(model),exact_zero=iszero(tau2),
                                near_boundary=icc<=1e-8)
    base_snapshot=deepcopy(estimates)
    info_limit=information_limit(d)
    interval_failure=nothing
    interval_result=try
        coefficient_inference(table,base_snapshot)
    catch e
        e isa InterruptException && rethrow()
        interval_failure=sprint(showerror,e)
        empty=(Dict(level=>Dict{Symbol,Tuple{Float64,Float64}}() for level in INTERVAL_LEVELS),
               nothing,Dict{Tuple{Symbol,Float64},String}())
        (;intervals_by_level=empty[1],covariance=empty[2],interval_failures=empty[3])
    end
    method_result=interval_method==:normal ?
        merge(interval_result,(interval_method=:normal,inference_status=Dict((t,l)=>haskey(interval_result.intervals_by_level[l],t) ? :finite : :error for t in (:alpha,:beta) for l in INTERVAL_LEVELS),
              profile_residuals=Dict((t,l)=>missing for t in (:alpha,:beta) for l in INTERVAL_LEVELS),
              profile_endpoint_distances=Dict((t,l)=>missing for t in (:alpha,:beta) for l in INTERVAL_LEVELS),
              profile_elapsed=0.,profile_elapsed_seconds=0.,profile_timeout=profile_timeout,
              profile_message=Dict((t,l)=>interval_failure for t in (:alpha,:beta) for l in INTERVAL_LEVELS),
              inference_messages=Dict((t,l)=>interval_failure for t in (:alpha,:beta) for l in INTERVAL_LEVELS))) :
        begin
            profile=try
                run_profile_helper(table,base_snapshot,maxfeval,profile_timeout)
            catch e
                e isa InterruptException && rethrow()
                result=empty_profile_result()
                message=sprint(showerror,e)
                merge(result,(;profile_elapsed=0.,profile_elapsed_seconds=0.,profile_timeout,
                    profile_helper_status=:error,profile_helper_message=message,
                    inference_status=Dict(key=>:error for key in keys(result.inference_status)),
                    profile_message=Dict(key=>message for key in keys(result.inference_status)),
                    inference_messages=Dict(key=>message for key in keys(result.inference_status)),
                    profile_endpoint_distances=Dict(key=>missing for key in keys(result.inference_status))))
            end
            merge(profile,(interval_method=:profile,covariance=interval_result.covariance,
                  interval_failures=interval_result.interval_failures))
        end
    final_diagnostics=merge(diagnostics,method_result,(;criterion,information_limit=info_limit,
        interval_level=.95,interval_levels=INTERVAL_LEVELS,
        coefficient_interval_method=interval_method==:normal ? :plugin_normal_wald : :native_ml_profile,
        variance_interval_reason=:not_expected,interval_failure))
    FitResult(base_snapshot;intervals=method_result.intervals_by_level[.95],diagnostics=final_diagnostics)
end

end # module GroundTruthLMM
