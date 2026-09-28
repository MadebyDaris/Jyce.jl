# Parameter sweeps

[`sweep`](@ref) re-runs a circuit for every combination of parameter values.
Each run regenerates the netlist with the swept values substituted, so anything
the netlist references as a `.PARAM` can be swept - component values, model
parameters, source amplitudes, subcircuit parameters.

Every run needs somewhere to send its results: pass `outputs`, or attach probes
to the circuit with [`output!`](@ref). A run with no `.PRINT` card writes no
table, and Jyce warns when that happens.

## Setting up

Reference a parameter from a component value with a `Symbol`, and declare it
with [`param!`](@ref):

```julia
rc = Circuit(
    VoltageSource(:V1, :in, :gnd, DC(0), AC(1)),
    Resistor(:R1, :in, :out, :rload),
    Capacitor(:C1, :out, :gnd, :cload),
)
param!(rc, :rload => 1e3, :cload => 1e-6)
```

## Keeping every waveform

```julia
res = sweep(rc, ACSweep(10, 1e6; points = 20), :rload => [1e2, 1e3, 1e4];
            outputs = [vdb(:out)])
```

The [`SweepResult`](@ref) holds the parameter point and the
[`SimulationOutput`](@ref) of each run:

```julia
length(res)          # number of runs
points(res)          # the parameter combinations
outputs(res)         # the individual runs
failures(res)        # runs Xyce rejected

for (point, out) in res
    println(point.rload, " -> ", maximum(out["VDB(OUT)"]))
end
```

`DataFrame(res)` gives one long-format table, with the parameter values
repeated alongside every row - the shape `groupby` and plotting want:

```julia
df = DataFrame(res)
first(df, 3)
# FREQ   VDB(OUT)   run   rload
```

Plotting a sweep draws one labelled series per run:

```julia
plot(res; signal = "VDB(OUT)", xscale = :log10)
```

## Reducing each run

Passing a function makes the sweep return one row per parameter combination -
the natural form for design-space exploration:

```julia
corners = sweep(rc, ACSweep(10, 1e6; points = 20),
                :rload => [1e2, 1e3, 1e4],
                :cload => [1e-7, 1e-6]; outputs = [vdb(:out)]) do out
    mag, freq = out["VDB(OUT)"], out["FREQ"]
    (; cutoff_hz = freq[argmin(abs.(mag .- (mag[1] - 3)))],
       peak_db   = maximum(mag))
end
```

`corners` is a `DataFrame` with columns `rload`, `cload`, `cutoff_hz`,
`peak_db`. Several parameters sweep as a Cartesian product, with the first
varying fastest.

## Monte Carlo and other distributions

The values are just Julia collections, so a Monte Carlo run is a sweep over
samples:

```julia
using Random
samples = 1e3 .* (1 .+ 0.05 .* randn(MersenneTwister(1), 200))

yield = sweep(rc, ACSweep(10, 1e6), :rload => samples; outputs = [vdb(:out)]) do out
    mag, freq = out["VDB(OUT)"], out["FREQ"]
    (; cutoff_hz = freq[argmin(abs.(mag .- (mag[1] - 3)))])
end

using Statistics
mean(yield.cutoff_hz), std(yield.cutoff_hz)
```

## Keeping the raw files

```julia
sweep(rc, Transient(1e-6, 1e-3), :rload => [1e2, 1e3];
      outputs = [:out], output_dir = "results/rload")
```

writes `results/rload/run_1.prn`, `run_2.prn`, ... instead of letting Xyce
overwrite one temporary file.

## Failures inside a sweep

By default the first failed run aborts the sweep. To survey a space where some
corners will not converge, use `strict = false` and inspect
[`failures`](@ref):

```julia
res = sweep(rc, Transient(1e-6, 1e-3), :rload => rvals; outputs = [:out], strict = false)
for (point, out) in failures(res)
    @warn "did not converge" point out.error_message
end
```

## Sweeping inside Xyce instead

[`Step`](@ref) emits a `.STEP` card and lets Xyce do the looping in one
process, writing a single file. It is faster for large sweeps of a single
parameter, but the result is one table you have to split yourself, and the
values must be a range or list Xyce accepts. `sweep` is the more flexible
option; `.STEP` the more efficient one.

## Performance notes

Runs execute sequentially - one native Xyce instance at a time - and reuse a
single [`Simulator`](@ref) unless you pass your own. Most of the cost is inside
Xyce, so the practical lever is the analysis itself: coarser print intervals,
shorter transients, and `OperatingPoint` instead of `Transient` where it
answers the question.
