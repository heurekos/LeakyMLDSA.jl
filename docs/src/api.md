# Public API

```@meta
CurrentModule = LeakyMLDSA
```

## Parameter Sets

```@docs
MLDSA
MLDSA44
MLDSA65
MLDSA87
```

## Key and Signature Generation

```@docs
Signatures
generate_key
generate_leaky_signature
is_informative
```

## Attacks

```@docs
NLPAttack
ContinuousNLPAttack
CombinatorialNLPAttack
run_attack
attack_succeeded
key_guess
key_violations
sig_violations
```

## Parameter Tuning

```@docs
Hyperparameters
psi_none
psi_normal
psi_logistic
psi_cauchy
psi_sin
psi_box
psi_square
```
