# Required Signatures

*Determination of the number of informative signatures required for key recovery using the NLP attack.*

The data files `data/{exact,noisy}/{MLDSA44,MLDSA65,MLDSA87}.json` were generated using a beta version of this package.
Since generating these files was computationally expensive, we did not regenerate them using the current version.
We include these files merely to document the values shown in [Figure 10](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#figure.10) and [Figure 11](https://heurekos.github.io/LeakyMLDSA.jl/tches2027_1-paper208.pdf#figure.11), which the code below computes from these files.

### Helper Functions

```@example required_signatures
using DataFrames
using JSON
using PrettyTables

function print_statistics(identifier; dir = joinpath(@__DIR__, "../../data"))
    df = DataFrame(; lambda = Int[], p_err = Float64[], nsigs = Int[])

    for experiment in JSON.parsefile(joinpath(dir, "$(identifier).json"))
        p = experiment["parameters"]
        push!(df, (p["lambda"], p["p_err"],
            minimum(r["nsigs"] for r in experiment["history"] if r["success"])))
    end

    df = combine(groupby(df, [:lambda, :p_err]),
        :nsigs => (v -> sum(v) / length(v)),
        :nsigs => minimum,
        :nsigs => maximum)

    println()
    pretty_table(sort!(df, [:lambda, :p_err]);
        title = identifier,
        column_labels = ["λ", "p_err", "Average", "Minimum", "Maximum"],
        formatters = [fmt__printf("%.2f", [2]), fmt__printf("%.0f", [3])],
        minimum_data_column_widths = [0, 0, 10, 10, 10],
        display_size = (-1, -1))
end

nothing # hide
```

### Exact Leakage

Across 100 experiments per row, we obtain for the number of signatures required for key recovery:

```@example required_signatures
for parameter_set in ["MLDSA44", "MLDSA65", "MLDSA87"]
    print_statistics("exact/$(parameter_set)")
end
```

### Noisy Leakage

Across 10 experiments per row, we obtain for the number of signatures required for key recovery:

```@example required_signatures
for parameter_set in ["MLDSA44", "MLDSA65", "MLDSA87"]
    print_statistics("noisy/$(parameter_set)")
end
```
