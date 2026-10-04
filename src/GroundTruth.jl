module GroundTruth
using Random, SHA, Statistics, LinearAlgebra, Distributions
export Scenario, truth, generate, Adapter, FitResult, ols, logistic_mle, oracle_gls,
       runstudy, summarize, seedfor, replay, export_data, write_results, reference_bundle

"A scenario is a data-generating contract; its id must be unique within a study."
struct Scenario
    id::String
    family::Symbol
    n::Int
    alpha::Float64
    beta::Float64
    sigma::Float64
    tau::Float64
    groups::Int
    function Scenario(id; family=:gaussian, n=100, alpha=1., beta=.7,
                      sigma=1.2, tau=.7, groups=10)
        family in (:gaussian,:logistic,:random_intercept) || throw(ArgumentError("unknown family"))
        n > 2 && isfinite(alpha) && isfinite(beta) && isfinite(sigma) && sigma > 0 &&
            isfinite(tau) && tau >= 0 && 1 <= groups <= n || throw(ArgumentError("invalid scenario"))
        isempty(id) && throw(ArgumentError("empty id"))
        new(String(id), family, n, alpha, beta, sigma, tau, groups)
    end
end
truth(s::Scenario) = Dict(:alpha=>s.alpha, :beta=>s.beta)

"Stable across Julia sessions; SHA-derived separate data/fit stream keys."
function seedfor(base::Integer, scenario::String, rep::Integer, stream::String)
    base >= 0 && rep > 0 || throw(ArgumentError("base >= 0 and rep > 0 required"))
    # Length prefixes avoid ambiguous composite keys; no process-randomized hash().
    key = join(("$(ncodeunits(v)):$v" for v in string.((base,scenario,rep,stream))), "|")
    bytes = sha256(key)
    foldl((v,b)->(v<<8)|UInt64(b), bytes[1:8]; init=UInt64(0))
end

"Independent generator. No fitted-model code, priors or estimator calls."
function generate(s::Scenario, rng::AbstractRNG)
    x = randn(rng,s.n)
    group = [mod1(i,s.groups) for i in 1:s.n]
    eta = s.alpha .+ s.beta .* x
    if s.family == :logistic
        p = 1 ./ (1 .+ exp.(-eta))
        y = Float64.(rand(rng,s.n) .< p)
    elseif s.family == :random_intercept
        u = s.tau .* randn(rng,s.groups)
        y = eta .+ u[group] .+ s.sigma .* randn(rng,s.n)
    else
        y = eta .+ s.sigma .* randn(rng,s.n)
    end
    (x=x, y=y, group=group, family=s.family)
end
replay(s::Scenario, rep; seed=20261004) = generate(s, Xoshiro(seedfor(seed,s.id,rep,"data")))

struct FitResult
    estimates::Dict{Symbol,Float64}
    intervals::Dict{Symbol,Tuple{Float64,Float64}}
    converged::Bool
    message::String
end
FitResult(e; intervals=Dict{Symbol,Tuple{Float64,Float64}}(), converged=true, message="") =
    FitResult(Dict{Symbol,Float64}(e), Dict{Symbol,Tuple{Float64,Float64}}(intervals), converged, message)

"Adapter fit(data, rng) returns FitResult; metadata identifies priors and inference."
struct Adapter{F}
    id::String
    fit::F
    metadata::NamedTuple
end
Adapter(id,fit; metadata=(likelihood="unspecified",target="alpha,beta",prior="none",inference="unspecified")) = Adapter(String(id),fit,metadata)
function coefresult(b, se, q)
    names=(:alpha,:beta)
    FitResult(Dict(names[i]=>b[i] for i in 1:2);
              intervals=Dict(names[i]=>(b[i]-q*se[i],b[i]+q*se[i]) for i in 1:2))
end
function ols(d, rng; level=.95)
    d.family == :gaussian || throw(ArgumentError("OLS requires Gaussian scenario"))
    0 < level < 1 || throw(ArgumentError("invalid level"))
    X=hcat(ones(length(d.x)),d.x)
    b=X\d.y
    v=sum(abs2,d.y-X*b)/(length(d.y)-2)
    se=sqrt.(diag(v*inv(Symmetric(X'X))))
    coefresult(b,se,quantile(TDist(length(d.y)-2),(1+level)/2))
end
function logistic_mle(d, rng; level=.95, maxiter=80, tol=1e-9)
    d.family == :logistic || throw(ArgumentError("requires logistic data"))
    0 < level < 1 || throw(ArgumentError("invalid level"))
    X=hcat(ones(length(d.x)),d.x); b=zeros(2)
    for k in 1:maxiter
        p=1 ./ (1 .+ exp.(-(X*b)))
        H=X'*(X .* (p.*(1 .- p)))
        step=H\(X'*(d.y-p))
        b += step
        all(isfinite,b) && maximum(abs,b)<30 || return FitResult(Dict();converged=false,message="separation or unstable coefficients")
        if maximum(abs,step)<tol
            p=1 ./ (1 .+ exp.(-(X*b)))
            H=X'*(X .* (p.*(1 .- p)))
            return coefresult(b,sqrt.(diag(inv(Symmetric(H)))),quantile(Normal(),(1+level)/2))
        end
    end
    FitResult(Dict();converged=false,message="iteration limit")
end
function oracle_gls(d, rng; sigma, tau, level=.95)
    d.family == :random_intercept || throw(ArgumentError("requires random-intercept data"))
    sigma>0 && tau>=0 && 0<level<1 || throw(ArgumentError("invalid GLS settings"))
    n=length(d.y); X=hcat(ones(n),d.x)
    V=[(i==j ? sigma^2 : 0.) + (d.group[i]==d.group[j] ? tau^2 : 0.) for i in 1:n,j in 1:n]
    C=inv(Symmetric(X'*(V\X))); b=C*(X'*(V\d.y))
    coefresult(b,sqrt.(diag(C)),quantile(Normal(),(1+level)/2))
end

"Serial bounded runner. Every adapter attempt has a ledger record, including failures."
function runstudy(scenarios, adapters; reps=10, seed=20261004)
    reps>0 || throw(ArgumentError("reps must be positive"))
    length(unique(s.id for s in scenarios))==length(scenarios) || throw(ArgumentError("duplicate scenario id"))
    length(unique(a.id for a in adapters))==length(adapters) || throw(ArgumentError("duplicate adapter id"))
    ledger=NamedTuple[]; rows=NamedTuple[]
    for s in scenarios, rep in 1:reps
        ds=seedfor(seed,s.id,rep,"data")
        data=nothing; generation_error=""
        try data=generate(s,Xoshiro(ds)) catch e; generation_error=sprint(showerror,e) end
        for a in adapters
            fs=seedfor(seed,s.id,rep,"fit:"*a.id)
            status=:ok; message=""; result=nothing
            start=time_ns()
            if data===nothing
                status=:generation_error; message=generation_error
            else
                try
                    result=a.fit(deepcopy(data),Xoshiro(fs))
                    result isa FitResult || throw(ArgumentError("adapter must return FitResult"))
                    if !result.converged
                        status=:nonconverged; message=result.message
                    elseif !all(haskey(result.estimates,t) && isfinite(result.estimates[t]) for t in keys(truth(s)))
                        status=:invalid_estimate; message="missing/nonfinite target"
                    end
                catch e
                    status=:fit_error; message=sprint(showerror,e)
                end
            end
            push!(ledger,(scenario=s.id,rep=rep,adapter=a.id,data_seed=ds,fit_seed=fs,
                          status=status,message=message,seconds=(time_ns()-start)/1e9))
            for (target,t) in sort!(collect(truth(s));by=first)
                estimate=status==:ok ? result.estimates[target] : missing
                interval=status==:ok ? get(result.intervals,target,nothing) : nothing
                usable=interval!==nothing && all(isfinite,interval) && interval[1]<=interval[2]
                lo=usable ? interval[1] : missing; hi=usable ? interval[2] : missing
                push!(rows,(scenario=s.id,rep=rep,adapter=a.id,target=target,truth=t,
                    estimate=estimate,lower=lo,upper=hi,usable_interval=usable,
                    covered=usable ? lo<=t<=hi : missing))
            end
        end
    end
    (ledger=ledger,rows=rows,provenance=(julia=string(VERSION),seed=seed,reps=reps,
        rng="Xoshiro; SHA256 first 64 bits; algorithm v1",scenarios=collect(scenarios),
        adapters=[(id=a.id,metadata=a.metadata) for a in adapters]))
end
mcse(v)=length(v)>1 ? std(v)/sqrt(length(v)) : missing
function summarize(study)
    out=NamedTuple[]
    cells=unique((r.scenario,r.adapter,r.target) for r in study.rows)
    for (scenario,adapter,target) in cells
        rows=filter(r->(r.scenario,r.adapter,r.target)==(scenario,adapter,target),study.rows)
        errors=[r.estimate-r.truth for r in rows if !ismissing(r.estimate)]
        covers=Float64[r.covered for r in rows if r.usable_interval]
        n=length(errors); m=length(covers); attempted=length(rows)
        bias=n>0 ? mean(errors) : missing
        mse=n>0 ? mean(abs2,errors) : missing
        rmse=n>0 ? sqrt(mse) : missing
        # Delta method; all-zero errors give zero MCSE, singleton remains unknown.
        rmse_mcse=n>1 ? (rmse==0 ? 0. : mcse(errors.^2)/(2rmse)) : missing
        coverage=m>0 ? mean(covers) : missing
        # Wilson 95% Monte Carlo interval avoids falsely exact boundary coverage.
        z=quantile(Normal(),.975)
        center=m>0 ? (coverage+z^2/(2m))/(1+z^2/m) : missing
        half=m>0 ? z*sqrt(coverage*(1-coverage)/m+z^2/(4m^2))/(1+z^2/m) : missing
        push!(out,(scenario=scenario,adapter=adapter,target=target,attempted=attempted,
            successful=n,failed=attempted-n,usable_intervals=m,unusable_intervals=attempted-m,
            bias=bias,bias_mcse=mcse(errors),rmse=rmse,rmse_mcse=rmse_mcse,
            coverage=coverage,coverage_mcse=m>1 ? sqrt(coverage*(1-coverage)/m) : missing,
            coverage_mc_lower=m>0 ? max(0.,center-half) : missing,
            coverage_mc_upper=m>0 ? min(1.,center+half) : missing,
            covered_per_attempt=attempted>0 ? sum(covers)/attempted : missing))
    end
    out
end
# Minimal CSV export, interoperable with R/Stan/TMB; no execution or shell coupling.
csvcell(x)=ismissing(x) ? "" : "\""*replace(string(x),'"'=>"\"\"")*"\""
function write_results(path,rows)
    isempty(rows) && throw(ArgumentError("cannot infer columns from empty rows"))
    open(path,"w") do io
        println(io,join(string.(keys(first(rows))),","))
        for r in rows; println(io,join(csvcell.(values(r)),",")); end
    end
    path
end
export_data(path,d)=write_results(path,[(x=d.x[i],y=d.y[i],group=d.group[i]) for i in eachindex(d.y)])
"Emit an audited simple Gaussian template and data; never translates arbitrary model code."
function reference_bundle(dir, d; engine=:stan)
    d.family == :gaussian || throw(ArgumentError("reference templates currently cover Gaussian LM only"))
    engine in (:stan,:tmb) || throw(ArgumentError("engine must be :stan or :tmb"))
    length(d.x)==length(d.y)>2 && all(isfinite,d.x) && all(isfinite,d.y) ||
        throw(ArgumentError("finite equal-length x and y required"))
    mkpath(dir)
    extension=engine==:stan ? "stan" : "cpp"
    source=joinpath(dirname(@__DIR__),"reference","linear."*extension)
    destination=joinpath(dir,"linear."*extension)
    isfile(destination) && throw(ArgumentError("template exists; choose a fresh directory"))
    cp(source,destination)
    export_data(joinpath(dir,"data.csv"),d)
    open(joinpath(dir,"data.json"),"w") do io
        print(io,"{\"N\":",length(d.y),",\"x\":[",join(d.x,","),"],\"y\":[",join(d.y,","),"]}")
    end
    open(joinpath(dir,"CONFORMANCE.txt"),"w") do io
        println(io,"family=Gaussian identity; targets alpha=intercept, beta=slope")
        println(io,"data SHA256=",bytes2hex(sha256(read(joinpath(dir,"data.csv")))))
        println(io,"template SHA256=",bytes2hex(sha256(read(destination))))
        println(io,engine==:stan ? "prior: alpha~N(0,5), beta~N(0,2), log_sigma~N(0,0.5); inference: posterior NUTS (optional)" :
            "prior: none; inference: maximum likelihood via TMB/nlminb (optional)")
        println(io,"Template export does not run an engine or verify a posterior fit.")
    end
    destination
end

end
