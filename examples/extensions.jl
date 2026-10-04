# Small GLM plus random-intercept ORACLE example; no estimated variance components.
using GroundTruth, SHA
root=dirname(@__DIR__); out=joinpath(root,"results","extensions"); mkpath(out)
logit=Scenario("logistic-n120";family=:logistic,n=120,alpha=-.3,beta=.5)
ri=Scenario("random-intercept-n60";family=:random_intercept,n=60,groups=10,sigma=1.2,tau=.7)
a=Adapter("logistic-MLE",logistic_mle;metadata=(likelihood="Bernoulli logit",target="alpha,beta",
    prior="none",inference="MLE normal Wald",interval_level=.95))
b=Adapter("oracle-GLS",(d,rng)->oracle_gls(d,rng;sigma=1.2,tau=.7);
    metadata=(likelihood="Gaussian random intercept",target="alpha,beta",prior="none",
    inference="GLS known sigma=1.2,tau=0.7; oracle normal intervals",interval_level=.95))
for (s,adapter,label) in ((logit,a,"logistic"),(ri,b,"random-intercept"))
    study=runstudy([s],[adapter];reps=20,seed=20261004)
    write_results(joinpath(out,label*"-summary.csv"),summarize(study))
    write_results(joinpath(out,label*"-ledger.csv"),study.ledger)
    write_results(joinpath(out,label*"-estimates.csv"),study.rows)
    export_data(joinpath(out,label*"-rep1-data.csv"),replay(s,1))
    f=adapter.fit(replay(s,1),nothing)
    write_results(joinpath(out,label*"-rep1-julia.csv"),[(target=t,estimate=f.estimates[t],lower=f.intervals[t][1],upper=f.intervals[t][2]) for t in (:alpha,:beta)])
    open(joinpath(out,label*"-provenance.txt"),"w") do io
        println(io,repr(study.provenance))
        for p in ("src/GroundTruth.jl","Project.toml","Manifest.toml","examples/extensions.jl")
            println(io,p," sha256=",bytes2hex(sha256(read(joinpath(root,p)))))
        end
        println(io,"data sha256=",bytes2hex(sha256(read(joinpath(out,label*"-rep1-data.csv")))))
    end
    foreach(println,summarize(study))
end
