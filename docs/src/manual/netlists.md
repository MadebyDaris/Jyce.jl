# Netlist interop

Jyce is a layer over Xyce, not a replacement for it. Anything Xyce accepts can
be run, and generated and handwritten netlists mix freely.

## The title line

Xyce treats the first line of a netlist as its title and ignores it, so a file
that begins with a card silently loses that card. Jyce adds a `* Jyce netlist`
line when the text does not already start with a comment, and puts any
registered definitions after it - generated netlists always carry their own
`* title` line.

## Running netlist text

```julia
res = simulate("""
* Handwritten netlist
V1 in 0 SIN(0 1 10)
R1 in out 1k
R2 out 0 2k
.TRAN 1ms 300ms
.PRINT TRAN V(in) V(out) I(V1)
.END
""")
```

## Running a file

```julia
res = simulate_file("circuits/amplifier.cir")
```

Or, with a simulator you keep:

```julia
sim = Simulator()
load_file!(sim, "circuits/amplifier.cir")
res = simulate(sim)
```

Note the difference between the two loaders: [`load!`](@ref) (netlist text)
prepends the simulator's registered definitions, while [`load_file!`](@ref)
uses the file exactly as written.

## Mixing generated and handwritten cards

[`RawCard`](@ref) drops text into a generated circuit, and
[`directive!`](@ref) appends raw directives:

```julia
ckt = Circuit(
    VoltageSource(:V1, :in, :gnd, Sine(0, 1, 10)),
    RawCard("R1 in out 1k"),
    Resistor(:R2, :out, :gnd, 2e3),
)
directive!(ckt, ".OPTIONS TIMEINT RELTOL=1e-4")
directive!(ckt, ".MEASURE TRAN vmax MAX V(out)")
```

[`RawAnalysis`](@ref) and [`RawWaveform`](@ref) do the same for analyses and
source specifications. Between the four of them, no Xyce feature is out of
reach from a generated circuit.

## Including model libraries

```julia
include!(ckt, "models/bsim4.lib")        # emits .INCLUDE
```

## Definitions held on the simulator

Instead of putting them in the circuit, subcircuits, includes and snippets can
live on the [`Simulator`](@ref) and be prepended to every netlist loaded with
[`load!`](@ref). This suits a library of blocks reused across many runs:

```julia
sim = Simulator()
include_file!(sim, "lib/memristor.sub")
snippet!(sim, ".PARAM SCALE=1")
register_subcircuit!(sim, Subcircuit(:rdivider, (:in, :out),
    Resistor(:Rtop, :in, :out, expr"SCALE*1k"),
    Resistor(:Rbot, :out, :gnd, expr"SCALE*2k")))

println(definitions_prelude(sim))   # exactly what gets prepended

load!(sim, """
V1 vin 0 DC 1
X1 vin vout rdivider
.OP
.PRINT DC V(vin) V(vout)
.END
""")
res = simulate(sim)
```

[`clear_definitions!`](@ref) resets them.

For a [`Simulator`](@ref) these definitions are assembled in Julia and
prepended to the netlist, after the title line. A bare native `XyceSimulator`
handle still uses the C++ prelude mechanism, which places its first directive
on the title line where Xyce ignores it - one more reason to prefer the
`Simulator` wrapper.

## Exporting generated netlists

`netlist(ckt)` returns a `String`, so writing Xyce input for another tool or
for version control is one line:

```julia
write("build/amp.cir", netlist(ckt; analysis = Transient(1e-6, 1e-3)))
```

This needs no native backend, which makes netlist generation a reasonable thing
to test in CI.

## Converting results

```julia
export_csv(sim, "run.prn", "run.csv")   # native converter
CSV.write("run.csv", res)               # the parsed table from Julia
```
