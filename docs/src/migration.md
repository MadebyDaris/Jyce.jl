# Migrating from 0.1

Nothing was removed. Every name the package exported before still works, on
both a [`Simulator`](@ref) and a bare native `XyceSimulator` handle, so
existing notebooks and scripts keep running unchanged. The table below maps the
old names onto the current ones.

| Before | Now | Notes |
|:--|:--|:--|
| `XyceSimulator(false)` | `Simulator()` | `Simulator` tracks netlist, params and plugins, and prints a useful summary |
| `Jyce.loadNetlistString(sim, text)` | `load!(sim, text)` | raises a clear error instead of returning `false` |
| `Jyce.loadNetlistFile(sim, path)` | `load_file!(sim, path)` | |
| `Jyce.runSimulation(sim)` | `simulate(sim)` | returns a [`SimulationOutput`](@ref) with the parsed table |
| `Jyce.runSimulationOutput(sim, file)` | `simulate(sim; output_file = file)` | |
| `run_simulation_data(sim)` | `simulate(sim)` | the old form still returns the native `NamedTuple` |
| `simulation_success(r)` | `issuccess(res)` / `res.success` | |
| `simulation_error_message(r)` | `res.error_message` | |
| `simulation_prn_file_path(r)` | `res.prn_file_path` | |
| `register_subcircuit(sim, name, text)` | [`register_subcircuit!`](@ref) | also accepts a [`Subcircuit`](@ref) value |
| `add_include_file(sim, path)` | [`include_file!`](@ref) | |
| `add_inline_snippet(sim, text)` | [`snippet!`](@ref) | |
| `clear_custom_components(sim)` | [`clear_definitions!`](@ref) | |
| `custom_components_prelude(sim)` | [`definitions_prelude`](@ref) | |
| `add_plugin_library(sim, path)` | [`add_plugin!`](@ref) | checks the file exists |
| `clear_plugin_libraries(sim)` | [`clear_plugins!`](@ref) | |
| `read_simulation_data(path)` | unchanged | or just `DataFrame(res)` |
| `plot_transient_voltages(path; ...)` | unchanged | now also takes a result or `DataFrame` |
| `plot_iv_characteristic(path; ...)` | unchanged | same |

## A before/after example

Before:

```julia
sim = Jyce.XyceSimulator(false)
Jyce.loadNetlistString(sim, """
V1 in 0 DC 5
R1 in out 1k
R2 out 0 2k
.OP
.PRINT DC V(in) V(out)
.END
""")
result = Jyce.runSimulation(sim)
if Jyce.simulation_success(result)
    data = Jyce.read_simulation_data(Jyce.simulation_prn_file_path(result))
    println(data)
else
    println(Jyce.simulation_error_message(result))
end
```

After:

```julia
ckt = Circuit(VoltageSource(:V1, :in, :gnd, DC(5)),
              Resistor(:R1, :in, :out, 1e3),
              Resistor(:R2, :out, :gnd, 2e3))

res = simulate(ckt, OperatingPoint(); outputs = [:in, :out])
println(DataFrame(res))
```

## One renamed export

`current` (the probe constructor) is exported as
[`branch_current`](@ref), because `Plots.current` already claims that name and
`using Jyce, Plots` would make the bare name ambiguous. `Jyce.current` still
works as a qualified synonym.
