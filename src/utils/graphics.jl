# Utilities for reading Xyce output files and plotting transient/I-V data.

_find_column_name(data::DataFrame, candidates::Vector{String}) = begin
    name_map = Dict(uppercase(string(col)) => string(col) for col in names(data))
    for candidate in candidates
        key = uppercase(candidate)
        if haskey(name_map, key)
            return name_map[key]
        end
    end

    for col in names(data)
        col_str = string(col)
        up = uppercase(col_str)
        for candidate in candidates
            if occursin(uppercase(candidate), up)
                return col_str
            end
        end
    end

    return ""
end

_to_float_or_missing(x) = begin
    if x isa Missing
        return missing
    elseif x isa Number
        return Float64(x)
    elseif x isa AbstractString
        v = tryparse(Float64, strip(x))
        return isnothing(v) ? missing : v
    else
        return missing
    end
end

function _read_csv_data(csv_file::AbstractString)::DataFrame
    if !isfile(csv_file)
        error("CSV file not found: $csv_file")
    end

    raw_df = CSV.read(csv_file, DataFrame)
    if nrow(raw_df) == 0
        error("CSV file is empty: $csv_file")
    end

    colnames = names(raw_df)
    parsed_cols = Dict{Any, Vector{Union{Missing, Float64}}}()
    for col in colnames
        parsed_cols[col] = _to_float_or_missing.(raw_df[:, col])
    end

    valid_rows = trues(nrow(raw_df))
    for col in colnames
        valid_rows .&= .!ismissing.(parsed_cols[col])
    end

    if !any(valid_rows)
        error("No numeric data rows found in CSV: $csv_file")
    end

    clean_df = DataFrame()
    for col in colnames
        clean_df[!, col] = Float64.(parsed_cols[col][valid_rows])
    end

    return clean_df
end

function _read_prn_data(prn_file::AbstractString)::DataFrame
    if !isfile(prn_file)
        error("PRN file not found: $prn_file")
    end

    lines = readlines(prn_file)
    if isempty(lines)
        error("PRN file is empty: $prn_file")
    end

    header_tokens = String[]
    header_index = 0
    for (i, line) in enumerate(lines)
        s = strip(line)
        if isempty(s)
            continue
        end
        tokens = split(s)
        if length(tokens) >= 2
            header_tokens = String.(tokens)
            header_index = i
            break
        end
    end

    if isempty(header_tokens)
        error("Could not find PRN header in: $prn_file")
    end

    col_count = length(header_tokens)
    columns = [Float64[] for _ in 1:col_count]

    for line in lines[(header_index + 1):end]
        s = strip(line)
        if isempty(s)
            continue
        end

        tokens = split(s)
        if length(tokens) != col_count
            continue
        end

        parsed = Vector{Float64}(undef, col_count)
        valid = true
        for i in 1:col_count
            v = tryparse(Float64, tokens[i])
            if isnothing(v)
                valid = false
                break
            end
            parsed[i] = v
        end

        if !valid
            continue
        end

        for i in 1:col_count
            push!(columns[i], parsed[i])
        end
    end

    if isempty(columns[1])
        error("No numeric data rows found in PRN: $prn_file")
    end

    df = DataFrame()
    for i in 1:col_count
        df[!, Symbol(header_tokens[i])] = columns[i]
    end
    return df
end

function read_simulation_data(data_file::AbstractString)::DataFrame
    if !isfile(data_file)
        error("Data file not found: $data_file")
    end

    ext = lowercase(splitext(data_file)[2])
    if ext == ".prn"
        return _read_prn_data(data_file)
    elseif ext == ".csv"
        return _read_csv_data(data_file)
    end

    try
        return _read_csv_data(data_file)
    catch
        return _read_prn_data(data_file)
    end
end

get_signal_names(data::DataFrame)::Vector{String} = string.(names(data))

function get_time_vector(data::DataFrame)::Vector{Float64}
    time_col = _find_column_name(data, ["TIME", "T"])
    if isempty(time_col)
        if ncol(data) >= 2
            first_col = uppercase(string(names(data)[1]))
            if first_col == "INDEX"
                return Float64.(data[:, 2])
            end
        end
        return Float64.(data[:, 1])
    end
    return Float64.(data[:, Symbol(time_col)])
end

function get_plot_signals(data::DataFrame)::Vector{String}
    out = String[]
    for col in names(data)
        name = string(col)
        up = uppercase(name)
        if up == "INDEX" || up == "TIME" || up == "FREQ"
            continue
        end
        push!(out, name)
    end
    return out
end

function get_voltage(data::DataFrame, node_name::AbstractString)::Vector{Float64}
    col = _find_column_name(data, [node_name])
    isempty(col) && error("Voltage column not found: $node_name")
    return Float64.(data[:, Symbol(col)])
end

function get_current(data::DataFrame, current_name::AbstractString)::Vector{Float64}
    col = _find_column_name(data, [current_name])
    isempty(col) && error("Current column not found: $current_name")
    return Float64.(data[:, Symbol(col)])
end

function detect_iv_columns(data::DataFrame)
    voltage_col = _find_column_name(data, ["V(IN,OUT)", "V(IN-OUT)", "V(IN)", "V(INPUT)", "V(N001)", "V(OUT)", "V(OUTPUT)"])
    current_col = _find_column_name(data, ["I(VSRC)", "I(VIN)", "I(V1)", "I(V)"])

    return (
        voltage_col = voltage_col,
        current_col = current_col,
        available_columns = string.(names(data)),
    )
end

detect_iv_columns(data_file::AbstractString) = detect_iv_columns(read_simulation_data(data_file))

function plot_transient_voltages(data_file::AbstractString;
                                 nodes::Vector{String}=String[],
                                 output_file::AbstractString="",
                                 title::AbstractString="Transient Analysis",
                                 xlabel::AbstractString="Time (s)",
                                 ylabel::AbstractString="Voltage (V)")
    data = read_simulation_data(data_file)
    time = get_time_vector(data)

    if isempty(nodes)
        nodes = get_plot_signals(data)
    end
    isempty(nodes) && error("No plottable transient signals found in $data_file")

    p = plot(time, data[:, Symbol(nodes[1])],
             label=nodes[1],
             linewidth=2,
             xlabel=xlabel,
             ylabel=ylabel,
             title=title,
             grid=true,
             legend=:best)

    for node in nodes[2:end]
        plot!(p, time, data[:, Symbol(node)], label=node, linewidth=2)
    end

    if !isempty(output_file)
        mkpath(dirname(output_file))
        savefig(p, output_file)
    else
        display(p)
    end

    return p
end

function plot_iv_characteristic(data_file::AbstractString;
                                voltage_col::AbstractString="",
                                voltage_minus_col::AbstractString="",
                                current_col::AbstractString="",
                                output_file::AbstractString="",
                                title::AbstractString="I-V Characteristic",
                                cycle_overlay::Bool=true,
                                invert_current::Bool=true,
                                last_cycle_only::Bool=false,
                                cycle_selection::Symbol=:all)
    data = read_simulation_data(data_file)

    resolved_voltage_col = voltage_col
    resolved_voltage_minus_col = voltage_minus_col
    resolved_current_col = current_col

    if isempty(resolved_voltage_col)
        in_col = _find_column_name(data, ["V(IN)", "V(INPUT)", "VIN", "V(N001)"])
        out_col = _find_column_name(data, ["V(OUT)", "V(OUTPUT)"])
        if !isempty(in_col) && !isempty(out_col)
            resolved_voltage_col = in_col
            resolved_voltage_minus_col = out_col
        else
            resolved_voltage_col = _find_column_name(data, ["V(IN,OUT)", "V(IN-OUT)", "V(IN)", "V(INPUT)", "V(N001)", "V(OUT)", "V(OUTPUT)"])
        end
    else
        resolved_voltage_col = _find_column_name(data, [resolved_voltage_col])
        if !isempty(resolved_voltage_minus_col)
            resolved_voltage_minus_col = _find_column_name(data, [resolved_voltage_minus_col])
        end
    end

    if isempty(resolved_current_col)
        resolved_current_col = _find_column_name(data, ["I(VSRC)", "I(VIN)", "I(V1)", "I(V)"])
    else
        resolved_current_col = _find_column_name(data, [resolved_current_col])
    end

    isempty(resolved_voltage_col) && error("Voltage column not found. Available: $(names(data))")
    isempty(resolved_current_col) && error("Current column not found. Available: $(names(data))")

    v = Float64.(data[:, Symbol(resolved_voltage_col)])
    if !isempty(resolved_voltage_minus_col)
        v .-= Float64.(data[:, Symbol(resolved_voltage_minus_col)])
    end

    i = Float64.(data[:, Symbol(resolved_current_col)])
    if invert_current
        i = .-i
    end

    selected_cycle = last_cycle_only ? :last : cycle_selection

    if selected_cycle != :all
        crossing_starts = Int[]
        for k in 1:(length(v) - 1)
            if v[k] <= 0.0 && v[k + 1] > 0.0
                push!(crossing_starts, k + 1)
            end
        end

        if length(crossing_starts) >= 2
            if selected_cycle == :first
                i0 = crossing_starts[1]
                i1 = crossing_starts[2] - 1
                v = v[i0:i1]
                i = i[i0:i1]
            elseif selected_cycle == :last
                i0 = crossing_starts[end - 1]
                i1 = crossing_starts[end] - 1
                v = v[i0:i1]
                i = i[i0:i1]
            end
        end
    end

    if cycle_overlay
        n = length(v)
        p = plot(v, i,
                 line_z=1:n,
                 color=:plasma,
                 colorbar=false,
                 xlabel="Voltage (V)",
                 ylabel="Current (A)",
                 title=title,
                 linewidth=1.5,
                 label="",
                 grid=true)
        scatter!(p, [0.0], [0.0], color=:red, markersize=5, label="origin")
    else
        p = plot(v, i,
                 xlabel="Voltage (V)",
                 ylabel="Current (A)",
                 title=title,
                 linewidth=1.5,
                 label="I-V",
                 grid=true)
    end

    if !isempty(output_file)
        mkpath(dirname(output_file))
        savefig(p, output_file)
    else
        display(p)
    end

    return p
end
