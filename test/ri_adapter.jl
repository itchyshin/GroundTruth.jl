using Test, GroundTruth, Random, LinearAlgebra, Distributions

adapter_path = joinpath(@__DIR__, "..", "adapters", "lmm", "lmm_ml.jl")
@test isfile(adapter_path)
if isfile(adapter_path) && hasfield(FitResult, :diagnostics)
    include(adapter_path)
    using .GroundTruthLMM: lmm_ml
    function ri_fixture(name)
        cells = [replace.(split(line, ','), "\""=>"") for line in readlines(joinpath(@__DIR__, "fixtures", "ri", name * "-data.csv"))[2:end]]
        (; x=parse.(Float64, getindex.(cells,1)), y=parse.(Float64, getindex.(cells,2)),
           group=getindex.(cells,3), family=:random_intercept)
    end
    function ri_record_extra!(rows,name,fit)
        push!(rows,(scenario=name,engine="MixedModels",status=fit.converged ? :ok : :nonconverged,
                    alpha=get(fit.estimates,:alpha,missing),beta=get(fit.estimates,:beta,missing),
                    sigma2=get(fit.estimates,:sigma2,missing),tau2=get(fit.estimates,:tau2,missing),
                    objective=get(fit.diagnostics,:objective,missing),message=fit.message,
                    diagnostics=fit.diagnostics))
        path=joinpath(@__DIR__,"..",".unlazy","ri-twins","evidence","julia-additional-fits.csv")
        mkpath(dirname(path)); write_results(path,rows)
    end
    @testset "Frozen RI ML points and two independently computed Wald levels" begin
        d = ri_fixture("lmm-interior-fixture")
        f = lmm_ml(d, Xoshiro(1))
        @test f.converged
        @test Set(keys(f.estimates)) == Set((:alpha,:beta,:sigma2,:tau2))
        @test Set(keys(f.intervals)) == Set((:alpha,:beta))
        @test Set(keys(f.diagnostics.intervals_by_level)) == Set((.9,.95))
        @test f.intervals == f.diagnostics.intervals_by_level[.95]
        @test f.diagnostics.criterion == :ML
        @test f.diagnostics.optimizer_status in (:SUCCESS,:STOPVAL_REACHED,:FTOL_REACHED,:XTOL_REACHED)
        @test f.diagnostics.optimizer_controls.maxfeval == 10000
        @test f.diagnostics.accepted_statuses == (:SUCCESS,:STOPVAL_REACHED,:FTOL_REACHED,:XTOL_REACHED)
        @test f.diagnostics.variance_interval_reason == :not_expected
        @test f.diagnostics.observed_groups == 6
        @test f.diagnostics.exact_zero == false
        @test f.diagnostics.near_boundary == false
        X = hcat(ones(length(d.x)),d.x)
        V = f.estimates[:sigma2]*Matrix{Float64}(I,length(d.x),length(d.x)) +
            f.estimates[:tau2]*[a==b for a in d.group,b in d.group]
        C = inv(Symmetric(X'*(V\X)))
        @test f.diagnostics.covariance ≈ C atol=1e-10
        r = d.y-X*[f.estimates[:alpha],f.estimates[:beta]]
        L = cholesky(Symmetric(V))
        nll=(length(d.y)*log(2pi)+2sum(log,diag(L.L))+dot(r,L\r))/2
        @test f.diagnostics.objective ≈ nll atol=1e-7
        for level in (.9,.95), (t,j) in ((:alpha,1),(:beta,2))
            q = quantile(Normal(),(1+level)/2)
            @test f.diagnostics.intervals_by_level[level][t][1] ≈ f.estimates[t]-q*sqrt(C[j,j]) atol=1e-7
            @test f.diagnostics.intervals_by_level[level][t][2] ≈ f.estimates[t]+q*sqrt(C[j,j]) atol=1e-7
        end
        decoy = merge(d, (alpha=999.,beta=-999.,sigma2=-1.,tau2=-1.))
        @test lmm_ml(decoy,nothing).estimates == f.estimates
        renamed = merge(d, (group=["site-"*g for g in d.group],))
        relabeled = lmm_ml(renamed,nothing)
        @test all(isapprox(f.estimates[t],relabeled.estimates[t];atol=1e-7) for t in keys(f.estimates))
        permutation=reverse(eachindex(d.y))
        permuted=lmm_ml(merge(d,(x=d.x[permutation],y=d.y[permutation],group=d.group[permutation])),nothing)
        @test permuted.converged
        @test abs(permuted.diagnostics.objective-f.diagnostics.objective)<=1e-6
        @test all(abs(permuted.estimates[t]-f.estimates[t])<=1e-6*(1+abs(f.estimates[t])) for t in (:alpha,:beta))
        @test all(abs(permuted.estimates[t]-f.estimates[t])<=1e-5*(1+abs(f.estimates[t])) for t in (:sigma2,:tau2))
        predictor=lmm_ml(merge(d,(x=3 .+ 2 .* d.x,)),nothing)
        @test predictor.converged
        expected=Dict(:alpha=>f.estimates[:alpha]-1.5*f.estimates[:beta],:beta=>f.estimates[:beta]/2,
                      :sigma2=>f.estimates[:sigma2],:tau2=>f.estimates[:tau2])
        @test all(abs(predictor.estimates[t]-expected[t])<=(t in (:alpha,:beta) ? 1e-6 : 1e-5)*(1+abs(expected[t])) for t in keys(expected))
        A=[1. -1.5;0. .5]
        @test predictor.diagnostics.covariance ≈ A*C*A' atol=1e-6
        response=lmm_ml(merge(d,(y=4 .+ 1.5 .* d.y,)),nothing)
        @test response.converged
        expected=Dict(:alpha=>4+1.5*f.estimates[:alpha],:beta=>1.5*f.estimates[:beta],
                      :sigma2=>2.25*f.estimates[:sigma2],:tau2=>2.25*f.estimates[:tau2])
        @test all(abs(response.estimates[t]-expected[t])<=(t in (:alpha,:beta) ? 1e-6 : 1e-5)*(1+abs(expected[t])) for t in keys(expected))
        for level in (.9,.95),target in (:alpha,:beta),endpoint in (1,2)
            original=f.diagnostics.intervals_by_level[level][target][endpoint]
            expected=target==:alpha ? 4+1.5*original : 1.5*original
            @test abs(response.diagnostics.intervals_by_level[level][target][endpoint]-expected)<=1e-6*(1+abs(expected))
        end
        @test !lmm_ml(d,nothing;maxfeval=1).converged
        @test_throws ArgumentError lmm_ml(d,nothing;maxfeval=0)
        @test_throws ArgumentError lmm_ml(d,nothing;level=.9)
    end
    @testset "Zero group variance is valid ML; residual collapse is rejected" begin
        d = ri_fixture("lmm-boundary-fixture")
        # A large response origin must not turn visible within-group noise into
        # a perfect fixed-plus-group prediction. This is an input check, no fit.
        @test_nowarn GroundTruthLMM.checked_data(merge(d,(y=d.y .+ 1e14,)))
        f = lmm_ml(d,nothing)
        @test f.converged && f.diagnostics.exact_zero && f.diagnostics.boundary
        @test f.estimates[:tau2] <= 1e-10
        @test f.estimates[:tau2] ≈ 0. atol=1e-8
        @test f.diagnostics.near_boundary
        X = hcat(ones(length(d.x)),d.x); b = X\d.y
        @test f.estimates[:alpha] ≈ b[1] atol=1e-7
        @test f.estimates[:beta] ≈ b[2] atol=1e-7
        @test f.estimates[:sigma2] ≈ sum(abs2,d.y-X*b)/length(d.y) atol=1e-7
        for bad in (merge(d,(family=:gaussian,)), merge(d,(group=fill("one",length(d.y)),)),
                    merge(d,(group=string.(1:length(d.y)),)), merge(d,(x=ones(length(d.x)),)),
                    merge(d,(x=[NaN;d.x[2:end]],)), merge(d,(y=d.y[2:end],)),
                    merge(d,(group=Any[g=="2" ? 1 : g=="1" ? "1" : g for g in d.group],)))
            @test_throws ArgumentError lmm_ml(bad,nothing)
        end
        exact = (; x=repeat([-1.,0.,1.],4),group=repeat(1:4;inner=3),
                  y=repeat([-.5,1.,2.5],4) .+ repeat([1.,-1.,2.,-2.];inner=3),family=:random_intercept)
        @test_throws ArgumentError lmm_ml(exact,nothing)
        @test_throws ArgumentError lmm_ml(merge(exact,(y=1 .+ 1.5 .* exact.x,)),nothing)
    end
    @testset "Parent-frozen unequal, singleton and weak-group designs" begin
        attempts=NamedTuple[]
        for name in ("few-groups","mixed-singletons","strong-unequal","group-covariate")
            d=ri_fixture(name)
            f=lmm_ml(d,nothing)
            ri_record_extra!(attempts,name,f)
            @test f.converged
            @test f.estimates[:sigma2]>0 && f.estimates[:tau2]>=0
            @test f.diagnostics.observed_groups==length(unique(d.group))
            @test f.diagnostics.weak_group_information==(length(unique(d.group))<5)
            @test all(isfinite,values(f.estimates))
            @test !haskey(f.intervals,:sigma2) && !haskey(f.intervals,:tau2)
        end
        d=ri_fixture("boundary-simple")
        boundary=lmm_ml(d,nothing)
        ri_record_extra!(attempts,"boundary-simple",boundary)
        if boundary.converged
            @test boundary.diagnostics.exact_zero
            @test boundary.estimates[:tau2]<=1e-10
        else
            # This exact zero-face design can cause NLopt roundoff limitation.
            # Matching the analytic objective does not override optimizer status.
            @test boundary.diagnostics.optimizer_status==:ROUNDOFF_LIMITED
            @test all(ismissing, (boundary.diagnostics.boundary,boundary.diagnostics.issingular,boundary.diagnostics.exact_zero,boundary.diagnostics.near_boundary))
            @test isempty(boundary.estimates) && isempty(boundary.intervals)
            @test occursin("ROUNDOFF_LIMITED",boundary.message)
            @test any(w->occursin("roundoff",lowercase(w)),boundary.diagnostics.warnings)
        end
        X=hcat(ones(length(d.y)),d.x); b=X\d.y; residual=d.y-X*b
        sigma2=sum(abs2,residual)/length(d.y)
        @test b ≈ [1.,.7] atol=1e-12
        @test sigma2 ≈ 1. atol=1e-12
        @test all(g->abs(sum(residual[d.group.==g]))<=1e-12,unique(d.group))
        # Balanced zero-mean residuals make tau2=0 the analytic optimum;
        # nonzero tau2 only adds positive group-block log-determinant terms.
        nll=length(d.y)/2*(log(2pi)+log(sigma2)+1)
        density_nll=-sum(logpdf.(Normal(0.,sqrt(sigma2)),residual))
        @test abs(density_nll-nll)<=1e-9
        if boundary.converged
            @test abs(boundary.diagnostics.objective-nll)<=1e-6
        end
        @test_throws ArgumentError lmm_ml(ri_fixture("residual-degenerate"),nothing)
    end
    @testset "Coefficient inference failure retains finite ML points" begin
        points=Dict(:alpha=>1.,:beta=>.7,:sigma2=>1.,:tau2=>0.)
        f=GroundTruthLMM.result_with_intervals(points,(criterion=:ML,),()->error("forced covariance failure"))
        @test f.converged && f.estimates==points && isempty(f.intervals)
        @test occursin("forced covariance failure",f.diagnostics.interval_failure)
        @test all(isempty,values(f.diagnostics.intervals_by_level))
    end
end
