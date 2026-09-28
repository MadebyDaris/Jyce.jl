"""
    SimulationOutput

The result of one Xyce run.  Fields:

| field            | meaning                                                  |
|:-----------------|:---------------------------------------------------------|
| `success`        | whether Xyce reported a successful run                    |
| `error_message`  | Xyce's message when it did not                            |
| `prn_file_path`  | the `.prn` file that was written                          |
| `data`           | the parsed table, or `nothing` if it could not be read    |
| `netlist`        | the exact netlist text that was simulated                 |
| `metadata`       | parameters, plugins and analyses used for the run         |

Indexing reads columns (`res["V(OUT)"]`, `res[:out]`), `DataFrame(res)` hands
back the table, and the object implements the Tables.jl interface, so it can be
passed straight to `DataFrame`, `CSV.write`, or a plotting call.

See [`issuccess`](@ref), [`signals`](@ref), [`times`](@ref).
"""
struct SimulationOutput
    success::Bool
    error_message::String
    prn_file_path::String
    data::Union{Nothing,DataFrame}
    netlist::String
    metadata::Dict{Symbol,Any}
end

SimulationOutput(; success, error_message = "", prn_file_path = "", data = nothing,
                 netlist = "", metadata = Dict{Symbol,Any}()) =
    SimulationOutput(success, String(error_message), String(prn_file_path), data,
                     String(netlist), metadata)

"""
    SimulationFailure(output)

Thrown by [`simulate`](@ref) when Xyce reports a failed run.  The offending
[`SimulationOutput`](@ref) — including the netlist that was sent — is available
as `err.output`, and `simulate(...; strict = false)` returns it instead of
throwing.
"""
struct SimulationFailure <: Exception
    output::SimulationOutput
end

function Base.showerror(io::IO, e::SimulationFailure)
    print(io, "SimulationFailure: ", isempty(e.output.error_message) ?
              "Xyce reported a failed run" : e.output.error_message)
    isempty(e.output.prn_file_path) || print(io, "\n  output file: ", e.output.prn_file_path)
    print(io, "\n  (the netlist is available as `err.output.netlist`)")
end

"""
    issuccess(output) -> Bool

Whether the run succeeded.  Use it when calling [`simulate`](@ref) with
`strict = false`.
"""
issuccess(r::SimulationOutput) = r.success

"""
    DataFrame(output) -> DataFrame

The result table.  Errors if the output file could not be parsed.
"""
function DataFrames.DataFrame(r::SimulationOutput)
    r.data === nothing && error("no data available for this run" *
                                (isempty(r.prn_file_path) ? "" : " (expected $(r.prn_file_path))"))
    return r.data
end

"""
    signals(output) -> Vector{String}

Names of the columns Xyce wrote.
"""
signals(r::SimulationOutput) = get_signal_names(DataFrames.DataFrame(r))

"""
    times(output) -> Vector{Float64}

The independent variable of the run: time for transients, the swept source for
`.DC`, frequency for `.AC`.
"""
times(r::SimulationOutput) = get_time_vector(DataFrames.DataFrame(r))

"""
    voltage(output, node) -> Vector{Float64}

The `V(node)` column of a run.
"""
voltage(r::SimulationOutput, n::NodeLike) = get_voltage(DataFrames.DataFrame(r), "V(" * node(n) * ")")

"""
    branch_current(output, element) -> Vector{Float64}

The `I(element)` column of a run.
"""
branch_current(r::SimulationOutput, e::Union{Symbol,AbstractString}) =
    get_current(DataFrames.DataFrame(r), "I(" * String(string(e)) * ")")
branch_current(r::SimulationOutput, c::AbstractComponent) = branch_current(r, designator(c))

function Base.getindex(r::SimulationOutput, key::AbstractString)
    df = DataFrames.DataFrame(r)
    col = _find_column_name(df, [String(key)])
    isempty(col) && throw(KeyError(key))
    return Float64.(df[:, Symbol(col)])
end

function Base.getindex(r::SimulationOutput, key::Symbol)
    df = DataFrames.DataFrame(r)
    col = _find_column_name(df, ["V(" * node(key) * ")", String(key)])
    isempty(col) && throw(KeyError(key))
    return Float64.(df[:, Symbol(col)])
end

Base.getindex(r::SimulationOutput, p::Probe) = r[probe_text(p)]

Base.haskey(r::SimulationOutput, key) =
    r.data !== nothing && !isempty(_find_column_name(r.data, [String(string(key))]))

# Tables.jl: `DataFrame(res)`, `CSV.write("out.csv", res)`, `res |> ...` all work.
Tables.istable(::Type{SimulationOutput}) = true
Tables.columnaccess(::Type{SimulationOutput}) = true
Tables.columns(r::SimulationOutput) = Tables.columns(DataFrames.DataFrame(r))
Tables.schema(r::SimulationOutput) = Tables.schema(DataFrames.DataFrame(r))

function Base.show(io::IO, ::MIME"text/plain", r::SimulationOutput)
    status = r.success ? "success" : "FAILED"
    println(io, "SimulationOutput (", status, ")")
    r.success || println(io, "  error: ", r.error_message)
    isempty(r.prn_file_path) || println(io, "  file: ", r.prn_file_path)
    if r.data !== nothing
        println(io, "  rows: ", nrow(r.data))
        println(io, "  signals: ", join(get_signal_names(r.data), " "))
    end
    params = get(r.metadata, :params, nothing)
    params === nothing || isempty(params) ||
        println(io, "  params: ", join((string(k) * "=" * string(v) for (k, v) in params), ", "))
    print(io, "  (DataFrame(res) for the table, res[\"V(OUT)\"] for one column)")
end

Base.show(io::IO, r::SimulationOutput) =
    print(io, "SimulationOutput(", r.success ? "success" : "failed", ", ",
          r.data === nothing ? 0 : nrow(r.data), " rows)")
