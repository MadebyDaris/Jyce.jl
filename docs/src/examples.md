# Examples

The [`examples/`](https://github.com/MadebyDaris/Jyce/tree/master/examples)
directory holds runnable scripts, each self-contained:

```bash
julia --project examples/01_voltage_divider.jl
```

Figures are written to `examples/plots/`.

| Example | What it shows |
|:--|:--|
| `01_voltage_divider.jl` | Components, [`OperatingPoint`](@ref), results as a `DataFrame` |
| `02_rc_lowpass_ac.jl` | [`@circuit`](@ref), [`ACSweep`](@ref), Bode plot, measuring the cutoff |
| `03_rc_transient_pulse.jl` | [`Pulse`](@ref) source, [`Transient`](@ref), the `plot` recipe |
| `04_rlc_ringing.jl` | Initial conditions, `uic`, comparing damping factors |
| `05_diode_rectifier.jl` | [`Model`](@ref) cards, [`DCSweep`](@ref), device I-V curves |
| `06_common_source_amp.jl` | [`MOSFET`](@ref) models; one circuit, three analyses |
| `07_opamp_subcircuit.jl` | [`Subcircuit`](@ref)/[`SubcircuitCall`](@ref), controlled sources |
| `08_parameter_sweep.jl` | [`sweep`](@ref), reductions, tidy `DataFrame` output |
| `09_memristor_subcircuit.jl` | Biolek memristor, pinched hysteresis, I-V plots |
| `10_memristor_plugin.jl` | Compiled Verilog-A device via [`PluginDevice`](@ref) |
| `11_crossbar_array.jl` | A circuit computed from a matrix: 4x4 crossbar read-out |
| `12_raw_netlist_interop.jl` | Netlist strings and files, mixing generated and handwritten cards |

`examples/circuits.ipynb` is the original notebook walkthrough.

## The shortest useful program

```julia
using Jyce

ckt = Circuit(VoltageSource(:V1, :in, :gnd, DC(5)),
              Resistor(:R1, :in, :out, 1e3),
              Resistor(:R2, :out, :gnd, 2e3))

res = simulate(ckt, OperatingPoint(); outputs = [:in, :out])
res[:out]    # 3.3333...
```

## A circuit that could not be a netlist

```julia
# Read every row of a memristive crossbar whose conductances come from data.
function crossbar(G; vread = 0.2, row = 1, rsense = 100.0)
    n, m = size(G)
    ckt = Circuit(; title = "crossbar")
    for i in 1:n
        add!(ckt, VoltageSource(Symbol("Vw$i"), Symbol("w$i"), :gnd, DC(i == row ? vread : 0.0)))
    end
    for j in 1:m
        add!(ckt, Resistor(Symbol("Rs$j"), Symbol("b$j"), :gnd, rsense))
    end
    for i in 1:n, j in 1:m
        add!(ckt, Resistor(Symbol("R$(i)_$(j)"), Symbol("w$i"), Symbol("b$j"), 1 / G[i, j]))
    end
    output!(ckt, (voltage(Symbol("b$j")) for j in 1:m)...)
    return ckt
end

readout = [simulate(crossbar(G; row = i), OperatingPoint())[Symbol("b$j")][end]
           for i in axes(G, 1), j in axes(G, 2)]
```
