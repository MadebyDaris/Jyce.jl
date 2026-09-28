# Jyce.jl

Jyce is a Julia interface to the [Xyce](https://xyce.sandia.gov/) parallel
electronic simulator. Circuits are Julia values, simulations run in-process
through the C++ solver, and results arrive as `DataFrame`s ready for analysis
and plotting.

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

## Why a Julia layer

Netlists are strings, and strings do not compose. A crossbar array, a Monte
Carlo run, or a design sweep all want the circuit to be *computed* - from a
matrix, a distribution, a fitted parameter set. Jyce keeps the circuit as data
(see [Building circuits](@ref)), so the whole language is available while
building it, and drops down to raw netlist text wherever Xyce offers something
the wrapper does not model (see [Netlist interop](@ref)).

## Three levels, one package

| Level | You write | Use when |
|:--|:--|:--|
| Circuit DSL | `Circuit`, `Resistor`, `Transient` | the circuit is generated, parameterised or reused |
| Netlist text | `simulate(netlist_string)`, `simulate_file(path)` | you already have Xyce input, or need an unsupported construct |
| Native handle | `XyceSimulator`, `loadNetlistString` | you need something the wrapper does not expose yet |

The levels mix freely: [`RawCard`](@ref) drops verbatim text into a generated
circuit, and every Jyce function that takes a `Simulator` also accepts a bare
native handle.

## Contents

```@contents
Pages = ["installation.md", "getting_started.md",
         "manual/circuits.md", "manual/analyses.md", "manual/running.md",
         "manual/results.md", "manual/sweeps.md", "manual/netlists.md",
         "manual/plugins.md", "manual/plotting.md",
         "examples.md", "api.md", "migration.md", "roadmap.md"]
Depth = 2
```

## Status

Jyce is research software built by me Daris IDIRENE around the
[XyceSolver](https://github.com/MadebyDaris) C++ bindings and a memristor
modelling workflow. The API described here is the supported surface; the
pre-0.2 names still work and are listed under [Migrating from 0.1](@ref).
