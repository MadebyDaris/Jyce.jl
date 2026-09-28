# Building circuits

A [`Circuit`](@ref) is an ordered collection of elements plus the directives
around them. It is a mutable Julia value: build it in a loop, copy it, store it
in a dictionary, generate it from data.

## Components

Every component takes an instance name first, then nodes, then a value:

```julia
Resistor(:R1, :in, :out, 1e3)
Capacitor(:C1, :out, :gnd, 100e-9; ic = 0.0)
Inductor(:L1, :a, :b, 10e-3)
VoltageSource(:V1, :in, :gnd, DC(0), AC(1), Sine(0, 1, 1e3))
CurrentSource(:I1, :gnd, :out, DC(1e-3))
Diode(:D1, :a, :b, :D1N4148)
MOSFET(:M1, :d, :g, :s, :s, :NMOS1; l = 1e-6, w = 10e-6)
BJT(:Q1, :c, :b, :e, :QN2222)
```

The SPICE designator letter is added automatically when the name does not
already start with it, so `Resistor(:load, ...)` emits `Rload`.

Controlled sources and switches:

```julia
VCVS(:E1, :out, :gnd, :inp, :inn, 1e5)    # E: voltage-controlled voltage source
VCCS(:G1, :out, :gnd, :inp, :inn, 1e-3)   # G
CCCS(:F1, :out, :gnd, :V1, 10)            # F, sensing I(V1)
CCVS(:H1, :out, :gnd, :V1, 1e3)           # H
Behavioral(:B1, :out, :gnd; v = "V(in)^2")
VoltageSwitch(:S1, :a, :b, :ctrl, :gnd, :SWMOD)
```

Anything Jyce does not model goes in verbatim with [`RawCard`](@ref):

```julia
add!(ckt, RawCard("YMEMRISTOR m1 plus minus 0 mymem"))
```

## Nodes

Nodes are `Symbol`s, `String`s or `Integer`s. `:gnd`, `:GND`, `:ground`, `:0`
and `0` all mean ground. [`nodes`](@ref) lists every node a circuit references,
which is a quick way to catch a typo that silently created a floating node:

```julia
nodes(ckt)    # ["0", "in", "out"]
```

## Values, parameters and expressions

A component value can be a number, a string with a SPICE suffix, a `Symbol`
naming a `.PARAM`, or an expression:

```julia
Resistor(:R1, :a, :b, 1e3)          # R1 a b 1000
Resistor(:R2, :a, :b, "4k7")        # R2 a b 4k7
Resistor(:R3, :a, :b, :rload)       # R3 a b {rload}
Resistor(:R4, :a, :b, expr"2*rload")# R4 a b {2*rload}
```

Declare the parameters with [`param!`](@ref):

```julia
param!(ckt, :rload => 1e3, :cload => 1e-9)
```

Parameters are what [`sweep`](@ref) overrides, so anything you might want to
vary is worth naming.

## Models

```julia
add!(ckt, Model(:D1N4148, :D; is = 2.52e-9, rs = 0.568, n = 1.752))
add!(ckt, Model(:NMOS1, :NMOS; level = 1, vto = 0.7, kp = 120e-6))
```

## Subcircuits

[`Subcircuit`](@ref) defines a block, [`SubcircuitCall`](@ref) instantiates it.
Because the definition is a function result, blocks can be parameterised in
Julia rather than in SPICE:

```julia
function rc_stage(name; r = 1e3, c = 1e-9)
    return Subcircuit(name, (:in, :out),
        Resistor(:R, :in, :out, r),
        Capacitor(:C, :out, :gnd, c))
end

ckt = Circuit(rc_stage(:stage; r = 10e3),
              SubcircuitCall(:X1, (:in, :mid), :stage),
              SubcircuitCall(:X2, (:mid, :out), :stage))
```

SPICE-level parameters work too:

```julia
Subcircuit(:rdivider, (:in, :out),
    Resistor(:Rtop, :in, :out, expr"rtop"),
    Resistor(:Rbot, :out, :gnd, expr"rbot");
    rtop = 1e3, rbot = 2e3)

SubcircuitCall(:X1, (:in, :out), :rdivider; rtop = 4.7e3)
```

## The `@circuit` macro

```julia
ckt = @circuit "Two-stage filter" begin
    V1 = VoltageSource(:in, :gnd, DC(0), AC(1))
    R1 = Resistor(:in, :mid, 1e3)
    C1 = Capacitor(:mid, :gnd, 1e-9)
    R2 = Resistor(:mid, :out, 1e3)
    C2 = Capacitor(:out, :gnd, 1e-9)

    ACSweep(1, 1e9)          # analyses can live in the circuit
    vdb(:out)                # and so can output probes
end
```

Inside the block, `Name = Constructor(args...)` becomes
`Constructor(:Name, args...)`. Every other expression is passed to
[`add!`](@ref), which accepts components, models, subcircuits, analyses,
probes, `name => value` parameters, raw strings, and vectors of any of those -
so a comprehension works as a statement:

```julia
@circuit "Ladder" begin
    V1 = VoltageSource(:in, :gnd, DC(1))
    [Resistor(Symbol("R$i"), Symbol("n$i"), Symbol("n$(i+1)"), 1e3) for i in 1:10]
end
```

## Building circuits programmatically

`add!` is the workhorse when the circuit comes from data:

```julia
function crossbar(G::AbstractMatrix; vread = 0.2)
    n, m = size(G)
    ckt = Circuit(; title = "$(n)x$(m) crossbar")
    for i in 1:n
        add!(ckt, VoltageSource(Symbol("Vw$i"), Symbol("w$i"), :gnd, DC(vread)))
    end
    for i in 1:n, j in 1:m
        add!(ckt, Resistor(Symbol("R$(i)_$(j)"), Symbol("w$i"), Symbol("b$j"), 1 / G[i, j]))
    end
    return ckt
end
```

See [`examples/11_crossbar_array.jl`](https://github.com/MadebyDaris/Jyce/blob/master/examples/11_crossbar_array.jl)
for the complete version.

## Other directives

```julia
include!(ckt, "models/bsim4.lib")              # .INCLUDE
options!(ckt, :TIMEINT; reltol = 1e-6)         # .OPTIONS
ic!(ckt, :out => 1.0)                          # .IC, used with uic = true
directive!(ckt, ".MEASURE TRAN vmax MAX V(out)")
plugin!(ckt, "plugins/build/libmemristor_plugin.so")
```

## Checking a circuit

```julia
validate(ckt; strict = false)
```

[`validate`](@ref) reports duplicate instance names, undeclared parameters,
undefined models and subcircuits, and nodes with a single connection.
[`simulate`](@ref) runs it by default, because Xyce answers a netlist error by
aborting the process - see [Running simulations](@ref).

## Parameters inside subcircuits

A top-level `.PARAM` is not visible inside a `.SUBCKT` body in Xyce. Give the
subcircuit its own parameters instead:

```julia
Subcircuit(:rdivider, (:in, :out),
    Resistor(:Rtop, :in, :out, expr"rtop"),
    Resistor(:Rbot, :out, :gnd, expr"rbot");
    rtop = 1e3, rbot = 2e3)
```

and override them per instance with `SubcircuitCall(:X1, (:in, :out), :rdivider; rtop = 4.7e3)`.

## Generating the netlist

```julia
netlist(ckt)                                       # whatever the circuit carries
netlist(ckt; analysis = Transient(1e-6, 1e-3))     # override the analysis
netlist(ckt; outputs = [:in, :out], format = :csv) # override the probes
```

`netlist` never touches the native backend, so it works on machines without
Xyce - useful in CI and for generating input for another tool.
