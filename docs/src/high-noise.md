# High Noise

See [Remark 32](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#remark.32).

```@example high_noise
using LeakyMLDSA

@show Threads.nthreads()

for (MLDSAParameterSet, p_err, lambda, n_inf, threads, timeout, memlimit) in [
    (MLDSA44, 0.490, 4,   6_000_000,  1,  30,   4 * 2^30),
    (MLDSA44, 0.490, 8, 100_000_000,  1, 240,  80 * 2^30),
    (MLDSA65, 0.490, 9, 150_000_000,  1, 240,  80 * 2^30),
    (MLDSA87, 0.490, 8, 100_000_000,  1, 240,  80 * 2^30),
    (MLDSA44, 0.499, 4, 600_000_000, 64, 240, 160 * 2^30),
]
    if Sys.free_memory() < memlimit
        @info "skipping attack" p_err lambda n_inf
        continue
    else
        @info "running attack" p_err lambda n_inf threads
    end

    mldsa = MLDSAParameterSet(; p_err, lambda)
    sigs = Signatures(mldsa; count = n_inf, seed = 0)

    elapsed = @elapsed result = begin
        attack = ContinuousNLPAttack(sigs; threads,
            options = (; iterations = 25, show_trace = true))

        attack = CombinatorialNLPAttack(sigs; threads, timeout,
            initial_guess = key_guess(run_attack(attack)))

        run_attack(attack)
    end

    if attack_succeeded(result)
        @info "succeeded in $(elapsed) s"
    else
        @warn "failed in $(elapsed) s" sig_violations(result) key_violations(result)
    end
end
```
