# Custom definitions kept on the simulator and prepended to every netlist
# loaded from a string: include files, inline snippets and .SUBCKT blocks.
#

"""
    register_subcircuit!(simulator, name, definition) -> Simulator

Register a full `.SUBCKT ... .ENDS` block, prepended to every netlist loaded
with [`load!`](@ref).  Registering the same name twice replaces the definition.

A [`Subcircuit`](@ref) value can be passed instead of the text:

```julia
register_subcircuit!(sim, Subcircuit(:rdivider, (:in, :out),
                                     Resistor(:Rtop, :in, :out, 1e3),
                                     Resistor(:Rbot, :out, :gnd, 2e3)))
```
"""
function register_subcircuit!(sim::Simulator, name::AbstractString, definition::AbstractString)
    key = String(name)
    idx = findfirst(p -> first(p) == key, sim.subcircuits)
    entry = key => String(definition)
    idx === nothing ? push!(sim.subcircuits, entry) : (sim.subcircuits[idx] = entry)
    return sim
end

function register_subcircuit!(sim, name::AbstractString, definition::AbstractString)
    registerSubcircuitDefinition(_handle(sim), String(name), String(definition))
    return sim
end
register_subcircuit!(sim, s::Subcircuit) = register_subcircuit!(sim, String(string(s.name)), card(s))

"""
    include_file!(simulator, path) -> Simulator

Add an `.INCLUDE` directive to the prelude prepended to string netlists.
"""
function include_file!(sim::Simulator, filepath::AbstractString)
    push!(sim.includes, String(filepath))
    return sim
end

function include_file!(sim, filepath::AbstractString)
    appendIncludeFile(_handle(sim), String(filepath))
    return sim
end

"""
    snippet!(simulator, text) -> Simulator

Add raw netlist text (`.MODEL`, `.PARAM`, `.OPTIONS`, ...) to the prelude.
"""
function snippet!(sim::Simulator, snippet::AbstractString)
    push!(sim.snippets, String(snippet))
    return sim
end

function snippet!(sim, snippet::AbstractString)
    appendInlineSnippet(_handle(sim), String(snippet))
    return sim
end

"""
    clear_definitions!(simulator) -> Simulator

Remove every registered subcircuit, include and snippet.
"""
function clear_definitions!(sim::Simulator)
    empty!(sim.includes)
    empty!(sim.snippets)
    empty!(sim.subcircuits)
    clearCustomDefinitions(_handle(sim))
    return sim
end

function clear_definitions!(sim)
    clearCustomDefinitions(_handle(sim))
    return sim
end

"""
    definitions_prelude(simulator) -> String

The text currently prepended to string netlists; useful for debugging what the
simulator will actually send to Xyce.
"""
function definitions_prelude(sim::Simulator)
    io = IOBuffer()
    for path in sim.includes
        println(io, ".INCLUDE \"", path, "\"")
    end
    for snippet in sim.snippets
        println(io, rstrip(snippet))
    end
    for (_, definition) in sim.subcircuits
        println(io, rstrip(definition))
    end
    return String(take!(io))
end

definitions_prelude(sim) = String(getCustomDefinitionsPrelude(_handle(sim)))
