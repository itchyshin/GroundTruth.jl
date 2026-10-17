using GroundTruth, Random, LinearAlgebra

BLAS.set_num_threads(1)
Threads.nthreads()==1 && BLAS.get_num_threads()==1 || error("RI checks require one Julia/BLAS thread")
isdefined(Main,:GroundTruthLMM) || include(joinpath(@__DIR__,"..","adapters","lmm","lmm_ml.jl"))

function ri_export_fixture(name)
    path=joinpath(@__DIR__,"..","test","fixtures","ri",name*"-data.csv")
    lines=readlines(path)
    first(lines)=="x,y,group" || error("unexpected frozen fixture schema")
    cells=[replace.(split(line,','),"\""=>"") for line in lines[2:end]]
    (; x=parse.(Float64,getindex.(cells,1)),y=parse.(Float64,getindex.(cells,2)),
       group=getindex.(cells,3),family=:random_intercept)
end
function ri_export_end(fit,target,level,endindex)
    by_level=get(fit.diagnostics,:intervals_by_level,Dict())
    values=get(get(by_level,level,Dict()),target,nothing)
    values===nothing ? missing : values[endindex]
end
rows=NamedTuple[]
out=joinpath(dirname(@__DIR__),".unlazy","ri-twins","evidence","julia-fits.csv")
mkpath(dirname(out))
for name in ("lmm-interior","lmm-unequal","lmm-zero","lmm-weak",
             "lmm-interior-fixture","lmm-boundary-fixture")
    data=ri_export_fixture(name)
    fit=GroundTruthLMM.lmm_ml(data,Xoshiro(1))
    status=fit.converged ? :ok : :nonconverged
    getpoint(target)=get(fit.estimates,target,missing)
    push!(rows,(scenario=name,engine="MixedModels",status,
        alpha=getpoint(:alpha),beta=getpoint(:beta),sigma2=getpoint(:sigma2),tau2=getpoint(:tau2),
        objective=get(fit.diagnostics,:objective,missing),
        alpha_lower90=ri_export_end(fit,:alpha,.9,1),alpha_upper90=ri_export_end(fit,:alpha,.9,2),
        beta_lower90=ri_export_end(fit,:beta,.9,1),beta_upper90=ri_export_end(fit,:beta,.9,2),
        alpha_lower95=ri_export_end(fit,:alpha,.95,1),alpha_upper95=ri_export_end(fit,:alpha,.95,2),
        beta_lower95=ri_export_end(fit,:beta,.95,1),beta_upper95=ri_export_end(fit,:beta,.95,2),message=fit.message))
    # Persist completed attempts before asserting success; never hide a failure.
    write_results(out,rows)
    fit.converged || error("frozen reference fit failed: $name ($(fit.message))")
end
println("RI_JULIA_FROZEN_FITS_EXPORTED ",length(rows))
