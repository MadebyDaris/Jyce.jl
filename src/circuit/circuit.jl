# The Circuit container and netlist generation.

"""
    Circuit(elements...; title = "Jyce circuit")
    Circuit(title, elements...)

An editable circuit: components, `.MODEL`/`.SUBCKT` definitions, parameters,
includes, analyses and output probes.  A `Circuit` is a plain Julia value, so
it can be built in loops, stored, copied and diffed; [`netlist`](@ref) turns it
into Xyce input and [`simulate`](@ref) runs it.

```jldoctest
julia> ckt = Circuit(VoltageSource(:V1, :in, :gnd, DC(1)),
                     Resistor(:R1, :in, :out, 1e3),
                     Resistor(:R2, :out, :gnd, 2e3); title = "divider");

julia> print(netlist(ckt; analysis = OperatingPoint(), outputs = [:in, :out]))
* divider
V1 in 0 DC 1
R1 in out 1000
R2 out 0 2000
.OP
.PRINT DC V(in) V(out)
.END
```

Elements can be added after construction with [`add!`](@ref) or `push!`, and
the whole circuit can be assembled declaratively with [`@circuit`](@ref).
"""
mutable struct Circuit
    title::String
    elements::Vector{AbstractElement}
    params::ParamList
    includes::Vector{String}
    options::Vector{String}
    initial_conditions::ParamList
    analyses::Vector{AbstractAnalysis}
    steps::Vector{Step}
    outputs::Vector{Probe}
    plugins::Vector{String}
    directives::Vector{String}
end

function Circuit(elements...; title::AbstractString = "Jyce circuit")
    ckt = Circuit(String(title), AbstractElement[], paramlist(), String[], String[],
                  paramlist(), AbstractAnalysis[], Step[], Probe[], String[], String[])
    for e in elements
        add!(ckt, e)
    end
    return ckt
end
Circuit(title::AbstractString, elements...) = Circuit(elements...; title = title)

Base.copy(c::Circuit) = Circuit(c.title, copy(c.elements), copy(c.params), copy(c.includes),
                                copy(c.options), copy(c.initial_conditions), copy(c.analyses),
                                copy(c.steps), copy(c.outputs), copy(c.plugins), copy(c.directives))

"""
    add!(circuit, item...) -> Circuit

Add elements to a circuit.  Dispatches on what is given: components, models and
subcircuit definitions go into the body, [`Probe`](@ref)s become outputs,
[`AbstractAnalysis`](@ref) values become analyses, `name => value` pairs become
`.PARAM`s, strings become raw cards, and vectors/tuples are added elementwise.

`push!(circuit, item)` is a synonym.
"""
add!(c::Circuit, e::AbstractElement) = (push!(c.elements, e); c)
add!(c::Circuit, a::AbstractAnalysis) = (push!(c.analyses, a); c)
add!(c::Circuit, s::Step) = (push!(c.steps, s); c)
add!(c::Circuit, p::Probe) = (push!(c.outputs, p); c)
add!(c::Circuit, p::Pair) = param!(c, p)
add!(c::Circuit, s::AbstractString) = (push!(c.elements, RawCard(String(s))); c)
add!(c::Circuit, ::Nothing) = c
add!(c::Circuit, xs::Union{Tuple,AbstractVector}) = (foreach(x -> add!(c, x), xs); c)
add!(c::Circuit, x) = throw(ArgumentError("don't know how to add $(repr(x)) to a Circuit"))
add!(c::Circuit, items...) = (foreach(x -> add!(c, x), items); c)

Base.push!(c::Circuit, items...) = add!(c, items...)

"""
    param!(circuit, name => value, ...) -> Circuit

Declare `.PARAM`s.  Reference them from component values with a `Symbol`
(`Resistor(:R1, :a, :b, :rload)`) or inside an [`SpiceExpr`](@ref).
Re-declaring a name replaces its value, which is what [`sweep`](@ref) uses to
override parameters per run.
"""
function param!(c::Circuit, ps::Pair...)
    for p in ps
        k = Symbol(first(p))
        idx = findfirst(q -> first(q) === k, c.params)
        idx === nothing ? push!(c.params, k => last(p)) : (c.params[idx] = k => last(p))
    end
    return c
end
param!(c::Circuit, ps::AbstractDict) = param!(c, (Symbol(k) => v for (k, v) in ps)...)

"""
    include!(circuit, path...) -> Circuit

Add `.INCLUDE` directives for model libraries or subcircuit files.
"""
include!(c::Circuit, paths::AbstractString...) = (append!(c.includes, String.(paths)); c)

"""
    options!(circuit, package; params...) -> Circuit

Add a `.OPTIONS` card, e.g. `options!(ckt, :TIMEINT; reltol = 1e-6)`.
"""
function options!(c::Circuit, package; kwargs...)
    push!(c.options, _join_card(".OPTIONS", uppercase(String(string(package))),
                                _params_string(paramlist(kwargs))))
    return c
end

"""
    ic!(circuit, node => value, ...) -> Circuit

Declare initial conditions (`.IC`) used by transient runs started with
`uic = true`.
"""
function ic!(c::Circuit, ps::Pair...)
    for p in ps
        push!(c.initial_conditions, Symbol(node(first(p))) => last(p))
    end
    return c
end

"""
    output!(circuit, probes...) -> Circuit

Request additional `.PRINT` columns; see [`voltage`](@ref), [`current`](@ref).
Bare symbols are interpreted as node voltages.
"""
output!(c::Circuit, probes...) = (append!(c.outputs, _as_probes(collect(probes))); c)

"""
    analysis!(circuit, analysis...) -> Circuit

Attach analyses to the circuit, so [`simulate(circuit)`](@ref simulate) needs
no second argument.
"""
analysis!(c::Circuit, analyses::AbstractAnalysis...) = (append!(c.analyses, analyses); c)

"""
    plugin!(circuit, library_path...) -> Circuit

Record Verilog-A plugin shared libraries this circuit needs; [`simulate`](@ref)
loads them into the simulator before running.
"""
plugin!(c::Circuit, paths::AbstractString...) = (append!(c.plugins, String.(paths)); c)

"""
    directive!(circuit, text...) -> Circuit

Append raw netlist directives (`.MEASURE`, `.GLOBAL_PARAM`, ...) emitted just
before the analysis cards.
"""
directive!(c::Circuit, texts::AbstractString...) = (append!(c.directives, String.(texts)); c)

"""
    components(circuit) -> Vector{AbstractComponent}

The circuit's device instances, in insertion order.
"""
components(c::Circuit) = AbstractComponent[e for e in c.elements if e isa AbstractComponent]

"""
    nodes(circuit) -> Vector{String}

Every node referenced by the circuit's components, sorted, with ground first
when present.
"""
function nodes(c::Circuit)
    seen = String[]
    for comp in components(c), n in terminals(comp)
        n in seen || push!(seen, n)
    end
    ground = "0" in seen ? ["0"] : String[]
    return vcat(ground, sort(filter(!=("0"), seen)))
end

"""
    netlist(circuit; analysis = nothing, outputs = nothing, format = nothing,
            end_card = true) -> String

Render the circuit as Xyce netlist text.  `analysis` overrides (or supplies)
the analysis attached to the circuit and `outputs` overrides its probes;
`format` sets `FORMAT=` on the `.PRINT` line.

This function never touches the native backend, so netlists can be generated
and inspected on machines without Xyce installed.
"""
function netlist(c::Circuit; analysis = nothing, outputs = nothing, format = nothing,
                 end_card::Bool = true)
    analyses = analysis === nothing ? c.analyses :
               analysis isa AbstractAnalysis ? [analysis] : collect(analysis)
    probes = outputs === nothing ? c.outputs : _as_probes(outputs)

    io = IOBuffer()
    println(io, "* ", c.title)

    for path in c.includes
        println(io, ".INCLUDE ", path)
    end

    for (k, v) in c.params
        println(io, ".PARAM ", k, "=", spice(v))
    end

    for opt in c.options
        println(io, opt)
    end

    for e in c.elements
        e isa Subcircuit && println(io, card(e))
    end
    for e in c.elements
        e isa Model && println(io, card(e))
    end
    for e in c.elements
        (e isa Subcircuit || e isa Model) && continue
        println(io, card(e))
    end

    if !isempty(c.initial_conditions)
        println(io, ".IC ", join(("V(" * string(k) * ")=" * spice(v)
                                  for (k, v) in c.initial_conditions), " "))
    end

    for d in c.directives
        println(io, d)
    end

    for a in analyses
        println(io, directive(a))
    end

    for s in c.steps
        println(io, directive(s))
    end

    if !isempty(probes)
        tag = isempty(analyses) ? "TRAN" : print_tag(first(analyses))
        line = _join_card(".PRINT", tag, format === nothing ? "" : "FORMAT=" * String(string(format)),
                          join(probe_text.(probes), " "))
        println(io, line)
    end

    end_card && println(io, ".END")

    return String(take!(io))
end

netlist(s::AbstractString; kwargs...) = String(s)

function Base.show(io::IO, ::MIME"text/plain", c::Circuit)
    comps = components(c)
    println(io, "Circuit \"", c.title, "\" with ", length(comps), " component(s), ",
            length(nodes(c)), " node(s)")
    isempty(c.params) || println(io, "  params: ", join((string(k) * "=" * spice(v) for (k, v) in c.params), ", "))
    isempty(c.analyses) || println(io, "  analyses: ", join(directive.(c.analyses), "; "))
    isempty(c.outputs) || println(io, "  outputs: ", join(probe_text.(c.outputs), " "))
    isempty(c.plugins) || println(io, "  plugins: ", join(c.plugins, ", "))
    print(io, "  (use `netlist(circuit)` to see the generated netlist)")
end

Base.show(io::IO, c::Circuit) = print(io, "Circuit(\"", c.title, "\", ",
                                      length(components(c)), " components)")

# --- @circuit --------------------------------------------------------------

"""
    @circuit [title] begin ... end

Build a [`Circuit`](@ref) declaratively.  Inside the block, an assignment
`Name = Constructor(args...)` becomes `Constructor(:Name, args...)`, so the
instance name is written once, on the left:

```julia
rc = @circuit "RC low-pass" begin
    V1 = VoltageSource(:in, :gnd, DC(0), AC(1), Sine(0, 1, 1e3))
    R1 = Resistor(:in, :out, 1e3)
    C1 = Capacitor(:out, :gnd, 1e-6)

    Transient(10e-6, 5e-3)
    voltage(:in); voltage(:out)
end
```

Any other expression in the block is added with [`add!`](@ref), so analyses,
probes, models, `name => value` parameters, raw cards and vectors of elements
(from a comprehension, for instance) can be listed directly.  Expressions
evaluating to `nothing` — such as `for` loops — are ignored.
"""
macro circuit(args...)
    if length(args) == 1
        title, block = "Jyce circuit", args[1]
    elseif length(args) == 2
        title, block = args[1], args[2]
    else
        throw(ArgumentError("@circuit takes an optional title and a begin ... end block"))
    end

    Base.isexpr(block, :block) || throw(ArgumentError("@circuit expects a begin ... end block"))

    ckt = gensym("circuit")
    stmts = Any[:($ckt = $(Circuit)(; title = $(esc(title))))]

    for stmt in block.args
        stmt isa LineNumberNode && continue
        push!(stmts, :($(add!)($ckt, $(esc(_circuit_stmt(stmt))))))
    end

    push!(stmts, :($ckt))
    return Expr(:block, stmts...)
end

# `Name = Ctor(args...)` -> `Ctor(:Name, args...)`; everything else unchanged.
function _circuit_stmt(stmt)
    if Base.isexpr(stmt, :(=)) && stmt.args[1] isa Symbol && Base.isexpr(stmt.args[2], :call)
        name = stmt.args[1]
        call = copy(stmt.args[2])
        insert_at = (length(call.args) >= 2 && Base.isexpr(call.args[2], :parameters)) ? 3 : 2
        insert!(call.args, insert_at, QuoteNode(name))
        return call
    end
    return stmt
end
