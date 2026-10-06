# Evidence transport uses final-information inference, independent scalar identities,
# and the immutable shared input bytes. No native-reference covariance is relabeled.
isdefined(Main, :scalar_oracle) || include(joinpath(@__DIR__,"..","test","logistic_support.jl"))
rows=NamedTuple[]
accepted=String[]; rejected=String[]
for name in LOGISTIC_NAMES
    d=logistic_fixture(name)
    f90=logistic_mle(d,nothing;level=.90)
    f95=logistic_mle(d,nothing;level=.95)
    @assert f90.converged==f95.converged
    if f95.converged
        push!(accepted,name)
        @assert f90.estimates==f95.estimates
        a=f95.estimates[:alpha]; b=f95.estimates[:beta]
        o=scalar_oracle(d,a,b)
        @assert maximum(abs,o.score)<1e-7
        for (j,t) in enumerate((:alpha,:beta))
            @assert haskey(f90.intervals,t) && haskey(f95.intervals,t)
            @assert isapprox(se_from_interval(f95,t,.95),o.se[j];atol=1e-7,rtol=1e-7)
            push!(rows,(fixture=name,engine="julia",status="ok",target=string(t),
                estimate=f95.estimates[t],se=o.se[j],lower90=f90.intervals[t][1],upper90=f90.intervals[t][2],
                lower95=f95.intervals[t][1],upper95=f95.intervals[t][2],nll=o.nll,
                score_alpha=o.score[1],score_beta=o.score[2],Iaa=o.information[1,1],Iab=o.information[1,2],Ibb=o.information[2,2],message=f95.message))
        end
    else
        push!(rejected,name)
        @assert isempty(f95.estimates) && isempty(f95.intervals) && !isempty(f95.message)
        for t in (:alpha,:beta)
            push!(rows,(fixture=name,engine="julia",status="nonconverged",target=string(t),
                estimate=missing,se=missing,lower90=missing,upper90=missing,lower95=missing,upper95=missing,
                nll=missing,score_alpha=missing,score_beta=missing,Iaa=missing,Iab=missing,Ibb=missing,message=f95.message))
        end
    end
end
@assert Set(accepted)==Set(("retained","analytic","asymmetric","inverted","scaled","shifted","tied"))
@assert Set(rejected)==Set(("complete","quasi","all_zero","all_one","constant"))
evidence=joinpath(@__DIR__,"..",".unlazy","logistic-twins","evidence")
mkpath(evidence)
write_results(joinpath(evidence,"julia-fits.csv"),rows)
open(joinpath(evidence,"julia-inference.md"),"w") do io
    println(io,"# Julia logistic inference")
    println(io,"Engine: GroundTruth native standardized Newton optimizer. Accepted points: ",join(accepted,", "),".")
    println(io,"Rejected points: ",join(rejected,", "),". Both interval levels were fitted independently.")
    println(io,"Declared inference: final-information normal Wald; full covariance transformed to original units.")
    println(io,"FitResult schema is unchanged; no engine warnings or iteration count were invented. Scalar CSV identities are independently recomputed for audit.")
end
