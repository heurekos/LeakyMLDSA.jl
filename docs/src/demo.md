# Demo

### Setup

We begin by loading the package:

```@example demo
using LeakyMLDSA
```

Let's gather some info about the running Julia instance and the system -- in particular, the number of threads available (see [Multi-Threading](https://docs.julialang.org/en/v1/manual/multi-threading/) in the Julia documentation for instructions on how to change this):

```@example demo
using InteractiveUtils; versioninfo()
```

### Helper Functions

Let's define a convenience function that, for a given key guess, prints the number of violated signatures and the number of recovered key entries:

```@example demo
function evaluate_key_guess(sigs::Signatures, key_guess::AbstractVector{<: Integer})
    @info "signatures violated: $(sig_violations(sigs, key_guess))"
    @info "key entries not recovered: $(key_violations(sigs, key_guess))"
end

nothing # hide
```

### Parameter Choice

First, we select ML-DSA-44 with exact leakage ($p_\mathsf{err} = 0$) from the lowest bit index $\lambda = 4$ for which the attacks succeed. We can explore other parameter choices later.

```@example demo
mldsa = MLDSA44(; p_err = 0.0, lambda = 4)
# mldsa = MLDSA44(; p_err = 0.2, lambda = 4)
# mldsa = MLDSA65(; p_err = 0.0, lambda = 9)
# mldsa = MLDSA44(; p_err = 0.3, lambda = 8)
```

### Signature Generation

We then generate as many informative signatures with leakage as specified by [`n_inf_hint`](@ref), an exported function that estimates a number typically more than sufficient for key recovery.
The estimate is based on the upper bound $n_\mathsf{inf,upper}$ (see [Figure 1](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#figure.1) and [Section 4.3](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#subsection.4.3)).
 A seed is provided for reproducibility.

```@example demo
sigs = Signatures(mldsa; count = n_inf_hint(mldsa), seed = 0)

length(sigs)
```

The secret key is stored together with the signatures as `sigs.key`. In the case of exact leakage, supplying the correct key as the guess results in no violations:

```@example demo
evaluate_key_guess(sigs, sigs.key)
```

### NLP Attack

[`NLPAttack`](@ref) is the most convenient method for key recovery. In the first stage, it runs the continuous method (optionally, repeatedly with varying hyperparameters). In the final stage, it performs the combinatorial search starting from the best key guess identified earlier. In particular, when $p_\mathsf{err} > 0$, it is advisable to set a `timeout`.

```@example demo
nlp_attack = NLPAttack(sigs; timeout = 5)
nlp_result = run_attack(nlp_attack)

evaluate_key_guess(sigs, key_guess(nlp_result))
```

The attack is customizable. Below, we adjust the number of random hyperparameters to try for the continuous method. We also restrict the number of iterations used by [Optim.jl](https://julianlsolvers.github.io/Optim.jl/stable/) during gradient descent, specify the number of threads to use, set a timeout, and disable the display of intermediate progress.

```@example demo
nlp_attack = NLPAttack(sigs;
    hyperparameters = Hyperparameters(; iterations = 50, seed = 0),
    continuous_options = (; options = (; iterations = 20)),
    threads = 2, timeout = 300, show_progress = false,
)
nlp_result = run_attack(nlp_attack)

evaluate_key_guess(sigs, key_guess(nlp_result))
```

### Continuous Method

We can also run the continuous method on its own, avoiding the significantly slower combinatorial method. This is much faster, but it may fail to recover all key entries when the number of signatures is insufficient. Still, it should produce a key guess with relatively few signature violations:

```@example demo
continuous_attack = ContinuousNLPAttack(sigs)
continuous_result = run_attack(continuous_attack)

evaluate_key_guess(sigs, key_guess(continuous_result))
```

### Combinatorial Method

Similarly, the combinatorial method can be run on its own:

```@example demo
combinatorial_attack = CombinatorialNLPAttack(sigs;
    timeout = 120, show_progress = false,
)
combinatorial_result = run_attack(combinatorial_attack)

evaluate_key_guess(sigs, key_guess(combinatorial_result))
```

### Further Customization

For finer control, we can manually combine the continuous and combinatorial attacks instead of using [`NLPAttack`](@ref). For example, we can start the combinatorial search from a single guess produced by the continuous method as follows:

```@example demo
combinatorial_attack = CombinatorialNLPAttack(sigs;
    initial_guess = key_guess(continuous_result),
    timeout = 120, show_progress = false,
)
combinatorial_result = run_attack(combinatorial_attack)

evaluate_key_guess(sigs, key_guess(combinatorial_result))
```

Rather than relying on the predefined [`Hyperparameters`](@ref), we may also specify `hyperparameters` manually in [`NLPAttack`](@ref). For example, we can run the continuous method multiple times from different initial key guesses as follows:

```@example demo
import Random; rng = Random.Xoshiro(4711)

nlp_attack = NLPAttack(sigs;
    hyperparameters = ((; initial_guess = generate_key(mldsa; rng)) for _ in 1:100),
    combinatorial_options = nothing, show_progress = false,
)
nlp_result = run_attack(nlp_attack)

evaluate_key_guess(sigs, key_guess(nlp_result))
```
