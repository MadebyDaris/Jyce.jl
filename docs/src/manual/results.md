# Results

Every run returns a [`SimulationOutput`](@ref): the status, the file Xyce
wrote, the parsed table, and the netlist that produced it.

```julia
res = simulate(ckt, Transient(1e-6, 1e-3); outputs = [:in, :out])

res.success          # did Xyce converge
res.error_message    # why not
res.prn_file_path    # the file on disk
res.netlist          # exactly what was simulated
res.metadata         # analyses, parameters, plugins used
```

## Reading columns

```julia
res[:out]            # V(OUT) by node name
res["I(V1)"]         # any column by name
res[voltage(:out)]   # by probe
times(res)           # independent variable: time, frequency, or swept source
signals(res)         # every column name
haskey(res, "V(OUT)")
```

Lookup is case-insensitive and falls back to a substring match, so `res[:out]`
finds `V(OUT)` whatever case Xyce used.

## As a table

```julia
using DataFrames
df = DataFrame(res)
```

`SimulationOutput` implements the Tables.jl interface, so it goes anywhere a
table is expected:

```julia
using CSV
CSV.write("run.csv", res)
```

From there it is ordinary DataFrames work:

```julia
df = DataFrame(res)
subset(df, :TIME => t -> t .> 1e-3)
combine(df, names(df, Not(:TIME)) .=> maximum)
```

## Analysing a run

Nothing about the results is Xyce-specific once they are in Julia:

```julia
t, v = times(res), res[:out]

settling = t[findfirst(>=(0.9 * maximum(v)), v)]
overshoot = (maximum(v) - v[end]) / v[end]
energy = sum(abs2, v) * (t[2] - t[1])
```

## Reading files written earlier

Result files can be read without running anything:

```julia
data = read_simulation_data("results/run1.prn")   # .prn or .csv
get_signal_names(data)
get_time_vector(data)
get_voltage(data, "V(OUT)")
get_current(data, "I(V1)")
detect_iv_columns(data)      # guess the drive/sense columns of a two-terminal test
```

This path needs no native backend, which makes it convenient for post-
processing on a laptop when the simulations ran elsewhere.

## Failed runs

With `strict = false`, a failed run comes back as data rather than an
exception, and `res.data` is `nothing`:

```julia
res = simulate(ckt, Transient(1e-9, 10.0); strict = false)
if !issuccess(res)
    @warn "no convergence" res.error_message
end
```
