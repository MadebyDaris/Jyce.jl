"""
    get_signal_names(data) -> Vector{String}

Every column in a results table, including the sweep/index columns.
"""
get_signal_names(data::DataFrame)::Vector{String} = string.(names(data))

"""
    independent_column(data) -> String

Name of the column holding a run's independent variable: `TIME` for a
transient, `FREQ` for an AC sweep, the swept source for a `.DC` sweep (the
first column after `Index`).

Matching is exact - a substring search would happily mistake `VDB(OUT)` for a
time column.
"""
function independent_column(data::DataFrame)::String
    name_map = Dict(uppercase(string(col)) => string(col) for col in names(data))
    for candidate in ("TIME", "FREQ", "FREQUENCY")
        haskey(name_map, candidate) && return name_map[candidate]
    end

    cols = names(data)
    if length(cols) >= 2 && uppercase(string(cols[1])) == "INDEX"
        return string(cols[2])
    end
    return string(cols[1])
end

"""
    get_time_vector(data) -> Vector{Float64}

The independent variable of a run as a vector: time for a transient, frequency
for an AC sweep, the swept value for a `.DC` sweep.  See
[`independent_column`](@ref).
"""
get_time_vector(data::DataFrame)::Vector{Float64} =
    Float64.(data[:, Symbol(independent_column(data))])

"""
    get_plot_signals(data) -> Vector{String}

Columns worth plotting: everything except `Index`, `TIME` and `FREQ`.
"""
function get_plot_signals(data::DataFrame)::Vector{String}
    independent = independent_column(data)
    out = String[]
    for col in names(data)
        name = string(col)
        (uppercase(name) in ("INDEX", "TIME", "FREQ", "FREQUENCY") || name == independent) && continue
        push!(out, name)
    end
    return out
end

"""
    get_voltage(data, node) -> Vector{Float64}

Fetch a voltage column by node name, matching case-insensitively and falling
back to a substring match (`"out"` finds `"V(OUT)"`).
"""
function get_voltage(data::DataFrame, node_name::AbstractString)::Vector{Float64}
    col = _find_column_name(data, [node_name])
    isempty(col) && error("Voltage column not found: $node_name")
    return Float64.(data[:, Symbol(col)])
end

"""
    get_current(data, element) -> Vector{Float64}

Fetch a current column by element name, with the same matching rules as
[`get_voltage`](@ref).
"""
function get_current(data::DataFrame, current_name::AbstractString)::Vector{Float64}
    col = _find_column_name(data, [current_name])
    isempty(col) && error("Current column not found: $current_name")
    return Float64.(data[:, Symbol(col)])
end

"""
    detect_iv_columns(data_or_path) -> NamedTuple

Guess which columns hold the drive voltage and the sensed current, for I–V
plots of two-terminal devices.  Returns `(; voltage_col, current_col,
available_columns)`; empty strings mean "not found", in which case pass the
column names explicitly to [`plot_iv_characteristic`](@ref).
"""
function detect_iv_columns(data::DataFrame)
    voltage_col = _find_column_name(data, ["V(IN,OUT)", "V(IN-OUT)", "V(IN)", "V(INPUT)",
                                           "V(N001)", "V(OUT)", "V(OUTPUT)"])
    current_col = _find_column_name(data, ["I(VSRC)", "I(VIN)", "I(V1)", "I(V)"])

    return (
        voltage_col = voltage_col,
        current_col = current_col,
        available_columns = string.(names(data)),
    )
end

detect_iv_columns(data_file::AbstractString) = detect_iv_columns(read_simulation_data(data_file))
