# Parameter sweeps and batch runs
"""
    SweepResult

The outcome of a [`sweep`](@ref): the swept parameter names, one point per
parameter combination, and the corresponding [`SimulationOutput`](@ref)s.

It iterates and indexes over `(point, output)` pairs, and
`DataFrame(sweep_result)` produces a long-format table with the parameter
values repeated alongside every row of each run.
"""
struct SweepResult
    parameters::Vector{Symbol}
    points::Vector{NamedTuple}
    outputs::Vector{SimulationOutput}
end

Base.length(s::SweepResult) = length(s.outputs)
Base.getindex(s::SweepResult, i::Integer) = (s.points[i], s.outputs[i])
Base.iterate(s::SweepResult, i::Int = 1) = i > length(s) ? nothing : (s[i], i + 1)
Base.eltype(::Type{SweepResult}) = Tuple{NamedTuple,SimulationOutput}

"""
    outputs(sweep_result) -> Vector{SimulationOutput}

The individual runs, in sweep order.
"""
outputs(s::SweepResult) = s.outputs

"""
    points(sweep_result) -> Vector{NamedTuple}

The parameter combination used for each run.
"""
points(s::SweepResult) = s.points

"""
    failures(sweep_result) -> Vector{Tuple{NamedTuple,SimulationOutput}}

The runs Xyce reported as failed — empty when everything converged.
"""
failures(s::SweepResult) = [(p, o) for (p, o) in s if !issuccess(o)]

function DataFrames.DataFrame(s::SweepResult)
    frames = DataFrame[]
    for (i, (point, out)) in enumerate(s)
        out.data === nothing && continue
        df = copy(out.data)
        df[!, :run] .= i
        for (k, v) in pairs(point)
            df[!, k] .= v
        end
        push!(frames, df)
    end
    isempty(frames) && return DataFrame()
    return reduce(vcat, frames; cols = :union)
end

function Base.show(io::IO, ::MIME"text/plain", s::SweepResult)
    bad = count(!issuccess, s.outputs)
    println(io, "SweepResult over ", join(string.(s.parameters), " x "), ": ",
            length(s), " run(s)", bad == 0 ? "" : ", $bad failed")
    for (point, out) in Iterators.take(s, 5)
        println(io, "  ", join((string(k) * "=" * string(v) for (k, v) in pairs(point)), ", "),
                " -> ", issuccess(out) ? "ok" : "FAILED",
                out.data === nothing ? "" : " (" * string(nrow(out.data)) * " rows)")
    end
    length(s) > 5 && println(io, "  ...")
    print(io, "  (DataFrame(result) for a tidy table)")
end

Base.show(io::IO, s::SweepResult) = print(io, "SweepResult(", length(s), " runs)")

"""
    sweep(circuit, analysis, parameter => values, ...; kwargs...) -> SweepResult
    sweep(f, circuit, analysis, parameter => values, ...; kwargs...) -> DataFrame

Run `circuit` once for every combination of the given `.PARAM` values.  Each
run regenerates the netlist with the swept values substituted, so any parameter
the netlist references works — component values (`Resistor(:R1, :a, :b, :rload)`),
model parameters, source amplitudes, and so on.

```julia
ckt = Circuit(VoltageSource(:V1, :in, :gnd, DC(1)),
              Resistor(:R1, :in, :out, :rtop),
              Resistor(:R2, :out, :gnd, 1e3))
param!(ckt, :rtop => 1e3)

res = sweep(ckt, OperatingPoint(), :rtop => [1e3, 2e3, 5e3]; outputs = [:out])
df  = DataFrame(res)     # one tidy table, with an `rtop` column
```

Several parameters sweep as a Cartesian product, in column-major order
(the first parameter varies fastest):

```julia
sweep(ckt, Transient(1e-5, 1e-2), :rtop => [1e3, 2e3], :cload => [1e-9, 1e-8];
      outputs = [:out])
```

With a function as the first argument, each run is reduced on the fly and the
result is a `DataFrame` with one row per parameter combination — the natural
form for design-space exploration:

```julia
gains = sweep(ckt, ACSweep(1, 1e6), :rtop => 1e3:1e3:1e4; outputs = [vdb(:out)]) do out
    (; gain_db = maximum(out["VDB(OUT)"]))
end
```

Keyword arguments:

- `outputs`, `format`: passed to [`netlist`](@ref). A run with no probes and no
  `.PRINT` card writes no table, so pass them here unless the circuit already
  carries them.
- `sim`: reuse a [`Simulator`](@ref) across runs (the default reuses one).
- `output_dir`: write each run's table to `output_dir/run_<n>.prn`, keeping
  every raw file instead of letting Xyce overwrite a temporary.
- `strict`: `true` (default) aborts the sweep on the first failed run; with
  `false` failed runs are kept and reported by [`failures`](@ref).
- `verbose`: log each run as it starts.

Runs execute sequentially: one native Xyce instance is driven at a time.
"""
function sweep(circuit::Circuit, analysis, params::Pair...;
               outputs = nothing, format = nothing,
               sim::Union{Nothing,Simulator} = nothing,
               output_dir = nothing, strict::Bool = true, verbose::Bool = false,
               read_data::Bool = true, validate::Bool = true)
    isempty(params) && throw(ArgumentError("sweep needs at least one `parameter => values` pair"))

    names_ = Symbol[Symbol(first(p)) for p in params]
    grids = [collect(last(p)) for p in params]

    simulator = sim === nothing ? Simulator() : sim
    output_dir === nothing || mkpath(output_dir)

    pts = NamedTuple[]
    outs = SimulationOutput[]

    for (i, combo) in enumerate(Iterators.product(grids...))
        point = NamedTuple{Tuple(names_)}(combo)
        verbose && @info "sweep run $i" point...

        variant = copy(circuit)
        param!(variant, (k => v for (k, v) in pairs(point))...)

        file = output_dir === nothing ? nothing : joinpath(output_dir, "run_$(i).prn")
        out = simulate(variant, analysis; outputs = outputs, format = format, sim = simulator,
                       output_file = file, strict = strict, read_data = read_data,
                       validate = validate && i == 1)

        push!(pts, point)
        push!(outs, out)
    end

    return SweepResult(names_, pts, outs)
end

function sweep(f, circuit::Circuit, analysis, params::Pair...; kwargs...)
    result = sweep(circuit, analysis, params...; kwargs...)

    rows = NamedTuple[]
    for (point, out) in result
        value = f(out)
        row = value isa NamedTuple ? value : (; value = value)
        push!(rows, merge(point, row))
    end

    return DataFrame(rows)
end
