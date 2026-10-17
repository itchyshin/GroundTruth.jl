using GroundTruth, SHA, Dates, LinearAlgebra, MixedModels, Serialization
BLAS.set_num_threads(1)
Threads.nthreads()==1 && BLAS.get_num_threads()==1 || error("inference capture requires one Julia and BLAS thread")
include(joinpath(@__DIR__,"..","adapters","lmm","lmm_ml.jl"))

module HeldoutProfileHelper
include(joinpath(@__DIR__,"..","adapters","lmm","inference_profile_helper.jl"))
end

# Held-out numerical fixture checks reuse the exact production helper and collector.
# Only the balanced fixture exercises the full isolated public adapter workflow.
function heldout_profile(data)
    base=GroundTruthLMM.lmm_ml(data,nothing;criterion=:ML,interval_method=:normal)
    base.converged || return base
    started=time()
    result=mktempdir() do directory
        input=joinpath(directory,"input.bin");output=joinpath(directory,"output.bin")
        open(input,"w") do io
            serialize(io,(x=data.x,y=data.y,group=string.(data.group),expected=deepcopy(base.estimates),maxfeval=10_000))
        end
        HeldoutProfileHelper.main(input,output)
        payload=open(deserialize,output)
        result=GroundTruthLMM.empty_profile_result()
        GroundTruthLMM.apply_profile_payload!(result,payload.status,payload.message,payload)
        result
    end
    diagnostics=merge(base.diagnostics,result,(interval_method=:profile,
        coefficient_interval_method=:native_ml_profile,profile_elapsed_seconds=time()-started,
        inference_messages=result.profile_message))
    GroundTruth.FitResult(deepcopy(base.estimates);intervals=result.intervals_by_level[.95],diagnostics)
end

const FIXTURE_DIR=joinpath(@__DIR__,"..","test","fixtures","inference")
const OUTPUT_DIR=joinpath(@__DIR__,"..",".unlazy","inference","evidence")
const VALID_FIXTURES=("balanced_interior","boundary_zero","unbalanced_singleton",
    "two_group_within_x","two_group_group_x","six_group_group_x",
    "near_residual_collapse","predictor_shift_rescale","response_shift_rescale")
const PROFILE_FIXTURES=Set(("balanced_interior","boundary_zero","unbalanced_singleton","six_group_group_x"))

function fixture(name)
    lines=readlines(joinpath(FIXTURE_DIR,name*".csv"))
    first(lines)=="x,y,group" || error("unexpected schema for $name")
    cells=[split(line,',') for line in lines[2:end]]
    (;x=parse.(Float64,getindex.(cells,1)),y=parse.(Float64,getindex.(cells,2)),
       group=getindex.(cells,3),family=:random_intercept)
end
function digest(paths)
    chunks=String[]
    root=normpath(joinpath(@__DIR__,".."))
    ordered=sort(collect(paths);by=path->relpath(path,root))
    for path in ordered
        push!(chunks,string(relpath(path,root),"\0",bytes2hex(sha256(read(path)))))
    end
    bytes2hex(sha256(join(chunks,"\n")))
end
function rows_for(name,criterion,method,fit)
    execution_route=method==:normal ? "adapter_direct" : name=="balanced_interior" ? "adapter_isolated" : "helper_inprocess_fixture_validation"
    out=NamedTuple[]
    intervals=get(fit.diagnostics,:intervals_by_level,Dict())
    covariance=get(fit.diagnostics,:covariance,nothing)
    for level in (.90,.95), target in (:alpha,:beta)
        endpoints=get(get(intervals,level,Dict()),target,(missing,missing))
        key=(target,level)
        fallback=fit.converged && all(x->x isa Real && isfinite(x),endpoints) ? :finite : :error
        state=get(get(fit.diagnostics,:inference_status,Dict()),key,
                  fallback)
        push!(out,(fixture=name,criterion=criterion,interval_method=method,target=target,level=level,
            estimate=get(fit.estimates,target,missing),sigma2=get(fit.estimates,:sigma2,missing),
            tau2=get(fit.estimates,:tau2,missing),objective=get(fit.diagnostics,:objective,missing),
            cov11=covariance===nothing ? missing : covariance[1,1],
            cov12=covariance===nothing ? missing : covariance[1,2],
            cov22=covariance===nothing ? missing : covariance[2,2],
            lower=endpoints[1],upper=endpoints[2],state,
            base_status=get(fit.diagnostics,:optimizer_status,missing),
            engine_version=get(fit.diagnostics,:engine_version,missing),execution_route,
            root_lr_residual=get(get(fit.diagnostics,:profile_residuals,Dict()),key,missing),
            elapsed_seconds=get(fit.diagnostics,:profile_elapsed_seconds,missing),
            message=get(get(fit.diagnostics,:inference_messages,Dict()),key,"")))
    end
    out
end
function write_sidecar(path, metadata)
    esc(s)="\""*replace(string(s),"\\"=>"\\\\","\""=>"\\\"","\n"=>"\\n")*"\""
    open(path,"w") do io
        println(io,"{")
        items=collect(Base.pairs(metadata))
        for (i,(key,value)) in enumerate(items)
            print(io,"  ",esc(key),": ")
            if value isa Bool
                print(io,value ? "true" : "false")
            elseif value isa Integer || value isa AbstractFloat
                print(io,value)
            else
                print(io,esc(value))
            end
            println(io,i==length(items) ? "" : ",")
        end
        println(io,"}")
    end
end

mkpath(OUTPUT_DIR)
csv_path=joinpath(OUTPUT_DIR,"julia-capture.csv")
sidecar_path=joinpath(OUTPUT_DIR,"julia-capture.json")
manifest=joinpath(FIXTURE_DIR,"manifest.json")
repo=normpath(joinpath(@__DIR__,".."))
source_paths=vcat(filter(p->endswith(p,".jl"),readdir(joinpath(repo,"src");join=true)),
                  filter(p->endswith(p,".jl"),readdir(joinpath(repo,"adapters","lmm");join=true)))
source_files=join(sort(relpath.(source_paths,Ref(repo))),";")
function main()
    rows=NamedTuple[]
    outer_fits=0; helper_base_fit_attempts=0; profile_calls=0
    start=now()
    frozen_source_sha=digest(source_paths)
    frozen_source_files=source_files
    frozen_fixture_manifest_sha=bytes2hex(sha256(read(manifest)))
    (isfile(csv_path) || isfile(sidecar_path)) && error("refusing to overwrite existing full-capture output")
    function save_progress(;complete=false)
        digest(source_paths)==frozen_source_sha || error("production source changed during native capture")
        isempty(rows) || GroundTruth.write_results(csv_path,rows)
        write_sidecar(sidecar_path,(schema="groundtruth-julia-inference-capture-v1",
            source_sha256=frozen_source_sha,source_files=frozen_source_files,
            harness_sha256=bytes2hex(sha256(read(@__FILE__))),
            profile_execution_design="four numerical fixtures; one isolated public adapter workflow",
            fixture_manifest_sha256=frozen_fixture_manifest_sha,
            csv_sha256=isfile(csv_path) ? bytes2hex(sha256(read(csv_path))) : "",
            julia_version=string(VERSION),mixedmodels_version=string(Base.pkgversion(MixedModels)),
            started_at=string(start),updated_at=string(now()),outer_fit_attempts=outer_fits,
            profile_helper_base_fit_attempts=helper_base_fit_attempts,profile_calls=profile_calls,
            fixture_names=join(VALID_FIXTURES,";"),output_rows=length(rows),complete))
    end
for name in VALID_FIXTURES
    data=fixture(name)
    strategies=[(:ML,:normal),(:REML,:normal)]
    name in PROFILE_FIXTURES && push!(strategies,(:ML,:profile))
    for (criterion,method) in strategies
        outer_fits+=1
        method==:profile && (profile_calls+=1;helper_base_fit_attempts+=1)
        fit=try
            criterion==:ML && method==:normal ?
                GroundTruthLMM.lmm_ml(data,nothing) :
                method==:profile && name!="balanced_interior" ? heldout_profile(data) :
                GroundTruthLMM.lmm_ml(data,nothing;criterion,interval_method=method)
        catch err
            err isa InterruptException && rethrow()
            GroundTruth.FitResult(Dict{Symbol,Float64}();converged=false,
                message=sprint(showerror,err),diagnostics=(criterion=criterion,interval_method=method,
                optimizer_status=:EXCEPTION,objective=missing,covariance=nothing,
                inference_status=Dict((target,level)=>:error for target in (:alpha,:beta),level in (.90,.95)),
                profile_residuals=Dict(),profile_elapsed_seconds=missing,inference_messages=Dict()))
        end
        append!(rows,rows_for(name,criterion,method,fit))
        save_progress()
        fit.converged || @warn "inference fixture fit not accepted" fixture=name criterion interval_method=method message=fit.message
        if name=="balanced_interior" && method==:profile
            profile_rows=[row for row in rows if row.fixture==name && row.criterion==criterion && row.interval_method==method]
            if length(profile_rows)!=4 || any(row->row.state!=:finite,profile_rows)
                save_progress(complete=false)
                println("INFERENCE_JULIA_CAPTURE_STOP_AFTER_BALANCED_PROFILE outer_fits=$outer_fits profile_calls=$profile_calls helper_base_fits=$helper_base_fit_attempts rows=$(length(rows)) states=$(join(string.([row.state for row in profile_rows]),","))")
                return nothing
            end
        end
    end
end
save_progress(complete=true)
println("INFERENCE_JULIA_CAPTURE_OK outer_fits=$outer_fits profile_calls=$profile_calls helper_base_fits=$helper_base_fit_attempts rows=$(length(rows))")
end
main()
