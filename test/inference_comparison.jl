using Test
isdefined(Main, :GroundTruth) || @eval using GroundTruth

@test isdefined(GroundTruth, :compare_inference)
if isdefined(GroundTruth, :compare_inference)
    make(id, u, c) = [(scenario="control", rep=i, adapter=id, target=:alpha, level=.95, truth=0.0,
        estimate=i == 4 ? missing : 0.0, lower=u[i] ? (c[i] ? -1.0 : 1.0) : missing,
        upper=u[i] ? (c[i] ? 1.0 : 2.0) : missing, usable_interval=u[i],
        covered=u[i] ? c[i] : missing, interval_expected=true) for i in 1:4]
    a = make("a", [true, true, false, false], [true, false, false, false])
    b = make("b", [true, false, true, false], [true, false, true, false])
    s = (rows=vcat(a, b),)
    z = only(GroundTruth.compare_inference(s; baseline="a", comparison="b"))
    @test z.attempted == 4 && z.baseline_usable == 2 && z.comparison_usable == 2
    @test z.coverage_difference == 0.5 && z.finite_yield_difference == 0.25
    @test z.finite_yield_difference_mcse ≈ 0.25 atol=1e-12
    @test z.coverage_difference_mcse ≈ sqrt(2 / 3) / 2 atol=1e-12
    @test_throws ArgumentError GroundTruth.compare_inference((rows=vcat(a, b, b[1:1]),); baseline="a", comparison="b")
    @test_throws ArgumentError GroundTruth.compare_inference((rows=vcat(a, b[2:end]),); baseline="a", comparison="b")
    @test isequal(
        only(GroundTruth.compare_inference((rows=s.rows[[8, 1, 6, 3, 5, 2, 4, 7]],); baseline="a", comparison="b")),
        z,
    )
    @test_throws ArgumentError GroundTruth.compare_inference((
        rows=[r for r in s.rows if r.rep != 4],
        reps=4,
    ); baseline="a", comparison="b")
    @test z.baseline_finite_hits == 1 && z.comparison_finite_hits == 2
    @test z.baseline_state_unknown == 4 && !z.schedule_verified
    @test isempty(GroundTruth.inference_details(s))

    detail_row = (
        scenario="control", rep=1, adapter="a", target=:alpha, level=.95, state=:finite,
        criterion=:ML, interval_method=:normal, lower=-1.0, upper=1.0,
        root_lr_residual=0.01, endpoint_distance=0.02, elapsed_seconds=1.5, message="",
    )
    from_field = (inference_details=[detail_row],)
    @test only(GroundTruth.inference_details(from_field)) == detail_row

    ledger_row = (
        scenario="control", rep=1, adapter="profile",
        diagnostics=(
            inference_status=Dict((:beta, .90) => :timeout, (:alpha, .95) => :finite),
            intervals_by_level=Dict(.90 => Dict(), .95 => Dict(:alpha => (-0.5, 0.5))),
            criterion=:REML,
            interval_method=:profile,
            profile_residuals=Dict((:alpha, .95) => 0.003),
            profile_endpoint_distances=Dict((:alpha, .95) => 0.004),
            profile_elapsed_seconds=2.5,
            inference_messages=Dict((:alpha, .95) => "ok"),
        ),
    )
    from_ledger = GroundTruth.inference_details((ledger=[ledger_row],))
    @test length(from_ledger) == 2
    # Profile timeout rows omit interval bounds from statuses without a mapped level cell.
    timeout = only(filter(r -> r.state == :timeout, from_ledger))
    @test timeout.target == :beta && timeout.level == .90
    finite = only(filter(r -> r.state == :finite, from_ledger))
    @test (finite.lower, finite.upper) == (-0.5, 0.5)
    @test finite.root_lr_residual ≈ 0.003
    @test finite.interval_method == :profile

    dup = (
        inference_details=[
            detail_row,
            merge(detail_row, (message="duplicate",)),
        ],
    )
    @test_throws ArgumentError GroundTruth.inference_details(dup)
    bad_state = (inference_details=[merge(detail_row, (state=:bogus,))],)
    @test_throws ArgumentError GroundTruth.inference_details(bad_state)

    ledger = vcat(
        [(scenario="control", rep=i, adapter=id) for i in 1:4 for id in ("a", "b")],
    )
    scheduled = (rows=s.rows, reps=4, ledger=ledger)
    verified = only(GroundTruth.compare_inference(scheduled; baseline="a", comparison="b"))
    @test verified.schedule_verified

    provenance = (rows=s.rows, provenance=(reps=4,), ledger=ledger)
    @test only(GroundTruth.compare_inference(provenance; baseline="a", comparison="b")).schedule_verified

    bad_ledger = (
        rows=s.rows,
        reps=4,
        ledger=[(scenario="control", rep=i, adapter="a") for i in 1:4],
    )
    @test_throws ArgumentError GroundTruth.compare_inference(bad_ledger; baseline="a", comparison="b")

    profile_rows = [
        (
            scenario=r.scenario, rep=r.rep, adapter="profiled", target=r.target, level=r.level,
            truth=r.truth, estimate=r.usable_interval ? 0.0 : missing,
            lower=r.usable_interval ? -2.0 : missing, upper=r.usable_interval ? 2.0 : missing,
            usable_interval=r.usable_interval,
            covered=r.usable_interval ? true : missing, interval_expected=true,
        )
        for r in b
    ]
    profile_details = [
        (
            scenario="control", rep=r.rep, adapter="profiled", target=:alpha, level=.95,
            state=r.usable_interval ? :finite : :timeout,
            criterion=:ML, interval_method=:profile,
            lower=r.usable_interval ? -2.0 : missing, upper=r.usable_interval ? 2.0 : missing,
            root_lr_residual=r.usable_interval ? 0.003 : missing,
            endpoint_distance=missing, elapsed_seconds=missing,
            message=r.usable_interval ? "" : "deadline",
        )
        for r in b
    ]
    profile_ledger = vcat(
        [(scenario="control", rep=i, adapter=id) for i in 1:4 for id in ("a", "profiled")],
    )
    stateful = (rows=vcat(a, profile_rows), inference_details=profile_details, reps=4, ledger=profile_ledger)
    stateful_result = only(GroundTruth.compare_inference(stateful; baseline="a", comparison="profiled"))
    @test stateful_result.comparison_state_finite == 2
    @test stateful_result.comparison_state_timeout == 2
    @test stateful_result.baseline_state_unknown == 4

    inconsistent = [i == 1 ? merge(a[i], (covered=false,)) : a[i] for i in eachindex(a)]
    @test_throws ArgumentError GroundTruth.compare_inference((
        rows=vcat(inconsistent, b),
    ); baseline="a", comparison="b")

    disagree = [i == 1 ? merge(a[i], (usable_interval=false,)) : a[i] for i in eachindex(a)]
    disagree_details = [
        (scenario="control", rep=1, adapter="a", target=:alpha, level=.95, state=:finite,
            criterion=:ML, interval_method=:normal, lower=-1.0, upper=1.0,
            root_lr_residual=missing, endpoint_distance=missing, elapsed_seconds=missing, message="")
    ]
    @test_throws ArgumentError GroundTruth.compare_inference((
        rows=vcat(disagree, b),
        inference_details=disagree_details,
    ); baseline="a", comparison="b")

    println("INFERENCE_ACCOUNTING_OK")
end
