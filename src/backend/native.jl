# ---------------------------------------------------------------------------
# Native backend discovery and initialisation.
#
# Jyce talks to Xyce through the `xycesolver_julia` CxxWrap module built from
# the companion XyceSolver C++ project.  Everything in this file is concerned
# with locating that shared library, wrapping it, and reporting clearly when it
# cannot be found.
# ---------------------------------------------------------------------------

"""Environment variable holding an absolute path to the `xycesolver_julia` module."""
const XYCESOLVER_MODULE_ENV = "JYCE_XYCESOLVER_JULIA_LIB"

"""Environment variable holding an XyceSolver build/install root."""
const XYCESOLVER_ROOT_ENV = "JYCE_XYCESOLVER_ROOT"

"""Environment variable controlling whether `XyceSolver_jll` products are consulted first."""
const XYCESOLVER_PREFER_JLL_ENV = "JYCE_PREFER_JLL"

"""Environment variable that downgrades a missing native backend from an error to a warning."""
const XYCESOLVER_ALLOW_MISSING_ENV = "JYCE_ALLOW_MISSING_NATIVE"

const XYCESOLVER_JLL_MODULES = (:XyceSolver_jll,)
const XYCESOLVER_JLL_PRODUCTS = (:xycesolver_julia, :libxycesolver_julia)

const _native_initialized = Ref(false)
const _native_init_error = Ref{Union{Nothing,Exception}}(nothing)

_is_truthy(value::AbstractString) = lowercase(strip(String(value))) in ("1", "true", "yes", "on")

function _extract_jll_product_path(value)
    if value isa AbstractString
        candidate = strip(String(value))
        return isempty(candidate) ? nothing : candidate
    end

    if value isa Function
        try
            resolved = value()
            if resolved isa AbstractString
                candidate = strip(String(resolved))
                return isempty(candidate) ? nothing : candidate
            end
        catch
            return nothing
        end
    end

    return nothing
end

function _jll_module_paths()
    if !_is_truthy(get(ENV, XYCESOLVER_PREFER_JLL_ENV, "1"))
        return String[]
    end

    paths = String[]

    for modsym in XYCESOLVER_JLL_MODULES
        loaded_mod = nothing
        try
            @eval import $(modsym)
            loaded_mod = getfield(@__MODULE__, modsym)
        catch
            continue
        end

        for product_sym in XYCESOLVER_JLL_PRODUCTS
            if isdefined(loaded_mod, product_sym)
                candidate = _extract_jll_product_path(getproperty(loaded_mod, product_sym))
                candidate === nothing || push!(paths, candidate)
            end
        end
    end

    return unique(paths)
end

function _candidate_module_paths()
    module_name = "xycesolver_julia." * Libdl.dlext

    candidates = String[]
    append!(candidates, _jll_module_paths())

    if haskey(ENV, XYCESOLVER_MODULE_ENV)
        push!(candidates, ENV[XYCESOLVER_MODULE_ENV])
    end

    if haskey(ENV, XYCESOLVER_ROOT_ENV)
        root = ENV[XYCESOLVER_ROOT_ENV]
        push!(candidates, joinpath(root, "lib", module_name))
        push!(candidates, joinpath(root, "build", module_name))
    end

    # Local package layout fallback: Jyce/lib/xycesolver_julia.<ext>
    push!(candidates, joinpath(@__DIR__, "..", "..", "lib", module_name))

    # Monorepo fallback for active development.
    push!(candidates, joinpath(@__DIR__, "..", "..", "..", "XyceSolver", "build", module_name))

    return unique(map(abspath, candidates))
end

function _resolve_xycesolver_module_path()
    for path in _candidate_module_paths()
        isfile(path) && return path
    end

    searched = join(_candidate_module_paths(), "\n  - ")
    error(
        "Could not locate xycesolver_julia shared module.\n" *
        "Set " * XYCESOLVER_MODULE_ENV * " to an absolute path, or " *
        XYCESOLVER_ROOT_ENV * " to an installation root.\n" *
        "Optional: provide XyceSolver_jll and keep " * XYCESOLVER_PREFER_JLL_ENV * "=1.\n" *
        "Searched:\n  - " * searched,
    )
end

const _wrapped_module_path = let
    try
        _resolve_xycesolver_module_path()
    catch err
        _native_init_error[] = err
        nothing
    end
end

const _native_wrapped = _wrapped_module_path !== nothing

if _native_wrapped
    @wrapmodule(() -> _wrapped_module_path, :define_julia_module)
else
    # Placeholder types so the package still loads (and can be documented or
    # used for pure netlist generation) when the native module is absent.
    # Constructing one raises the same actionable error as `require_native!`.
    struct XyceSimulator
        XyceSimulator(args...) = require_native!()
    end
    struct SimulationResult end
    struct SimulationData end
end

@doc """
    XyceSimulator(verbose::Bool)

The native Xyce handle exposed by the `xycesolver_julia` C++ module.  Prefer
[`Simulator`](@ref), which wraps it and keeps track of what has been loaded;
this type stays exported so pre-0.2 code keeps working, and every Jyce function
that takes a simulator also accepts one of these.
""" XyceSimulator

@doc """
    SimulationResult

Native result object returned by the raw `runSimulation` binding, with
`success`, `error_message` and `prn_file_path` accessors (see
[`simulation_success`](@ref)).  [`simulate`](@ref) returns the richer
[`SimulationOutput`](@ref) instead.
""" SimulationResult

function __init__()
    if !_native_wrapped
        if _is_truthy(get(ENV, XYCESOLVER_ALLOW_MISSING_ENV, ""))
            @warn "Jyce native backend unavailable; continuing without native bindings." exception = (_native_init_error[], nothing)
            return
        end

        err = _native_init_error[]
        err === nothing && error("Jyce native backend could not be initialized: module path unresolved.")
        throw(err)
    end

    try
        @initcxx
        _native_initialized[] = true
        _native_init_error[] = nothing
    catch err
        _native_initialized[] = false
        _native_init_error[] = err
        if _is_truthy(get(ENV, XYCESOLVER_ALLOW_MISSING_ENV, ""))
            @warn "Jyce native backend unavailable; continuing without native bindings." exception = (err, catch_backtrace())
        else
            rethrow()
        end
    end
end

"""
    native_available() -> Bool

Return `true` when the `xycesolver_julia` backend was found and initialised, so
simulations can actually run.  Netlist generation works regardless.

See also [`require_native!`](@ref), [`native_diagnostics`](@ref).
"""
native_available() = _native_initialized[]

"""
    native_error() -> Union{Nothing,Exception}

The exception recorded while loading the native backend, or `nothing` if the
backend loaded cleanly.
"""
native_error() = _native_init_error[]

"""
    require_native!()

Throw a descriptive error unless the native backend is available.  Call this at
the top of scripts that must run simulations, so failures are reported before
any circuit is built.
"""
function require_native!()
    native_available() && return nothing

    err = native_error()
    err === nothing && error("Jyce native backend is not initialized.")

    error(
        "Jyce native backend is unavailable. " *
        "Set " * XYCESOLVER_MODULE_ENV * " or " * XYCESOLVER_ROOT_ENV *
        " to a valid build/install path. Inner error: " * sprint(showerror, err),
    )
end

"""
    native_diagnostics() -> NamedTuple

Structured report of how the backend was (or was not) resolved: the search
paths, which of them exist, the relevant environment variables, and any load
error.  Useful when filing a bug report.
"""
function native_diagnostics()
    candidates = _candidate_module_paths()
    existing = filter(isfile, candidates)

    return (
        native_available = native_available(),
        native_wrapped = _native_wrapped,
        wrapped_module_path = _wrapped_module_path,
        native_error = native_error(),
        env = (
            xycesolver_module = get(ENV, XYCESOLVER_MODULE_ENV, nothing),
            xycesolver_root = get(ENV, XYCESOLVER_ROOT_ENV, nothing),
            prefer_jll = get(ENV, XYCESOLVER_PREFER_JLL_ENV, "1"),
            allow_missing = get(ENV, XYCESOLVER_ALLOW_MISSING_ENV, ""),
        ),
        candidate_paths = candidates,
        existing_paths = existing,
    )
end

"""
    print_native_diagnostics([io]) -> NamedTuple

Print [`native_diagnostics`](@ref) in a human-readable form and return it.
"""
function print_native_diagnostics(io::IO = stdout)
    d = native_diagnostics()

    println(io, "Jyce native diagnostics")
    println(io, "  native_available: ", d.native_available)
    println(io, "  native_wrapped: ", d.native_wrapped)
    println(io, "  wrapped_module_path: ", d.wrapped_module_path)
    println(io, "  env:")
    println(io, "    ", XYCESOLVER_MODULE_ENV, "=", d.env.xycesolver_module)
    println(io, "    ", XYCESOLVER_ROOT_ENV, "=", d.env.xycesolver_root)
    println(io, "    ", XYCESOLVER_PREFER_JLL_ENV, "=", d.env.prefer_jll)
    println(io, "    ", XYCESOLVER_ALLOW_MISSING_ENV, "=", d.env.allow_missing)
    println(io, "  candidate_paths:")
    for p in d.candidate_paths
        println(io, "    - ", p)
    end
    println(io, "  existing_paths:")
    for p in d.existing_paths
        println(io, "    - ", p)
    end
    if d.native_error !== nothing
        println(io, "  native_error: ", sprint(showerror, d.native_error))
    end

    return d
end
