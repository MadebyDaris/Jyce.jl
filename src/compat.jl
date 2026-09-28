# ---------------------------------------------------------------------------
# Compatibility layer.
#
# ---------------------------------------------------------------------------

"""
    simulation_success(result) -> Bool

Legacy accessor for a native result object.  Prefer [`issuccess`](@ref) on a
[`SimulationOutput`](@ref).
"""
simulation_success(result) = success(result)

"""
    simulation_error_message(result) -> String

Legacy accessor; prefer `output.error_message`.
"""
simulation_error_message(result) = error_message(result)

"""
    simulation_prn_file_path(result) -> String

Legacy accessor; prefer `output.prn_file_path`.
"""
simulation_prn_file_path(result) = prn_file_path(result)

"""
    register_subcircuit(sim, name, definition)

Legacy name for [`register_subcircuit!`](@ref).
"""
register_subcircuit(sim, name::AbstractString, definition::AbstractString) =
    register_subcircuit!(sim, name, definition)

"""
    add_include_file(sim, path)

Legacy name for [`include_file!`](@ref).
"""
add_include_file(sim, filepath::AbstractString) = include_file!(sim, filepath)

"""
    add_inline_snippet(sim, text)

Legacy name for [`snippet!`](@ref).
"""
add_inline_snippet(sim, snippet::AbstractString) = snippet!(sim, snippet)

"""
    clear_custom_components(sim)

Legacy name for [`clear_definitions!`](@ref).
"""
clear_custom_components(sim) = clear_definitions!(sim)

"""
    custom_components_prelude(sim) -> String

Legacy name for [`definitions_prelude`](@ref).
"""
custom_components_prelude(sim) = definitions_prelude(sim)

"""
    add_plugin_library(sim, path)

Legacy name for [`add_plugin!`](@ref).
"""
function add_plugin_library(sim, plugin_path::AbstractString)
    addPluginLibrary(_handle(sim), String(plugin_path))
    sim isa Simulator && (plugin_path in sim.plugins || push!(sim.plugins, String(plugin_path)))
    return sim
end

"""
    clear_plugin_libraries(sim)

Legacy name for [`clear_plugins!`](@ref).
"""
function clear_plugin_libraries(sim)
    clearPluginLibraries(_handle(sim))
    sim isa Simulator && empty!(sim.plugins)
    return sim
end

"""
    run_simulation_data(sim; output_file = nothing) -> NamedTuple

Run the loaded netlist and return the native in-memory result as a
`NamedTuple`.  Prefer [`simulate`](@ref), which returns a
[`SimulationOutput`](@ref) with the parsed table attached.
"""
function run_simulation_data(sim; output_file::Union{Nothing,String} = nothing)
    handle = _handle(sim)
    raw = output_file === nothing ? runSimulationData(handle) : runSimulationDataOutput(handle, output_file)
    return (
        success = success(raw),
        error_message = String(error_message(raw)),
        prn_file_path = String(prn_file_path(raw)),
        parameter_pairs = String[String(x) for x in parameter_pairs(raw)],
        plugin_libraries = String[String(x) for x in plugin_libraries(raw)],
        time_points = Float64[Float64(x) for x in time_points(raw)],
        node_names = String[String(x) for x in node_names(raw)],
        node_voltages = Vector{Float64}[Float64[Float64(x) for x in row] for row in node_voltages(raw)],
    )
end

"""
    greet()

Print a friendly banner; handy for checking that the package loaded.
"""
greet() = print("Jyce is ready.")
