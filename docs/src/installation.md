# Installation

Jyce has two halves: the Julia package, and the native `xycesolver_julia`
module that embeds Xyce. The package installs like any other; the native module
has to be built against your Xyce and Trilinos installation.

## The Julia package

```julia
using Pkg
Pkg.develop(path = "/path/to/Jyce")   # or Pkg.add(url = ...)
```

Jyce loads without the native backend, which is enough to build circuits,
generate netlists and read previously written result files. Running
simulations needs the backend.

## Building the native backend

```bash
cd XyceSolver
cmake -S . -B build \
  -DBUILD_CXXWRAP_MODULE=ON \
  -DXYCE_ROOT=$HOME/XyceInstall/Serial \
  -DTRILINOS_ROOT=$HOME/XyceLibs/Serial \
  -DCMAKE_PREFIX_PATH=$(julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')
cmake --build build -j
```

Then point Jyce at the build:

```bash
export JYCE_XYCESOLVER_ROOT=/absolute/path/to/XyceSolver
```

## How the backend is located

[`Jyce.native_diagnostics`](@ref) reports the search in full. In order:

1. `XyceSolver_jll` products, when the package is available and
   `JYCE_PREFER_JLL=1` (the default).
2. `JYCE_XYCESOLVER_JULIA_LIB` - an absolute path to the module file.
3. `$JYCE_XYCESOLVER_ROOT/lib/xycesolver_julia.<ext>`
4. `$JYCE_XYCESOLVER_ROOT/build/xycesolver_julia.<ext>`
5. `Jyce/lib/xycesolver_julia.<ext>`
6. `../XyceSolver/build/xycesolver_julia.<ext>` (monorepo layout)

## Environment variables

| Variable | Effect |
|:--|:--|
| `JYCE_XYCESOLVER_JULIA_LIB` | absolute path to the CxxWrap module |
| `JYCE_XYCESOLVER_ROOT` | XyceSolver build or install root |
| `JYCE_PREFER_JLL` | set to `0` to skip the JLL lookup |
| `JYCE_ALLOW_MISSING_NATIVE` | set to `1` to import Jyce without the backend |

## Checking the installation

```julia
using Jyce
native_available()          # true when simulations can run
print_native_diagnostics()  # what was searched, what was found
```

From the shell:

```bash
julia --project scripts/diagnose_native.jl   # report the search
julia --project scripts/smoke_native.jl      # load and run a minimal netlist
julia --project scripts/probe_load_stage.jl  # netlist loading only, no run
```

If `probe_load_stage.jl` succeeds and `smoke_native.jl` fails, the problem is
in simulator initialisation rather than netlist parsing.

## Continuous integration

Set `JYCE_ALLOW_MISSING_NATIVE=1` for jobs that build documentation or test
netlist generation on machines without Xyce. The package imports, and
[`native_available`](@ref) returns `false`.

The repository includes `.github/workflows/Documenter.yml`, which builds the
docs on pushes to `master` and publishes them to GitHub Pages.
