using Test, GroundTruth, Random, LinearAlgebra, Distributions, SHA

adapter_path = joinpath(@__DIR__, "..", "adapters", "lmm", "lmm_ml.jl")
include(adapter_path)
using .GroundTruthLMM: lmm_ml
function inference_fixture(name)
    path = joinpath(@__DIR__, "fixtures", "inference", name * ".csv")
    cells = [replace.(split(line, ','), "\"" => "") for line in readlines(path)[2:end]]
    (; x=parse.(Float64, getindex.(cells,1)), y=parse.(Float64, getindex.(cells,2)),
       group=getindex.(cells,3), family=:random_intercept)
end

@testset "Frozen inference fixtures are self-contained" begin
    fixture_dir = joinpath(@__DIR__, "fixtures", "inference")
    manifest_path = joinpath(fixture_dir, "manifest.json")
    @test isfile(manifest_path)
    manifest = read(manifest_path, String)
    for name in ("balanced_interior", "boundary_zero", "unbalanced_singleton",
                 "two_group_within_x", "two_group_group_x", "six_group_group_x",
                 "near_residual_collapse", "exact_residual_collapse", "rank_deficient",
                 "predictor_shift_rescale", "response_shift_rescale")
        @test isfile(joinpath(fixture_dir, name * ".csv"))
        @test occursin(name * ".csv", manifest)
    end
    entries = collect(eachmatch(r"\"file\": \"([^\"]+)\",\s*\"sha256\": \"([0-9a-f]{64})\"", manifest))
    @test length(entries) == 11
    for entry in entries
        file, expected = entry.captures
        @test bytes2hex(sha256(read(joinpath(fixture_dir, file)))) == expected
    end
end

@testset "Inference choices validate before any fit" begin
    d = (family=:random_intercept, x=[-1., 0., 1., -1., 0., 1.],
         y=[0., 1., 3., 1., 2., 2.], group=[1,1,1,2,2,2])
    @test_throws ArgumentError lmm_ml(d, nothing; criterion=:REML, interval_method=:profile)
    @test_throws ArgumentError lmm_ml(d, nothing; criterion=:OTHER)
    @test_throws ArgumentError lmm_ml(d, nothing; interval_method=:profiled)
    for deadline in (0., -1., Inf, NaN, true, "60")
        @test_throws ArgumentError lmm_ml(d, nothing; profile_timeout=deadline)
    end
end

@testset "ML and REML normal outputs declare their estimand" begin
    d = inference_fixture("balanced_interior")
    ml = lmm_ml(d, nothing)
    ml_explicit = lmm_ml(d, nothing; criterion=:ML, interval_method=:normal)
    reml = lmm_ml(d, nothing; criterion=:REML)
    @test ml.estimates == ml_explicit.estimates
    @test ml.intervals == ml_explicit.intervals
    @test ml.diagnostics.criterion == :ML
    @test reml.diagnostics.criterion == :REML
    @test reml.diagnostics.interval_method == :normal
    @test reml.diagnostics.objective_convention == :explicit_restricted_gaussian_nll
    @test reml.diagnostics.covariance ≈ begin
        X = hcat(ones(length(d.y)), d.x)
        V = reml.estimates[:sigma2] * Matrix{Float64}(I, length(d.y), length(d.y)) .+
            reml.estimates[:tau2] .* [a == b for a in d.group, b in d.group]
        inv(Symmetric(X' * (V \ X)))
    end rtol=1e-8
    V = reml.estimates[:sigma2] * Matrix{Float64}(I, length(d.y), length(d.y)) .+
        reml.estimates[:tau2] .* [a == b for a in d.group, b in d.group]
    X = hcat(ones(length(d.y)), d.x)
    C = reml.diagnostics.covariance
    residual = d.y - X * [reml.estimates[:alpha],reml.estimates[:beta]]
    nll = ((length(d.y)-2)*log(2pi) + logdet(Symmetric(V)) +
           logdet(Symmetric(X'*(V\X))) + dot(residual,V\residual))/2
    @test reml.diagnostics.objective ≈ nll rtol=1e-8
    for level in (.90,.95), (target,column) in ((:alpha,1),(:beta,2))
        q=quantile(Normal(),(1+level)/2)
        endpoints=reml.diagnostics.intervals_by_level[level][target]
        @test endpoints[1] ≈ reml.estimates[target]-q*sqrt(C[column,column]) rtol=1e-8
        @test endpoints[2] ≈ reml.estimates[target]+q*sqrt(C[column,column]) rtol=1e-8
    end
    @test Set(keys(reml.diagnostics.intervals_by_level)) == Set((.90, .95))
end

@testset "Profile output keeps the accepted point snapshot and typed states" begin
    d = inference_fixture("balanced_interior")
    normal = lmm_ml(d, nothing)
    profiled = lmm_ml(d, nothing; interval_method=:profile, profile_timeout=60.)
    @test profiled.estimates == normal.estimates
    @test profiled.diagnostics.objective == normal.diagnostics.objective
    @test profiled.diagnostics.interval_method == :profile
    @test profiled.diagnostics.profile_elapsed >= 0
    @test profiled.diagnostics.profile_timeout == 60.
    @test Set(keys(profiled.diagnostics.inference_status)) == Set(((:alpha,.90),(:alpha,.95),(:beta,.90),(:beta,.95)))
    @test all(s -> s in (:finite,:unbounded,:incomplete,:error,:timeout,:invalid), values(profiled.diagnostics.inference_status))
    for (key, state) in profiled.diagnostics.inference_status
        if state == :finite
            lo, hi = profiled.diagnostics.intervals_by_level[key[2]][key[1]]
            @test isfinite(lo) && isfinite(hi) && lo < hi
            @test abs(profiled.diagnostics.profile_residuals[key]) <= .02
        else
            @test !haskey(profiled.diagnostics.intervals_by_level[key[2]], key[1])
        end
    end
end

@testset "Group-constant x with two groups is documented as REML information-limited" begin
    d = inference_fixture("two_group_group_x")
    @test GroundTruthLMM.information_limit(d).reml_tau2_identified == false
    @test occursin("zero residual group-mean degrees of freedom", GroundTruthLMM.information_limit(d).message)
end
