# Jyce.jl

A Julia interface to the [Xyce](https://xyce.sandia.gov/) parallel electronic
simulator. Circuits are Julia values, simulations run in-process through the
C++ solver, and results come back as `DataFrame`s.

```julia
using Jyce

rc = @circuit "RC low-pass" begin
    V1 = VoltageSource(:in, :gnd, DC(0), AC(1))
    R1 = Resistor(:in, :out, 1e3)
    C1 = Capacitor(:out, :gnd, 1e-6)
end

res = simulate(rc, ACSweep(1, 100e3); outputs = [vdb(:out), vphase(:out)])
plot_bode(res; node = :out)
```

## Why

Netlists are strings, and strings do not compose. A crossbar array, a Monte
Carlo run or a design sweep all want the circuit to be *computed* from a
matrix, a distribution, a fitted parameter set. Jyce keeps the circuit as data
so the whole language is available while building it, and drops down to raw
netlist text wherever Xyce offers something the wrapper does not model.

## Features

- **Typed circuit DSL** `Resistor`, `VoltageSource`, `MOSFET`,
  `Subcircuit`, `PluginDevice`, ... assembled into a `Circuit` you can
  generate, copy, parameterise and diff.
- **Analyses as values** `OperatingPoint`, `DCSweep`, `ACSweep`,
  `Transient`, `Noise`; one circuit, many runs.
- **Netlist escape hatches** run netlist strings or `.cir` files directly,
  or mix `RawCard`/`RawAnalysis` into a generated circuit.
- **Results as tables** `SimulationOutput` indexes by node, implements the
  Tables.jl interface, and carries the netlist that produced it.
- **Parameter sweeps** `sweep(ckt, analysis, :rload => values)`, with
  per-run reductions collected into a tidy `DataFrame`.
- **Verilog-A plugins** load compiled ADMS devices and instantiate them with
  `PluginDevice`.
- **Plotting** Plots.jl recipes plus ready-made transient, Bode and I-V
  figures.

## Installation

```julia
using Pkg
Pkg.develop(path = "/path/to/Jyce")
```

Simulations need the native `xycesolver_julia` module built from the companion
XyceSolver project:

```bash
cd ../XyceSolver
cmake -S . -B build -DBUILD_CXXWRAP_MODULE=ON \
  -DXYCE_ROOT=$HOME/XyceInstall/Serial \
  -DTRILINOS_ROOT=$HOME/XyceLibs/Serial \
  -DCMAKE_PREFIX_PATH=$(julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')
cmake --build build -j

export JYCE_XYCESOLVER_ROOT=/absolute/path/to/XyceSolver
```

Check it with `julia --project scripts/diagnose_native.jl`, or from Julia:

```julia
using Jyce
native_available()          # true when simulations can run
print_native_diagnostics()  # what was searched, what was found
```

Jyce imports without the backend (set `JYCE_ALLOW_MISSING_NATIVE=1`), which is
enough to build circuits, generate netlists and read result files.

## Documentation

Full documentation lives in [`docs/`](docs/src) and builds with Documenter:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

| Page | |
|:--|:--|
| [Installation](docs/src/installation.md) | backend setup, environment variables, diagnostics |
| [Getting started](docs/src/getting_started.md) | one session end to end |
| [Building circuits](docs/src/manual/circuits.md) | components, subcircuits, models, parameters |
| [Analyses and probes](docs/src/manual/analyses.md) | what to solve, what to print |
| [Running simulations](docs/src/manual/running.md) | `simulate`, failures, reusing simulators |
| [Results](docs/src/manual/results.md) | tables, columns, post-processing |
| [Parameter sweeps](docs/src/manual/sweeps.md) | design-space exploration, Monte Carlo |
| [Netlist interop](docs/src/manual/netlists.md) | existing `.cir` files, raw cards |
| [Verilog-A plugins](docs/src/manual/plugins.md) | compiled device models |
| [Plotting](docs/src/manual/plotting.md) | recipes and ready-made figures |
| [Migrating from 0.1](docs/src/migration.md) | old names to new ones |
| [Roadmap](docs/src/roadmap.md) | where this could go next |

## Examples

Twelve runnable scripts in [`examples/`](examples), from a voltage divider to a
memristive crossbar generated from a conductance matrix:

```bash
julia --project examples/01_voltage_divider.jl
```

## Compatibility

Everything the package exported before still works, including the native
`XyceSimulator` handle and `loadNetlistString`/`runSimulation`; see
[Migrating from 0.1](docs/src/migration.md).

## Project layout

```
src/
  Jyce.jl              module definition and exports
  backend/native.jl    locating and wrapping xycesolver_julia
  circuit/             values, sources, components, the Circuit type
  analysis/            analyses and output probes
  io/                  .prn/.csv readers, signal access, SimulationOutput
  simulator.jl         Simulator handle and `simulate`
  sweep.jl             parameter sweeps
  definitions.jl       subcircuits/includes/snippets held on a simulator
  plotting.jl          Plots recipes and figures
  compat.jl            pre-0.2 API
docs/                  Documenter site
examples/              runnable examples
scripts/               native diagnostics and smoke tests
plugins/               Verilog-A plugin build area
```
# Jyce.jl

A Julia interface to the [Xyce](https://xyce.sandia.gov/) parallel electronic
simulator. Circuits are Julia values, simulations run in-process through the
C++ solver, and results come back as `DataFrame`s.

```julia
using Jyce

rc = @circuit "RC low-pass" begin
    V1 = VoltageSource(:in, :gnd, DC(0), AC(1))
    R1 = Resistor(:in, :out, 1e3)
    C1 = Capacitor(:out, :gnd, 1e-6)
end

res = simulate(rc, ACSweep(1, 100e3); outputs = [vdb(:out), vphase(:out)])
plot_bode(res; node = :out)
```

## Why

Netlists are strings, and strings do not compose. A crossbar array, a Monte
Carlo run or a design sweep all want the circuit to be *computed* from a
matrix, a distribution, a fitted parameter set. Jyce keeps the circuit as data
so the whole language is available while building it, and drops down to raw
netlist text wherever Xyce offers something the wrapper does not model.

## Features

- **Typed circuit DSL** `Resistor`, `VoltageSource`, `MOSFET`,
  `Subcircuit`, `PluginDevice`, ... assembled into a `Circuit` you can
  generate, copy, parameterise and diff.
- **Analyses as values** `OperatingPoint`, `DCSweep`, `ACSweep`,
  `Transient`, `Noise`; one circuit, many runs.
- **Netlist escape hatches** run netlist strings or `.cir` files directly,
  or mix `RawCard`/`RawAnalysis` into a generated circuit.
- **Results as tables** `SimulationOutput` indexes by node, implements the
  Tables.jl interface, and carries the netlist that produced it.
- **Parameter sweeps** `sweep(ckt, analysis, :rload => values)`, with
  per-run reductions collected into a tidy `DataFrame`.
- **Verilog-A plugins** load compiled ADMS devices and instantiate them with
  `PluginDevice`.
- **Plotting** Plots.jl recipes plus ready-made transient, Bode and I-V
  figures.

## Installation

```julia
using Pkg
Pkg.develop(path = "/path/to/Jyce")
```

Simulations need the native `xycesolver_julia` module built from the companion
XyceSolver project:

```bash
cd ../XyceSolver
cmake -S . -B build -DBUILD_CXXWRAP_MODULE=ON \
  -DXYCE_ROOT=$HOME/XyceInstall/Serial \
  -DTRILINOS_ROOT=$HOME/XyceLibs/Serial \
  -DCMAKE_PREFIX_PATH=$(julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')
cmake --build build -j

export JYCE_XYCESOLVER_ROOT=/absolute/path/to/XyceSolver
```

Check it with `julia --project scripts/diagnose_native.jl`, or from Julia:

```julia
using Jyce
native_available()          # true when simulations can run
print_native_diagnostics()  # what was searched, what was found
```

Jyce imports without the backend (set `JYCE_ALLOW_MISSING_NATIVE=1`), which is
enough to build circuits, generate netlists and read result files.

## Documentation

Full documentation lives in [`docs/`](docs/src) and builds with Documenter:

```bash
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

| Page | |
|:--|:--|
| [Installation](docs/src/installation.md) | backend setup, environment variables, diagnostics |
| [Getting started](docs/src/getting_started.md) | one session end to end |
| [Building circuits](docs/src/manual/circuits.md) | components, subcircuits, models, parameters |
| [Analyses and probes](docs/src/manual/analyses.md) | what to solve, what to print |
| [Running simulations](docs/src/manual/running.md) | `simulate`, failures, reusing simulators |
| [Results](docs/src/manual/results.md) | tables, columns, post-processing |
| [Parameter sweeps](docs/src/manual/sweeps.md) | design-space exploration, Monte Carlo |
| [Netlist interop](docs/src/manual/netlists.md) | existing `.cir` files, raw cards |
| [Verilog-A plugins](docs/src/manual/plugins.md) | compiled device models |
| [Plotting](docs/src/manual/plotting.md) | recipes and ready-made figures |
| [Migrating from 0.1](docs/src/migration.md) | old names to new ones |
| [Roadmap](docs/src/roadmap.md) | where this could go next |

## Examples

Twelve runnable scripts in [`examples/`](examples), from a voltage divider to a
memristive crossbar generated from a conductance matrix:

```bash
julia --project examples/01_voltage_divider.jl
```

## Compatibility

Everything the package exported before still works, including the native
`XyceSimulator` handle and `loadNetlistString`/`runSimulation`; see
[Migrating from 0.1](docs/src/migration.md).

## Project layout

```
src/
  Jyce.jl              module definition and exports
  backend/native.jl    locating and wrapping xycesolver_julia
  circuit/             values, sources, components, the Circuit type
  analysis/            analyses and output probes
  io/                  .prn/.csv readers, signal access, SimulationOutput
  simulator.jl         Simulator handle and `simulate`
  sweep.jl             parameter sweeps
  definitions.jl       subcircuits/includes/snippets held on a simulator
  plotting.jl          Plots recipes and figures
  compat.jl            pre-0.2 API
docs/                  Documenter site
examples/              runnable examples
scripts/               native diagnostics and smoke tests
plugins/               Verilog-A plugin build area
```
