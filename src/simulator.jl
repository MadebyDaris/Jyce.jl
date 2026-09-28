# ---------------------------------------------------------------------------
# The Julia-facing simulator handle and the `simulate` entry points.
# ---------------------------------------------------------------------------

"""
    Simulator(; verbose = false)

A live Xyce simulator.  It owns the native handle and remembers what has been
loaded into it (netlist, parameters, plugin libraries), which makes it cheap to
re-run a circuit with different parameters.

```julia
sim = Simulator()
load!(sim, netlist(my_circuit; analysis = Transient(1e-4, 1e-2)))
res = simulate(sim)
```

Most code does not need to create one explicitly: [`simulate`](@ref) makes a
simulator on demand when handed a [`Circuit`](@ref) or netlist text.

Creating a `Simulator` requires the native backend; see
[`require_native!`](@ref).
"""
mutable struct Simulator
    handle::Any
    verbose::Bool
    params::Vector{Pair{String,String}}
    plugins::Vector{String}
    includes::Vector{String}
    snippets::Vector{String}
    subcircuits::Vector{Pair{String,String}}
    netlist::String
    source::String
end

function Simulator(; verbose::Bool = false)
    require_native!()
    return Simulator(XyceSimulator(verbose), verbose, Pair{String,String}[], String[],
                     String[], String[], Pair{String,String}[], "", "")
end

Simulator(verbose::Bool) = Simulator(; verbose = verbose)

# Accept either a `Simulator` or a bare native handle everywhere.
_handle(s::Simulator) = s.handle
_handle(s) = s

function Base.show(io::IO, ::MIME"text/plain", s::Simulator)
    println(io, "Simulator(verbose = ", s.verbose, ")")
    println(io, "  loaded: ", isempty(s.source) ? "nothing" : s.source)
    isempty(s.params) || println(io, "  params: ", join((k * "=" * v for (k, v) in s.params), ", "))
    isempty(s.plugins) || println(io, "  plugins: ", join(s.plugins, ", "))
    print(io, "  ready: ", isready(s))
end
Base.show(io::IO, s::Simulator) = print(io, "Simulator(", isempty(s.source) ? "empty" : s.source, ")")

"""
    load!(simulator, netlist_text) -> Simulator
    load!(simulator, circuit; analysis, outputs, format) -> Simulator

Load a netlist into the simulator.  A `String` is treated as netlist *text*
(use [`load_file!`](@ref) for a path on disk); a [`Circuit`](@ref) is rendered
with [`netlist`](@ref) first.

Any custom definitions registered with [`register_subcircuit`](@ref),
[`add_include_file`](@ref) or [`add_inline_snippet`](@ref) are prepended by the
native layer.
"""
function load!(sim::Simulator, text::AbstractString)
    require_native!()
    full = _prepare_netlist(sim, String(text))
    ok = loadNetlistString(_handle(sim), full)
    ok || error("failed to load netlist: " * last_error(sim))
    sim.netlist = full
    sim.source = "<string>"
    return sim
end

# Xyce treats the first line of a netlist as its title and ignores it, so a
# netlist that begins with a card silently loses that card.  Jyce guarantees a
# title line, and assembles the simulator's registered definitions in front of
# the circuit itself.
function _prepare_netlist(sim::Simulator, text::AbstractString)
    prelude = definitions_prelude(sim)
    body = isempty(strip(prelude)) ? String(text) : rstrip(prelude) * "\n" * String(text)
    return _ensure_title(body)
end

function _ensure_title(text::AbstractString)
    for line in eachline(IOBuffer(text))
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, "*") && return String(text)
        break
    end
    return "* Jyce netlist\n" * String(text)
end

function load!(sim::Simulator, circuit::Circuit; kwargs...)
    return load!(sim, netlist(circuit; kwargs...))
end

"""
    load_file!(simulator, path) -> Simulator

Load a netlist file from disk.  Unlike [`load!`](@ref), custom definitions
registered on the simulator are *not* prepended: the file is used as-is.
"""
function load_file!(sim::Simulator, path::AbstractString)
    require_native!()
    isfile(path) || error("netlist file not found: $path")
    ok = loadNetlistFile(_handle(sim), String(path))
    ok || error("failed to load netlist file $path: " * last_error(sim))
    sim.netlist = read(path, String)
    sim.source = String(path)
    return sim
end

"""
    set_param!(simulator, name => value, ...) -> Simulator

Override `.PARAM` values for subsequent runs without editing the netlist.  This
is what [`sweep`](@ref) uses internally.
"""
function set_param!(sim::Simulator, ps::Pair...)
    for p in ps
        k, v = String(string(first(p))), spice(last(p))
        setParameter(_handle(sim), k, v)
        idx = findfirst(q -> first(q) == k, sim.params)
        idx === nothing ? push!(sim.params, k => v) : (sim.params[idx] = k => v)
    end
    return sim
end

"""
    clear_params!(simulator) -> Simulator

Drop all parameter overrides set with [`set_param!`](@ref).
"""
function clear_params!(sim::Simulator)
    clearParameters(_handle(sim))
    empty!(sim.params)
    return sim
end

"""
    add_plugin!(simulator, library_path...) -> Simulator

Register compiled Verilog-A plugin libraries (`.so`/`.dylib`/`.dll`) with the
simulator, so the devices they define can be instantiated with
[`PluginDevice`](@ref).
"""
function add_plugin!(sim::Simulator, paths::AbstractString...)
    for path in paths
        isfile(path) || error("plugin library not found: $path")
        addPluginLibrary(_handle(sim), String(path))
        path in sim.plugins || push!(sim.plugins, String(path))
    end
    return sim
end

"""
    clear_plugins!(simulator) -> Simulator

Forget every plugin library registered with [`add_plugin!`](@ref).
"""
function clear_plugins!(sim::Simulator)
    clearPluginLibraries(_handle(sim))
    empty!(sim.plugins)
    return sim
end

"""
    output_suffix!(simulator, suffix) -> Simulator

Set the suffix appended to generated output file names, to keep concurrent runs
from overwriting each other.
"""
function output_suffix!(sim::Simulator, suffix::AbstractString)
    setOutputFileSuffix(_handle(sim), String(suffix))
    return sim
end

"""
    last_error(simulator) -> String

The most recent error reported by the native layer, or `""`.
"""
function last_error(sim)
    try
        return String(getLastError(_handle(sim)))
    catch
        return ""
    end
end

"""
    isready(simulator) -> Bool

Whether a netlist has been loaded successfully and the simulator can run.
"""
function Base.isready(sim::Simulator)
    try
        return Bool(isReady(_handle(sim)))
    catch
        return false
    end
end

"""
    debug_state(simulator) -> String

Native-side description of the simulator's internal state; for bug reports.
"""
debug_state(sim) = String(debugState(_handle(sim)))

"""
    prn_path(simulator) -> String

Path of the `.prn` file the last run wrote.
"""
prn_path(sim) = String(getPrnFilePath(_handle(sim)))

"""
    export_csv(simulator, prn_file, csv_file) -> Bool

Convert an Xyce `.prn` file to CSV using the native exporter.
"""
export_csv(sim, prn_file::AbstractString, csv_file::AbstractString) =
    Bool(exportToCSV(_handle(sim), String(prn_file), String(csv_file)))

# --- running ---------------------------------------------------------------

# Where results land.
#
# Left to itself, Xyce names its output after the netlist file - which is a
# temporary file the native layer creates - and appends an analysis tag, so an
# .AC run of `/tmp/xyce_netlist_42.cir` writes `/tmp/xyce_netlist_42.cir.FD.prn`.
# Jyce therefore always asks for an explicit output file, and still looks for
# the tagged variants when reading the table back.
const _ANALYSIS_FILE_TAGS = (".FD", ".NOISE", ".HB", ".TD")
const _RUN_COUNTER = Ref(0)

"""
    default_output_dir() -> String

Directory Jyce writes result files to when no `output_file` is given: a
per-process folder under `tempdir()`.  Set `JYCE_OUTPUT_DIR` to override it.
"""
default_output_dir() = get(ENV, "JYCE_OUTPUT_DIR",
                           joinpath(tempdir(), "jyce", string(getpid())))

function _default_output_file()
    dir = default_output_dir()
    mkpath(dir)
    _RUN_COUNTER[] += 1
    return joinpath(dir, "run_$(_RUN_COUNTER[]).prn")
end

function _resolve_output_path(requested, reported)
    candidates = String[]
    for p in (requested, reported)
        p === nothing && continue
        text = String(p)
        isempty(text) && continue
        push!(candidates, text)
        base, ext = splitext(text)
        for tag in _ANALYSIS_FILE_TAGS
            push!(candidates, base * tag * ext)
        end
        # Xyce's own naming: <netlist name including extension> + tag + .prn
        for netlist_ext in (".cir", ".net")
            push!(candidates, base * netlist_ext * ext)
            for tag in _ANALYSIS_FILE_TAGS
                push!(candidates, base * netlist_ext * tag * ext)
            end
        end
    end

    for c in candidates
        isfile(c) && return c
    end
    return isempty(candidates) ? "" : first(candidates)
end

"""
    simulate(simulator; output_file = nothing, strict = true, read_data = true) -> SimulationOutput
    simulate(circuit[, analysis]; kwargs...) -> SimulationOutput
    simulate(netlist_text; kwargs...) -> SimulationOutput

Run a simulation and return a [`SimulationOutput`](@ref).

For a [`Circuit`](@ref), the netlist is generated, a simulator is created (or
the one passed as `sim` is reused), plugins and parameters are applied, and the
run is executed.  `analysis` and `outputs` override what the circuit carries,
which makes it easy to run the same circuit several ways:

```julia
op   = simulate(ckt, OperatingPoint())
tran = simulate(ckt, Transient(1e-5, 1e-2); outputs = [:in, :out])
```

Keyword arguments:

- `analysis`, `outputs`, `format`: passed to [`netlist`](@ref).
- `sim`: reuse an existing [`Simulator`](@ref).
- `params`: `.PARAM` overrides applied before the run.
- `plugins`: extra plugin libraries to load.
- `output_file`: where Xyce should write its table (directories are created).
  With none, Jyce picks a unique file under [`default_output_dir`](@ref) and
  reports it as `output.prn_file_path`.
- `strict`: throw [`SimulationFailure`](@ref) on failure (default `true`);
  with `strict = false` the failed output is returned instead.
- `validate`: run [`validate`](@ref) on the circuit first (default `true`).
  Worth keeping on: Xyce reports netlist errors by aborting the process, which
  ends the Julia session.
- `read_data`: parse the output file into a `DataFrame` (default `true`).
"""
function simulate(sim::Simulator; output_file = nothing, strict::Bool = true,
                  read_data::Bool = true, metadata::Dict{Symbol,Any} = Dict{Symbol,Any}())
    require_native!()

    out = output_file === nothing ? _default_output_file() : String(output_file)
    dir = dirname(abspath(out))
    isempty(dir) || mkpath(dir)
    raw = runSimulationOutput(_handle(sim), out)

    ok = Bool(success(raw))
    message = String(error_message(raw))
    path = _resolve_output_path(out, String(prn_file_path(raw)))

    data = nothing
    if read_data && ok
        if !isempty(path) && isfile(path)
            try
                data = read_simulation_data(path)
            catch err
                @warn "Simulation succeeded but its output could not be parsed" path exception = err
            end
        else
            @warn """Simulation succeeded but wrote no output table. \
                     Did the netlist request any output? Pass `outputs = [...]`, \
                     attach probes with `output!`, or add a .PRINT card.""" expected = path
        end
    end

    meta = merge(Dict{Symbol,Any}(:params => copy(sim.params), :plugins => copy(sim.plugins)), metadata)
    output = SimulationOutput(ok, message, path, data, sim.netlist, meta)

    (strict && !ok) && throw(SimulationFailure(output))
    return output
end

function simulate(circuit::Circuit, analysis = nothing;
                  outputs = nothing, format = nothing,
                  sim::Union{Nothing,Simulator} = nothing,
                  params = (), plugins = (),
                  output_file = nothing, strict::Bool = true, read_data::Bool = true,
                  verbose::Bool = false, validate::Bool = true)
    validate && Jyce.validate(circuit)
    simulator = sim === nothing ? Simulator(; verbose = verbose) : sim

    for path in Iterators.flatten((circuit.plugins, plugins))
        add_plugin!(simulator, path)
    end

    text = netlist(circuit; analysis = analysis, outputs = outputs, format = format)
    load!(simulator, text)

    isempty(params) || set_param!(simulator, (Symbol(first(p)) => last(p) for p in pairs(params))...)

    analyses = analysis === nothing ? circuit.analyses :
               analysis isa AbstractAnalysis ? [analysis] : collect(analysis)
    isempty(analyses) && @warn "circuit has no analysis; Xyce will only parse the netlist"

    meta = Dict{Symbol,Any}(:analyses => analyses, :title => circuit.title)
    return simulate(simulator; output_file = output_file, strict = strict,
                    read_data = read_data, metadata = meta)
end

function simulate(text::AbstractString; sim::Union{Nothing,Simulator} = nothing,
                  params = (), plugins = (), output_file = nothing,
                  strict::Bool = true, read_data::Bool = true, verbose::Bool = false)
    simulator = sim === nothing ? Simulator(; verbose = verbose) : sim
    for path in plugins
        add_plugin!(simulator, path)
    end
    load!(simulator, text)
    isempty(params) || set_param!(simulator, (Symbol(first(p)) => last(p) for p in pairs(params))...)
    return simulate(simulator; output_file = output_file, strict = strict, read_data = read_data)
end

"""
    simulate_file(path; kwargs...) -> SimulationOutput

Run a netlist file from disk.  Accepts the same keywords as [`simulate`](@ref).
"""
function simulate_file(path::AbstractString; sim::Union{Nothing,Simulator} = nothing,
                       params = (), plugins = (), output_file = nothing,
                       strict::Bool = true, read_data::Bool = true, verbose::Bool = false)
    simulator = sim === nothing ? Simulator(; verbose = verbose) : sim
    for p in plugins
        add_plugin!(simulator, p)
    end
    load_file!(simulator, path)
    isempty(params) || set_param!(simulator, (Symbol(first(p)) => last(p) for p in pairs(params))...)
    return simulate(simulator; output_file = output_file, strict = strict, read_data = read_data)
end
