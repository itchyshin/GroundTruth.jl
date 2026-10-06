include("logistic_support.jl")
include("logistic_regression.jl")
@testset "Frozen numeric CSV quoting and named columns" begin
    # Existing retained bytes provide a quoted-numeric regression.
    retained=logistic_fixture("retained")
    @test retained.x[1] == -1.211659778454643
    @test retained.y[1] == 0.
    reordered=logistic_fixture_rows(["\"group\",\"y\",\"x\"", "\"7\",\"1.0\",\"-2.5\"", "8,0,3.5"])
    @test reordered.x == [-2.5,3.5]
    @test reordered.y == [1.,0.]
    for name in LOGISTIC_NAMES
        d=logistic_fixture(name)
        @test length(d.x)==length(d.y)>2
        @test all(isfinite,d.x) && all(y->y in (0.,1.),d.y)
    end
end
@testset "Frozen logistic fits and normal Wald intervals" begin
    for name in ("retained","analytic","asymmetric","inverted","scaled","shifted","tied")
        for level in (.90,.95)
            f,o=fitted_oracle(name;level=level)
            # Raw score is an audit test here, never a runtime stopping rule.
            @test maximum(abs,o.score)<1e-7
            for (j,t) in enumerate((:alpha,:beta))
                @test se_from_interval(f,t,level) ≈ o.se[j] atol=1e-7 rtol=1e-7
                q=quantile(Normal(),(1+level)/2)
                @test f.intervals[t][1] ≈ f.estimates[t]-q*o.se[j] atol=1e-7 rtol=1e-7
                @test f.intervals[t][2] ≈ f.estimates[t]+q*o.se[j] atol=1e-7 rtol=1e-7
            end
        end
    end
    a=(log(.2/.8)+log(.7/.3))/2; b=(log(.7/.3)-log(.2/.8))/2
    f,o=fitted_oracle("analytic")
    expected=scalar_oracle(logistic_fixture("analytic"),a,b)
    @test f.estimates[:alpha] ≈ a atol=1e-10 rtol=0
    @test f.estimates[:beta] ≈ b atol=1e-10 rtol=0
    @test o.information ≈ [3.7 .5;.5 3.7] atol=1e-10 rtol=0
    for (j,t) in enumerate((:alpha,:beta))
        @test se_from_interval(f,t,.95) ≈ expected.se[j] atol=1e-10 rtol=0
        @test f.intervals[t][1] ≈ (a,b)[j]-quantile(Normal(),.975)*expected.se[j] atol=1e-9 rtol=0
    end
    tf,to=fitted_oracle("tied")
    @test tf.estimates[:alpha] ≈ -log(3) atol=1e-10
    @test tf.estimates[:beta] ≈ 0 atol=1e-10
    # x'=3-100x: beta'=beta/(-100), alpha'=alpha-3beta'.
    sf,so=fitted_oracle("shifted"); T=[1. .03;0. -.01]
    @test [sf.estimates[:alpha],sf.estimates[:beta]] ≈ T*[a,b] atol=1e-10 rtol=0
    @test so.covariance ≈ T*expected.covariance*T' atol=1e-10 rtol=0
    @test so.covariance[1,2] ≈ (T*expected.covariance*T')[1,2] atol=1e-10
    @test sf.intervals[:beta][1] ≈ -f.intervals[:beta][2]/100 atol=1e-10
    @test sf.intervals[:beta][2] ≈ -f.intervals[:beta][1]/100 atol=1e-10
    # A variance may be unrepresentable while its SE and interval remain finite.
    # Relative checks cannot accidentally accept a collapsed interval at tiny width.
    for scale in (1e200,1e-160), level in (.90,.95)
        extreme=(x=[-scale,0.,0.,scale],y=[0.,0.,1.,0.],family=:logistic)
        representable=logistic_mle(extreme,nothing;level=level)
        @test representable.converged && all(isfinite,values(representable.estimates))
        @test haskey(representable.intervals,:alpha) && haskey(representable.intervals,:beta)
        q=quantile(Normal(),(1+level)/2)
        width=q*sqrt(8/3)/scale
        @test representable.intervals[:beta][1] < representable.intervals[:beta][2]
        @test representable.intervals[:beta][1] ≈ -width atol=0 rtol=1e-12
        @test representable.intervals[:beta][2] ≈ width atol=0 rtol=1e-12
        @test isempty(representable.message)
    end
    # Genuine interval overflow keeps finite points and the unaffected alpha interval.
    tiny=(x=[-1e-310,0.,0.,1e-310],y=[0.,0.,1.,0.],family=:logistic)
    partial=logistic_mle(tiny,nothing)
    @test partial.converged && all(isfinite,values(partial.estimates))
    @test haskey(partial.intervals,:alpha) && !haskey(partial.intervals,:beta)
    @test occursin("interval",partial.message)
    # Finite standardized fit whose raw slope cannot be represented rejects points.
    d=logistic_fixture("analytic")
    overflow=logistic_mle(merge(d,(x=d.x.*1e-310,)),nothing)
    @test !overflow.converged && isempty(overflow.estimates)
    @test occursin("nonfinite",overflow.message)
end
@testset "Exact existence, input and iteration controls" begin
    for name in ("complete","quasi","all_zero","all_one","constant")
        d=logistic_fixture(name)
        for x in (d.x,-d.x)
            f=logistic_mle(merge(d,(x=x,)),nothing)
            @test !f.converged && isempty(f.estimates) && isempty(f.intervals)
            @test !isempty(f.message)
        end
    end
    @test occursin("complete separation",logistic_mle(logistic_fixture("complete"),nothing).message)
    @test occursin("quasi separation",logistic_mle(logistic_fixture("quasi"),nothing).message)
    for k in (0,1)
        f=logistic_mle(logistic_fixture("analytic"),nothing;maxiter=k)
        @test !f.converged && isempty(f.estimates) && occursin("iteration limit",f.message)
    end
    d=logistic_fixture("analytic")
    for kwargs in ((level=0.,),(level=1.,),(level=NaN,),(maxiter=-1,),(maxiter=1.2,),(tol=0.,),(tol=Inf,),(tol=NaN,))
        @test_throws ArgumentError logistic_mle(d,nothing;kwargs...)
    end
    for bad in ((x=[0.,1.],y=[0.,1.],family=:logistic),
                (x=[0.,1.,2.],y=[0.,1.],family=:logistic),
                (x=[0.,Inf,2.],y=[0.,1.,0.],family=:logistic),
                (x=[0.,1.,2.],y=[0.,.5,1.],family=:logistic),
                (x=[0.,1.,2.],y=[0.,NaN,1.],family=:logistic),
                (x=["0","1","2"],y=[0.,1.,0.],family=:logistic))
        @test_throws ArgumentError logistic_mle(bad,nothing)
    end
end
@testset "Independent fixed-point large-logit identities" begin
    # Logistic tails retain score and information at eta=40 rather than rounding them to zero.
    for eta in (-40.,40.,-700.,700.)
        v=exp(-abs(eta)); p=eta>=0 ? 1/(1+v) : v/(1+v)
        @test GroundTruth.logistic_weight(eta) ≈ v/(1+v)^2 rtol=1e-14 atol=0
        @test GroundTruth.logistic_residual(eta,1.) > 0
        @test GroundTruth.logistic_residual(eta,0.) < 0
        @test GroundTruth.logistic_loss(eta,1.) ≈ max(-eta,0)+log1p(v) rtol=1e-14 atol=0
        @test GroundTruth.logistic_loss(eta,0.) ≈ max(eta,0)+log1p(v) rtol=1e-14 atol=0
    end
end
