using Test, GroundTruth, Random, Statistics, LinearAlgebra, Distributions

@testset "Gaussian contract and replay" begin
    s=Scenario("lm";n=40,alpha=1.,beta=.7,sigma=1.2)
    d=replay(s,1)
    @test d==replay(s,1)
    @test d!=replay(s,2)
    @test seedfor(1,"a",1,"data")!=seedfor(1,"a",1,"fit:ols")
    @test seedfor(1,"a",1,"fit:a")!=seedfor(1,"a",1,"fit:b")
    @test truth(s)==Dict(:alpha=>1.,:beta=>.7)
    @test_throws ArgumentError Scenario("bad";n=2)
    @test_throws ArgumentError Scenario("bad";sigma=NaN)
    rng=Xoshiro(seedfor(20261004,"lm",1,"data"))
    x=randn(rng,40); noise=randn(rng,40)
    @test d.x==x
    @test d.y==1 .+ 0.7 .* x .+ 1.2 .* noise
    # Independent scalar formulas for two-coefficient ordinary least squares.
    fit=ols(d,Xoshiro(1)); beta=cov(d.x,d.y)/var(d.x)
    alpha=mean(d.y)-beta*mean(d.x)
    @test fit.estimates[:beta]≈beta atol=1e-12
    @test fit.estimates[:alpha]≈alpha atol=1e-12
    residual=d.y .- alpha .- beta.*d.x
    sb=sqrt(sum(abs2,residual)/38/sum(abs2,d.x .- mean(d.x)))
    q=quantile(TDist(38),.975)
    @test fit.intervals[:beta][1]≈beta-q*sb atol=1e-12
    @test fit.intervals[:beta][2]≈beta+q*sb atol=1e-12
end

@testset "Failure ledger and exact denominators" begin
    s=Scenario("denominator";n=10)
    good=Adapter("good",(d,rng)->FitResult(Dict(:alpha=>2.,:beta=>1.7);
        intervals=Dict(:alpha=>(0.,3.),:beta=>(2.,3.))))
    bad=Adapter("throws",(d,rng)->error("deliberate failure"))
    nc=Adapter("nonconverged",(d,rng)->FitResult(Dict();converged=false,message="limit"))
    invalid=Adapter("invalid",(d,rng)->FitResult(Dict(:alpha=>NaN,:beta=>1.)))
    partial=Adapter("partial",(d,rng)->FitResult(Dict(:alpha=>1.,:beta=>.7);
        intervals=Dict(:alpha=>(2.,1.),:beta=>(-Inf,Inf))))
    study=runstudy([s],[good,bad,nc,invalid,partial];reps=3)
    @test length(study.ledger)==15
    @test length(study.rows)==30
    @test count(r->r.status==:fit_error,study.ledger)==3
    @test all(occursin("deliberate",r.message) for r in study.ledger if r.adapter=="throws")
    @test count(r->r.status==:nonconverged,study.ledger)==3
    @test count(r->r.status==:invalid_estimate,study.ledger)==3
    stats=summarize(study)
    a=only(filter(r->r.adapter=="good" && r.target==:alpha,stats))
    b=only(filter(r->r.adapter=="good" && r.target==:beta,stats))
    @test a.attempted==a.successful==a.usable_intervals==3
    @test a.bias==a.rmse==1.
    @test a.bias_mcse==a.rmse_mcse==0.
    @test a.coverage==1. && b.coverage==0.
    @test a.coverage_mcse==0.
    for row in filter(r->r.adapter in ("throws","nonconverged","invalid"),stats)
        @test row.failed==row.attempted==3
        @test row.successful==row.usable_intervals==0
        @test ismissing(row.bias) && ismissing(row.coverage)
        @test row.covered_per_attempt==0.
    end
    p=only(filter(r->r.adapter=="partial" && r.target==:alpha,stats))
    @test p.successful==3 && p.usable_intervals==0 && ismissing(p.coverage)
    one=only(filter(r->r.target==:alpha,summarize(runstudy([s],[good];reps=1))))
    @test ismissing(one.bias_mcse) && ismissing(one.coverage_mcse)
    @test_throws ArgumentError runstudy([s,s],[good])
    @test_throws ArgumentError runstudy([s],[good,good])
    @test_throws ArgumentError runstudy([s],[good];reps=0)
end

@testset "Monte Carlo formulas, paired data and order independence" begin
    s=Scenario("mc";n=20)
    random=Adapter("random",(d,rng)->FitResult(Dict(:alpha=>randn(rng),:beta=>randn(rng))))
    fixed=Adapter("fixed",ols)
    a=runstudy([s],[random,fixed];reps=5,seed=21)
    b=runstudy([s],[fixed,random];reps=5,seed=21)
    @test isequal(filter(r->r.adapter=="random",a.rows),filter(r->r.adapter=="random",b.rows))
    row=only(filter(r->r.adapter=="random" && r.target==:alpha,summarize(a)))
    errors=[r.estimate-r.truth for r in a.rows if r.adapter=="random" && r.target==:alpha]
    @test row.bias≈mean(errors)
    @test row.bias_mcse≈std(errors)/sqrt(5)
    @test row.rmse≈sqrt(mean(errors.^2))
    @test row.rmse_mcse≈std(errors.^2)/sqrt(5)/(2row.rmse)
    # A buggy adapter must not alter the paired data received by another adapter.
    corrupt=Adapter("mutates",(d,rng)->(fill!(d.y,0);ols(d,rng)))
    c=runstudy([s],[corrupt,fixed];reps=5,seed=21)
    @test filter(r->r.adapter=="fixed",a.rows)==filter(r->r.adapter=="fixed",c.rows)
end

@testset "Bounded Gaussian recovery smoke" begin
    s=Scenario("recovery";n=100)
    stats=summarize(runstudy([s],[Adapter("ols",ols)];reps=100,seed=42))
    for row in stats
        @test row.successful==row.usable_intervals==100
        @test abs(row.bias)<5row.bias_mcse
        @test .85<=row.coverage<=1.
        @test row.coverage_mcse≈sqrt(row.coverage*(1-row.coverage)/100)
    end
end

@testset "Explicit reference bundle" begin
    mktempdir() do dir
        d=replay(Scenario("template"),1)
        path=reference_bundle(joinpath(dir,"stan"),d;engine=:stan)
        @test isfile(path)
        @test occursin("log_sigma ~ normal(0, 0.5)",read(path,String))
        @test occursin("prior:",read(joinpath(dir,"stan","CONFORMANCE.txt"),String))
        @test occursin("\"N\":100",read(joinpath(dir,"stan","data.json"),String))
        @test_throws ArgumentError reference_bundle(joinpath(dir,"stan"),d)
        @test isfile(reference_bundle(joinpath(dir,"tmb"),d;engine=:tmb))
        @test_throws ArgumentError reference_bundle(dir,d;engine=:unknown)
        @test_throws ArgumentError reference_bundle(dir,replay(Scenario("glm";family=:logistic),1))
    end
end

@testset "Bounded logistic and known-covariance random intercept" begin
    logit=Scenario("logit";family=:logistic,n=120,alpha=-.3,beta=.5)
    d=replay(logit,1)
    @test all(y->y in (0.,1.),d.y)
    f=logistic_mle(d,nothing)
    @test f.converged
    X=hcat(ones(length(d.y)),d.x); b=[f.estimates[:alpha],f.estimates[:beta]]
    p=1 ./ (1 .+ exp.(-(X*b)))
    @test maximum(abs,X'*(d.y-p))<1e-7
    separated=(x=collect(-10.:10.),y=Float64.(collect(-10.:10.).>0),group=ones(Int,21),family=:logistic)
    failed=runstudy([logit],[Adapter("iteration-limit",(d,rng)->logistic_mle(d,rng;maxiter=0))];reps=2)
    @test all(r->r.status==:nonconverged,failed.ledger)
    @test !logistic_mle(separated,nothing).converged
    ri=Scenario("ri";family=:random_intercept,n=60,groups=10,sigma=1.2,tau=.7)
    d=replay(ri,1)
    rng=Xoshiro(seedfor(20261004,"ri",1,"data"))
    x=randn(rng,60); u=.7 .* randn(rng,10); noise=1.2 .* randn(rng,60)
    @test d.y==1 .+ .7 .* x .+ u[d.group] .+ noise
    fit=oracle_gls(d,nothing;sigma=1.2,tau=.7)
    @test fit.converged && all(isfinite,values(fit.estimates))
    z=replay(Scenario("ri0";family=:random_intercept,n=60,groups=10,tau=0.),1)
    oracle=oracle_gls(z,nothing;sigma=1.2,tau=0.)
    ordinary=ols(merge(z,(family=:gaussian,)),nothing)
    @test oracle.estimates[:alpha]≈ordinary.estimates[:alpha] atol=1e-12
    @test oracle.estimates[:beta]≈ordinary.estimates[:beta] atol=1e-12
    @test_throws ArgumentError ols(d,nothing)
    @test_throws ArgumentError logistic_mle(d,nothing)
    @test_throws ArgumentError oracle_gls(d,nothing;sigma=-1.,tau=.7)
end

@testset "Mixed attempts and boundary Monte Carlo uncertainty" begin
    counter=Ref(0)
    a=Adapter("mixed",(d,rng)->begin
        counter[]+=1
        counter[]==2 && error("failed replication")
        interval=counter[]==3 ? Dict{Symbol,Tuple{Float64,Float64}}() : Dict(:alpha=>(0.,2.),:beta=>(0.,2.))
        FitResult(Dict(:alpha=>1.,:beta=>.7);intervals=interval)
    end)
    stats=summarize(runstudy([Scenario("mixed")],[a];reps=4))
    for r in stats
        @test (r.attempted,r.successful,r.failed,r.usable_intervals,r.unusable_intervals)==(4,3,1,2,2)
        @test r.coverage==1. && r.covered_per_attempt==.5
        @test r.coverage_mcse==0.
        @test 0<r.coverage_mc_lower<1. && r.coverage_mc_upper≈1.
    end
end
