# Build the Jyce documentation:
#
#     julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
#     julia --project=docs docs/make.jl
#
# The native Xyce backend is not required: netlist generation, the API
# reference and the doctests all run without it.
ENV["JYCE_ALLOW_MISSING_NATIVE"] = "1"
ENV["GKSwstype"] = "100"   # headless plotting

using Documenter
using Jyce

DocMeta.setdocmeta!(Jyce, :DocTestSetup, :(using Jyce); recursive = true)

# Set JYCE_DOCS_REPO (e.g. "github.com/MadebyDaris/Jyce.jl") or rely on
# GITHUB_REPOSITORY in CI to enable the "edit on GitHub" links and
# documentation deployment. Without either value the site builds standalone,
# which also works in a clone that has no git remote.
const REPO = let
    docs_repo = get(ENV, "JYCE_DOCS_REPO", "")
    github_repo = get(ENV, "GITHUB_REPOSITORY", "")
    if !isempty(docs_repo)
        docs_repo
    elseif !isempty(github_repo)
        "github.com/" * github_repo
    else
        ""
    end
end
const DEPLOY = !isempty(REPO) && get(ENV, "GITHUB_EVENT_NAME", "") != "pull_request"

settings = (;
    modules = [Jyce],
    authors = "MadebyDaris <daris.idirene@gmail.com>",
    sitename = "Jyce.jl",
    format = Documenter.HTML(;
        canonical = "https://MadebyDaris.github.io/Jyce.jl",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Installation" => "installation.md",
        "Getting started" => "getting_started.md",
        "Manual" => [
            "Building circuits" => "manual/circuits.md",
            "Analyses and probes" => "manual/analyses.md",
            "Running simulations" => "manual/running.md",
            "Results" => "manual/results.md",
            "Parameter sweeps" => "manual/sweeps.md",
            "Netlist interop" => "manual/netlists.md",
            "Verilog-A plugins" => "manual/plugins.md",
            "Plotting" => "manual/plotting.md",
        ],
        "Examples" => "examples.md",
        "API reference" => "api.md",
        "Migrating from 0.1" => "migration.md",
        "Roadmap" => "roadmap.md",
    ],
    checkdocs = :exports,
    doctest = true,
)

if !DEPLOY
    makedocs(; settings..., remotes = nothing)
else
    makedocs(; settings..., repo = REPO)
    deploydocs(; repo = REPO, devbranch = "master")
end
