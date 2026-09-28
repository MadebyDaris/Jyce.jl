# ---------------------------------------------------------------------------
# Circuit elements.
#
# Every element knows how to write its own netlist card; a `Circuit` is little
# more than an ordered collection of them plus the directives that surround
# them.  Instance names are auto-prefixed with the SPICE designator letter, so
# `Resistor(:load, ...)` emits `Rload` and `Resistor(:R1, ...)` emits `R1`.
# ---------------------------------------------------------------------------

"""
    AbstractElement

Supertype for everything that can be written into a netlist body: components,
`.MODEL` cards, subcircuit definitions and raw text.
"""
abstract type AbstractElement end

"""
    AbstractComponent <: AbstractElement

Supertype of circuit devices (resistors, sources, transistors, subcircuit
calls, ...).  Implement [`card`](@ref) and [`terminals`](@ref) to add one.
"""
abstract type AbstractComponent <: AbstractElement end

"""
    card(element) -> String

The netlist text for a single element.  Multi-line elements (subcircuit
definitions) return several lines joined by newlines.
"""
function card end

"""
    designator(component) -> String

The instance name as it appears in the netlist, including the SPICE prefix
letter (`Resistor(:load, ...)` → `"Rload"`).
"""
designator(c::AbstractComponent) = _designator(prefix(c), c.name)

"""
    prefix(component) -> Char

The SPICE designator letter for a component type (`'R'` for [`Resistor`](@ref)).
"""
function prefix end

"""
    terminals(component) -> Vector{String}

Normalised node names the component connects to, in netlist order.
"""
function terminals end

function _designator(pfx::Char, name)
    s = String(string(name))
    isempty(s) && throw(ArgumentError("component name must not be empty"))
    return uppercase(first(s)) == uppercase(pfx) ? s : string(pfx) * s
end

_join_card(parts...) = join(filter(!isempty, [string(p) for p in parts]), " ")

# --- Passives --------------------------------------------------------------

"""
    Resistor(name, pos, neg, value; params...)
Linear resistor.  `value` may be a number, a string such as `"1k"`, a `Symbol`
naming a `.PARAM`, or an [`SpiceExpr`](@ref).  Extra keywords become instance
parameters (for example `TC1`).

```jldoctest
julia> Jyce.card(Resistor(:R1, :in, :out, 1e3))
"R1 in out 1000"
```
"""
struct Resistor <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    value::Any
    params::ParamList
end
Resistor(name, pos::NodeLike, neg::NodeLike, value; kwargs...) =
    Resistor(Symbol(name), node(pos), node(neg), value, paramlist(kwargs))
prefix(::Resistor) = 'R'
terminals(c::Resistor) = [c.pos, c.neg]
card(c::Resistor) = _join_card(designator(c), c.pos, c.neg, spice(c.value), _params_string(c.params))

"""
    Capacitor(name, pos, neg, value; ic = nothing, params...)
Linear capacitor; `ic` sets the initial condition used with `uic = true`
transient runs.
"""
struct Capacitor <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    value::Any
    params::ParamList
end
function Capacitor(name, pos::NodeLike, neg::NodeLike, value; ic = nothing, kwargs...)
    params = paramlist(kwargs)
    ic === nothing || pushfirst!(params, :IC => ic)
    return Capacitor(Symbol(name), node(pos), node(neg), value, params)
end
prefix(::Capacitor) = 'C'
terminals(c::Capacitor) = [c.pos, c.neg]
card(c::Capacitor) = _join_card(designator(c), c.pos, c.neg, spice(c.value), _params_string(c.params))

"""
    Inductor(name, pos, neg, value; ic = nothing, params...)

Linear inductor; `ic` sets the initial current.
"""
struct Inductor <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    value::Any
    params::ParamList
end
function Inductor(name, pos::NodeLike, neg::NodeLike, value; ic = nothing, kwargs...)
    params = paramlist(kwargs)
    ic === nothing || pushfirst!(params, :IC => ic)
    return Inductor(Symbol(name), node(pos), node(neg), value, params)
end
prefix(::Inductor) = 'L'
terminals(c::Inductor) = [c.pos, c.neg]
card(c::Inductor) = _join_card(designator(c), c.pos, c.neg, spice(c.value), _params_string(c.params))

"""
    MutualInductance(name, inductor1, inductor2, coupling)

Magnetic coupling between two [`Inductor`](@ref)s, emitted as a `K` card.
"""
struct MutualInductance <: AbstractComponent
    name::Symbol
    l1::String
    l2::String
    coupling::Any
end
const InductorRef = Union{Symbol,AbstractString,Inductor}
_inductor_name(l::Inductor) = designator(l)
_inductor_name(l::Union{Symbol,AbstractString}) = _designator('L', l)

MutualInductance(name, l1::InductorRef, l2::InductorRef, coupling) =
    MutualInductance(Symbol(name), _inductor_name(l1), _inductor_name(l2), coupling)
prefix(::MutualInductance) = 'K'
terminals(::MutualInductance) = String[]
card(c::MutualInductance) = _join_card(designator(c), c.l1, c.l2, spice(c.coupling))

# Independent sources

"""
    VoltageSource(name, pos, neg, spec...)

Independent voltage source.  Each `spec` is a number (constant value) or an
[`AbstractWaveform`](@ref); several may be combined so one source serves DC, AC
and transient analyses at once.

```jldoctest
julia> Jyce.card(VoltageSource(:V1, :in, :gnd, DC(0), AC(1), Sine(0, 1, 1e3)))
"V1 in 0 DC 0 AC 1 0 SIN(0 1 1000 0 0 0)"
```
"""
struct VoltageSource <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    specs::Vector{AbstractWaveform}
end
VoltageSource(name, pos::NodeLike, neg::NodeLike, specs...) =
    VoltageSource(Symbol(name), node(pos), node(neg), AbstractWaveform[_as_waveform(s) for s in specs])
prefix(::VoltageSource) = 'V'
terminals(c::VoltageSource) = [c.pos, c.neg]
card(c::VoltageSource) = _join_card(designator(c), c.pos, c.neg, join(waveform.(c.specs), " "))

"""
    CurrentSource(name, pos, neg, spec...)

Independent current source; positive current flows from `pos` to `neg` inside
the source.  Accepts the same specifications as [`VoltageSource`](@ref).
"""
struct CurrentSource <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    specs::Vector{AbstractWaveform}
end
CurrentSource(name, pos::NodeLike, neg::NodeLike, specs...) =
    CurrentSource(Symbol(name), node(pos), node(neg), AbstractWaveform[_as_waveform(s) for s in specs])
prefix(::CurrentSource) = 'I'
terminals(c::CurrentSource) = [c.pos, c.neg]
card(c::CurrentSource) = _join_card(designator(c), c.pos, c.neg, join(waveform.(c.specs), " "))

# --- Controlled sources ----------------------------------------------------

"""
    VCVS(name, pos, neg, ctrl_pos, ctrl_neg, gain)

Voltage-controlled voltage source (`E` card).
"""
struct VCVS <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    ctrl_pos::String
    ctrl_neg::String
    gain::Any
end
VCVS(name, pos::NodeLike, neg::NodeLike, cp::NodeLike, cn::NodeLike, gain) =
    VCVS(Symbol(name), node(pos), node(neg), node(cp), node(cn), gain)
prefix(::VCVS) = 'E'
terminals(c::VCVS) = [c.pos, c.neg, c.ctrl_pos, c.ctrl_neg]
card(c::VCVS) = _join_card(designator(c), c.pos, c.neg, c.ctrl_pos, c.ctrl_neg, spice(c.gain))

"""
    VCCS(name, pos, neg, ctrl_pos, ctrl_neg, transconductance)

Voltage-controlled current source (`G` card).
"""
struct VCCS <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    ctrl_pos::String
    ctrl_neg::String
    gain::Any
end
VCCS(name, pos::NodeLike, neg::NodeLike, cp::NodeLike, cn::NodeLike, gain) =
    VCCS(Symbol(name), node(pos), node(neg), node(cp), node(cn), gain)
prefix(::VCCS) = 'G'
terminals(c::VCCS) = [c.pos, c.neg, c.ctrl_pos, c.ctrl_neg]
card(c::VCCS) = _join_card(designator(c), c.pos, c.neg, c.ctrl_pos, c.ctrl_neg, spice(c.gain))

"""
    CCCS(name, pos, neg, control_source, gain)

Current-controlled current source (`F` card); `control_source` names the
voltage source whose current is sensed.
"""
struct CCCS <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    control::String
    gain::Any
end
CCCS(name, pos::NodeLike, neg::NodeLike, control, gain) =
    CCCS(Symbol(name), node(pos), node(neg), _designator('V', control), gain)
prefix(::CCCS) = 'F'
terminals(c::CCCS) = [c.pos, c.neg]
card(c::CCCS) = _join_card(designator(c), c.pos, c.neg, c.control, spice(c.gain))

"""
    CCVS(name, pos, neg, control_source, transresistance)

Current-controlled voltage source (`H` card).
"""
struct CCVS <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    control::String
    gain::Any
end
CCVS(name, pos::NodeLike, neg::NodeLike, control, gain) =
    CCVS(Symbol(name), node(pos), node(neg), _designator('V', control), gain)
prefix(::CCVS) = 'H'
terminals(c::CCVS) = [c.pos, c.neg]
card(c::CCVS) = _join_card(designator(c), c.pos, c.neg, c.control, spice(c.gain))

"""
    Behavioral(name, pos, neg; v = nothing, i = nothing)

Behavioural (`B`) source defined by an expression in node voltages and branch
currents, for example `Behavioral(:B1, :out, :gnd; v = "V(in)^2")`.  Exactly one
of `v` or `i` must be given.
"""
struct Behavioral <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    kind::Symbol       # :V or :I
    expr::String
end
function Behavioral(name, pos::NodeLike, neg::NodeLike; v = nothing, i = nothing)
    (v === nothing) == (i === nothing) &&
        throw(ArgumentError("Behavioral source needs exactly one of `v` or `i`"))
    kind = v === nothing ? :I : :V
    e = v === nothing ? i : v
    text = e isa SpiceExpr ? e.expr : String(string(e))
    return Behavioral(Symbol(name), node(pos), node(neg), kind, text)
end
prefix(::Behavioral) = 'B'
terminals(c::Behavioral) = [c.pos, c.neg]
card(c::Behavioral) = _join_card(designator(c), c.pos, c.neg, string(c.kind) * "={" * c.expr * "}")

"""
    VoltageSwitch(name, pos, neg, ctrl_pos, ctrl_neg, model; on = false)

Voltage-controlled switch (`S` card) referring to a `.MODEL` of type `VSWITCH`.
"""
struct VoltageSwitch <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    ctrl_pos::String
    ctrl_neg::String
    model::String
    on::Bool
end
VoltageSwitch(name, pos::NodeLike, neg::NodeLike, cp::NodeLike, cn::NodeLike, model; on::Bool = false) =
    VoltageSwitch(Symbol(name), node(pos), node(neg), node(cp), node(cn), String(string(model)), on)
prefix(::VoltageSwitch) = 'S'
terminals(c::VoltageSwitch) = [c.pos, c.neg, c.ctrl_pos, c.ctrl_neg]
card(c::VoltageSwitch) =
    _join_card(designator(c), c.pos, c.neg, c.ctrl_pos, c.ctrl_neg, c.model, c.on ? "ON" : "OFF")

# Semiconductor Devices

"""
    Diode(name, pos, neg, model; params...)

Diode instance referring to a `.MODEL` card (see [`Model`](@ref)).
"""
struct Diode <: AbstractComponent
    name::Symbol
    pos::String
    neg::String
    model::String
    params::ParamList
end
Diode(name, pos::NodeLike, neg::NodeLike, model; kwargs...) =
    Diode(Symbol(name), node(pos), node(neg), String(string(model)), paramlist(kwargs))
prefix(::Diode) = 'D'
terminals(c::Diode) = [c.pos, c.neg]
card(c::Diode) = _join_card(designator(c), c.pos, c.neg, c.model, _params_string(c.params))

"""
    BJT(name, collector, base, emitter, model; substrate = nothing, params...)

Bipolar transistor instance (`Q` card).
"""
struct BJT <: AbstractComponent
    name::Symbol
    collector::String
    base::String
    emitter::String
    substrate::Union{Nothing,String}
    model::String
    params::ParamList
end
BJT(name, c::NodeLike, b::NodeLike, e::NodeLike, model; substrate = nothing, kwargs...) =
    BJT(Symbol(name), node(c), node(b), node(e),
        substrate === nothing ? nothing : node(substrate),
        String(string(model)), paramlist(kwargs))
prefix(::BJT) = 'Q'
terminals(c::BJT) = c.substrate === nothing ? [c.collector, c.base, c.emitter] :
                    [c.collector, c.base, c.emitter, c.substrate]
card(c::BJT) = _join_card(designator(c), join(terminals(c), " "), c.model, _params_string(c.params))

"""
    MOSFET(name, drain, gate, source, bulk, model; l = nothing, w = nothing, params...)

MOS transistor instance (`M` card).  `l` and `w` are emitted as `L=`/`W=`
instance parameters when given.
"""
struct MOSFET <: AbstractComponent
    name::Symbol
    drain::String
    gate::String
    source::String
    bulk::String
    model::String
    params::ParamList
end
function MOSFET(name, d::NodeLike, g::NodeLike, s::NodeLike, b::NodeLike, model;
                l = nothing, w = nothing, kwargs...)
    params = paramlist(kwargs)
    w === nothing || pushfirst!(params, :W => w)
    l === nothing || pushfirst!(params, :L => l)
    return MOSFET(Symbol(name), node(d), node(g), node(s), node(b), String(string(model)), params)
end
prefix(::MOSFET) = 'M'
terminals(c::MOSFET) = [c.drain, c.gate, c.source, c.bulk]
card(c::MOSFET) = _join_card(designator(c), join(terminals(c), " "), c.model, _params_string(c.params))

"""
    JFET(name, drain, gate, source, model; params...)

Junction FET instance (`J` card).
"""
struct JFET <: AbstractComponent
    name::Symbol
    drain::String
    gate::String
    source::String
    model::String
    params::ParamList
end
JFET(name, d::NodeLike, g::NodeLike, s::NodeLike, model; kwargs...) =
    JFET(Symbol(name), node(d), node(g), node(s), String(string(model)), paramlist(kwargs))
prefix(::JFET) = 'J'
terminals(c::JFET) = [c.drain, c.gate, c.source]
card(c::JFET) = _join_card(designator(c), join(terminals(c), " "), c.model, _params_string(c.params))

# --- Hierarchy and plugins -------------------------------------------------

"""
    SubcircuitCall(name, nodes, subcircuit; params...)

Instantiate a subcircuit (`X` card).  `nodes` is the ordered list of terminals
to connect, `subcircuit` the name of a [`Subcircuit`](@ref) definition or of a
`.SUBCKT` supplied through an include file.

```jldoctest
julia> Jyce.card(SubcircuitCall(:X1, (:in, :out), :rdivider; scale = 2))
"X1 in out rdivider PARAMS: scale=2"
```
"""
struct SubcircuitCall <: AbstractComponent
    name::Symbol
    nodes::Vector{String}
    subcircuit::String
    params::ParamList
end
SubcircuitCall(name, nodes, subcircuit; kwargs...) =
    SubcircuitCall(Symbol(name), [node(n) for n in nodes], String(string(subcircuit)), paramlist(kwargs))
prefix(::SubcircuitCall) = 'X'
terminals(c::SubcircuitCall) = c.nodes
function card(c::SubcircuitCall)
    params = _params_string(c.params)
    return _join_card(designator(c), join(c.nodes, " "), c.subcircuit,
                      isempty(params) ? "" : "PARAMS: " * params)
end

"""
    PluginDevice(name, device_type, nodes, model; params...)

Instance of a device provided by a compiled Verilog-A plugin (`Y` card).  For
the ADMS memristor shipped with this repository the device type is `MEMRISTOR`
and the device has three terminals:

```julia
PluginDevice(:m1, :MEMRISTOR, (:plus, :minus, :gnd), :mymem)
```

emits `YMEMRISTOR m1 plus minus 0 mymem` - the device type joins the `Y`, then
the instance name, the terminals and the `.MODEL` name.  See
[`add_plugin!`](@ref) for loading the shared library and
[`plugin!`](@ref) for attaching one to a circuit.
"""
struct PluginDevice <: AbstractComponent
    name::Symbol
    device_type::String
    nodes::Vector{String}
    model::String
    params::ParamList
end
PluginDevice(name, device_type, nodes, model; kwargs...) =
    PluginDevice(Symbol(name), uppercase(String(string(device_type))),
                 [node(n) for n in nodes], String(string(model)), paramlist(kwargs))
prefix(::PluginDevice) = 'Y'
terminals(c::PluginDevice) = c.nodes
card(c::PluginDevice) = _join_card("Y" * c.device_type, String(string(c.name)),
                                   join(c.nodes, " "), c.model, _params_string(c.params))

"""
    RawCard(text)

Verbatim netlist text inserted into the circuit body.  The escape hatch for
devices Jyce does not model.
"""
struct RawCard <: AbstractElement
    text::String
end
card(c::RawCard) = c.text

# --- Model and subcircuit definitions --------------------------------------

"""
    Model(name, type; params...)

A `.MODEL` card, for example `Model(:D1N4148, :D; is = 2.52e-9, n = 1.752)`.
"""
struct Model <: AbstractElement
    name::Symbol
    type::String
    params::ParamList
end
Model(name, type; kwargs...) = Model(Symbol(name), String(string(type)), paramlist(kwargs))
function card(m::Model)
    params = _params_string(m.params)
    return _join_card(".MODEL", string(m.name), m.type, isempty(params) ? "" : "(" * params * ")")
end

"""
    Subcircuit(name, ports, elements...; params...)

A reusable `.SUBCKT` definition.  `ports` lists the external terminals, the
remaining arguments are the elements of the body, and keyword arguments become
the subcircuit's default `PARAMS:`.

```julia
divider = Subcircuit(:rdivider, (:in, :out),
    Resistor(:Rtop, :in, :out, expr"rtop"),
    Resistor(:Rbot, :out, :gnd, expr"rbot");
    rtop = 1e3, rbot = 2e3)
```

Instantiate it with [`SubcircuitCall`](@ref).
"""
struct Subcircuit <: AbstractElement
    name::Symbol
    ports::Vector{String}
    elements::Vector{AbstractElement}
    params::ParamList
end
Subcircuit(name, ports, elements::AbstractElement...; kwargs...) =
    Subcircuit(Symbol(name), [node(p) for p in ports],
               AbstractElement[e for e in elements], paramlist(kwargs))
function card(s::Subcircuit)
    params = _params_string(s.params)
    header = _join_card(".SUBCKT", string(s.name), join(s.ports, " "),
                        isempty(params) ? "" : "PARAMS: " * params)
    body = [card(e) for e in s.elements]
    return join([header; body; ".ENDS " * string(s.name)], "\n")
end

Base.show(io::IO, c::AbstractElement) = print(io, typeof(c).name.name, "(", card(c), ")")
function Base.show(io::IO, ::MIME"text/plain", c::AbstractElement)
    print(io, typeof(c).name.name, ": ", card(c))
end
