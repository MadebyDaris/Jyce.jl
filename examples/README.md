# Jyce examples

Each file is self-contained and runnable from the package root:

```bash
julia --project examples/01_voltage_divider.jl
```

They need the native backend (see the [installation
guide](../docs/src/installation.md)); figures are written to `examples/plots/`.

| Example | What it shows |
|:--|:--|
| [`01_voltage_divider.jl`](01_voltage_divider.jl) | Components, `OperatingPoint`, reading results as a `DataFrame` |
| [`02_rc_lowpass_ac.jl`](02_rc_lowpass_ac.jl) | `@circuit`, `ACSweep`, Bode plot, measuring the cutoff |
| [`03_rc_transient_pulse.jl`](03_rc_transient_pulse.jl) | `Pulse` source, `Transient`, `plot(res)` recipe |
| [`04_rlc_ringing.jl`](04_rlc_ringing.jl) | Initial conditions, `uic`, comparing damping factors |
| [`05_diode_rectifier.jl`](05_diode_rectifier.jl) | `.MODEL` cards, `DCSweep`, device I-V curves |
| [`06_common_source_amp.jl`](06_common_source_amp.jl) | MOSFET models; one circuit, three analyses |
| [`07_opamp_subcircuit.jl`](07_opamp_subcircuit.jl) | `Subcircuit`/`SubcircuitCall`, controlled sources |
| [`08_parameter_sweep.jl`](08_parameter_sweep.jl) | `sweep`, reductions, tidy `DataFrame` output |
| [`09_memristor_subcircuit.jl`](09_memristor_subcircuit.jl) | Biolek memristor, pinched hysteresis, I-V plots |
| [`10_memristor_plugin.jl`](10_memristor_plugin.jl) | Compiled Verilog-A plugin via `PluginDevice` |
| [`11_crossbar_array.jl`](11_crossbar_array.jl) | A circuit computed from a matrix: 4x4 crossbar read-out |
| [`12_raw_netlist_interop.jl`](12_raw_netlist_interop.jl) | Netlist strings and files, mixing generated and handwritten cards |

`circuits.ipynb` is the original notebook walkthrough and still works; the
scripts above cover the same ground with the current API.
