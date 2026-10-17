using Test, GroundTruth, Random, Statistics, LinearAlgebra

@testset "Explicit RI design and unchanged legacy draws" begin
    @test isdefined(GroundTruth, :ri_scenario)
    if isdefined(GroundTruth, :ri_scenario)
        sizes = [1, 3, 2]
        s = ri_scenario("unequal"; group_sizes=sizes, sigma=1.2, tau=.7)
        @test s isa Scenario
        @test (s.n, s.groups, s.family) == (6, 3, :random_intercept)
        @test s.group_sizes == sizes
        sizes[1] = 99
        @test s.group_sizes == [1, 3, 2]
        d = replay(s, 1)
        @test [count(==(g), d.group) for g in 1:3] == [1, 3, 2]
        @test d == replay(s, 1)
        rng = Xoshiro(seedfor(20261004, "unequal", 1, "data"))
        x = randn(rng, 6); u = .7 .* randn(rng, 3); noise = 1.2 .* randn(rng, 6)
        @test d.x == x
        @test d.y == 1 .+ .7 .* x .+ u[d.group] .+ noise
        for bad in (Int[], [3], [1, 1], [0, 3], [-1, 4], [1., 3.], [true, true])
            @test_throws ArgumentError ri_scenario("bad"; group_sizes=bad)
        end
        @test_throws ArgumentError ri_scenario("bad"; sigma=0.)
        @test_throws ArgumentError ri_scenario("bad"; tau=-1.)
    end
    for family in (:gaussian, :logistic, :random_intercept)
        s = Scenario("legacy-$family"; family, n=18, groups=4)
        d = replay(s, 2)
        rng = Xoshiro(seedfor(20261004, s.id, 2, "data"))
        x = randn(rng, 18); group = [mod1(i, 4) for i in 1:18]
        eta = s.alpha .+ s.beta .* x
        expected = if family == :random_intercept
            eta .+ (s.tau .* randn(rng, 4))[group] .+ s.sigma .* randn(rng, 18)
        elseif family == :logistic
            Float64.(rand(rng, 18) .< 1 ./ (1 .+ exp.(-eta)))
        else
            eta .+ s.sigma .* randn(rng, 18)
        end
        @test (d.x, d.y, d.group) == (x, expected, group)
    end
end

@testset "Named targets and compatible result construction" begin
    @test hasfield(FitResult, :diagnostics)
    if hasfield(FitResult, :diagnostics)
        p = Dict(:alpha=>1., :beta=>.7)
        ci = Dict(:alpha=>(0., 2.), :beta=>(0., 1.))
        @test FitResult(p, ci, true, "old").estimates == FitResult(p; intervals=ci).estimates
        @test isempty(FitResult(p).diagnostics)
        @test FitResult(p; diagnostics=(criterion=:ML,)).diagnostics.criterion == :ML
    end
    s = Scenario("targets"; family=:random_intercept, sigma=1.2, tau=.7)
    @test truth(s) == Dict(:alpha=>1., :beta=>.7, :sigma2=>1.44, :tau2=>.7^2)
    if isdefined(GroundTruth, :validate_targets)
        @test truth(s; targets=(:tau2,)) == Dict(:tau2=>.7^2)
        for targets in ((), (:alpha, :alpha), (:unknown,), ("alpha",))
            @test_throws ArgumentError truth(s; targets)
        end
        @test_throws ArgumentError truth(Scenario("ordinary"); targets=(:sigma2,))
    end
end

if hasfield(FitResult, :diagnostics) && isdefined(GroundTruth, :ri_scenario)
    @testset "RI target levels retain every attempt and point-only inference" begin
        s = ri_scenario("accounting"; group_sizes=[3, 3], sigma=1., tau=.5)
        counter = Ref(0)
        a = Adapter("four-attempts", (d, rng)->begin
            counter[] += 1
            counter[] == 4 && return FitResult(Dict(); converged=false, message="limit",
                                              diagnostics=(status=:limit,))
            points = Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25)
            intervals = counter[] == 3 ? Dict{Symbol,Tuple{Float64,Float64}}() :
                Dict(:alpha=>(counter[] == 1 ? (0., 2.) : (2., 3.)), :beta=>(0., 1.))
            FitResult(points; intervals, diagnostics=(intervals_by_level=Dict(.90=>intervals, .95=>intervals),))
        end)
        study = runstudy([s], [a]; reps=4)
        @test length(study.ledger) == 4
        @test length(study.rows) == 24
        @test study.provenance.targets[s.id] == (:alpha, :beta, :sigma2, :tau2)
        @test only(filter(r->r.rep==4, study.ledger)).diagnostics.status == :limit
        stats = summarize(study)
        for level in (.9, .95)
            row = only(filter(r->r.target==:alpha && isequal(r.level, level), stats))
            @test (row.attempted, row.successful, row.failed) == (4, 3, 1)
            @test (row.intervals_expected, row.usable_intervals, row.unusable_intervals) == (4, 2, 2)
            @test row.coverage == .5
            @test row.covered_per_attempt == .25
            @test row.bias == row.rmse == row.bias_mcse == row.rmse_mcse == 0.
        end
        for target in (:sigma2, :tau2)
            rows = filter(r->r.target==target, study.rows)
            @test length(rows) == 4
            @test all(r->ismissing(r.level) && !r.interval_expected && !r.usable_interval && ismissing(r.covered), rows)
            row = only(filter(r->r.target==target, stats))
            @test row.intervals_expected == row.usable_intervals == row.unusable_intervals == 0
            @test ismissing(row.coverage) && ismissing(row.covered_per_attempt)
        end
        subset = runstudy([s], [Adapter("points", (d,rng)->FitResult(
            Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25)))]; reps=1, targets=(:tau2,))
        @test length(subset.rows) == 1
        @test only(subset.ledger).status == :ok
        @test ismissing(only(summarize(subset)).bias_mcse)
        for values in (Dict(:alpha=>1., :beta=>.7, :sigma2=>-1., :tau2=>0.),
                       Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>-.1),
                       Dict(:alpha=>1., :beta=>.7, :sigma2=>0., :tau2=>0.),
                       Dict(:alpha=>1., :beta=>.7, :sigma2=>1.),
                       Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>0., :extra=>1.))
            requested = haskey(values, :tau2) ? (:alpha,) : (:tau2,)
            bad = runstudy([s], [Adapter("bad", (d,rng)->FitResult(values))]; reps=1, targets=requested)
            @test only(bad.ledger).status == :invalid_estimate
            @test all(r->ismissing(r.estimate), bad.rows)
        end
        for intervals in (Dict(:tau2=>(0., 1.)), Dict(:extra=>(0., 1.)))
            bad = runstudy([s], [Adapter("bad-interval", (d,rng)->FitResult(
                Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25); intervals))]; reps=1)
            @test only(bad.ledger).status == :invalid_estimate
        end
        failed = runstudy([s], [Adapter("failed", (d,rng)->error("forced"))]; reps=1)
        @test length(failed.rows) == 6
        @test all(r->r.successful==0 && ismissing(r.bias), summarize(failed))
        malformed = Adapter("malformed-level", (d,rng)->FitResult(
            Dict(:alpha=>1.,:beta=>.7,:sigma2=>1.,:tau2=>.25);
            intervals=Dict(:alpha=>(0.,2.),:beta=>(0.,1.)),
            diagnostics=(intervals_by_level=Dict(.9=>Dict(:alpha=>"bad",:beta=>(0.,1.))),)))
        kept = runstudy([s],[malformed];reps=1)
        @test only(kept.ledger).status == :ok
        @test !only(filter(r->r.target==:alpha && r.level==.9,kept.rows)).usable_interval
        @test only(filter(r->r.target==:beta && r.level==.9,kept.rows)).usable_interval
        @test all(!ismissing(r.estimate) for r in kept.rows)
        @test_throws ArgumentError runstudy([Scenario("ordinary"), s], [a]; targets=(:tau2,))
    end

    @testset "Ordinary shape preserved and mixed levels never fabricated" begin
        lm = Scenario("ordinary"; n=12)
        ri = ri_scenario("mixed-ri"; group_sizes=[3, 3])
        ordinary = Adapter("ordinary", (d,rng)->FitResult(Dict(:alpha=>1., :beta=>.7);
            intervals=Dict(:alpha=>(0., 2.), :beta=>(0., 1.))); metadata=(interval_level=.9,))
        old = runstudy([lm], [ordinary]; reps=1)
        @test keys(first(old.rows)) == (:scenario,:rep,:adapter,:target,:truth,:estimate,:lower,:upper,:usable_interval,:covered)
        @test keys(first(old.ledger)) == (:scenario,:rep,:adapter,:data_seed,:fit_seed,:status,:message,:seconds)
        @test keys(old.provenance) == (:julia,:seed,:reps,:rng,:scenarios,:adapters)
        @test !hasproperty(first(summarize(old)), :level)
        a = Adapter("mixed", (d,rng)-> d.family == :random_intercept ?
            FitResult(Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25)) : ordinary.fit(d,rng);
            metadata=(interval_level=.9,))
        study = runstudy([lm, ri], [a]; reps=1)
        ordinary_rows = filter(r->r.scenario==lm.id, study.rows)
        @test length(ordinary_rows) == 2
        @test all(r->r.level==.9 && r.interval_expected, ordinary_rows)
        @test length(summarize(study)) == 8
        selected = runstudy([ri], [Adapter("oracle", (d,rng)->oracle_gls(d,rng;sigma=ri.sigma,tau=ri.tau))];
                            reps=1, targets=(:alpha,:beta))
        @test only(selected.ledger).status == :ok
        @test all(!r.usable_interval for r in selected.rows if r.level==.9)
        @test all(r.usable_interval for r in selected.rows if r.level==.95)
        trace = [1,2]
        result = FitResult(Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25);
                           diagnostics=(trace=trace,))
        copied = runstudy([ri], [Adapter("copy", (d,rng)->result)]; reps=1)
        @test only(copied.ledger).diagnostics.trace == trace
        @test only(copied.ledger).diagnostics.trace !== trace
    end
end
