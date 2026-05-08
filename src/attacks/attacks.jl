abstract type Attack{T} end
abstract type AttackResult{T} end

"""
    attack_succeeded(result)

Check if attack recovered the full key.
"""
function attack_succeeded(result::AttackResult)
    return iszero(key_violations(result))
end

"""
    sig_violations(result)

Get signature violations from attack result.
"""
function sig_violations(result::AttackResult)
    if hasproperty(result, :violations)
        return result.violations
    else
        return sig_violations(result.attack.sigs, key_guess(result))
    end
end

"""
    key_violations(result)

Get key violations from attack result.
"""
function key_violations(result::AttackResult)
    return key_violations(result.attack.sigs, key_guess(result))
end

"""
    key_guess(result)

Get key guess from attack result.
"""
function key_guess(result::AttackResult)
    return result.key_guess
end

include("nlp-combinatorial.jl")
include("nlp-continuous.jl")
include("nlp.jl")
