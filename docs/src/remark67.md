# Remark 67

Computations for [Remark 67](https://eprint.iacr.org/2026/580.pdf#remark.67).

```@example remark67
using LeakyMLDSA

for (p_err, lambda, n_inf) in [
    (0.00, 4,     1_500),
    (0.00, 5,     3_000),
    (0.00, 6,     6_000),
    (0.00, 7,     9_000),
    (0.00, 8,    12_000),
    (0.45, 4,   200_000),
    (0.45, 5,   400_000),
    (0.45, 6,   800_000),
    (0.45, 7, 1_600_000),
    (0.45, 8, 3_200_000),
]
    @info "running attack" p_err lambda n_inf

    elapsed = @elapsed result = begin
        mldsa = MLDSA44(; p_err, lambda)
        sigs = Signatures(mldsa; count = n_inf, seed = 0)

        attack = ContinuousNLPAttack(sigs)

        attack = CombinatorialNLPAttack(sigs;
            initial_guess = key_guess(run_attack(attack)), timeout = 300)

        run_attack(attack)
    end

    if attack_succeeded(result)
        @info "succeeded in $(elapsed) s"
    else
        @warn "failed in $(elapsed) s" sig_violations(result) key_violations(result)
    end
end
```
