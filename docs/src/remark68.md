# Remark 68

Computations for [Remark 68](https://eprint.iacr.org/2026/580.pdf#remark.68).

```@example remark68
using LeakyMLDSA

@show Threads.nthreads()

for (MLDSAParameterSet, p_err, lambda, n_inf, threads, timeout) in [
    (MLDSA44, 0.490, 4,   6_000_000,  1,  30),
    # (MLDSA44, 0.490, 8, 100_000_000,  1, 240),
    # (MLDSA65, 0.490, 9, 150_000_000,  1, 240),
    # (MLDSA87, 0.490, 8, 100_000_000,  1, 240),
    # (MLDSA44, 0.499, 4, 600_000_000, 64, 240),
]
    @info "running attack" p_err lambda n_inf threads

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
