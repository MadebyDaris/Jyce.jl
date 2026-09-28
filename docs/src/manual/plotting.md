# Plotting

Jyce ships Plots.jl recipes and a few ready-made figures for the plots that
come up in circuit work.

## The recipe

```julia
using Plots

res = simulate(ckt, Transient(1e-6, 1e-3); outputs = [:in, :out])
plot(res)                              # every printed signal
plot(res; signals = ["V(OUT)"])        # a subset
plot(res; title = "Step response", ylabel = "V")
```

The x axis follows the analysis: time for transients, frequency for `.AC`, the
swept source for `.DC`. Any Plots attribute can be passed through.

A [`SweepResult`](@ref) plots one labelled series per run:

```julia
res = sweep(ckt, ACSweep(10, 1e6), :rload => [1e2, 1e3, 1e4]; outputs = [vdb(:out)])
plot(res; signal = "VDB(OUT)", xscale = :log10)
```

## Ready-made figures

```julia
plot_transient_voltages(res; nodes = ["V(IN)", "V(OUT)"],
                        output_file = "plots/tran.png")

plot_bode(res; node = :out, output_file = "plots/bode.png")

plot_iv_characteristic(res; voltage_col = "V(IN)", current_col = "I(V1)",
                       output_file = "plots/iv.png")
```

Each accepts a [`SimulationOutput`](@ref), a `DataFrame`, or the path of a
result file, so figures can be regenerated from runs made earlier:

```julia
plot_transient_voltages("results/run1.prn")
```

With `output_file` the figure is saved (creating directories as needed);
without it, it is displayed.

## I-V curves

[`plot_iv_characteristic`](@ref) is built for two-terminal device
characterisation - the pinched hysteresis loop of a memristor, a diode's
forward curve:

```julia
plot_iv_characteristic(res;
    voltage_col = "V(N001)",     # detected automatically when omitted
    current_col = "I(V1)",
    invert_current = true,       # current through a source is measured inward
    cycle_selection = :last,     # :all, :first or :last drive cycle
    cycle_overlay = true)        # colour by sample index to show direction
```

[`detect_iv_columns`](@ref) reports what the automatic detection found:

```julia
cols = detect_iv_columns(res.data)
cols.voltage_col, cols.current_col, cols.available_columns
```

## Headless use

For scripts and CI, set the GR backend to headless before plotting:

```julia
ENV["GKSwstype"] = "100"
```

## Other plotting libraries

The recipes are conveniences, not a dependency of the results: `DataFrame(res)`
is a plain table, so Makie, VegaLite, PGFPlots or Gnuplot work just as well.
