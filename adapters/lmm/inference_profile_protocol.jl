module GroundTruthInferenceProfileProtocol

export profile_beta_index, profile_brackets, run_profile_attempt

"Return the MixedModels beta-curve index from its :β1-style symbol."
function profile_beta_index(sym::Symbol)
    text=string(sym)
    startswith(text,"β") || return nothing
    parse(Int,SubString(text,nextind(text,firstindex(text))))
end

"Whether a native root-LR curve brackets both signed cutoffs."
profile_brackets(first_x, last_x, required_cutoff) =
    isfinite(first_x) && isfinite(last_x) && isfinite(required_cutoff) &&
    first_x <= -required_cutoff && last_x >= required_cutoff

"Run an isolated attempt and always publish its final state, including errors."
function run_profile_attempt(action, publish)
    status=:error
    message="native profile helper failed"
    value=nothing
    try
        value=action()
        status=:ok
        message="native fixed-effect profile completed"
    catch err
        err isa InterruptException && rethrow()
        message=sprint(showerror,err)
        status=startswith(message,"POINT_MISMATCH:") ? :invalid : :error
    finally
        publish((;status,message))
    end
    (;status,message,value)
end

end
