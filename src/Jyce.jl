module Jyce

using CxxWrap
using Libdl
using CSV
using DataFrames
using Plots

include("utils/graphics.jl")

const XYCESOLVER_MODULE_ENV = "JYCE_XYCESOLVER_JULIA_LIB"
const XYCESOLVER_ROOT_ENV = "JYCE_XYCESOLVER_ROOT"
const XYCESOLVER_PREFER_JLL_ENV = "JYCE_PREFER_JLL"
const XYCESOLVER_ALLOW_MISSING_ENV = "JYCE_ALLOW_MISSING_NATIVE"

const XYCESOLVER_JLL_MODULES = (:XyceSolver_jll,)
const XYCESOLVER_JLL_PRODUCTS = (:xycesolver_julia, :libxycesolver_julia)

const _native_initialized = Ref(false)
const _native_init_error = Ref{Union{Nothing,Exception}}(nothing)

_is_truthy(value::String) = value in ("1", "true", "TRUE", "yes", "YES", "on", "ON")

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
				if candidate !== nothing
					push!(paths, candidate)
				end
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
	push!(candidates, joinpath(@__DIR__, "..", "lib", module_name))

	# Monorepo fallback for active development.
	push!(candidates, joinpath(@__DIR__, "..", "..", "XyceSolver", "build", module_name))

	return unique(map(abspath, candidates))
end

function _resolve_xycesolver_module_path()
	for path in _candidate_module_paths()
		if isfile(path)
			return path
		end
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
end

function __init__()
	if !_native_wrapped
		if _is_truthy(get(ENV, XYCESOLVER_ALLOW_MISSING_ENV, ""))
			@warn "Jyce native backend unavailable; continuing without native bindings." exception=(_native_init_error[], nothing)
			return
		end

		err = _native_init_error[]
		if err === nothing
			error("Jyce native backend could not be initialized: module path unresolved.")
		end
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
			@warn "Jyce native backend unavailable; continuing without native bindings." exception=(err, catch_backtrace())
		else
			rethrow()
		end
	end
end

native_available() = _native_initialized[]

function native_error()
	return _native_init_error[]
end

function require_native!()
	if native_available()
		return nothing
	end

	err = native_error()
	if err === nothing
		error("Jyce native backend is not initialized.")
	end

	error(
		"Jyce native backend is unavailable. " *
		"Set " * XYCESOLVER_MODULE_ENV * " or " * XYCESOLVER_ROOT_ENV *
		" to a valid build/install path. Inner error: " * sprint(showerror, err),
	)
end

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

function print_native_diagnostics(io::IO=stdout)
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

simulation_success(result) = success(result)
simulation_error_message(result) = error_message(result)
simulation_prn_file_path(result) = prn_file_path(result)

function register_subcircuit(sim::XyceSimulator, name::String, definition::String)
	registerSubcircuitDefinition(sim, name, definition)
	return sim
end

function add_include_file(sim::XyceSimulator, filepath::String)
	appendIncludeFile(sim, filepath)
	return sim
end

function add_inline_snippet(sim::XyceSimulator, snippet::String)
	appendInlineSnippet(sim, snippet)
	return sim
end

function clear_custom_components(sim::XyceSimulator)
	clearCustomDefinitions(sim)
	return sim
end

custom_components_prelude(sim::XyceSimulator) = String(getCustomDefinitionsPrelude(sim))

function add_plugin_library(sim::XyceSimulator, plugin_path::String)
	addPluginLibrary(sim, plugin_path)
	return sim
end

function clear_plugin_libraries(sim::XyceSimulator)
	clearPluginLibraries(sim)
	return sim
end

function run_simulation_data(sim::XyceSimulator; output_file::Union{Nothing,String}=nothing)
	raw = output_file === nothing ? runSimulationData(sim) : runSimulationDataOutput(sim, output_file)
	parameter_pairs_jl = String[String(x) for x in parameter_pairs(raw)]
	plugin_libraries_jl = String[String(x) for x in plugin_libraries(raw)]
	time_points_jl = Float64[Float64(x) for x in time_points(raw)]
	node_names_jl = String[String(x) for x in node_names(raw)]
	node_voltages_jl = Vector{Float64}[Float64[Float64(x) for x in row] for row in node_voltages(raw)]
	return (
		success = success(raw),
		error_message = String(error_message(raw)),
		prn_file_path = String(prn_file_path(raw)),
		parameter_pairs = parameter_pairs_jl,
		plugin_libraries = plugin_libraries_jl,
		time_points = time_points_jl,
		node_names = node_names_jl,
		node_voltages = node_voltages_jl,
	)
end

greet() = print("Jyce is ready.")

export XyceSimulator
export SimulationResult
export native_available
export native_error
export require_native!
export native_diagnostics
export print_native_diagnostics
export simulation_success
export simulation_error_message
export simulation_prn_file_path
export register_subcircuit
export add_include_file
export add_inline_snippet
export clear_custom_components
export custom_components_prelude
export add_plugin_library
export clear_plugin_libraries
export run_simulation_data
export read_simulation_data
export get_signal_names
export get_time_vector
export get_plot_signals
export get_voltage
export get_current
export detect_iv_columns
export plot_transient_voltages
export plot_iv_characteristic
export greet

end # module Jyce
