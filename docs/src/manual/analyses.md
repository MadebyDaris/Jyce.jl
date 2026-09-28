# Analyses and probes

An analysis says what Xyce should solve; probes say which columns land in the
output file. Both are values, so they can be stored, passed around and chosen
at run time.

## Analyses

| Type | Netlist card | Independent variable |
|:--|:--|:--|
| [`OperatingPoint()`](@ref OperatingPoint) | `.OP` | none (one row) |
| [`DCSweep(source, start, stop, step)`](@ref DCSweep) | `.DC` | the swept source |
| [`ACSweep(fstart, fstop; kind, points)`](@ref ACSweep) | `.AC` | frequency |
| [`Transient(step, stop; start, maxstep, uic)`](@ref Transient) | `.TRAN` | time |
| [`Noise(output, source, fstart, fstop)`](@ref Noise) | `.NOISE` | frequency |
| [`RawAnalysis(text, tag)`](@ref RawAnalysis) | verbatim | whatever you say |

```julia
simulate(ckt, OperatingPoint())
simulate(ckt, DCSweep(:V1, 0, 5, 0.05))
simulate(ckt, DCSweep(:V1, 0:0.05:5))          # ranges work too
simulate(ckt, ACSweep(1, 1e6; kind = :dec, points = 20))
simulate(ckt, Transient(1e-6, 1e-3))
simulate(ckt, Transient(1e-6, 1e-3; uic = true))
```

An analysis can also be attached to the circuit with [`analysis!`](@ref) (or by
listing it inside [`@circuit`](@ref)), in which case `simulate(ckt)` needs no
second argument.

### Transient runs and initial conditions

`Transient(step, stop)` prints every `step` seconds until `stop`. With
`uic = true`, Xyce skips the DC operating point and starts from the initial
conditions declared on components (`Capacitor(...; ic = 1.0)`) or on the
circuit ([`ic!`](@ref)):

```julia
ckt = Circuit(Resistor(:R1, :out, :a, 10.0),
              Inductor(:L1, :a, :gnd, 10e-3),
              Capacitor(:C1, :out, :gnd, 100e-9; ic = 1.0))
ic!(ckt, :out => 1.0)
simulate(ckt, Transient(1e-6, 2e-3; uic = true); outputs = [:out])
```

### Sweeping inside Xyce

[`Step`](@ref) emits a `.STEP` card, so Xyce loops over a parameter itself and
writes one file containing every run:

```julia
add!(ckt, Step(:rload, 1e3:1e3:5e3))
```

Use it when you want Xyce's own sweep machinery. For sweeps you want to post-
process in Julia - arbitrary values, reductions, per-run plots - use
[`sweep`](@ref) instead; see [Parameter sweeps](@ref).

## Probes

Probes become the `.PRINT` line:

```julia
voltage(:out)          # V(out)
voltage(:in, :out)     # V(in,out), the differential voltage
branch_current(:V1)           # I(V1)
branch_current(my_resistor)   # I(R1), from the component itself
power(:R1)             # P(R1)
vdb(:out)              # VDB(out), magnitude in dB   (AC)
vphase(:out)           # VP(out),  phase in degrees  (AC)
vmag(:out)             # VM(out),  magnitude         (AC)
```

Anywhere probes are accepted, a bare `Symbol` means the node voltage and a
`String` is passed through verbatim, so these are the same:

```julia
outputs = [:in, :out, branch_current(:V1)]
outputs = ["V(in)", "V(out)", "I(V1)"]
```

Probes can be attached to the circuit with [`output!`](@ref) or passed per run:

```julia
output!(ckt, voltage(:out), branch_current(:V1))       # sticks to the circuit
simulate(ckt, Transient(1e-6, 1e-3); outputs = [:in, :out])   # this run only
```

With no probes at all, Xyce writes its default output, which is usually every
node voltage.

## Output format

`.PRINT` accepts a format keyword, passed through by [`netlist`](@ref) and
[`simulate`](@ref):

```julia
simulate(ckt, Transient(1e-6, 1e-3); outputs = [:out], format = :csv)
```

Jyce reads both the default `.prn` tables and CSV, so the choice only matters
if another tool consumes the file.
