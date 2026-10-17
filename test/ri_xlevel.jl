using Test, GroundTruth, Random, LinearAlgebra, SHA

# Mode selection lets the verifier exercise bounded contracts independently.
const RI_XLEVEL_MODE = get(ENV, "RI_XLEVEL_MODE", "all")
xlevel_mode(modes...) = RI_XLEVEL_MODE == "all" || RI_XLEVEL_MODE in modes

if xlevel_mode("red")
    @testset "Both RI public constructors accept x_level" begin
        convenience = try
            ri_scenario("xlevel-red"; group_sizes=[2, 3], x_level=:group)
        catch err
            err
        end
        generic = try
            Scenario("xlevel-red"; family=:random_intercept, n=5, groups=2,
                     group_sizes=[2, 3], x_level=:group)
        catch err
            err
        end
        @test convenience isa Scenario
        @test generic isa Scenario
        if convenience isa Exception
            println("RI_XLEVEL_RED_CONVENIENCE: ", sprint(showerror, convenience))
        end
        if generic isa Exception
            println("RI_XLEVEL_RED_GENERIC: ", sprint(showerror, generic))
        end
    end
end

if xlevel_mode("implementation")
    @testset "RI predictor design metadata and validation" begin
        default = ri_scenario("metadata"; group_sizes=[1, 3, 2])
        explicit = ri_scenario("metadata"; group_sizes=[1, 3, 2], x_level=:observation)
        grouped = ri_scenario("metadata"; group_sizes=[1, 3, 2], x_level=:group)
        generic = Scenario("metadata"; family=:random_intercept, n=6, groups=3,
                           group_sizes=[1, 3, 2], x_level=:group, sigma=1., tau=.5)
        @test default.x_level == explicit.x_level == :observation
        @test grouped.x_level == generic.x_level == :group
        @test grouped.generator_revision == generic.generator_revision == "random-intercept-v2"
        @test default.generator_revision == "random-intercept-v2"
        @test replay(default, 2) == replay(explicit, 2)
        @test replay(grouped, 2) == replay(generic, 2)
        for bad in (:unknown, "group", nothing, true)
            @test_throws ArgumentError ri_scenario("bad"; x_level=bad)
            @test_throws ArgumentError Scenario("bad"; family=:random_intercept, x_level=bad)
        end
        for family in (:gaussian, :logistic)
            @test Scenario("ordinary"; family).x_level == :observation
            @test Scenario("ordinary"; family).generator_revision === nothing
            @test_throws ArgumentError Scenario("ordinary"; family, x_level=:group)
        end
        # Capture actual adapter inputs without fitting: truth and design metadata
        # belong to the scenario/provenance, not the family data contract.
        inputs = NamedTuple[]
        adapter = Adapter("capture", (d,rng)->begin
            push!(inputs, deepcopy(d))
            FitResult(Dict(:alpha=>1., :beta=>.7, :sigma2=>1., :tau2=>.25))
        end)
        study = runstudy([grouped], [adapter]; reps=2)
        @test study.provenance.generator_revision == "random-intercept-v2"
        @test only(study.provenance.scenarios).x_level == :group
        @test only(study.provenance.scenarios).generator_revision == "random-intercept-v2"
        @test study.provenance.rng == "Xoshiro; SHA256 first 64 bits; algorithm v1"
        @test all(keys(d) == (:x, :y, :group, :family) for d in inputs)
        @test inputs == [replay(grouped, rep) for rep in 1:2]
        @test length(study.ledger) == 2 && length(study.rows) == 12
        @test [r.data_seed for r in study.ledger] == [seedfor(20261004, grouped.id, rep, "data") for rep in 1:2]
        @test [r.fit_seed for r in study.ledger] == [seedfor(20261004, grouped.id, rep, "fit:capture") for rep in 1:2]
        ordinary = runstudy([Scenario("ordinary")], [adapter]; reps=1)
        @test keys(ordinary.provenance) == (:julia,:seed,:reps,:rng,:scenarios,:adapters)
    end
end

if xlevel_mode("design-controls")
    @testset "Canonical group draws, response, and replay controls" begin
        for (id, sizes) in (("xlevel-unequal", [1, 3, 2]),
                            ("xlevel-two", [2, 3]),
                            ("xlevel-cell", fill(6, 20)))
            s = ri_scenario(id; group_sizes=sizes, alpha=-.2, beta=1.3,
                            sigma=1.2, tau=.7, x_level=:group)
            rng = Xoshiro(seedfor(20261004, id, 1, "data"))
            group_x = randn(rng, length(sizes))
            u = .7 .* randn(rng, length(sizes))
            noise = 1.2 .* randn(rng, sum(sizes))
            groups = reduce(vcat, [fill(g, count) for (g, count) in enumerate(sizes)])
            expanded_x = group_x[groups]
            d = replay(s, 1)
            @test d.group == groups
            @test d.x == expanded_x
            @test all(length(unique(d.x[d.group .== g])) == 1 for g in eachindex(sizes))
            @test d.y == -.2 .+ 1.3 .* expanded_x .+ u[groups] .+ noise
            @test d == replay(s, 1)
            @test d != replay(s, 2)
            @test generate(s, Xoshiro(seedfor(20261004, id, 1, "data"))) == d
            # Fixed acceptance seeds prove nonconstant rank without resampling.
            # Two groups give the minimum full-rank between-group design only;
            # they do not certify useful variance or coverage information.
            @test maximum(group_x) > minimum(group_x)
            @test rank(hcat(ones(length(group_x)), group_x)) == 2
            @test rank(hcat(ones(s.n), d.x)) == 2
            @test !(group_x == u) && !(d.x == noise)
            @test truth(s) == Dict(:alpha=>-.2, :beta=>1.3, :sigma2=>1.2^2, :tau2=>.7^2)
        end
        # The generic constructor retains its legacy interleaved group order.
        s = Scenario("xlevel-interleaved"; family=:random_intercept, n=11,
                     groups=3, x_level=:group)
        rng = Xoshiro(seedfor(20261004, s.id, 1, "data"))
        group_x = randn(rng, 3)
        d = replay(s, 1)
        @test d.group == [mod1(i, 3) for i in 1:11]
        @test d.x == group_x[d.group]
        @test d == replay(s, 1)
    end
end

if xlevel_mode("compatibility")
    @testset "Frozen default CSV bytes and seed keys" begin
        cases = ((ri_scenario("xlevel-golden"; group_sizes=[1,3,2], sigma=1.2, tau=.7),
                  "9fa88f83d7db6e0d746a442c831a3dd3a29e32962ea1f3436aa19036abe35684", UInt64(5195133493828447952)),
                 (Scenario("xlevel-legacy"; family=:random_intercept, n=18, groups=4),
                  "186d38da8384b041b00367d19ebb6d12a3d39361e28181358cf62d93e6afdf9c", UInt64(10767785294830203573)))
        for (s, digest, seed) in cases
            d = replay(s, 2)
            mktempdir() do dir
                path = export_data(joinpath(dir, "default.csv"), d)
                @test bytes2hex(sha256(read(path))) == digest
                @test first(readlines(path)) == "x,y,group"
            end
            @test seedfor(20261004, s.id, 2, "data") == seed
            rng = Xoshiro(seed)
            x = randn(rng, s.n)
            u = s.tau .* randn(rng, s.groups)
            noise = s.sigma .* randn(rng, s.n)
            @test d.x == x
            @test d.y == s.alpha .+ s.beta .* x .+ u[d.group] .+ noise
            @test d == replay(s, 2)
        end
    end
end
