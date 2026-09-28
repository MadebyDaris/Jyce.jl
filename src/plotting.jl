# Plot helpers and Plots.jl recipes.
_as_dataframe(df::DataFrame) = df
_as_dataframe(r::SimulationOutput) = DataFrames.DataFrame(r)
_as_dataframe(path::AbstractString) = read_simulation_data(path)

function _finish_plot(p, output_file)
    if !isempty(String(output_file))
        dir = dirname(abspath(String(output_file)))
        isempty(dir) || mkpath(dir)
        savefig(p, String(output_file))
    else
        display(p)
    end
    return p
end

"""
    plot_transient_voltages(source; nodes = String[], output_file = "", title, xlabel, ylabel)

Plot signals against the independent variable.  `source` may be a
[`SimulationOutput`](@ref), a `DataFrame`, or the path of a `.prn`/`.csv` file.
With no `nodes`, every plottable column is drawn.  When `output_file` is given
the figure is saved there; otherwise it is displayed.

```julia
res = simulate(ckt, Transient(1e-5, 2e-3); outputs = [:in, :out])
plot_transient_voltages(res; nodes = ["V(IN)", "V(OUT)"], output_file = "plots/tran.png")
```
"""
function plot_transient_voltages(source;
                                 nodes::Vector{String} = String[],
                                 output_file::AbstractString = "",
                                 title::AbstractString = "Transient Analysis",
                                 xlabel::AbstractString = "Time (s)",
                                 ylabel::AbstractString = "Voltage (V)")
    data = _as_dataframe(source)
    time = get_time_vector(data)

    selected = isempty(nodes) ? get_plot_signals(data) : nodes
    isempty(selected) && error("no plottable signals found")

    resolved = String[]
    for n in selected
        col = _find_column_name(data, [n])
        isempty(col) && error("signal not found: $n (available: $(join(get_signal_names(data), ", ")))")
        push!(resolved, col)
    end

    p = plot(time, data[:, Symbol(resolved[1])];
             label = resolved[1], linewidth = 2, xlabel = xlabel, ylabel = ylabel,
             title = title, grid = true, legend = :best)

    for col in resolved[2:end]
        plot!(p, time, data[:, Symbol(col)]; label = col, linewidth = 2)
    end

    return _finish_plot(p, output_file)
end

"""
    plot_iv_characteristic(source; voltage_col, voltage_minus_col, current_col,
                           output_file, title, cycle_overlay, invert_current,
                           cycle_selection)

Plot current against voltage — the pinched hysteresis loop for memristive
devices.  Columns are detected with [`detect_iv_columns`](@ref) unless given
explicitly; when both an input and an output node are found the voltage across
the device is used.

- `invert_current` (default `true`) flips the sign, since the current through a
  voltage source is measured into its positive terminal.
- `cycle_selection` is `:all`, `:first` or `:last`, using zero crossings of the
  drive voltage to isolate one period.
- `cycle_overlay` colours the trace by sample index so the direction of travel
  around the loop is visible.
"""
function plot_iv_characteristic(source;
                                voltage_col::AbstractString = "",
                                voltage_minus_col::AbstractString = "",
                                current_col::AbstractString = "",
                                output_file::AbstractString = "",
                                title::AbstractString = "I-V Characteristic",
                                cycle_overlay::Bool = true,
                                invert_current::Bool = true,
                                last_cycle_only::Bool = false,
                                cycle_selection::Symbol = :all)
    data = _as_dataframe(source)

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
            resolved_voltage_col = _find_column_name(data, ["V(IN,OUT)", "V(IN-OUT)", "V(IN)",
                                                            "V(INPUT)", "V(N001)", "V(OUT)", "V(OUTPUT)"])
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
        v = v .- Float64.(data[:, Symbol(resolved_voltage_minus_col)])
    end

    i = Float64.(data[:, Symbol(resolved_current_col)])
    invert_current && (i = .-i)

    selected_cycle = last_cycle_only ? :last : cycle_selection

    if selected_cycle != :all
        crossing_starts = Int[]
        for k in 1:(length(v)-1)
            if v[k] <= 0.0 && v[k+1] > 0.0
                push!(crossing_starts, k + 1)
            end
        end

        if length(crossing_starts) >= 2
            if selected_cycle == :first
                i0, i1 = crossing_starts[1], crossing_starts[2] - 1
                v, i = v[i0:i1], i[i0:i1]
            elseif selected_cycle == :last
                i0, i1 = crossing_starts[end-1], crossing_starts[end] - 1
                v, i = v[i0:i1], i[i0:i1]
            end
        end
    end

    p = if cycle_overlay
        q = plot(v, i; line_z = 1:length(v), color = :plasma, colorbar = false,
                 xlabel = "Voltage (V)", ylabel = "Current (A)", title = title,
                 linewidth = 1.5, label = "", grid = true)
        scatter!(q, [0.0], [0.0]; color = :red, markersize = 5, label = "origin")
        q
    else
        plot(v, i; xlabel = "Voltage (V)", ylabel = "Current (A)", title = title,
             linewidth = 1.5, label = "I-V", grid = true)
    end

    return _finish_plot(p, output_file)
end

"""
    plot_bode(source; node = nothing, output_file = "", title = "Frequency Response")

Magnitude/phase plot of an [`ACSweep`](@ref) run.  The `VDB(...)` and `VP(...)`
columns are located automatically; pass `node` to pick one when the run printed
several.  Returns a two-panel plot.
"""
function plot_bode(source; node = nothing, output_file::AbstractString = "",
                   title::AbstractString = "Frequency Response")
    data = _as_dataframe(source)
    freq_col = _find_column_name(data, ["FREQ", "FREQUENCY"])
    isempty(freq_col) && error("no FREQ column found; run an ACSweep and print VDB/VP")
    f = Float64.(data[:, Symbol(freq_col)])

    suffix = node === nothing ? "" : "(" * uppercase(string(node)) * ")"
    mag_col = _find_column_name(data, ["VDB" * suffix, "VM" * suffix, "VDB", "VM"])
    phase_col = _find_column_name(data, ["VP" * suffix, "VP"])
    isempty(mag_col) && error("no magnitude column (VDB/VM) found in $(names(data))")

    mag = plot(f, Float64.(data[:, Symbol(mag_col)]); xscale = :log10, xlabel = "Frequency (Hz)",
               ylabel = "Magnitude (dB)", label = mag_col, linewidth = 2, grid = true, title = title)

    p = if isempty(phase_col)
        mag
    else
        ph = plot(f, Float64.(data[:, Symbol(phase_col)]); xscale = :log10,
                  xlabel = "Frequency (Hz)", ylabel = "Phase (deg)", label = phase_col,
                  linewidth = 2, grid = true)
        plot(mag, ph; layout = (2, 1), size = (700, 600))
    end

    return _finish_plot(p, output_file)
end

# Plots.jl recipes

"""
    plot(output::SimulationOutput; signals = nothing)

Plot recipe: every printed signal against the run's independent variable.
Restrict the series with `signals = ["V(OUT)"]`.
"""
@recipe function f(r::SimulationOutput; signals = nothing)
    df = DataFrames.DataFrame(r)
    x = get_time_vector(df)
    cols = signals === nothing ? get_plot_signals(df) : [_find_column_name(df, [String(s)]) for s in signals]
    cols = filter(!isempty, cols)
    isempty(cols) && error("no plottable signals in this run")

    independent = independent_column(df)
    xlabel --> (uppercase(independent) == "TIME" ? "Time (s)" :
                startswith(uppercase(independent), "FREQ") ? "Frequency (Hz)" : independent)
    ylabel --> "Value"
    label --> reshape(cols, 1, :)
    linewidth --> 2
    grid --> true

    return x, reduce(hcat, (Float64.(df[:, Symbol(c)]) for c in cols))
end

"""
    plot(result::SweepResult; signal)

Plot recipe: one series per sweep run for the chosen `signal` (the first
plottable column when omitted), labelled with the parameter values.
"""
@recipe function f(s::SweepResult; signal = nothing)
    first_data = findfirst(o -> o.data !== nothing, s.outputs)
    if first_data !== nothing
        independent = independent_column(s.outputs[first_data].data)
        xlabel --> (uppercase(independent) == "TIME" ? "Time (s)" :
                    startswith(uppercase(independent), "FREQ") ? "Frequency (Hz)" : independent)
    end
    ylabel --> "Value"
    linewidth --> 2
    grid --> true

    for (point, out) in s
        out.data === nothing && continue
        df = out.data
        col = signal === nothing ? first(get_plot_signals(df)) : _find_column_name(df, [String(signal)])
        isempty(col) && continue

        @series begin
            label := join((string(k) * "=" * string(v) for (k, v) in pairs(point)), ", ")
            get_time_vector(df), Float64.(df[:, Symbol(col)])
        end
    end
end
