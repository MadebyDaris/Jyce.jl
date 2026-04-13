# Jyce

Jyce is the Julia package integration layer for the XyceSolver CxxWrap module.

This repo currently includes a local `XyceSolver_jll` shim package for development.
When a real artifact-backed `XyceSolver_jll` is published, replace the local source override in `Jyce/Project.toml`.

## Current Native Loading Order

Jyce resolves `xycesolver_julia` in this order:

1. Optional JLL products (if `XyceSolver_jll` is available and `JYCE_PREFER_JLL=1`)
2. `JYCE_XYCESOLVER_JULIA_LIB` (absolute path to the module file)
3. `JYCE_XYCESOLVER_ROOT/lib/xycesolver_julia.<ext>`
4. `JYCE_XYCESOLVER_ROOT/build/xycesolver_julia.<ext>`
5. `Jyce/lib/xycesolver_julia.<ext>`
6. Monorepo fallback: `XyceSolver/build/xycesolver_julia.<ext>`

To disable JLL lookup completely:

```bash
export JYCE_PREFER_JLL=0
```

## Development Workflow

1. Build native module from XyceSolver:

```bash
cd ../XyceSolver
cmake -S . -B build -DBUILD_CXXWRAP_MODULE=ON -DXYCE_ROOT=$HOME/XyceInstall/Serial -DTRILINOS_ROOT=$HOME/XyceLibs/Serial -DCMAKE_PREFIX_PATH=$(julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')
cmake --build build -j
```

2. Point Jyce at the build:

```bash
export JYCE_XYCESOLVER_ROOT=/absolute/path/to/XyceSolver
```

3. Run Jyce tests:

```bash
cd ../Jyce
julia --project -e 'using Pkg; Pkg.test()'
```

## Optional: Allow Missing Native Backend

For CI or documentation jobs that should not fail when native binaries are missing:

```bash
export JYCE_ALLOW_MISSING_NATIVE=1
```

In this mode, Jyce imports without native bindings and `Jyce.native_available()` returns `false`.

## Native Smoke Test (CI)

Run a full native smoke verification (requires native module availability):

```bash
cd ../Jyce
julia --project scripts/smoke_native.jl
```

The script performs:

1. `Jyce.require_native!()`
2. `XyceSimulator(false)` creation
3. `loadNetlistString(...)` on a minimal transient netlist
4. `runSimulation()` and success assertion

## Load-Stage Probe (No Simulation)

Use this to isolate whether failures come from netlist loading vs simulation execution:

```bash
cd ../Jyce
julia --project scripts/probe_load_stage.jl
```

If this probe succeeds but `scripts/smoke_native.jl` fails, the issue is in simulator initialization/run stage rather than `loadNetlistFile`/`loadNetlistString`.

## Custom Subcircuits and Components

Jyce supports programmatic custom circuit assembly for string-based netlists.

You can add:

1. `.include` files
2. inline snippets such as `.MODEL` / `.PARAM`
3. full `.SUBCKT ... .ENDS` definitions

These custom definitions are automatically prepended whenever you call `loadNetlistString(...)`.

```julia
using Jyce

sim = Jyce.XyceSimulator()

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

if !Jyce.simulation_success(result)
	error(Jyce.simulation_error_message(result))
end
```

To reset custom entries for a simulator instance:

```julia
Jyce.clear_custom_components(sim)
```

You can inspect the generated prelude text with:

```julia
println(Jyce.custom_components_prelude(sim))
```

Note: automatic prepend currently applies to `loadNetlistString(...)`. File-loaded netlists (`loadNetlistFile(...)`) keep their file content unchanged.

## Utils: Data + Plotting

Jyce now ships utility plotting/data helpers directly in the package, so users do not need to include files from `XyceSolver/graphic` manually.

Available functions:

1. `read_simulation_data(path)`
2. `get_signal_names(data)`
3. `get_plot_signals(data)`
4. `detect_iv_columns(data_or_path)`
5. `plot_transient_voltages(path; nodes=..., output_file=...)`
6. `plot_iv_characteristic(path; voltage_col=..., current_col=..., output_file=...)`

Example:

```julia
using Jyce

result = Jyce.runSimulation(sim)
prn = Jyce.simulation_prn_file_path(result)

data = Jyce.read_simulation_data(prn)
cols = Jyce.detect_iv_columns(data)
println("Detected voltage column: ", cols.voltage_col)
println("Detected current column: ", cols.current_col)

Jyce.plot_transient_voltages(prn; nodes=["V(N001)"], output_file="plots/transient.png")
Jyce.plot_iv_characteristic(
	prn;
	voltage_col=cols.voltage_col,
	current_col=cols.current_col,
	output_file="plots/iv.png",
)
```

## Verilog-A Plugin: Memristor

You can compile Verilog-A models into an Xyce plugin and load them from Jyce.

Build example (this repository):

```bash
cd /home/daris/Documents/workspace/memristor_proj

# 1) Convert Verilog-A to generated plugin project
buildxyceplugin.sh -o memristor_plugin memristor-model.va Jyce/plugins

# 2) Build generated project (explicit Xyce install path)
cmake -S Jyce/plugins -B Jyce/plugins/build \
	-DXYCE_INSTALL=/usr/local/XyceNF_7.10 \
	-DPLUGIN_NAME=memristor_plugin
cmake --build Jyce/plugins/build -j

# 3) Optional convenience name without lib prefix
cp Jyce/plugins/build/libmemristor_plugin.so Jyce/plugins/memristor_plugin.so
```

Load in Jyce:

```julia
using Jyce

sim = Jyce.XyceSimulator(false)
Jyce.add_plugin_library(sim, "/home/daris/Documents/workspace/memristor_proj/Jyce/plugins/memristor_plugin.so")

# then load/run your circuit as usual
Jyce.loadNetlistString(sim, netlist)
result = Jyce.runSimulation(sim)
```

To reset plugin registrations on a simulator instance:

```julia
Jyce.clear_plugin_libraries(sim)
```
