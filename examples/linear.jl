using GroundTruth, SHA
root=dirname(@__DIR__)
out=joinpath(root,"results","linear"); mkpath(out)
s=Scenario("gaussian-n100";n=100,alpha=1.,beta=.7,sigma=1.2)
a=Adapter("OLS",ols;metadata=(likelihood="Gaussian identity; unknown residual variance",
    target="alpha,beta",prior="none",inference="OLS, exact t intervals",interval_level=.95))
study=runstudy([s],[a];reps=100,seed=20261004)
write_results(joinpath(out,"summary.csv"),summarize(study))
write_results(joinpath(out,"ledger.csv"),study.ledger)
write_results(joinpath(out,"estimates.csv"),study.rows)
d=replay(s,1); export_data(joinpath(out,"rep1-data.csv"),d)
f=ols(d,nothing)
write_results(joinpath(out,"rep1-julia.csv"),[(target=t,estimate=f.estimates[t],lower=f.intervals[t][1],upper=f.intervals[t][2]) for t in (:alpha,:beta)])
open(joinpath(out,"provenance.txt"),"w") do io
    println(io,repr(study.provenance))
    for p in ("src/GroundTruth.jl","Project.toml","Manifest.toml","examples/linear.jl")
        println(io,p," sha256=",bytes2hex(sha256(read(joinpath(root,p)))))
    end
    println(io,"rep1-data.csv sha256=",bytes2hex(sha256(read(joinpath(out,"rep1-data.csv")))))
end
foreach(println,summarize(study))
println("Saved: ",out)
