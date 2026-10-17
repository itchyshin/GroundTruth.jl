"""
    inference_details(study)

Typed interval outcomes keyed by scenario, replication, adapter, target and level.
Legacy diagnostics without interval states produce no rows: their states remain
unknown. This companion preserves the existing target-row schema.
"""
function inference_details(study)
    out=NamedTuple[]
    if hasproperty(study,:inference_details)
        append!(out,study.inference_details)
    elseif hasproperty(study,:ledger)
        for entry in study.ledger
            hasproperty(entry,:diagnostics) || continue
            d=entry.diagnostics
            statuses=get(d,:inference_status,nothing)
            statuses===nothing && continue
            for ((target,level),state) in statuses
                levels=get(d,:intervals_by_level,Dict())
                interval=get(get(levels,level,Dict()),target,(missing,missing))
                push!(out,(scenario=entry.scenario,rep=entry.rep,adapter=entry.adapter,
                    target=target,level=level,state=Symbol(state),
                    criterion=get(d,:criterion,missing),interval_method=get(d,:interval_method,missing),
                    lower=interval[1],upper=interval[2],
                    root_lr_residual=get(get(d,:profile_residuals,Dict()),(target,level),missing),
                    endpoint_distance=get(get(d,:profile_endpoint_distances,Dict()),(target,level),missing),
                    elapsed_seconds=get(d,:profile_elapsed_seconds,missing),
                    message=get(get(d,:inference_messages,Dict()),(target,level),"")))
            end
        end
    end
    keys=[(r.scenario,r.rep,r.adapter,r.target,r.level) for r in out]
    length(unique(keys))==length(keys) || throw(ArgumentError("duplicate inference-detail keys"))
    all(r->r.state in (:finite,:unbounded,:incomplete,:error,:timeout,:invalid),out) ||
        throw(ArgumentError("unknown inference-detail state"))
    out
end

"""
    compare_inference(study; baseline, comparison)

Paired differences (comparison minus baseline) in coverage conditional on a
usable finite interval, finite covered-interval yield per scheduled attempt, and
joint-finite interval width. Conditional-coverage MCSE uses paired ratio
influence values. These are asymptotic Monte Carlo errors, not calibration.

Both methods must have unique matching replication keys. A recorded schedule or
attempt ledger is checked, including replications missing from both methods.
Synthetic row-only inputs have `schedule_verified=false`. Matching keys across
independent datasets does not make them paired: use one study's shared data.
Unknown companion states remain unknown; absence never implies unboundedness.
"""
function compare_inference(study;baseline,comparison)
    baseline isa AbstractString && comparison isa AbstractString && baseline!=comparison ||
        throw(ArgumentError("select distinct adapter IDs"))
    details=inference_details(study)
    rows=[r for r in study.rows if r.adapter in (baseline,comparison) &&
          r.target in (:alpha,:beta) && !ismissing(r.level)]
    all(id->any(r->r.adapter==id,rows),(baseline,comparison)) ||
        throw(ArgumentError("both adapters need fixed-effect interval rows"))
    cells=sort!(unique([(r.scenario,r.target,r.level) for r in rows]))
    out=NamedTuple[]
    for cell in cells
        z=[r for r in rows if (r.scenario,r.target,r.level)==cell]
        a=sort!([r for r in z if r.adapter==baseline];by=r->r.rep)
        b=sort!([r for r in z if r.adapter==comparison];by=r->r.rep)
        ra=[r.rep for r in a]; rb=[r.rep for r in b]
        !isempty(ra) && length(unique(ra))==length(ra) && length(unique(rb))==length(rb) && ra==rb ||
            throw(ArgumentError("pairing requires unique matching replication keys"))
        schedule_verified=false
        if hasproperty(study,:reps)
            ra==collect(1:study.reps) || throw(ArgumentError("scheduled replications missing from target rows"))
            schedule_verified=true
        elseif hasproperty(study,:provenance) && hasproperty(study.provenance,:reps)
            ra==collect(1:study.provenance.reps) || throw(ArgumentError("scheduled replications missing from target rows"))
            schedule_verified=true
        end
        if hasproperty(study,:ledger)
            for id in (baseline,comparison)
                expected=sort!([r.rep for r in study.ledger if r.scenario==cell[1] && r.adapter==id])
                length(unique(expected))==length(expected) && expected==ra ||
                    throw(ArgumentError("attempt ledger and target schedule disagree"))
            end
            schedule_verified=true
        end
        all(i->isfinite(a[i].truth) && isequal(a[i].truth,b[i].truth),eachindex(a)) ||
            throw(ArgumentError("paired targets need identical finite truth"))
        function validate(v)
            u=Bool[r.usable_interval===true for r in v]
            for (r,ok) in zip(v,u)
                ok || continue
                !ismissing(r.estimate) && isfinite(r.estimate) &&
                !ismissing(r.lower) && !ismissing(r.upper) &&
                isfinite(r.lower) && isfinite(r.upper) && r.lower<=r.upper &&
                isequal(r.covered,r.lower<=r.truth<=r.upper) ||
                    throw(ArgumentError("inconsistent usable interval or coverage flag"))
            end
            u
        end
        ua=validate(a); ub=validate(b)
        ca=Float64[ua[i] && a[i].covered===true for i in eachindex(a)]
        cb=Float64[ub[i] && b[i].covered===true for i in eachindex(b)]
        qa=any(ua) ? sum(ca)/sum(ua) : missing
        qb=any(ub) ? sum(cb)/sum(ub) : missing
        diffmc=any(ua)&&any(ub) ? mcse((cb.-qb.*ub)./mean(ub) .- (ca.-qa.*ua)./mean(ua)) : missing
        widths=Float64[(b[i].upper-b[i].lower)-(a[i].upper-a[i].lower)
                      for i in eachindex(a) if ua[i]&&ub[i]]
        function states(id,u)
            d=[r for r in details if (r.scenario,r.target,r.level)==cell && r.adapter==id]
            byrep=Dict(r.rep=>Symbol(r.state) for r in d)
            s=[get(byrep,r,:unknown) for r in ra]
            all(i->s[i]==:unknown || (s[i]==:finite)==u[i],eachindex(s)) ||
                throw(ArgumentError("companion states disagree with finite usable rows"))
            s
        end
        sa=states(baseline,ua); sb=states(comparison,ub)
        counts=Pair{Symbol,Int}[]
        for state in (:finite,:unbounded,:incomplete,:error,:timeout,:invalid,:unknown)
            push!(counts,Symbol("baseline_state_",state)=>count(==(state),sa))
            push!(counts,Symbol("comparison_state_",state)=>count(==(state),sb))
        end
        row=(scenario=cell[1],target=cell[2],level=cell[3],baseline=String(baseline),comparison=String(comparison),
             attempted=length(a),schedule_verified=schedule_verified,
             baseline_usable=sum(ua),comparison_usable=sum(ub),joint_usable=sum(ua.&ub),
             baseline_finite_hits=sum(ca),comparison_finite_hits=sum(cb),
             baseline_coverage=qa,comparison_coverage=qb,coverage_difference=qb-qa,
             coverage_difference_mcse=diffmc,
             baseline_finite_yield=mean(ca),comparison_finite_yield=mean(cb),
             finite_yield_difference=mean(cb-ca),finite_yield_difference_mcse=mcse(cb-ca),
             joint_width_difference=isempty(widths) ? missing : mean(widths),
             joint_width_difference_mcse=mcse(widths))
        push!(out,merge(row,(;counts...)))
    end
    out
end
