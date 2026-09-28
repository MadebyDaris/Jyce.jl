# API reference

```@meta
CurrentModule = Jyce
```

```@docs
Jyce
```

## Circuits

```@docs
Circuit
@circuit
netlist
add!
param!
include!
options!
ic!
output!
analysis!
plugin!
directive!
components
nodes
node
NodeLike
validate
CircuitValidationError
```

## Components

```@docs
AbstractElement
AbstractComponent
card
designator
prefix
terminals
Resistor
Capacitor
Inductor
MutualInductance
VoltageSource
CurrentSource
VCVS
VCCS
CCCS
CCVS
Behavioral
VoltageSwitch
Diode
BJT
MOSFET
JFET
SubcircuitCall
Subcircuit
Model
PluginDevice
RawCard
```

## Values and expressions

```@docs
spice
SpiceExpr
@expr_str
ParamList
```

## Source waveforms

```@docs
AbstractWaveform
waveform
DC
AC
Sine
Pulse
PWL
Exponential
SFFM
RawWaveform
```

## Analysis types and probes

```@docs
AbstractAnalysis
directive
print_tag
OperatingPoint
DCSweep
ACSweep
Transient
Noise
RawAnalysis
Step
Probe
voltage
branch_current
current
power
vdb
vphase
vmag
print_directive
```

## The simulator

`Base.isready(simulator)` reports whether a netlist has been loaded
successfully.

```@docs
Simulator
XyceSimulator
SimulationResult
simulate
simulate_file
load!
load_file!
set_param!
clear_params!
add_plugin!
clear_plugins!
output_suffix!
last_error
debug_state
prn_path
export_csv
default_output_dir
```

## Simulator-held definitions

```@docs
register_subcircuit!
include_file!
snippet!
clear_definitions!
definitions_prelude
```

## Results

```@docs
SimulationOutput
SimulationFailure
issuccess
signals
times
read_simulation_data
get_signal_names
get_time_vector
independent_column
get_plot_signals
get_voltage
get_current
detect_iv_columns
```

## Sweeps

```@docs
sweep
SweepResult
outputs
points
failures
```

## Plotting

```@docs
plot_transient_voltages
plot_iv_characteristic
plot_bode
```

## Native backend

```@docs
native_available
native_error
require_native!
native_diagnostics
print_native_diagnostics
```

## Legacy API

```@docs
simulation_success
simulation_error_message
simulation_prn_file_path
register_subcircuit
add_include_file
add_inline_snippet
clear_custom_components
custom_components_prelude
add_plugin_library
clear_plugin_libraries
run_simulation_data
greet
```

## Index

```@index
```
