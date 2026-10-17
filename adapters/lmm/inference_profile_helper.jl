using Serialization, LinearAlgebra, Distributions, Logging, MixedModels
BLAS.set_num_threads(1)
include(joinpath(@__DIR__, "lmm_ml.jl"))
include(joinpath(@__DIR__, "inference_profile_protocol.jl"))
using .GroundTruthInferenceProfileProtocol: profile_beta_index, profile_brackets, run_profile_attempt

const ACCEPTED = (:SUCCESS, :STOPVAL_REACHED, :FTOL_REACHED, :XTOL_REACHED)
const PROFILE_KEYS = [(target,level) for target in (:alpha,:beta) for level in (.90,.95)]
function reply(path, value)
    tmp=string(path,".",getpid(),".tmp")
    open(tmp, "w") do io
        serialize(io, value)
    end
    mv(tmp,path;force=true)
end
function payload(status,message,estimates,intervals,residuals,states,messages,processed)
    (;status,message,estimates,intervals,profile_residuals=residuals,
      inference_status=states,profile_message=messages,processed=collect(processed))
end

function main(input_path, output_path)
estimates=Dict{Symbol,Float64}()
intervals=Dict{Tuple{Symbol,Float64},Tuple{Float64,Float64}}()
residuals=Dict{Tuple{Symbol,Float64},Float64}()
states=Dict(key=>:incomplete for key in PROFILE_KEYS)
messages=Dict(key=>"profile helper has not reached this endpoint" for key in PROFILE_KEYS)
processed=Set{Tuple{Symbol,Float64}}()
run_profile_attempt(() -> begin
    data = open(deserialize, input_path)
    expected=data.expected
    table = GroundTruthLMM.checked_data(merge(data, (family=:random_intercept,)))
    model = MixedModels.MixedModel(GroundTruthLMM.LMM_FORMULA, table;
        contrasts=Dict(:group=>MixedModels.Grouping()))
    model.optsum.maxfeval=data.maxfeval
    GroundTruthLMM.configure_optimizer_precision!(model.optsum)
    with_logger(NullLogger()) do
        MixedModels.fit!(model; REML=false, progress=false)
    end
    model.optsum.returnvalue in ACCEPTED || error("profile helper base fit not accepted: $(model.optsum.returnvalue)")
    names = MixedModels.fixefnames(model)
    beta = MixedModels.fixef(model)
    components = MixedModels.VarCorr(model).σρ
    group_sd = only(values(only(values(components)).σ))
    # Pair iterables are not AbstractDict arguments to merge! in Julia 1.12.
    for (target,value) in (:alpha=>beta[only(findall(==("(Intercept)"),names))],
                           :beta=>beta[only(findall(==("x"),names))],
                           :sigma2=>MixedModels.sdest(model)^2, :tau2=>group_sd^2)
        estimates[target]=value
    end
    close_enough=target->isfinite(estimates[target]) &&
        abs(estimates[target]-expected[target]) <= (target in (:alpha,:beta) ? 1e-6 : 1e-5)*(1+abs(expected[target]))
    all(close_enough,keys(estimates)) || error("POINT_MISMATCH: isolated profile helper point fit did not reproduce accepted base estimates")
    profile = MixedModels.profile(model; threshold=4)
    curve_keys=keys(profile.rev)
    # The frozen contract requires evidence at the 95% cutoff even when a
    # particular reported interval is 90%; both levels come from this one curve.
    required_cutoff=quantile(Normal(),.975)
    for target in (:alpha,:beta), level in (.90,.95)
        key=(target,level)
        try
            coefficient_name=target==:alpha ? "(Intercept)" : "x"
            coefficient_index=only(findall(==(coefficient_name),names))
            sym=only(filter(k->profile_beta_index(k)==coefficient_index,curve_keys))
            cutoff=quantile(Normal(),(1+level)/2)
            curve=profile.rev[sym]
            if !profile_brackets(first(curve.x),last(curve.x),required_cutoff)
                states[key]=:incomplete
                messages[key]="native profile did not bracket both signed root-LR cutoffs"
            else
                lower=curve(-cutoff); upper=curve(cutoff)
                if !(isfinite(lower) && isfinite(upper) && lower<upper)
                    states[key]=:incomplete
                    messages[key]="native profile returned missing, nonfinite, or unordered endpoints"
                else
                    lower_residual=abs(profile.fwd[sym](lower)+cutoff)
                    upper_residual=abs(profile.fwd[sym](upper)-cutoff)
                    residual=max(lower_residual,upper_residual)
                    if !isfinite(residual) || residual>.02
                        states[key]=:invalid
                        messages[key]="native profile endpoint root-LR residual exceeded 0.02"
                    else
                        intervals[key]=(lower,upper)
                        residuals[key]=residual
                        states[key]=:finite
                        messages[key]=""
                    end
                end
            end
        catch endpoint_error
            endpoint_error isa InterruptException && rethrow()
            states[key]=:error
            messages[key]=sprint(showerror,endpoint_error)
        end
        push!(processed,key)
        reply(output_path,payload(:running,"profile endpoints being validated",estimates,
            intervals,residuals,states,messages,processed))
    end
    nothing
end, completion -> reply(output_path,payload(completion.status,completion.message,
    estimates,intervals,residuals,states,messages,processed)))
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("profile helper expects serialized input and output paths")
    main(ARGS[1],ARGS[2])
end
