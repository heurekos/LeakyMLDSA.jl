# Remark 69

Computations for [Remark 69](https://eprint.iacr.org/2026/580.pdf#remark.69).

Note that we don't set `initial_guess` in `ContinuousNLPAttack` and `CombinatorialNLPAttack`, so the search always starts from the zero key.

```@example remark69
using LeakyMLDSA

mldsa = MLDSA44(; lambda = 3)

for (AttackType, n_inf, seed) in [
    (   ContinuousNLPAttack, 20_000, 3418)
    (CombinatorialNLPAttack, 75_000,  518)
]
    @info "running attack" (AttackType, n_inf, seed)

    elapsed = @elapsed result = begin
        sigs = Signatures(mldsa; count = n_inf, seed)

        attack = AttackType(sigs)
        run_attack(attack)
    end

    key_entries = join(map(v -> v => count(==(v), sigs.key), mldsa.key_entry_range), ", ")
    if attack_succeeded(result)
        @info "succeeded in $(elapsed) s" key_entries
    else
        @warn "failed in $(elapsed) s" sig_violations(result) key_violations(result) key_entries
    end
end
```

The continuous-method example might not reproduce with the same seed across Julia versions and package setups. If the example fails, another working seed is usually easy to find:

```@example remark69
for seed in Iterators.countfrom(0)
    sigs = Signatures(mldsa; count = 100_000, seed)

    attack = ContinuousNLPAttack(sigs)
    result = run_attack(attack)

    if attack_succeeded(result)
        key_entries = join(map(v -> v => count(==(v), sigs.key), mldsa.key_entry_range), ", ")
        @info "succeeded with" seed key_entries
        break
    end
end
```
