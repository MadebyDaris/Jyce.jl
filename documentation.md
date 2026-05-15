# Jyce Documentation

This document summarizes how to use the Jyce Julia package, how native loading works, and how to diagnose failures.

## Overview

Jyce is the Julia integration layer for the XyceSolver CxxWrap module. It provides:
- A native-backed simulator interface (`XyceSimulator`).
- Netlist loading from strings or files.
- Programmatic injection of `.include` files, inline snippets, and subcircuits.
- Helpers for reading PRN data and plotting.

## Native Loading and Environment Variables

Jyce locates the `xycesolver_julia` shared module in this order:
1. JLL products (if `JYCE_PREFER_JLL=1` and `XyceSolver_jll` is available)
2. `JYCE_XYCESOLVER_JULIA_LIB` (absolute path to the module file)
3. `JYCE_XYCESOLVER_ROOT/lib/xycesolver_julia.<ext>`
4. `JYCE_XYCESOLVER_ROOT/build/xycesolver_julia.<ext>`
5. `Jyce/lib/xycesolver_julia.<ext>`
6. Monorepo fallback: `XyceSolver/build/xycesolver_julia.<ext>`

Optional controls:
- `JYCE_PREFER_JLL=0` disables JLL lookup.
- `JYCE_ALLOW_MISSING_NATIVE=1` allows import without native bindings (for CI/docs).

## Quick Diagnostics

Use these to see why the native backend is not loaded:

```julia
using Jyce
Jyce.print_native_diagnostics()
println("native_available=", Jyce.native_available())
println("native_error=", Jyce.native_error())
```

If native is missing, `require_native!()` throws a detailed error:

```julia
try
    Jyce.require_native!()
catch e
    @warn "require_native! failed" exception=(e, catch_backtrace())
end
```

## Basic Usage (Pure Jyce)

```julia
using Jyce

Jyce.require_native!()

sim = Jyce.XyceSimulator(false)

netlist = """
* Simple divider
V1 in 0 DC 1
R1 in out 1k
R2 out 0 2k
.OP
.PRINT DC V(in) V(out)
.END
"""

Jyce.loadNetlistString(sim, netlist)
result = Jyce.runSimulation(sim)

if !Jyce.simulation_success(result)
    error(Jyce.simulation_error_message(result))
end

println("PRN: ", Jyce.simulation_prn_file_path(result))
```

If you prefer the data object returned by the wrapper (time points, node names, voltages):

```julia
data = Jyce.run_simulation_data(sim)
println(data.success)
println(data.error_message)
println(data.prn_file_path)
```

## Programmatic Netlist Assembly

These helpers allow you to add custom definitions that are prepended when using `loadNetlistString`:

```julia
Jyce.add_include_file(sim, "./lib/reading/memristor.sub")
Jyce.add_inline_snippet(sim, ".PARAM SCALE=1")

Jyce.register_subcircuit(sim, "rdivider", """
.SUBCKT rdivider in out
Rtop in out {SCALE*1k}
Rbot out 0 {SCALE*2k}
.ENDS rdivider
""")

netlist = """
V1 vin 0 DC 1
X1 vin vout rdivider
.OP
.PRINT DC V(vin) V(vout)
.END
"""

Jyce.loadNetlistString(sim, netlist)
result = Jyce.runSimulation(sim)
```

To reset injected components:

```julia
Jyce.clear_custom_components(sim)
println(Jyce.custom_components_prelude(sim))
```

## Data Utilities

Jyce includes helpers for PRN data parsing and plotting:

```julia
data = Jyce.read_simulation_data("path/to/run.prn")
cols = Jyce.detect_iv_columns(data)

Jyce.plot_transient_voltages("path/to/run.prn"; nodes=["V(N001)"])
Jyce.plot_iv_characteristic(
    "path/to/run.prn";
    voltage_col=cols.voltage_col,
    current_col=cols.current_col,
)
```

## Plugin Loading (Verilog-A)

You can load a compiled plugin shared library and then run netlists normally:

```julia
sim = Jyce.XyceSimulator(false)
Jyce.add_plugin_library(sim, "/abs/path/to/memristor_plugin.so")

Jyce.loadNetlistString(sim, netlist)
result = Jyce.runSimulation(sim)
```

Reset plugin registrations:

```julia
Jyce.clear_plugin_libraries(sim)
```

## Included Scripts

- `scripts/diagnose_native.jl`: prints diagnostics (safe to run even when native is missing).
- `scripts/smoke_native.jl`: full native smoke test (loads a netlist and runs a simulation).
- `scripts/probe_load_stage.jl`: isolates load-stage failures without running a simulation.

## Common Failure Modes

- Native module not found:
  - Set `JYCE_XYCESOLVER_JULIA_LIB` to the full path of `xycesolver_julia.<ext>`, or
  - Set `JYCE_XYCESOLVER_ROOT` to the build/install root.

- Jyce loads but `native_available()` is false:
  - Check `Jyce.print_native_diagnostics()` to see searched paths and errors.

- Netlist load failures:
  - Try `scripts/probe_load_stage.jl` to see whether the failure is in `loadNetlistString` or `runSimulation`.

## Development Build Notes

To build the native module from the XyceSolver project and point Jyce at it:

```bash
cd ../XyceSolver
cmake -S . -B build \
  -DBUILD_CXXWRAP_MODULE=ON \
  -DXYCE_ROOT=$HOME/XyceInstall/Serial \
  -DTRILINOS_ROOT=$HOME/XyceLibs/Serial \
  -DCMAKE_PREFIX_PATH=$(julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')
cmake --build build -j

export JYCE_XYCESOLVER_ROOT=/absolute/path/to/XyceSolver
```

## API Reference (Selected)

Core:
- `XyceSimulator([use_plugins::Bool])`
- `loadNetlistString(sim, netlist::String)`
- `loadNetlistFile(sim, filepath::String)`
- `runSimulation(sim)`
- `run_simulation_data(sim; output_file=nothing)`

Diagnostics:
- `native_available()`
- `native_error()`
- `native_diagnostics()`
- `print_native_diagnostics()`
- `require_native!()`

Customization:
- `add_include_file(sim, path)`
- `add_inline_snippet(sim, snippet)`
- `register_subcircuit(sim, name, definition)`
- `clear_custom_components(sim)`
- `custom_components_prelude(sim)`

Results:
- `simulation_success(result)`
- `simulation_error_message(result)`
- `simulation_prn_file_path(result)`

Data utilities:
- `read_simulation_data(path)`
- `detect_iv_columns(data_or_path)`
- `plot_transient_voltages(path; ...)`
- `plot_iv_characteristic(path; ...)`
