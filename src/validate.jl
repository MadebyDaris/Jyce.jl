# ---------------------------------------------------------------------------
# Pre-flight checks on a generated circuit.
#
# Xyce reports netlist errors by aborting the process, which takes the Julia
# session with it.  Catching the common mistakes in Julia first turns a lost
# REPL into an exception.
# ---------------------------------------------------------------------------

"""
    CircuitValidationError(issues)

Thrown by [`validate`](@ref) (and by [`simulate`](@ref) before a circuit is
handed to Xyce) when a circuit has problems Xyce would reject.  `err.issues`
lists them.
"""
struct CircuitValidationError <: Exception
    issues::Vector{String}
end

function Base.showerror(io::IO, e::CircuitValidationError)
    println(io, "CircuitValidationError: the circuit would be rejected by Xyce:")
    for issue in e.issues
        println(io, "  - ", issue)
    end
    print(io, "Pass `validate = false` to `simulate` to send it anyway.")
end

# Fields that hold a Symbol for reasons other than a parameter reference.
const _NON_PARAM_SYMBOL_FIELDS = (:name, :kind)

function _symbol_parameter_refs(c::AbstractComponent)
    refs = Symbol[]
    for field in fieldnames(typeof(c))
        field in _NON_PARAM_SYMBOL_FIELDS && continue
        value = getfield(c, field)
        if value isa Symbol
            push!(refs, value)
        elseif value isa ParamList
            for (_, v) in value
                v isa Symbol && push!(refs, v)
            end
        end
    end
    return refs
end

_model_reference(c::Union{Diode,BJT,MOSFET,JFET,VoltageSwitch,PluginDevice}) = c.model
_model_reference(::AbstractComponent) = nothing

"""
    validate(circuit; strict = true) -> Vector{String}

Check a circuit for the mistakes Xyce rejects at parse time - duplicate
instance names, references to parameters, models or subcircuits that are never
defined, and nodes that only one device touches.  Returns the list of issues;
with `strict = true` a non-empty list is thrown as a
[`CircuitValidationError`](@ref).

The checks are deliberately conservative: they are skipped where the circuit
contains raw cards or `.INCLUDE`s, because those can define anything.
Expressions (`expr"..."`) are not analysed.

```julia
validate(ckt; strict = false)   # just look
simulate(ckt, Transient(1e-6, 1e-3); validate = false)   # skip the checks
```
"""
function validate(c::Circuit; strict::Bool = true)
    issues = String[]

    comps = components(c)
    has_raw = any(e -> e isa RawCard, c.elements) || !isempty(c.includes) || !isempty(c.directives)

    # Duplicate instance names.
    seen = Dict{String,Int}()
    for comp in comps
        key = uppercase(designator(comp))
        seen[key] = get(seen, key, 0) + 1
    end
    for (name, count) in sort(collect(seen))
        count > 1 && push!(issues, "duplicate instance name $name ($count devices)")
    end

    # Parameters referenced as Symbols but never declared.
    declared = Set(first.(c.params))
    for comp in comps, ref in _symbol_parameter_refs(comp)
        ref in declared && continue
        push!(issues, "$(designator(comp)) uses parameter `$ref`, which no .PARAM declares " *
                      "(add `param!(circuit, :$ref => value)`)")
    end

    if !has_raw
        # Models and subcircuits referenced but never defined.
        models = Set(uppercase(string(e.name)) for e in c.elements if e isa Model)
        subckts = Set(uppercase(string(e.name)) for e in c.elements if e isa Subcircuit)

        for comp in comps
            model = _model_reference(comp)
            if model !== nothing && !(uppercase(model) in models)
                push!(issues, "$(designator(comp)) refers to model `$model`, which is not defined " *
                              "(add a `Model`, or `.INCLUDE` the library)")
            end
            if comp isa SubcircuitCall && !(uppercase(comp.subcircuit) in subckts)
                push!(issues, "$(designator(comp)) instantiates subcircuit `$(comp.subcircuit)`, " *
                              "which is not defined")
            end
        end

        # Nodes touched by a single device are almost always a typo - except on a
        # plugin device, whose extra terminals may be internal state nodes.
        counts = Dict{String,Int}()
        exempt = Set{String}()
        for comp in comps, n in terminals(comp)
            counts[n] = get(counts, n, 0) + 1
            comp isa PluginDevice && push!(exempt, n)
        end
        for (n, count) in sort(collect(counts))
            (n == "0" || n in exempt) && continue
            count == 1 && push!(issues, "node `$n` is connected to only one device terminal")
        end
    end

    (strict && !isempty(issues)) && throw(CircuitValidationError(issues))
    return issues
end
