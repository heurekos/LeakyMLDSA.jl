# Belief Propagation

*Comparison with the BP-based hint solver from [IACR ePrint 2024/1211](https://eprint.iacr.org/2024/1211).*

See [Remark 33](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#remark.33).

This section assumes a Linux system with all prerequisites for building [juliusjh/distribution\_hints\_solvers](https://github.com/juliusjh/distribution_hints_solvers) in place.

### Building the Hint Solver

We begin by building the hint solver for all required values of the build-time constant `SZ_MSG`, which must be set to $2\eta + 1$ for the targeted parameter set.

```@example hint_solver
function build_hint_solvers(sz_msgs::AbstractVector{Int};
    hsdir = mktempdir(),
    hsrepo = "https://github.com/juliusjh/distribution_hints_solvers",
    hscommit = "b21a406622e5e8d7deee437212bc9453e1e0695d",
)
    pybin = joinpath(hsdir, ".venv", "bin", "python")
    hscfg = joinpath(hsdir, "src", "constants.rs")
    hslib = joinpath(hsdir, "src", "lib.rs")
    hspkg = joinpath(hsdir, "Cargo.toml")

    redirect_stdout(devnull) do; redirect_stderr(devnull) do
        if !isdir(joinpath(hsdir, ".git"))
            mkpath(hsdir)
            cd(hsdir) do
                run(`git clone $hsrepo .`)
                run(`git checkout $hscommit`)
                run(`python3 -m venv .venv`)
                run(`$pybin -m pip install maturin`)
            end
        end

        for sz in sz_msgs
            hsso = joinpath(hsdir, "target", "release", "libhint_solver_$sz.so")
            if !isfile(hsso)
                cd(hsdir) do
                    write(hscfg, replace(read(hscfg, String),
                        r"SZ_MSG: usize = [0-9]+" => "SZ_MSG: usize = $sz"))
                    for path in (hslib, hspkg)
                        write(path, replace(read(path, String),
                            r"hint_solver[0-9_]*" => "hint_solver_$sz"))
                    end
                    run(addenv(`$pybin -m maturin develop --release`,
                        "PYO3_USE_ABI3_FORWARD_COMPATIBILITY" => "1"))
                end
                @assert isfile(hsso)
            end
        end
    end; end

    return pybin
end

ENV["JULIA_PYTHONCALL_EXE"] = build_hint_solvers([2 * 2 + 1, 2 * 4 + 1])

nothing # hide
```

### Wrapping the Hint Solver

We then extend the `LeakyMLDSA` package by integrating the BP-based hint solver for key recovery.

```@example hint_solver
using LeakyMLDSA
using PythonCall

struct BPAttack{T} <: LeakyMLDSA.Attack{T}
    sigs::Signatures{T}

    threads::Int
    iterations::Int

    function BPAttack(sigs::Signatures{T};
        threads = Threads.nthreads(),
        iterations = 100,
    ) where {T}
        new{T}(sigs, threads, iterations)
    end
end

struct BPAttackResult <: LeakyMLDSA.AttackResult{BPAttack}
    attack::BPAttack
    key_guess::Vector{Int8}
end

function LeakyMLDSA.run_attack(attack::BPAttack)
    (; sigs, threads, iterations) = attack
    (; mldsa, cs, zs) = sigs
    (; n, eta, beta, p_err) = mldsa

    eqs = [zeros(Int8, n) for _ in 1:length(sigs)]
    rhs = Vector{Vector{Tuple{Int16, Float64}}}(undef, length(sigs))

    for (i, (c, z)) in enumerate(zip(cs, zs))
        for idx in c.pos eqs[i][idx + 1] = +1 end
        for idx in c.neg eqs[i][idx + 1] = -1 end

        rhs[i] = [(s, LeakyMLDSA.leakage(mldsa, z - s) ? p_err : 1.0 - p_err)
            for s in -beta:beta]
    end

    bp = pyimport("hint_solver_$(2eta + 1)").PyBP(eqs, rhs)
    bp.set_nthreads(threads)
    for _ in 1:iterations
        bp.propagate()
    end

    results = pyconvert(Vector{Vector{Float64}}, bp.get_results())
    from_compl(v) = v > eta ? v - 2eta - 1 : v
    guess = [from_compl(argmax(results[i]) - 1) for i in 1:n]

    return BPAttackResult(attack, guess)
end

nothing # hide
```

### Helper Functions

We use binary search to locate the minimum number of signatures required for key recovery by `BPAttack`:

```@example hint_solver
function binary_search(; step, lower = 1, upper, predicate)
    (l, h) = (fld(lower, step), fld(upper, step))

    predicate(h * step) || return nothing

    while h - l > 1
        m = (l + h) ÷ 2
        if predicate(m * step); h = m; else; l = m; end
    end

    return h * step
end

nothing # hide
```

Starting from the threshold identified by the binary search, we then perform a local search to determine the minimum number of signatures required by [`NLPAttack`](@ref):

```@example hint_solver
function local_search(; step, lower = 1, upper, pos, predicate)
    if predicate(pos)
        while true
            pos -= step
            (pos < lower || !predicate(pos)) && return pos + step
        end
    else
        while true
            pos += step
            pos > upper && return nothing
            predicate(pos) && return pos
        end
    end
end

nothing # hide
```

### Running the Comparison

We now run a selected set of experiments (targeting a precision of slightly above 2%):

```@example hint_solver
results = NamedTuple[]

(scheme, p_err, seed) = (:MLDSA44, 0.0, 0)
for lambda in 4:8
    mldsa = (@eval $scheme)(; p_err, lambda)
    sigs(n) = Signatures(mldsa; count = n, seed)

    upper = n_inf_hint(mldsa)
    step = round(Int, 0.02 * upper)

    n_sig_bp = binary_search(; step, upper, predicate = n -> begin
        attack_succeeded(run_attack(BPAttack(sigs(n); iterations = 50)))
    end)

    n_sig_nlp = local_search(; step, upper, pos = n_sig_bp, predicate = n -> begin
        attack_succeeded(run_attack(NLPAttack(sigs(n);
            hyperparameters = Hyperparameters(; iterations = 50, seed = 0),
        )))
    end)

    push!(results, (; scheme, p_err, lambda, seed, step, n_sig_bp, n_sig_nlp))
end
```

Finally, let's display the relative difference in the number of signatures required:

```@example hint_solver
using DataFrames
using PrettyTables

df = transform!(DataFrame(results),
    [:n_sig_nlp, :n_sig_bp]
        => ((x, y) -> @. round(100 * (x / y - 1.); digits = 1))
        => :delta
)

pretty_table(df; column_labels =
    ["Parameter Set", "p_err", "λ", "Seed", "Step", "BP", "NLP", "NLP/BP-1 (%)"])
```

### Additional Experiments

The table below presents results from a more comprehensive set of runs:

```
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.0 │ 4 │    1 │   25 │    950 │    950 │          0.0 │
│       MLDSA44 │   0.0 │ 4 │    2 │   25 │   1025 │   1000 │         -2.4 │
│       MLDSA44 │   0.0 │ 4 │    3 │   25 │   1050 │   1050 │          0.0 │
│       MLDSA44 │   0.0 │ 4 │    4 │   25 │   1000 │    975 │         -2.5 │
│       MLDSA44 │   0.0 │ 4 │    5 │   25 │   1025 │   1025 │          0.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.0 │ 5 │    1 │   51 │   1938 │   1938 │          0.0 │
│       MLDSA44 │   0.0 │ 5 │    2 │   51 │   2040 │   2142 │          5.0 │
│       MLDSA44 │   0.0 │ 5 │    3 │   51 │   1938 │   1938 │          0.0 │
│       MLDSA44 │   0.0 │ 5 │    4 │   51 │   2091 │   2040 │         -2.4 │
│       MLDSA44 │   0.0 │ 5 │    5 │   51 │   1836 │   1785 │         -2.8 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.0 │ 6 │    1 │  104 │   4264 │   4368 │          2.4 │
│       MLDSA44 │   0.0 │ 6 │    2 │  104 │   4160 │   3848 │         -7.5 │
│       MLDSA44 │   0.0 │ 6 │    3 │  104 │   4160 │   4056 │         -2.5 │
│       MLDSA44 │   0.0 │ 6 │    4 │  104 │   3952 │   3952 │          0.0 │
│       MLDSA44 │   0.0 │ 6 │    5 │  104 │   3640 │   3536 │         -2.9 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.0 │ 7 │    1 │  210 │   8820 │   8820 │          0.0 │
│       MLDSA44 │   0.0 │ 7 │    2 │  210 │   9240 │   8190 │        -11.4 │
│       MLDSA44 │   0.0 │ 7 │    3 │  210 │   8190 │   7770 │         -5.1 │
│       MLDSA44 │   0.0 │ 7 │    4 │  210 │   8190 │   6930 │        -15.4 │
│       MLDSA44 │   0.0 │ 7 │    5 │  210 │   7770 │   7560 │         -2.7 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.0 │ 8 │    1 │  257 │   8481 │   8224 │         -3.0 │
│       MLDSA44 │   0.0 │ 8 │    2 │  257 │   9766 │  10023 │          2.6 │
│       MLDSA44 │   0.0 │ 8 │    3 │  257 │   9509 │   9509 │          0.0 │
│       MLDSA44 │   0.0 │ 8 │    4 │  257 │   9252 │   9252 │          0.0 │
│       MLDSA44 │   0.0 │ 8 │    5 │  257 │  10537 │  10794 │          2.4 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.0 │ 5 │    1 │   47 │   1833 │   1786 │         -2.6 │
│       MLDSA65 │   0.0 │ 5 │    2 │   47 │   2021 │   1974 │         -2.3 │
│       MLDSA65 │   0.0 │ 5 │    3 │   47 │   1833 │   1833 │          0.0 │
│       MLDSA65 │   0.0 │ 5 │    4 │   47 │   1880 │   1880 │          0.0 │
│       MLDSA65 │   0.0 │ 5 │    5 │   47 │   1786 │   1786 │          0.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.0 │ 6 │    1 │   96 │   3552 │   3744 │          5.4 │
│       MLDSA65 │   0.0 │ 6 │    2 │   96 │   3552 │   3744 │          5.4 │
│       MLDSA65 │   0.0 │ 6 │    3 │   96 │   3552 │   3552 │          0.0 │
│       MLDSA65 │   0.0 │ 6 │    4 │   96 │   3264 │   3360 │          2.9 │
│       MLDSA65 │   0.0 │ 6 │    5 │   96 │   3936 │   3744 │         -4.9 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.0 │ 7 │    1 │  195 │   8190 │   7800 │         -4.8 │
│       MLDSA65 │   0.0 │ 7 │    2 │  195 │   8970 │   7995 │        -10.9 │
│       MLDSA65 │   0.0 │ 7 │    3 │  195 │   7215 │   7215 │          0.0 │
│       MLDSA65 │   0.0 │ 7 │    4 │  195 │   6240 │   6435 │          3.1 │
│       MLDSA65 │   0.0 │ 7 │    5 │  195 │   8385 │   7800 │         -7.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.0 │ 8 │    1 │  392 │  13720 │  14112 │          2.9 │
│       MLDSA65 │   0.0 │ 8 │    2 │  392 │  14112 │  14112 │          0.0 │
│       MLDSA65 │   0.0 │ 8 │    3 │  392 │  14504 │  14896 │          2.7 │
│       MLDSA65 │   0.0 │ 8 │    4 │  392 │  15288 │  15288 │          0.0 │
│       MLDSA65 │   0.0 │ 8 │    5 │  392 │  12936 │  13328 │          3.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.0 │ 9 │    1 │  602 │  21070 │  22876 │          8.6 │
│       MLDSA65 │   0.0 │ 9 │    2 │  602 │  21672 │  20468 │         -5.6 │
│       MLDSA65 │   0.0 │ 9 │    3 │  602 │  21672 │  20468 │         -5.6 │
│       MLDSA65 │   0.0 │ 9 │    4 │  602 │  22274 │  22274 │          0.0 │
│       MLDSA65 │   0.0 │ 9 │    5 │  602 │  19866 │  19264 │         -3.0 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.0 │ 4 │    1 │   50 │    800 │   1200 │         50.0 │
│       MLDSA87 │   0.0 │ 4 │    2 │   50 │    850 │   1100 │         29.4 │
│       MLDSA87 │   0.0 │ 4 │    3 │   50 │    800 │   1150 │         43.8 │
│       MLDSA87 │   0.0 │ 4 │    4 │   50 │   1000 │   1200 │         20.0 │
│       MLDSA87 │   0.0 │ 4 │    5 │   50 │    800 │   1250 │         56.2 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.0 │ 5 │    1 │   40 │   1480 │   1480 │          0.0 │
│       MLDSA87 │   0.0 │ 5 │    2 │   40 │   1480 │   1480 │          0.0 │
│       MLDSA87 │   0.0 │ 5 │    3 │   40 │   1640 │   1600 │         -2.4 │
│       MLDSA87 │   0.0 │ 5 │    4 │   40 │   1600 │   1600 │          0.0 │
│       MLDSA87 │   0.0 │ 5 │    5 │   40 │   1680 │   1640 │         -2.4 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.0 │ 6 │    1 │   82 │   3198 │   3362 │          5.1 │
│       MLDSA87 │   0.0 │ 6 │    2 │   82 │   3362 │   3444 │          2.4 │
│       MLDSA87 │   0.0 │ 6 │    3 │   82 │   3116 │   3198 │          2.6 │
│       MLDSA87 │   0.0 │ 6 │    4 │   82 │   2952 │   3116 │          5.6 │
│       MLDSA87 │   0.0 │ 6 │    5 │   82 │   3608 │   3362 │         -6.8 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.0 │ 7 │    1 │  167 │   6012 │   5845 │         -2.8 │
│       MLDSA87 │   0.0 │ 7 │    2 │  167 │   6179 │   5344 │        -13.5 │
│       MLDSA87 │   0.0 │ 7 │    3 │  167 │   6680 │   6680 │          0.0 │
│       MLDSA87 │   0.0 │ 7 │    4 │  167 │   6680 │   7181 │          7.5 │
│       MLDSA87 │   0.0 │ 7 │    5 │  167 │   5678 │   6012 │          5.9 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.0 │ 8 │    1 │  315 │  11340 │  11655 │          2.8 │
│       MLDSA87 │   0.0 │ 8 │    2 │  315 │  11970 │  11340 │         -5.3 │
│       MLDSA87 │   0.0 │ 8 │    3 │  315 │  12285 │  12285 │          0.0 │
│       MLDSA87 │   0.0 │ 8 │    4 │  315 │  12600 │  12600 │          0.0 │
│       MLDSA87 │   0.0 │ 8 │    5 │  315 │  12600 │  12285 │         -2.5 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.2 │ 4 │    1 │  123 │   3813 │   3936 │          3.2 │
│       MLDSA44 │   0.2 │ 4 │    2 │  123 │   3690 │   3813 │          3.3 │
│       MLDSA44 │   0.2 │ 4 │    3 │  123 │   4551 │   4182 │         -8.1 │
│       MLDSA44 │   0.2 │ 4 │    4 │  123 │   3813 │   3936 │          3.2 │
│       MLDSA44 │   0.2 │ 4 │    5 │  123 │   3813 │   3813 │          0.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.2 │ 5 │    1 │  256 │   7680 │   7168 │         -6.7 │
│       MLDSA44 │   0.2 │ 5 │    2 │  256 │   8192 │   8192 │          0.0 │
│       MLDSA44 │   0.2 │ 5 │    3 │  256 │   7936 │   7936 │          0.0 │
│       MLDSA44 │   0.2 │ 5 │    4 │  256 │   7424 │   6912 │         -6.9 │
│       MLDSA44 │   0.2 │ 5 │    5 │  256 │   8192 │   8448 │          3.1 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.2 │ 6 │    1 │  521 │  15109 │  15109 │          0.0 │
│       MLDSA44 │   0.2 │ 6 │    2 │  521 │  16151 │  16151 │          0.0 │
│       MLDSA44 │   0.2 │ 6 │    3 │  521 │  15630 │  16151 │          3.3 │
│       MLDSA44 │   0.2 │ 6 │    4 │  521 │  17714 │  16672 │         -5.9 │
│       MLDSA44 │   0.2 │ 6 │    5 │  521 │  15109 │  14588 │         -3.4 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.2 │ 7 │    1 │ 1052 │  29456 │  30508 │          3.6 │
│       MLDSA44 │   0.2 │ 7 │    2 │ 1052 │  28404 │  28404 │          0.0 │
│       MLDSA44 │   0.2 │ 7 │    3 │ 1052 │  33664 │  31560 │         -6.2 │
│       MLDSA44 │   0.2 │ 7 │    4 │ 1052 │  30508 │  30508 │          0.0 │
│       MLDSA44 │   0.2 │ 7 │    5 │ 1052 │  30508 │  31560 │          3.4 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA44 │   0.2 │ 8 │    1 │ 1284 │  32100 │  34668 │          8.0 │
│       MLDSA44 │   0.2 │ 8 │    2 │ 1284 │  34668 │  34668 │          0.0 │
│       MLDSA44 │   0.2 │ 8 │    3 │ 1284 │  34668 │  35952 │          3.7 │
│       MLDSA44 │   0.2 │ 8 │    4 │ 1284 │  39804 │  39804 │          0.0 │
│       MLDSA44 │   0.2 │ 8 │    5 │ 1284 │  37236 │  37236 │          0.0 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.2 │ 5 │    1 │  236 │   6844 │   6608 │         -3.4 │
│       MLDSA65 │   0.2 │ 5 │    2 │  236 │   7552 │   8024 │          6.2 │
│       MLDSA65 │   0.2 │ 5 │    3 │  236 │   7316 │   7080 │         -3.2 │
│       MLDSA65 │   0.2 │ 5 │    4 │  236 │   7080 │   7552 │          6.7 │
│       MLDSA65 │   0.2 │ 5 │    5 │  236 │   7080 │   6844 │         -3.3 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.2 │ 6 │    1 │  482 │  16870 │  16870 │          0.0 │
│       MLDSA65 │   0.2 │ 6 │    2 │  482 │  14460 │  15906 │         10.0 │
│       MLDSA65 │   0.2 │ 6 │    3 │  482 │  16870 │  15424 │         -8.6 │
│       MLDSA65 │   0.2 │ 6 │    4 │  482 │  14942 │  14942 │          0.0 │
│       MLDSA65 │   0.2 │ 6 │    5 │  482 │  15906 │  15906 │          0.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.2 │ 7 │    1 │  975 │  36075 │  31200 │        -13.5 │
│       MLDSA65 │   0.2 │ 7 │    2 │  975 │  26325 │  29250 │         11.1 │
│       MLDSA65 │   0.2 │ 7 │    3 │  975 │  30225 │  32175 │          6.5 │
│       MLDSA65 │   0.2 │ 7 │    4 │  975 │  31200 │  31200 │          0.0 │
│       MLDSA65 │   0.2 │ 7 │    5 │  975 │  29250 │  28275 │         -3.3 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.2 │ 8 │    1 │ 1960 │  60760 │  60760 │          0.0 │
│       MLDSA65 │   0.2 │ 8 │    2 │ 1960 │  60760 │  64680 │          6.5 │
│       MLDSA65 │   0.2 │ 8 │    3 │ 1960 │  62720 │  56840 │         -9.4 │
│       MLDSA65 │   0.2 │ 8 │    4 │ 1960 │  58800 │  60760 │          3.3 │
│       MLDSA65 │   0.2 │ 8 │    5 │ 1960 │  58800 │  56840 │         -3.3 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA65 │   0.2 │ 9 │    1 │ 3008 │ 108288 │ 111296 │          2.8 │
│       MLDSA65 │   0.2 │ 9 │    2 │ 3008 │ 108288 │ 105280 │         -2.8 │
│       MLDSA65 │   0.2 │ 9 │    3 │ 3008 │ 102272 │ 102272 │          0.0 │
│       MLDSA65 │   0.2 │ 9 │    4 │ 3008 │  90240 │  90240 │          0.0 │
│       MLDSA65 │   0.2 │ 9 │    5 │ 3008 │  93248 │  93248 │          0.0 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
┌───────────────┬───────┬───┬──────┬──────┬────────┬────────┬──────────────┐
│ Parameter Set │ p_err │ λ │ Seed │ Step │     BP │    NLP │ NLP/BP-1 (%) │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.2 │ 4 │    1 │  150 │   3600 │   4050 │         12.5 │
│       MLDSA87 │   0.2 │ 4 │    2 │  150 │   3600 │   3450 │         -4.2 │
│       MLDSA87 │   0.2 │ 4 │    3 │  150 │   3150 │   3750 │         19.0 │
│       MLDSA87 │   0.2 │ 4 │    4 │  150 │   3150 │   3750 │         19.0 │
│       MLDSA87 │   0.2 │ 4 │    5 │  150 │   2850 │   3000 │          5.3 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.2 │ 5 │    1 │  201 │   6432 │   6030 │         -6.2 │
│       MLDSA87 │   0.2 │ 5 │    2 │  201 │   6231 │   6834 │          9.7 │
│       MLDSA87 │   0.2 │ 5 │    3 │  201 │   6231 │   6231 │          0.0 │
│       MLDSA87 │   0.2 │ 5 │    4 │  201 │   6030 │   6030 │          0.0 │
│       MLDSA87 │   0.2 │ 5 │    5 │  201 │   6834 │   7035 │          2.9 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.2 │ 6 │    1 │  412 │  14420 │  11948 │        -17.1 │
│       MLDSA87 │   0.2 │ 6 │    2 │  412 │  16068 │  16480 │          2.6 │
│       MLDSA87 │   0.2 │ 6 │    3 │  412 │  13184 │  13184 │          0.0 │
│       MLDSA87 │   0.2 │ 6 │    4 │  412 │  13596 │  12360 │         -9.1 │
│       MLDSA87 │   0.2 │ 6 │    5 │  412 │  15244 │  14420 │         -5.4 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.2 │ 7 │    1 │  834 │  23352 │  24186 │          3.6 │
│       MLDSA87 │   0.2 │ 7 │    2 │  834 │  25020 │  25020 │          0.0 │
│       MLDSA87 │   0.2 │ 7 │    3 │  834 │  25854 │  25854 │          0.0 │
│       MLDSA87 │   0.2 │ 7 │    4 │  834 │  33360 │  33360 │          0.0 │
│       MLDSA87 │   0.2 │ 7 │    5 │  834 │  29190 │  29190 │          0.0 │
├───────────────┼───────┼───┼──────┼──────┼────────┼────────┼──────────────┤
│       MLDSA87 │   0.2 │ 8 │    1 │ 1573 │  53482 │  48763 │         -8.8 │
│       MLDSA87 │   0.2 │ 8 │    2 │ 1573 │  44044 │  40898 │         -7.1 │
│       MLDSA87 │   0.2 │ 8 │    3 │ 1573 │  45617 │  42471 │         -6.9 │
│       MLDSA87 │   0.2 │ 8 │    4 │ 1573 │  40898 │  44044 │          7.7 │
│       MLDSA87 │   0.2 │ 8 │    5 │ 1573 │  55055 │  50336 │         -8.6 │
└───────────────┴───────┴───┴──────┴──────┴────────┴────────┴──────────────┘
```
