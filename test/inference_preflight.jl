using Test, LinearAlgebra, SHA

# Evaluate only the adapter's pure preflight definitions. This intentionally
# avoids loading MixedModels while checking rejects that must happen before fit.
module InferencePreflightProbe
using LinearAlgebra

function load_preflight!(path)
    parsed = Meta.parseall(read(path, String))
    names = Set((:reject_residual_collapse, :checked_data, :information_limit, :lmm_ml,
                 :empty_profile_result, :apply_profile_payload!, :configure_optimizer_precision!))
    found = Set{Symbol}()
    constants = Set{Symbol}()
    function function_name(definition)
        definition isa Expr && definition.head == :function || return nothing
        signature = definition.args[1]
        signature isa Expr && signature.head == :call || return nothing
        name = signature.args[1]
        name isa Symbol ? name : nothing
    end
    function collect_definitions(node)
        node isa Expr || return
        if node.head == :const
            assignment = only(node.args)
            if assignment isa Expr && assignment.head == :(=) && assignment.args[1] == :INTERVAL_LEVELS
                Core.eval(@__MODULE__, node)
                push!(constants, :INTERVAL_LEVELS)
            end
        elseif node.head == :function
            name = function_name(node)
            if name in names
                Core.eval(@__MODULE__, node)
                push!(found, name)
            end
        else
            foreach(collect_definitions, node.args)
        end
    end
    collect_definitions(parsed)
    required = setdiff(names, Set((:configure_optimizer_precision!,)))
    required <= found || error("adapter preflight definitions missing: $(setdiff(required, found))")
    constants == Set((:INTERVAL_LEVELS,)) || error("adapter profile constants missing")
    nothing
end
end

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures", "inference")
InferencePreflightProbe.load_preflight!(joinpath(@__DIR__, "..", "adapters", "lmm", "lmm_ml.jl"))

function preflight_fixture(name)
    rows = [replace.(split(line, ','), '"' => "") for line in readlines(joinpath(FIXTURE_DIR, name * ".csv"))[2:end]]
    (; x=parse.(Float64, getindex.(rows, 1)), y=parse.(Float64, getindex.(rows, 2)),
       group=getindex.(rows, 3), family=:random_intercept)
end

@testset "Inference preflight is engine-free and fixtures are pinned" begin
    manifest = read(joinpath(FIXTURE_DIR, "manifest.json"), String)
    entries = collect(eachmatch(r"\"file\": \"([^\"]+)\",\s*\"sha256\": \"([0-9a-f]{64})\"", manifest))
    @test length(entries) == 11
    for entry in entries
        file, expected = entry.captures
        @test bytes2hex(sha256(read(joinpath(FIXTURE_DIR, file)))) == expected
    end

    @test_throws ArgumentError InferencePreflightProbe.checked_data(preflight_fixture("exact_residual_collapse"))
    @test_throws ArgumentError InferencePreflightProbe.checked_data(preflight_fixture("rank_deficient"))
    limited = InferencePreflightProbe.information_limit(preflight_fixture("two_group_group_x"))
    @test !limited.reml_tau2_identified
    @test occursin("zero residual group-mean degrees of freedom", limited.message)

    valid = preflight_fixture("balanced_interior")
    @test_throws ArgumentError InferencePreflightProbe.lmm_ml(valid, nothing; criterion=:OTHER)
    @test_throws ArgumentError InferencePreflightProbe.lmm_ml(valid, nothing; criterion=:REML, interval_method=:profile)
    for deadline in (0., -1., Inf, NaN, true, "60")
        @test_throws ArgumentError InferencePreflightProbe.lmm_ml(valid, nothing; profile_timeout=deadline)
    end

    partial = InferencePreflightProbe.empty_profile_result()
    key = (:alpha, .90)
    @test ismissing(partial.profile_residuals[key])
    partial.profile_residuals[key] = .01
    @test partial.profile_residuals[key] == .01
end

@testset "Profile accumulators retain finite diagnostics after missing defaults" begin
    result=InferencePreflightProbe.empty_profile_result()
    result.profile_residuals[(:alpha,.95)]=.003
    result.profile_endpoint_distances[(:alpha,.95)]=.004
    @test result.profile_residuals[(:alpha,.95)] == .003
    @test result.profile_endpoint_distances[(:alpha,.95)] == .004
    @test ismissing(result.profile_residuals[(:beta,.9)])
end

@testset "Actual helper collector preserves completed pairs at timeout" begin
    r=InferencePreflightProbe.empty_profile_result();k=(:alpha,.9)
    payload=(processed=[k],inference_status=Dict(k=>:finite),profile_message=Dict(k=>""),
             intervals=Dict(k=>(.2,1.2)),profile_residuals=Dict(k=>.003))
    InferencePreflightProbe.apply_profile_payload!(r,:timeout,"deadline",payload)
    @test r.inference_status[k] == :finite
    @test r.intervals_by_level[.9][:alpha] == (.2,1.2)
    @test r.profile_residuals[k] == .003
    @test r.inference_status[(:beta,.95)] == :timeout
end

# Same mutable control interface as native OptSummary, without loading an engine.
Base.@kwdef mutable struct PrecisionControlProbe
    maxfeval::Int = 10_000
    ftol_rel::Float64 = 1e-12
    ftol_abs::Float64 = 1e-8
    xtol_rel::Float64 = .13
    xtol_abs::Vector{Float64} = [.17]
    maxtime::Float64 = 7.0
    initial_step::Vector{Float64} = [.23]
    lowerbd::Vector{Float64} = [.29]
    xtol_zero_abs::Float64 = .31
    ftol_zero_abs::Float64 = .37
    backend::Symbol = :sentinel_backend
    optimizer::Symbol = :sentinel_optimizer
    rhobeg::Float64 = .41
    rhoend::Float64 = .43
    nAGQ::Int = 3
    REML::Bool = true
    sigma::Union{Nothing,Float64} = 1.7
end

@testset "Actual precision policy changes only objective stopping controls" begin
    available = isdefined(InferencePreflightProbe, :configure_optimizer_precision!)
    @test available
    if available
        for maxfeval in (10_000, 137)
            controls = PrecisionControlProbe(;maxfeval,ftol_rel=.47)
            before = deepcopy(controls)
            returned = InferencePreflightProbe.configure_optimizer_precision!(controls)
            @test returned === controls
            @test controls.ftol_rel == controls.ftol_abs == 1e-12
            for field in fieldnames(PrecisionControlProbe)
                field in (:ftol_rel,:ftol_abs) && continue
                @test getproperty(controls,field) == getproperty(before,field)
            end
            # Reapplying the shared policy must preserve the caller's limit too.
            @test InferencePreflightProbe.configure_optimizer_precision!(controls) === controls
            @test controls.maxfeval == maxfeval
        end
    end
end
