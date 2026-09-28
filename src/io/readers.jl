# Readers for the tabular files Xyce writes (.prn, .csv).

function _find_column_name(data::DataFrame, candidates::Vector{String})
    name_map = Dict(uppercase(string(col)) => string(col) for col in names(data))
    for candidate in candidates
        key = uppercase(candidate)
        haskey(name_map, key) && return name_map[key]
    end

    for col in names(data)
        col_str = string(col)
        up = uppercase(col_str)
        for candidate in candidates
            occursin(uppercase(candidate), up) && return col_str
        end
    end

    return ""
end

function _to_float_or_missing(x)
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
    isfile(csv_file) || error("CSV file not found: $csv_file")

    raw_df = CSV.read(csv_file, DataFrame)
    nrow(raw_df) == 0 && error("CSV file is empty: $csv_file")

    colnames = names(raw_df)
    parsed_cols = Dict{Any,Vector{Union{Missing,Float64}}}()
    for col in colnames
        parsed_cols[col] = _to_float_or_missing.(raw_df[:, col])
    end

    valid_rows = trues(nrow(raw_df))
    for col in colnames
        valid_rows .&= .!ismissing.(parsed_cols[col])
    end

    any(valid_rows) || error("No numeric data rows found in CSV: $csv_file")

    clean_df = DataFrame()
    for col in colnames
        clean_df[!, col] = Float64.(parsed_cols[col][valid_rows])
    end

    return clean_df
end

function _read_prn_data(prn_file::AbstractString)::DataFrame
    isfile(prn_file) || error("PRN file not found: $prn_file")

    lines = readlines(prn_file)
    isempty(lines) && error("PRN file is empty: $prn_file")

    header_tokens = String[]
    header_index = 0
    for (i, line) in enumerate(lines)
        s = strip(line)
        isempty(s) && continue
        tokens = split(s)
        if length(tokens) >= 2
            header_tokens = String.(tokens)
            header_index = i
            break
        end
    end

    isempty(header_tokens) && error("Could not find PRN header in: $prn_file")

    col_count = length(header_tokens)
    columns = [Float64[] for _ in 1:col_count]

    for line in lines[(header_index+1):end]
        s = strip(line)
        isempty(s) && continue

        tokens = split(s)
        length(tokens) == col_count || continue

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

        valid || continue

        for i in 1:col_count
            push!(columns[i], parsed[i])
        end
    end

    isempty(columns[1]) && error("No numeric data rows found in PRN: $prn_file")

    df = DataFrame()
    for i in 1:col_count
        df[!, Symbol(header_tokens[i])] = columns[i]
    end
    return df
end

"""
    read_simulation_data(path) -> DataFrame

Read an Xyce output table into a `DataFrame`.  `.prn` (whitespace separated,
one header row) and `.csv` files are detected by extension; unknown extensions
are tried as CSV and then as PRN.  Rows that cannot be parsed as numbers — such
as Xyce's trailing `End of Xyce(TM) Simulation` line — are skipped.

```julia
data = read_simulation_data("run.prn")
names(data)   # ["Index", "TIME", "V(IN)", "V(OUT)"]
```
"""
function read_simulation_data(data_file::AbstractString)::DataFrame
    isfile(data_file) || error("Data file not found: $data_file")

    ext = lowercase(splitext(data_file)[2])
    ext == ".prn" && return _read_prn_data(data_file)
    ext == ".csv" && return _read_csv_data(data_file)

    try
        return _read_csv_data(data_file)
    catch
        return _read_prn_data(data_file)
    end
end
