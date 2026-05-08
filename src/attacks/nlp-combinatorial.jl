import DataStructures: BinaryHeap
import StaticArrays: SVector

"""
    CombinatorialNLPAttack(sigs; initial_guess, diff_max, queue_max, visit_max, timeout, show_progress) -> CombinatorialNLPAttack{T}

Combinatorial NLP attack using best-first search over integer lattice.

# Arguments
- `sigs::Signatures{T}`: signatures to attack
- `initial_guess::Vector{Int8}`: initial key guess
- `diff_max::Int`: maximum allowed increase in signature violations
- `queue_max::Int`: maximum queue size
- `visit_max::Int`: maximum number of vertices to visit
- `timeout::Int`: time limit in seconds
- `show_progress::Bool`: whether to display a progress meter
"""
struct CombinatorialNLPAttack{T} <: Attack{T}
    sigs::Signatures{T}

    initial_guess::Vector{Int8}
    chunks::Vector{UnitRange{Int}}

    diff_max::Int
    queue_max::Int
    visit_max::Int
    timeout::Int
    Log::Union{Nothing, Type}

    function CombinatorialNLPAttack(sigs::Signatures{T};
        initial_guess = zeros(Int8, sigs.mldsa.n),
        diff_max = 0, queue_max = 1_000_000, visit_max = 1_000_000,
        threads = Threads.nthreads(), chunksize_min = 2_500,
        timeout = typemax(Int), show_progress = false,
        Log = show_progress ? ProgressLog : nothing,
    ) where {T}
        chunks = partition(1:length(sigs), threads; chunksize_min)

        return new{T}(sigs,
            initial_guess, chunks,
            diff_max, queue_max, visit_max, timeout, Log)
    end
end

struct CombinatorialNLPAttackResult <: AttackResult{CombinatorialNLPAttack}
    attack::CombinatorialNLPAttack
    key_guess::Vector{Int8}
    violations::Int
end

"""
    run_attack(attack::CombinatorialNLPAttack)

Run combinatorial NLP attack.
"""
function run_attack(attack::CombinatorialNLPAttack)
    (; sigs, queue_max, visit_max, timeout, Log) = attack
    (; visited, queue, visit) = build_model(attack)

    guess = nothing
    best_violations = length(sigs) + 1

    isnothing(Log) || (log = Log())
    starttime = time()

    while !isempty(queue)
        v = pop!(queue)

        if v.violations < best_violations
            guess = v.x
            best_violations = Int(v.violations)
        end

        isnothing(Log) || log_progress!(log, best_violations;
            desc = "combinatorial search",
            values = [
                "key entries not recovered" => key_violations(sigs, guess),
                "vertices visited" => length(visited),
                "vertices in queue" => length(queue),
        ])

        length(queue) > queue_max && break
        length(visited) > visit_max && break
        time() - starttime > timeout && break
        v.violations == 0 && break

        visit(v)
    end

    return CombinatorialNLPAttackResult(attack, guess, best_violations)
end

struct QueuedVertex{N, T}
    x::SVector{N, Int8}
    violations::Int32
end

function build_model(attack::CombinatorialNLPAttack{T}) where {T}
    (; sigs, initial_guess, chunks, diff_max) = attack
    (; mldsa, cs, zs) = sigs
    (; n, _2r_range, _4r_range, r, key_entry_range) = mldsa

    lower = first(key_entry_range)
    upper = last(key_entry_range)

    visited = Set{SVector{n, Int8}}()
    queue = BinaryHeap(Base.By(v -> v.violations), QueuedVertex{n, T}[])

    function record_visit(x, violations)
        push!(visited, x)
        push!(queue, QueuedVertex{n, T}(x, violations))
    end

    function visit_neighbor(v, j, x_j, diff)
        diff > diff_max && return

        x = @inbounds Base.setindex(v.x, x_j, j)
        x in visited || record_visit(x, v.violations + diff)
    end

    diff_l = Vector{Int32}(undef, n)
    diff_u = Vector{Int32}(undef, n)

    if length(chunks) == 1
        execution_mode = SingleThreaded()
    else
        execution_mode = MultiThreaded()
        _diff_ls = [Vector{Int32}(undef, n) for _ in 1:length(chunks)]
        _diff_us = [Vector{Int32}(undef, n) for _ in 1:length(chunks)]
    end

    function visit(v)
        _visit(v.x, execution_mode)

        @inbounds for (j, x_j) in enumerate(v.x)
            x_j > lower && visit_neighbor(v, j, x_j - 1, diff_l[j])
            x_j < upper && visit_neighbor(v, j, x_j + 1, diff_u[j])
        end
    end

    function _visit(x, ::SingleThreaded)
        _visit(x, diff_l, diff_u, chunks[])
    end

    function _visit(x, ::MultiThreaded)
        fill!(diff_l, 0)
        fill!(diff_u, 0)

        tasks = map(zip(chunks, _diff_ls, _diff_us)) do (chunk, _diff_l, _diff_u)
            Threads.@spawn _visit(x, _diff_l, _diff_u, chunk)
        end

        for (_diff_l, _diff_u) in fetch.(tasks)
            diff_l += _diff_l
            diff_u += _diff_u
        end
    end

    function _visit(x, _diff_l, _diff_u, chunk)
        fill!(_diff_l, 0)
        fill!(_diff_u, 0)

        @inbounds for i in chunk
            c = cs[i]
            s = mod(zs[i] - dot(c, x) - r, _4r_range)

            if s == first(_2r_range)
                for idx in c.pos _diff_u[idx + 1] += 1 end
                for idx in c.neg _diff_l[idx + 1] += 1 end
            elseif s == last(_2r_range)
                for idx in c.pos _diff_l[idx + 1] += 1 end
                for idx in c.neg _diff_u[idx + 1] += 1 end
            elseif s == first(_2r_range) - 1
                for idx in c.pos _diff_l[idx + 1] -= 1 end
                for idx in c.neg _diff_u[idx + 1] -= 1 end
            elseif s == last(_2r_range) + 1
                for idx in c.pos _diff_u[idx + 1] -= 1 end
                for idx in c.neg _diff_l[idx + 1] -= 1 end
            end
        end

        return (_diff_l, _diff_u)
    end

    record_visit(initial_guess, sig_violations(sigs, initial_guess))

    return (; visited, queue, visit)
end
