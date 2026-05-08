# Guide

This Julia package provides the NLP attack described in [Section 6](https://eprint.iacr.org/2026/580.pdf#section.6) of the [IACR ePrint 2026/580](https://eprint.iacr.org/2026/580).

## Installation

Once Julia is [installed](https://julialang.org/install/), the package can be added using the [package manager](https://docs.julialang.org/en/v1/stdlib/Pkg/):

```julia
julia> using Pkg
julia> Pkg.develop(; url = "https://github.com/heurekos/LeakyMLDSA.jl.git")
```

This installs the package in development mode, cloning from the GitHub repository.

## Quick Start

```@example
using LeakyMLDSA

mldsa = MLDSA44(; p_err = 0.0, lambda = 6)
sigs = Signatures(mldsa; count = 5000, seed = 0)
result = run_attack(NLPAttack(sigs; timeout = 60))

key_guess(result) == sigs.key
```

See the [Demo](demo.md) page for a more detailed walkthrough.
