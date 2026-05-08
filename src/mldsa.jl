import Random: AbstractRNG, Xoshiro, default_rng, shuffle!
import StatsBase: sample

"""
    MLDSA(; lambda, p_err, gamma, eta, tau)

# Arguments
- `lambda`: index of the leaked bit position
- `p_err`: error probability in leakage bit (0.0 = exact, 0.5 = random)
- `gamma`: bound for mask value `y`
- `eta`: bound for key entries
- `tau`: Hamming weight of challenge vector `c`
"""
struct MLDSA{T}
    n::Int
    gamma::Int
    eta::Int8
    tau::Int
    beta::Int
    lambda::Int
    p_err::Float64

    key_entry_range::UnitRange{Int8}
    z_range::UnitRange{Int}
    informative_range::UnitRange{Int}

    r::T
    _2r_range::UnitRange{T}
    _4r_range::UnitRange{T}

    id::String

    function MLDSA(; lambda, p_err = 0.0, gamma, eta, tau)
        n = 256
        beta = eta * tau

        key_entry_range = (-eta):eta
        z_range = (-(gamma - beta - 1)):(gamma - beta - 1)
        informative_range = (-beta):(beta - 1)

        r = big(1) << (lambda - 1)
        _2r_range = (-r):(r - 1)
        _4r_range = (-2r):(2r - 1)

        return new{minimal_int_type((-4r):(4r))}(
            n, gamma, eta, tau, beta, lambda, p_err,
            key_entry_range, z_range, informative_range, r, _2r_range, _4r_range,
            "n=$(n),eta=$(eta),gamma=$(gamma),tau=$(tau),lambda=$(lambda),p_err=$(p_err)",
        )
    end
end

"""
    MLDSA44(; kwargs...)

ML-DSA-44 parameter set.
"""
MLDSA44(; kwargs...) = MLDSA(; gamma = 1 << 17, eta = 2, tau = 39, kwargs...)

"""
    MLDSA65(; kwargs...)

ML-DSA-65 parameter set.
"""
MLDSA65(; kwargs...) = MLDSA(; gamma = 1 << 19, eta = 4, tau = 49, kwargs...)

"""
    MLDSA87(; kwargs...)

ML-DSA-87 parameter set.
"""
MLDSA87(; kwargs...) = MLDSA(; gamma = 1 << 19, eta = 2, tau = 60, kwargs...)

"""
    generate_key(mldsa::MLDSA; rng)

Generate random signing key.
"""
function generate_key(mldsa::MLDSA; rng::AbstractRNG = default_rng())
    return rand(rng, mldsa.key_entry_range, mldsa.n)
end

struct SparseSignVector
    pos::Vector{UInt8}
    neg::Vector{UInt8}
end

function Base.hash(c::SparseSignVector, h::UInt)
    hash((c.pos, c.neg), h)
end

function dot(c::SparseSignVector, x::AbstractVector)
    res = 0
    @inbounds for idx in c.pos res += x[idx + 1] end
    @inbounds for idx in c.neg res -= x[idx + 1] end
    return res
end

"""
    Signatures{T}

Collection of generated signatures.
"""
struct Signatures{T}
    mldsa::MLDSA{T}
    id::String
    key::Union{Nothing, Vector{Int8}}
    count::Int

    cs::Vector{SparseSignVector}
    zs::Vector{T}

    """
        Signatures(mldsa; count, key, seed, filter_informative)

    Generate from scratch.
    """
    function Signatures(mldsa::MLDSA{T};
        count::Integer, key = nothing, seed = rand(UInt),
        filter_informative::Bool = true,
    ) where {T}
        id = "$(mldsa.id),seed=$(seed)"

        isnothing(key) && (key = generate_key(mldsa; rng = Xoshiro("$(id)|key")))

        cs = Vector{SparseSignVector}(undef, count)
        zs = Vector{T}(undef, count)

        tasks = map(Iterators.partition(1:count, 10_000)) do chunk
            Threads.@spawn _generate_leaky_signatures!(cs, zs, chunk, mldsa, key;
                filter_informative, rng = Xoshiro("$(id)|sigs=$(chunk)"))
        end

        fetch.(tasks)

        return new{T}(mldsa, id, key, count, cs, zs)
    end

    """
        Signatures(mldsa, cs, zs, leaks; key)

    Construct from pre-computed values.
    """
    function Signatures(mldsa::MLDSA{T},
        cs::AbstractVector, zs::AbstractVector, leaks::AbstractVector;
        key = nothing,
    ) where {T}
        (; r, _4r_range) = mldsa

        cs = convert(Vector{SparseSignVector}, cs)
        zs = T[mod(z - 2r * b, _4r_range) for (z, b) in zip(zs, leaks)]

        id = "$(mldsa.id),hash=$(hash((cs, zs)))"

        return new{T}(mldsa, id, key, length(cs), cs, zs)
    end
end

function Base.length(sigs::Signatures)
    return sigs.count
end

function _generate_leaky_signatures!(cs::AbstractVector, zs::AbstractVector,
    chunk::AbstractUnitRange, mldsa::MLDSA, key::AbstractVector;
    filter_informative::Bool = true, rng::AbstractRNG = default_rng(),
)
    (; r, _4r_range) = mldsa

    @inbounds for i in chunk
        (c, z, b) = generate_leaky_signature(mldsa, key; filter_informative, rng)
        cs[i] = c
        zs[i] = mod(z - 2r * b, _4r_range)
    end
end

"""
    generate_leaky_signature(mldsa, key; filter_informative, rng)

Generate a single leaky signature.
"""
function generate_leaky_signature(mldsa::MLDSA, key::AbstractVector;
    filter_informative::Bool = true, rng::AbstractRNG = default_rng(),
)
    (; n, tau, z_range, p_err) = mldsa

    while true
        # Sample z and c independently, then derive y.
        # Per https://eprint.iacr.org/2026/580.pdf#lemma.16, this yields the
        # same distribution of (key, c, z, y) as in the problem definition.

        z = rand(rng, z_range)
        filter_informative && !is_informative(mldsa, z) && continue

        c = SparseSignVector(UInt8[], UInt8[])
        for idx in sample(rng, 0:(n - 1), tau; replace = false, ordered = true)
            push!(rand(rng, Bool) ? c.neg : c.pos, idx)
        end

        y = z - dot(c, key)

        b = leakage(mldsa, y)
        !iszero(p_err) && rand(rng) < p_err && (b = !b)

        return (c, z, b)
    end
end

"""
    is_informative(mldsa, z)

Check if signature with response `z` leaks information about the key.
"""
function is_informative(mldsa::MLDSA, z::Integer)
    return mod(z, mldsa._2r_range) in mldsa.informative_range
end

function leakage(mldsa::MLDSA, y::Integer)
    return mod(y, mldsa._4r_range) < 0
end

"""
    sig_violations(sigs, key_guess)

Count signature violations for a key guess.
"""
function sig_violations(sigs::Signatures, key_guess::AbstractVector)
    (; mldsa, cs, zs) = sigs

    return sum(leakage(mldsa, z - dot(c, key_guess)) for (c, z) in zip(cs, zs); init = 0)
end

"""
    key_violations(sigs, key_guess)

Count key entry mismatches.
"""
function key_violations(sigs::Signatures, key_guess::AbstractVector)
    isnothing(sigs.key) && return
    return count(key_guess .!= sigs.key)
end

"""
    key_guess(mldsa, key_estimate)

Clamp key estimate to valid key range.
"""
function key_guess(mldsa::MLDSA, key_estimate::AbstractVector)
    return [Int8(clamp(round(Int, v), mldsa.key_entry_range)) for v in key_estimate]
end
