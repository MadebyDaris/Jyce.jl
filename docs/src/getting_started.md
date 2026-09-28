# Getting started

This page walks through one complete session: build a circuit, run it, read the
results, and change a parameter.

```julia
using Jyce
require_native!()      # fail early and clearly if Xyce is not available
```

## 1. Describe the circuit

Components are values. Each one takes an instance name, its nodes, and a value:

```julia
divider = Circuit(
    VoltageSource(:V1, :in, :gnd, DC(5)),
    Resistor(:R1, :in, :out, 1e3),
    Resistor(:R2, :out, :gnd, 2e3);
    title = "Resistive divider",
)
```

`:gnd` (like `:GND`, `:ground` and `0`) is the ground node. The `@circuit`
macro is the same thing with the name written once, on the left:

```julia
divider = @circuit "Resistive divider" begin
    V1 = VoltageSource(:in, :gnd, DC(5))
    R1 = Resistor(:in, :out, 1e3)
    R2 = Resistor(:out, :gnd, 2e3)
end
```

## 2. Look at the netlist

Nothing is sent to Xyce until you ask, so the generated input can always be
inspected - and diffed against a handwritten netlist when something looks off:

```julia
println(netlist(divider; analysis = OperatingPoint(), outputs = [:in, :out]))
```

```
* Resistive divider
V1 in 0 DC 5
R1 in out 1000
R2 out 0 2000
.OP
.PRINT DC V(in) V(out)
.END
```

## 3. Run it

```julia
res = simulate(divider, OperatingPoint(); outputs = [:in, :out, branch_current(:V1)])
```

[`simulate`](@ref) validates the circuit, creates a simulator, loads the
netlist, runs Xyce and parses the output table. A failed run throws
[`SimulationFailure`](@ref) carrying the netlist that produced it; pass
`strict = false` to get the failed output back instead.

The validation step matters more than it looks: Xyce reports netlist errors by
aborting, which ends the Julia session, so [`validate`](@ref) catches the
common mistakes first. See [Running simulations](@ref).

## 4. Read the results

```julia
res[:out]        # the V(OUT) column
res["I(V1)"]     # any column, by name
times(res)       # the independent variable: time, frequency or swept source
signals(res)     # every column name
DataFrame(res)   # the whole table
```

`SimulationOutput` implements the Tables.jl interface, so `CSV.write("run.csv",
res)` and `DataFrame(res)` work directly.

## 5. Change something and run again

The same circuit serves every analysis:

```julia
ac   = simulate(divider, ACSweep(1, 1e6); outputs = [vdb(:out)])
tran = simulate(divider, Transient(1e-5, 1e-2); outputs = [:in, :out])
```

and a value named as a parameter can be swept without touching the circuit
definition:

```julia
divider = Circuit(VoltageSource(:V1, :in, :gnd, DC(5)),
                  Resistor(:R1, :in, :out, :rtop),      # value from a .PARAM
                  Resistor(:R2, :out, :gnd, 2e3))
param!(divider, :rtop => 1e3)

res = sweep(divider, OperatingPoint(), :rtop => [1e3, 2e3, 5e3]; outputs = [:out])
DataFrame(res)     # one row per value of rtop
```

## 6. Plot

```julia
using Plots
plot(res)                                   # every printed signal
plot_bode(ac; node = :out)                  # AC magnitude and phase
plot_iv_characteristic(res)                 # I-V loop for two-terminal devices
```

## Where to go next

- [Building circuits](@ref) - components, subcircuits, models, parameters.
- [Analyses and probes](@ref) - what to solve and what to print.
- [Parameter sweeps](@ref) - design-space exploration.
- [Netlist interop](@ref) - existing `.cir` files and unsupported constructs.
- [Verilog-A plugins](@ref) - compiled device models.
