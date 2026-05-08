using Documenter
using LeakyMLDSA

makedocs(;
    sitename = "LeakyMLDSA.jl",
    pages = [
        "Package" => [
            "index.md",
            "demo.md",
            "real-world.md"
        ],
        "Remarks" => [
            "remark67.md",
            "remark68.md",
            "remark69.md",
        ],
        "API Reference" => [
            "api.md",
        ],
    ],
    # remotes = nothing,
    # pagesonly = true,
)

deploydocs(; repo = "github.com/heurekos/LeakyMLDSA.jl")
