"""
    Jyce

A Julia interface to the [Xyce](https://xyce.sandia.gov/) parallel electronic
simulator.

Jyce has three layers, and you can work at whichever one suits the task:

1. **Circuits as Julia values** — build a [`Circuit`](@ref) from typed
   components ([`Resistor`](@ref), [`VoltageSource`](@ref), ...), pick an
   analysis ([`Transient`](@ref), [`ACSweep`](@ref), ...) and call
   [`simulate`](@ref).
2. **Netlists as text** — hand [`simulate`](@ref) a netlist string, or load a
   `.cir` file with [`simulate_file`](@ref).  Everything Xyce accepts works,
   including constructs Jyce does not model.
3. **The native handle** — drive the C++ `XyceSimulator` directly when you need
   something the wrapper does not expose.

Results come back as a [`SimulationOutput`](@ref): a `DataFrame`-backed table
with the netlist that produced it, ready for analysis, plotting or `CSV.write`.

```julia
using Jyce

rc = @circuit "RC low-pass" begin
    V1 = VoltageSource(:in, :gnd, DC(0), Pulse(0, 1; rise = 1e-6, width = 1e-3, period = 2e-3))
    R1 = Resistor(:in, :out, 1e3)
    C1 = Capacitor(:out, :gnd, 100e-9)
end

res = simulate(rc, Transient(1e-6, 4e-3); outputs = [:in, :out])
plot(res)
```

Running simulations needs the native `xycesolver_julia` module; see
[`native_available`](@ref) and [`print_native_diagnostics`](@ref).  Netlist
generation works without it.
"""
module Jyce

using CxxWrap
using Libdl
using Printf
using CSV
using DataFrames
using Tables
using Plots

# Native backend (defines XyceSimulator, SimulationResult, SimulationData and
# the wrapped C++ methods, or placeholder types when Xyce is unavailable).
include("backend/native.jl")

# Circuit description
include("circuit/values.jl")
include("circuit/sources.jl")
include("circuit/components.jl")
include("analysis/analyses.jl")
include("circuit/circuit.jl")

# Results
include("io/readers.jl")
include("io/signals.jl")
include("io/results.jl")

# Driving the simulator
include("validate.jl")
include("simulator.jl")
include("definitions.jl")
include("sweep.jl")

# Visualisation and legacy API
include("plotting.jl")
include("compat.jl")

# --- native backend ---
export native_available, native_error, require_native!, native_diagnostics,
       print_native_diagnostics

# --- simulator ---
export Simulator, XyceSimulator, SimulationResult
export load!, load_file!, simulate, simulate_file
export set_param!, clear_params!, add_plugin!, clear_plugins!, output_suffix!
export last_error, debug_state, prn_path, export_csv, default_output_dir
export register_subcircuit!, include_file!, snippet!, clear_definitions!, definitions_prelude

# --- circuit description ---
export Circuit, @circuit, netlist, add!, param!, include!, options!, ic!,
       validate, CircuitValidationError,
       output!, analysis!, plugin!, directive!, components, nodes, node
export SpiceExpr, @expr_str, spice, card, designator, terminals
export AbstractElement, AbstractComponent
export Resistor, Capacitor, Inductor, MutualInductance
export VoltageSource, CurrentSource, VCVS, VCCS, CCCS, CCVS, Behavioral, VoltageSwitch
export Diode, BJT, MOSFET, JFET
export SubcircuitCall, Subcircuit, Model, PluginDevice, RawCard

# --- sources ---
export AbstractWaveform, DC, AC, Sine, Pulse, PWL, Exponential, SFFM, RawWaveform, waveform

# --- analyses and probes ---
export AbstractAnalysis, OperatingPoint, DCSweep, ACSweep, Transient, Noise, RawAnalysis, Step
export directive, print_tag, Probe, voltage, branch_current, power, vdb, vphase, vmag

# --- results ---
export SimulationOutput, SimulationFailure, issuccess, signals, times
export read_simulation_data, get_signal_names, get_time_vector, independent_column,
       get_plot_signals,
       get_voltage, get_current, detect_iv_columns

# --- sweeps ---
export sweep, SweepResult, outputs, points, failures

# --- plotting ---
export plot_transient_voltages, plot_iv_characteristic, plot_bode

# --- legacy API (see src/compat.jl) ---
export simulation_success, simulation_error_message, simulation_prn_file_path,
       register_subcircuit, add_include_file, add_inline_snippet,
       clear_custom_components, custom_components_prelude,
       add_plugin_library, clear_plugin_libraries, run_simulation_data, greet

end # module Jyce
