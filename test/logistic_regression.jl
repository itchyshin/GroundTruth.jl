using Test, GroundTruth

@testset "Finite MLE under predictor rescaling" begin
    x=vcat(fill(-.01,10),fill(.01,10))
    y=vcat(ones(2),zeros(8),ones(7),zeros(3))
    fit=logistic_mle((x=x,y=y,family=:logistic),nothing)
    @test fit.converged
    if fit.converged
        @test fit.estimates[:alpha] ≈ (log(.2/.8)+log(.7/.3))/2 atol=1e-10
        @test fit.estimates[:beta] ≈ (log(.7/.3)-log(.2/.8))/.02 atol=1e-8
    end
end
