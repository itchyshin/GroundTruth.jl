using Test
include(joinpath(@__DIR__, "..", "adapters", "lmm", "inference_profile_protocol.jl"))
using .GroundTruthInferenceProfileProtocol

@testset "Native profile protocol preserves completed work and failure detail" begin
    @test profile_beta_index(:β1) == 1
    @test profile_beta_index(:β02) == 2
    @test profile_beta_index(:sigma1) === nothing
    @test profile_brackets(-2.1,2.1,1.96)
    @test !profile_brackets(-1.8,2.1,1.96) # enough for 90%, not the required 95%
    @test !profile_brackets(-2.1,Inf,1.96)

    states=Dict(:alpha=>:finite)
    processed=Set([:alpha])
    published=Ref{Any}(nothing)
    result=run_profile_attempt(() -> begin
        states[:beta]=:incomplete
        push!(processed,:beta)
        error("synthetic native failure")
    end, completion -> begin
        published[]=(completion,copy(states),copy(processed))
    end)
    @test result.status == :error
    @test result.message == "synthetic native failure"
    @test published[][1].status == :error
    @test published[][1].message == "synthetic native failure"
    @test published[][2] == Dict(:alpha=>:finite,:beta=>:incomplete)
    @test published[][3] == Set((:alpha,:beta))

    mismatch=run_profile_attempt(() -> error("POINT_MISMATCH: changed point"), _ -> nothing)
    @test mismatch.status == :invalid
    @test mismatch.message == "POINT_MISMATCH: changed point"
end

@testset "Helper accepts a tuple of estimate pairs" begin
    helper=read(joinpath(@__DIR__, "..", "adapters", "lmm", "inference_profile_helper.jl"),String)
    population=match(r"    for \(target,value\) in .*?\n    end"s,helper)
    @test population !== nothing
    mock=Module(:HelperEstimatePopulation)
    Core.eval(mock, :(begin
        estimates=Dict{Symbol,Float64}(); beta=[1.2,.7]; names=["(Intercept)","x"];group_sd=.5
        MixedModels=(sdest=x->.4,)
        model=nothing
    end))
    Core.eval(mock,Meta.parse(population.match))
    @test Core.eval(mock,:estimates)==Dict(:alpha=>1.2,:beta=>.7,:sigma2=>.4^2,:tau2=>.5^2)
end
