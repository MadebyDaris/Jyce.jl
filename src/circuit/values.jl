# Nodes, values and expressions: the small vocabulary shared by every card
# emitted by the circuit DSL.

"""
    NodeLike

Anything Jyce accepts as a circuit node: a `Symbol` (`:in`), a `String`
(`"n001"`) or an `Integer` (`0`).  The aliases `:gnd`, `:GND`, `:ground`,
`:0` and `0` all refer to the global ground node.
"""
const NodeLike = Union{Symbol,AbstractString,Integer}

const GROUND_ALIASES = ("0", "GND", "GROUND", "AGND", "DGND")

"""
    node(n) -> String

Normalise a [`NodeLike`](@ref) to the string Xyce expects, mapping every ground
alias onto `"0"`.

```jldoctest
julia> Jyce.node(:gnd), Jyce.node(:out), Jyce.node(0)
("0", "out", "0")
```
"""
function node(n::NodeLike)
    s = n isa Integer ? string(n) : String(string(n))
    isempty(s) && throw(ArgumentError("node name must not be empty"))
    uppercase(s) in GROUND_ALIASES && return "0"
    return s
end

"""
    SpiceExpr(str)

A raw netlist expression, emitted inside braces so Xyce evaluates it:
`SpiceExpr("2*Rbase")` becomes `{2*Rbase}`.  Useful for values that depend on
`.PARAM`s or on other node voltages.
"""
struct SpiceExpr
    expr::String
end

SpiceExpr(x::SpiceExpr) = x
Base.show(io::IO, e::SpiceExpr) = print(io, "SpiceExpr(", repr(e.expr), ")")

"""
    @expr_str -> SpiceExpr

String macro shorthand for [`SpiceExpr`](@ref): `expr"2*Rbase"`.
"""
macro expr_str(s)
    return :(SpiceExpr($s))
end

"""
    spice(value) -> String

Render a Julia value as a netlist token.

| Julia value        | netlist text   | meaning                              |
|:-------------------|:---------------|:-------------------------------------|
| `1000`, `1e3`      | `1000`         | plain number                         |
| `"1k"`             | `1k`           | passed through verbatim              |
| `:Rload`           | `{Rload}`      | reference to a `.PARAM`              |
| `expr"2*Rload"`    | `{2*Rload}`    | expression evaluated by Xyce         |
"""
spice(x::Integer) = string(x)
spice(x::Real) = _format_float(float(x))
spice(x::AbstractString) = String(x)
spice(x::Symbol) = "{" * string(x) * "}"
spice(x::SpiceExpr) = "{" * x.expr * "}"
spice(x::Bool) = x ? "1" : "0"
spice(x::Nothing) = ""

function _format_float(x::AbstractFloat)
    isfinite(x) || throw(ArgumentError("cannot emit non-finite value $x into a netlist"))
    x == 0 && return "0"
    if isinteger(x) && abs(x) < 1e15
        return string(Int(x))
    end
    return @sprintf("%.12g", x)
end

"""
    ParamList

Ordered `name => value` pairs attached to a component, model or analysis.  Any
value accepted by [`spice`](@ref) may be used.
"""
const ParamList = Vector{Pair{Symbol,Any}}

paramlist() = ParamList()
paramlist(ps::ParamList) = ps
paramlist(ps::Union{AbstractDict,NamedTuple,Base.Pairs}) =
    ParamList([Symbol(k) => v for (k, v) in pairs(ps)])
paramlist(ps) = ParamList([Symbol(first(p)) => last(p) for p in ps])

function _params_string(params::ParamList; sep::AbstractString = " ")
    isempty(params) && return ""
    return join((string(k) * "=" * spice(v) for (k, v) in params), sep)
end
