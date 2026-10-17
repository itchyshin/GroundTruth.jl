using Test
isdefined(Main,:GroundTruth) || @eval using GroundTruth
@test isdefined(GroundTruth,:compare_inference)
if isdefined(GroundTruth,:compare_inference)
    make(id,u,c)=[(scenario="control",rep=i,adapter=id,target=:alpha,level=.95,truth=0.,
        estimate=i==4 ? missing : 0.,lower=u[i] ? (c[i] ? -1. : 1.) : missing,
        upper=u[i] ? (c[i] ? 1. : 2.) : missing,usable_interval=u[i],
        covered=u[i] ? c[i] : missing,interval_expected=true) for i in 1:4]
    a=make("a",[true,true,false,false],[true,false,false,false])
    b=make("b",[true,false,true,false],[true,false,true,false])
    s=(rows=vcat(a,b),)
    z=only(GroundTruth.compare_inference(s;baseline="a",comparison="b"))
    @test z.attempted==4 && z.baseline_usable==2 && z.comparison_usable==2
    @test z.coverage_difference==.5 && z.finite_yield_difference==.25
    @test z.finite_yield_difference_mcse≈.25 atol=1e-12
    @test z.coverage_difference_mcse≈sqrt(2/3)/2 atol=1e-12
    @test_throws ArgumentError GroundTruth.compare_inference((rows=vcat(a,b,b[1:1]),);baseline="a",comparison="b")
    @test_throws ArgumentError GroundTruth.compare_inference((rows=vcat(a,b[2:end]),);baseline="a",comparison="b")
    @test isequal(only(GroundTruth.compare_inference((rows=s.rows[[8,1,6,3,5,2,4,7]],);baseline="a",comparison="b")),z)
    @test_throws ArgumentError GroundTruth.compare_inference((rows=[r for r in s.rows if r.rep!=4],reps=4,);baseline="a",comparison="b")
    @test z.baseline_finite_hits==1 && z.comparison_finite_hits==2
    @test z.baseline_state_unknown==4 && !z.schedule_verified
    @test isempty(GroundTruth.inference_details(s))
    println("INFERENCE_ACCOUNTING_OK")
end
