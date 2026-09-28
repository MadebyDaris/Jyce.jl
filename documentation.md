# Jyce documentation

The full documentation now lives in [`docs/`](docs/src) and builds with
Documenter:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Start here:

- [Installation](docs/src/installation.md) — building the native backend, environment variables, diagnostics.
- [Getting started](docs/src/getting_started.md) — build a circuit, run it, read the results.
- [Building circuits](docs/src/manual/circuits.md) — components, subcircuits, models, parameters, `@circuit`.
- [Analyses and probes](docs/src/manual/analyses.md) — `OperatingPoint`, `DCSweep`, `ACSweep`, `Transient`, `Noise`.
- [Running simulations](docs/src/manual/running.md) — `simulate`, failure handling, reusing a `Simulator`.
- [Results](docs/src/manual/results.md) — `SimulationOutput`, tables, post-processing.
- [Parameter sweeps](docs/src/manual/sweeps.md) — `sweep`, reductions, Monte Carlo.
- [Netlist interop](docs/src/manual/netlists.md) — netlist strings, `.cir` files, raw cards.
- [Verilog-A plugins](docs/src/manual/plugins.md) — compiled ADMS devices.
- [Plotting](docs/src/manual/plotting.md) — recipes, Bode and I-V figures.
- [API reference](docs/src/api.md) — every exported function, generated from the docstrings.
- [Migrating from 0.1](docs/src/migration.md) — the pre-0.2 names and what replaced them.
- [Roadmap](docs/src/roadmap.md) — candidate directions for the package.

Runnable examples are in [`examples/`](examples/README.md).
