using Documenter
using LeakyMLDSA

const sitename = "LeakyMLDSA.jl"
const remote = Documenter.Remotes.GitHub("heurekos", "LeakyMLDSA.jl")
const branch = "ches-submission"
const remotes = Dict(dirname(@__DIR__) => (remote, branch))
const repo = "github.com/$(remote.user)/$(remote.repo)"
const format = Documenter.HTML(;
    edit_link = branch,
    repolink = "https://$(repo)/tree/$(branch)",
)
const pages = [
    "Package" => [
        "index.md",
        "demo.md",
    ],
    "Examples" => [
        "featured.md",
        "real-world.md",
        "high-noise.md",
        "lowest-bit-indices.md",
        "bp-comparison.md",
        "required-signatures.md",
    ],
    "API Reference" => [
        "api.md",
    ],
]

# If page names are provided as command-line arguments, include only those pages.
if !isempty(ARGS)
    included = Set(ARGS)
    foreach(pages) do (_, md_file)
        filter!(in(included), md_file)
    end
end

makedocs(; sitename, remotes, format, pages, pagesonly = true)

if get(ENV, "GITHUB_ACTIONS", nothing) == "true"
    deploydocs(; repo, devbranch = branch, dirname = branch)
end
