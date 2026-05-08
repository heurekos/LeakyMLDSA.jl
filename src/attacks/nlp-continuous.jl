import Optim
import ProgressMeter

include("nlp-continuous-objectives.jl")

"""
    ContinuousNLPAttack(sigs; psi_approx, psi_box, psi_int, box_offset, initial_guess, threads, optimizer, options) -> ContinuousNLPAttack{T}

Continuous NLP attack using gradient-based optimization.
Relaxes integer constraints to continuous, then minimizes objective.

# Arguments
- `sigs::Signatures{T}`: signatures to attack
- `psi_approx::Function`: approximate objective function
- `psi_box::Function`: box constraint penalty
- `psi_int::Function`: integer constraint penalty
- `box_offset::Float64`: box constraint offset
- `initial_guess::Vector{Float64}`: initial key estimate
- `threads::Int`: number of threads
- `optimizer`: optimizer type (default: LBFGS)
- `options`: optimizer options
"""
struct ContinuousNLPAttack{T} <: Attack{T}
    sigs::Signatures{T}

    psi_approx::Function
    psi_box::Function
    psi_int::Function
    box_offset::Float64
    initial_guess::Vector{Float64}
    chunks::Vector{UnitRange{Int}}

    optimizer::Optim.AbstractOptimizer
    options::Optim.Options

    function ContinuousNLPAttack(sigs::Signatures{T};
        psi_approx = psi_square(psi_logistic(; k = 1.0)),
        psi_box = psi_box(psi_logistic(; k = 20.0)),
        psi_int = psi_square(psi_sin(; w = 0.2)),
        box_offset = 0.25,
        initial_guess = zeros(Float64, sigs.mldsa.n),
        threads = Threads.nthreads(), chunksize_min = 250,
        optimizer = Optim.LBFGS(),
        options = (; iterations = 50, show_trace = false),
    ) where {T}
        chunks = partition(1:length(sigs), threads; chunksize_min)
        options = Optim.Options(; Optim.default_options(optimizer)..., options...)

        return new{T}(sigs,
            psi_approx, psi_box, psi_int, box_offset, initial_guess, chunks,
            optimizer, options)
    end
end

struct ContinuousNLPAttackResult <: AttackResult{ContinuousNLPAttack}
    attack::ContinuousNLPAttack
    key_guess::Vector{Int8}
    key_estimate::Vector{Float64}
    result::Optim.MultivariateOptimizationResults
end

"""
    run_attack(attack::ContinuousNLPAttack)

Run continuous NLP attack.
"""
function run_attack(attack::ContinuousNLPAttack)
    (; sigs, initial_guess, optimizer, options) = attack
    (; fg!) = build_model(attack)

    result = Optim.optimize(Optim.NLSolversBase.only_fg!(fg!), initial_guess, optimizer, options)
    estimate = Optim.minimizer(result)
    guess = key_guess(sigs.mldsa, Optim.minimizer(result))

    return ContinuousNLPAttackResult(attack, guess, estimate, result)
end

function build_model(attack)
    (; sigs, psi_approx, psi_box, psi_int, box_offset, chunks) = attack
    (; mldsa, cs, zs) = sigs
    (; n, r, key_entry_range) = mldsa

    lower = first(key_entry_range) - box_offset
    upper = last(key_entry_range) + box_offset

    if length(chunks) == 1
        execution_mode = SingleThreaded()
    else
        execution_mode = MultiThreaded()
        _Gs = [Vector{Float64}(undef, n) for _ in 1:length(chunks)]
    end

    function fg!(F, G, x)
        (F, G) = _fg!(F, G, x, execution_mode)

        @inbounds for j in eachindex(x)
            (psi0_box, psi1_box) = psi_box(x[j], lower, upper)
            (psi0_int, psi1_int) = psi_int(x[j])

            F += psi0_box + psi0_int
            G[j] += psi1_box + psi1_int
        end

        return F
    end

    function _fg!(F, G, x, ::SingleThreaded)
        return _fg!(F, G, x, chunks[])
    end

    function _fg!(F, G, x, ::MultiThreaded)
        F = zero(F)
        fill!(G, zero(eltype(G)))

        tasks = map(zip(chunks, _Gs)) do (chunk, _G)
            Threads.@spawn _fg!(F, _G, x, chunk)
        end

        for (_F, _G) in fetch.(tasks)
            F += _F
            G .+= _G
        end

        return (F, G)
    end

    function _fg!(F, G, x, chunk)
        F = zero(F)
        fill!(G, zero(eltype(G)))

        @inbounds for i in chunk
            c = cs[i]
            z = zs[i]

            t = mod(z + 0.5 - dot(c, x), 4r)
            if t >= r
                flip = t >= 3r
                t = flip ? (t - 4r) : (2r - t)
            else
                flip = true
            end

            (psi0, psi1) = psi_approx(t)
            flip && (psi1 = -psi1)

            F += psi0
            for idx in c.pos G[idx + 1] += psi1 end
            for idx in c.neg G[idx + 1] -= psi1 end
        end

        return (F, G)
    end

    return (; fg!)
end
