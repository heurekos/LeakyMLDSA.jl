import Distributions: Uniform
import Random: Xoshiro

"""
    Hyperparameters

Hyperparameter config for attack tuning.
"""
@kwdef struct Hyperparameters
    iterations::Int = 1
    seed::UInt = rand(UInt)
end

function Base.iterate(hp::Hyperparameters)
    rng = Xoshiro("seed=$(hp.seed)|hyperparameters")
    return ((;), (1, rng))
end

function Base.iterate(hp::Hyperparameters, state)
    (iteration, rng) = state
    iteration == hp.iterations && return
    params = (;
        psi_approx = psi_square(psi_logistic(; k = rand(rng, Uniform(0.3, 1.5)))),
        psi_int = psi_square(psi_sin(; w = rand(rng, Uniform(0.0, 0.5)))),
    )
    return (params, (iteration + 1, rng))
end

"""
    NLPAttack(sigs; hyperparameters, continuous_options, combinatorial_options, threads, timeout, show_progress) -> NLPAttack{T}

Full NLP attack combining continuous and combinatorial methods.
First runs continuous optimization, then refines with combinatorial search.

# Arguments
- `sigs::Signatures{T}`: signatures to attack
- `hyperparameters`: iterable hyperparameters for continuous stage
- `continuous_options`: options for continuous stage
- `combinatorial_options`: options for combinatorial stage
- `threads::Int`: number of threads
- `timeout::Int`: time limit in seconds
- `show_progress::Bool`: whether to display a progress meter
"""
struct NLPAttack{T} <: Attack{T}
    sigs::Signatures{T}

    hyperparameters::Any
    continuous_options::NamedTuple
    combinatorial_options::Union{Nothing, NamedTuple}
    threads::Int
    timeout::Int
    Log::Union{Nothing, Type}

    function NLPAttack(sigs::Signatures{T};
        hyperparameters = Hyperparameters(),
        continuous_options = (;), combinatorial_options = (;),
        threads = Threads.nthreads(), timeout = typemax(Int), show_progress = false,
        Log = show_progress ? ProgressLog : nothing,
    ) where {T}
        return new{T}(sigs, hyperparameters,
            continuous_options, combinatorial_options,
            threads, timeout, Log)
    end
end

struct NLPAttackResult <: AttackResult{NLPAttack}
    attack::NLPAttack
    key_guess::Vector{Int8}
    violations::Int
end

"""
    run_attack(attack::NLPAttack)

Run full NLP attack (continuous + combinatorial).
"""
function run_attack(attack::NLPAttack)
    (; sigs, hyperparameters,
        continuous_options, combinatorial_options,
        threads, timeout, Log) = attack

    guess = nothing
    best_violations = length(sigs) + 1

    isnothing(Log) || (log = Log())
    starttime = time()

    for (iteration, params) in enumerate(hyperparameters)
        continuous_attack = ContinuousNLPAttack(sigs;
            threads, continuous_options..., params...)
        continuous_result = run_attack(continuous_attack)
        violations = sig_violations(continuous_result)

        if violations < best_violations
            guess = key_guess(continuous_result)
            best_violations = violations
        end

        isnothing(Log) || log_progress!(log, best_violations;
            desc = "parameter tuning",
            values = [
                "key entries not recovered" => key_violations(sigs, guess),
                "iteration" => iteration,
        ])

        time() - starttime > timeout && break
    end

    timeout -= floor(Int, time() - starttime)

    if !isnothing(combinatorial_options) && best_violations > 0 && timeout > 0
        combinatorial_attack = CombinatorialNLPAttack(sigs;
            threads, timeout, Log, combinatorial_options...,
            initial_guess = guess)
        combinatorial_result = run_attack(combinatorial_attack)

        guess = key_guess(combinatorial_result)
        best_violations = sig_violations(combinatorial_result)
    end

    return NLPAttackResult(attack, guess, best_violations)
end
