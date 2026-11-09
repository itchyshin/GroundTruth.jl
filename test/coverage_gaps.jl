using Test, GroundTruth, Random, LinearAlgebra

@testset "Random-intercept interval scope and estimate validation" begin
    s = ri_scenario("scope"; group_sizes=[3, 3])
    for (label, diagnostics) in (
        ("non-dict levels", (intervals_by_level=42,)),
        ("invalid level", (intervals_by_level=Dict(.80 => Dict(:alpha=>(0.0, 2.0))),)),
        ("extra interval target", (intervals_by_level=Dict(.90 => Dict(:tau2 => (0.0, 1.0))),)),
    )
        bad = runstudy(
            [s],
            [Adapter(label, (d, rng) -> FitResult(
                Dict(:alpha => 1.0, :beta => 0.7, :sigma2 => 1.0, :tau2 => 0.25);
                intervals=Dict(:alpha => (0.0, 2.0), :beta => (0.0, 1.0)),
                diagnostics=diagnostics,
            ))];
            reps=1,
        )
        @test only(bad.ledger).status == :invalid_estimate
        @test occursin("unexpected interval", only(bad.ledger).message)
    end
    extra = runstudy(
        [s],
        [Adapter("extra-target", (d, rng) -> FitResult(
            Dict(:alpha => 1.0, :beta => 0.7, :sigma2 => 1.0, :tau2 => 0.25, :extra => 1.0),
        ))];
        reps=1,
    )
    @test only(extra.ledger).status == :invalid_estimate
    @test occursin("invalid random-intercept target", only(extra.ledger).message)
end
