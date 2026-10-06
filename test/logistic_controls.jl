isdefined(Main, :scalar_oracle) || include("logistic_support.jl")
using SHA

function candidate_valid(rows,d;analytic=false)
    length(rows)==2 || return false
    targets=[r.target for r in rows]
    Set(targets)==Set((:alpha,:beta)) || return false
    pair=Dict(r.target=>r for r in rows)
    a=pair[:alpha].estimate; b=pair[:beta].estimate
    all(isfinite,(a,b)) || return false
    o=scalar_oracle(d,a,b)
    maximum(abs,o.score)<=1e-7 || return false
    if analytic
        exact=((log(.2/.8)+log(.7/.3))/2,(log(.7/.3)-log(.2/.8))/2)
        all(isapprox((a,b)[j],exact[j];atol=1e-10,rtol=0) for j in 1:2) || return false
    end
    for (j,t) in enumerate((:alpha,:beta))
        r=pair[t]
        isapprox(r.se,o.se[j];atol=1e-7,rtol=1e-7) || return false
        for level in (.90,.95)
            interval=level==.90 ? r.interval90 : r.interval95
            q=quantile(Normal(),(1+level)/2)
            expected=(r.estimate-q*o.se[j],r.estimate+q*o.se[j])
            all(isapprox(interval[k],expected[k];atol=1e-7,rtol=1e-7) for k in 1:2) || return false
        end
    end
    true
end
function candidate_rows()
    d=logistic_fixture("analytic")
    a=(log(.2/.8)+log(.7/.3))/2; b=(log(.7/.3)-log(.2/.8))/2
    o=scalar_oracle(d,a,b)
    [(target=t,estimate=(a,b)[j],se=o.se[j],
      interval90=((a,b)[j]-quantile(Normal(),.95)*o.se[j],(a,b)[j]+quantile(Normal(),.95)*o.se[j]),
      interval95=((a,b)[j]-quantile(Normal(),.975)*o.se[j],(a,b)[j]+quantile(Normal(),.975)*o.se[j]))
     for (j,t) in enumerate((:alpha,:beta))]
end
@testset "Independent wrong-answer controls" begin
    d=logistic_fixture("analytic"); valid=candidate_rows()
    @test candidate_valid(valid,d;analytic=true)
    @test candidate_valid(reverse(valid),d;analytic=true)
    @test !candidate_valid(valid[1:1],d;analytic=true)
    @test !candidate_valid(vcat(valid,valid[1:1]),d;analytic=true)
    swapped=[merge(valid[1],(target=:beta,)),merge(valid[2],(target=:alpha,))]
    @test !candidate_valid(swapped,d;analytic=true)
    signflip=[valid[1],merge(valid[2],(estimate=-valid[2].estimate,))]
    @test !candidate_valid(signflip,d;analytic=true)
    # At zero coefficients information is X'X/4, not the final information.
    initial=[merge(r,(se=sqrt(.2),
        interval90=(r.estimate-quantile(Normal(),.95)*sqrt(.2),r.estimate+quantile(Normal(),.95)*sqrt(.2)),
        interval95=(r.estimate-quantile(Normal(),.975)*sqrt(.2),r.estimate+quantile(Normal(),.975)*sqrt(.2)))) for r in valid]
    @test !candidate_valid(initial,d;analytic=true)
    # The scientific checker sees the same fixture rows in any order.
    @test candidate_valid(valid,merge(d,(x=reverse(d.x),y=reverse(d.y)));analytic=true)
end
@testset "Four-attempt accounting including interval-only failures" begin
    count=Ref(0)
    adapter=Adapter("four-attempts",(d,rng)->begin
        count[]+=1
        count[]==2 && error("one failed attempt")
        intervals=count[]==3 ? Dict{Symbol,Tuple{Float64,Float64}}() :
            (count[]==4 ? Dict(:alpha=>(3.,4.),:beta=>(3.,4.)) : Dict(:alpha=>(0.,2.),:beta=>(0.,2.)))
        FitResult(Dict(:alpha=>1.,:beta=>.7);intervals=intervals,
            message=count[]==3 ? "interval unavailable" : "")
    end)
    study=runstudy([Scenario("four-attempts";n=10)],[adapter];reps=4)
    for row in summarize(study)
        @test (row.attempted,row.successful,row.failed,row.usable_intervals,row.unusable_intervals)==(4,3,1,2,2)
        @test row.coverage==.5 && row.covered_per_attempt==.25
        @test row.bias==row.rmse==row.bias_mcse==row.rmse_mcse==0.
    end
    @test study.ledger[2].status==:fit_error
    @test study.ledger[3].status==:ok
    @test study.ledger[3].message=="interval unavailable"
    @test all(!r.usable_interval && !ismissing(r.estimate) for r in study.rows if r.rep==3)
    failed=runstudy([Scenario("all-failed";n=10)],[Adapter("fail",(d,rng)->error("always"))];reps=2)
    @test all(r->ismissing(r.bias) && ismissing(r.coverage) && r.covered_per_attempt==0.,summarize(failed))
    single=runstudy([Scenario("single";n=10)],[Adapter("exact",(d,rng)->FitResult(Dict(:alpha=>1.,:beta=>.7)))];reps=1)
    @test all(r->r.bias==r.rmse==0. && ismissing(r.bias_mcse) && ismissing(r.rmse_mcse),summarize(single))
end
@testset "Gaussian wrong-normal and SSE/n controls" begin
    d=(x=[-2.,-1.,0.,1.,2.],y=[-.1,.4,1.8,1.6,3.1],family=:gaussian)
    f=ols(d,nothing)
    X=hcat(ones(length(d.x)),d.x); coef=X\d.y
    sse=sum(abs2,d.y-X*coef)
    se=sqrt.(diag((sse/(length(d.x)-2))*inv(Symmetric(X'X))))
    t=quantile(TDist(length(d.x)-2),.975); normal=quantile(Normal(),.975)
    for (j,target) in enumerate((:alpha,:beta))
        correct=(coef[j]-t*se[j],coef[j]+t*se[j])
        @test all(isapprox(f.intervals[target][k],correct[k];atol=1e-12,rtol=0) for k in 1:2)
        @test !isapprox(f.intervals[target][1],coef[j]-normal*se[j];atol=1e-7,rtol=1e-7)
        @test !isapprox(f.intervals[target][1],coef[j]-t*se[j]*sqrt((length(d.x)-2)/length(d.x));atol=1e-7,rtol=1e-7)
    end
end

@testset "Frozen byte identity and altered-byte control" begin
    manifest=read(joinpath(LOGISTIC_FIXTURES,"freeze.json"),String)
    hashes=Dict(m.captures[1]=>m.captures[2] for m in eachmatch(r"\"([^\"]+\.csv)\":\s*\"([0-9a-f]{64})\"",manifest))
    @test Set(keys(hashes))==Set(name*".csv" for name in LOGISTIC_NAMES)
    for (file,hash) in hashes
        bytes=read(joinpath(LOGISTIC_FIXTURES,file))
        @test bytes2hex(sha256(bytes))==hash
        @test bytes2hex(sha256(vcat(bytes,UInt8[0x0a])))!=hash
    end
end
