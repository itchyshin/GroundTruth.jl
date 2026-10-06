# Independent scalar test oracle. Does not call production loss/information helpers.
using Test, GroundTruth, LinearAlgebra, Distributions, Random
const LOGISTIC_FIXTURES=joinpath(@__DIR__,"fixtures","logistic")
const LOGISTIC_NAMES=("retained","analytic","asymmetric","inverted","scaled","complete","quasi","all_zero","all_one","constant","shifted","tied")
# Frozen files contain numeric cells only, optionally CSV-quoted; headers name x/y.
# There are no embedded-comma or multiline fields in this immutable fixture schema.
function logistic_csv_cell(cell)
    value=strip(cell)
    if startswith(value, '"') || endswith(value, '"')
        startswith(value, '"') && endswith(value, '"') && ncodeunits(value)>=2 ||
            throw(ArgumentError("invalid frozen numeric CSV quoting"))
        return value[2:end-1]
    end
    value
end
function logistic_fixture_rows(lines)
    header=logistic_csv_cell.(split(strip(first(lines)),','))
    count(==("x"),header)==count(==("y"),header)==1 ||
        throw(ArgumentError("frozen numeric CSV requires unique x and y headers"))
    xindex=only(findall(==("x"),header)); yindex=only(findall(==("y"),header))
    rows=[logistic_csv_cell.(split(strip(line),',')) for line in lines[2:end]]
    all(row->length(row)==length(header),rows) || throw(ArgumentError("invalid frozen CSV row width"))
    (x=[parse(Float64,row[xindex]) for row in rows],
     y=[parse(Float64,row[yindex]) for row in rows],family=:logistic)
end
logistic_fixture(name)=logistic_fixture_rows(readlines(joinpath(LOGISTIC_FIXTURES,name*".csv")))
function scalar_oracle(d,a,b)
    nll=sa=sb=iaa=iab=ibb=0.
    for (x,y) in zip(d.x,d.y)
        eta=a+b*x
        # Independently accumulate Bernoulli identities, including large logits.
        v=exp(-abs(eta)); p=eta>=0 ? 1/(1+v) : v/(1+v)
        residual=y==1 ? (eta>=0 ? v/(1+v) : 1/(1+v)) : -p
        signed=(1-2y)*eta
        nll+=max(signed,0)+log1p(exp(-abs(signed)))
        w=v/(1+v)^2
        sa+=residual; sb+=x*residual
        iaa+=w; iab+=x*w; ibb+=x*x*w
    end
    I=[iaa iab;iab ibb]; C=inv(Symmetric(I))
    (nll=nll,score=[sa,sb],information=I,covariance=Matrix(C),se=sqrt.(diag(C)))
end
function se_from_interval(f,t,level)
    q=quantile(Normal(),(1+level)/2)
    (f.intervals[t][2]-f.intervals[t][1])/(2q)
end
function fitted_oracle(name;level=.95)
    d=logistic_fixture(name); f=logistic_mle(d,nothing;level=level)
    @test f.converged
    if !f.converged; error("fixture $name rejected: $(f.message)"); end
    o=scalar_oracle(d,f.estimates[:alpha],f.estimates[:beta])
    f,o
end
