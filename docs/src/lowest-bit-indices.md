# Lowest Bit Indices

See [Remark 30](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#remark.30).

Note that we don't set `initial_guess` in [`ContinuousNLPAttack`](@ref) and [`CombinatorialNLPAttack`](@ref), so the search always starts from the zero key.

```@example lowest_bit_indices
using LeakyMLDSA

for (MLDSAParameterSet, lambda, n_inf) in [
    (MLDSA44, 3, 1_000_000),
    (MLDSA65, 4, 2_000_000),
]
    @info "running attack" lambda n_inf

    mldsa = MLDSAParameterSet(; lambda)
    sigs = Signatures(mldsa; count = n_inf, seed = 0)

    elapsed = @elapsed result = begin
        attack = ContinuousNLPAttack(sigs;
            options = (; iterations = 25, show_trace = true))

        run_attack(attack)
    end

    if attack_succeeded(result)
        @info "succeeded in $(elapsed) s"
    else
        @warn "failed in $(elapsed) s" sig_violations(result) key_violations(result)
    end
end
```
