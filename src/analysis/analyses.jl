# ---------------------------------------------------------------------------
# Analyses and output probes: the directives that tell Xyce what to solve and
# what to write to the .prn file.
# ---------------------------------------------------------------------------

"""
    AbstractAnalysis

Supertype of the analysis directives ([`OperatingPoint`](@ref),
[`DCSweep`](@ref), [`ACSweep`](@ref), [`Transient`](@ref), [`Noise`](@ref)).

Two functions define an analysis: [`directive`](@ref), which writes the `.TRAN`
/ `.AC` / ... card, and [`print_tag`](@ref), which says what kind of `.PRINT`
line collects its results.
"""
abstract type AbstractAnalysis end

"""
    directive(analysis) -> String

The netlist card for an analysis, e.g. `".TRAN 0.001 2 0 0"`.
"""
function directive end

"""
    print_tag(analysis) -> String

The analysis keyword used on `.PRINT` lines for this analysis (`"TRAN"`,
`"AC"`, `"DC"`, `"NOISE"`).
"""
function print_tag end

"""
    OperatingPoint()

DC operating point (`.OP`).  Results are printed with `.PRINT DC`.
"""
struct OperatingPoint <: AbstractAnalysis end
directive(::OperatingPoint) = ".OP"
print_tag(::OperatingPoint) = "DC"

"""
    DCSweep(source, start, stop, step)
    DCSweep(source, range)

Sweep an independent source (`.DC`).  The source may be given by name
(`:V1`, `"V1"`) or as the [`VoltageSource`](@ref)/[`CurrentSource`](@ref)
itself.  A `StepRange`/`AbstractRange` is expanded into start/stop/step.

```jldoctest
julia> Jyce.directive(DCSweep(:V1, 0, 5, 0.1))
".DC V1 0 5 0.1"
```
"""
struct DCSweep <: AbstractAnalysis
    source::String
    start::Any
    stop::Any
    step::Any
end
const SourceRef = Union{Symbol,AbstractString,VoltageSource,CurrentSource}

DCSweep(source::SourceRef, start, stop, step) = DCSweep(_source_name(source), start, stop, step)
DCSweep(source::SourceRef, r::AbstractRange) =
    DCSweep(_source_name(source), first(r), last(r), Base.step(r))
directive(a::DCSweep) = _join_card(".DC", a.source, spice(a.start), spice(a.stop), spice(a.step))
print_tag(::DCSweep) = "DC"

_source_name(s::AbstractString) = String(s)
_source_name(s::Symbol) = String(s)
_source_name(s::VoltageSource) = designator(s)
_source_name(s::CurrentSource) = designator(s)

"""
    ACSweep(fstart, fstop; kind = :dec, points = 10)

Small-signal frequency sweep (`.AC`).  `kind` is `:dec`, `:oct` or `:lin` and
`points` is points-per-decade/octave (or the total number of points for
`:lin`).

```jldoctest
julia> Jyce.directive(ACSweep(1, 100e3; points = 20))
".AC DEC 20 1 100000"
```
"""
struct ACSweep <: AbstractAnalysis
    kind::Symbol
    points::Int
    fstart::Any
    fstop::Any
end
ACSweep(fstart, fstop; kind::Symbol = :dec, points::Integer = 10) =
    ACSweep(kind, Int(points), fstart, fstop)
function directive(a::ACSweep)
    kw = a.kind === :dec ? "DEC" : a.kind === :oct ? "OCT" : a.kind === :lin ? "LIN" :
         throw(ArgumentError("ACSweep kind must be :dec, :oct or :lin, got $(a.kind)"))
    return _join_card(".AC", kw, string(a.points), spice(a.fstart), spice(a.fstop))
end
print_tag(::ACSweep) = "AC"

"""
    Transient(step, stop; start = 0, maxstep = nothing, uic = false)

Time-domain analysis (`.TRAN`).  `step` is the printing interval, `stop` the
end time.  Set `uic = true` to start from the initial conditions declared on
capacitors/inductors instead of the DC operating point.

```jldoctest
julia> Jyce.directive(Transient(1e-3, 2.0))
".TRAN 0.001 2"
```
"""
struct Transient <: AbstractAnalysis
    step::Any
    stop::Any
    start::Any
    maxstep::Any
    uic::Bool
end
Transient(step, stop; start = 0, maxstep = nothing, uic::Bool = false) =
    Transient(step, stop, start, maxstep, uic)
function directive(a::Transient)
    parts = [".TRAN", spice(a.step), spice(a.stop)]
    if a.maxstep !== nothing
        push!(parts, spice(a.start), spice(a.maxstep))
    elseif !(a.start == 0)
        push!(parts, spice(a.start))
    end
    a.uic && push!(parts, "UIC")
    return join(parts, " ")
end
print_tag(::Transient) = "TRAN"

"""
    Noise(output, source, fstart, fstop; kind = :dec, points = 10)

Noise analysis (`.NOISE`).  `output` is the observed probe (a node symbol or a
[`Probe`](@ref)) and `source` the input source name.
"""
struct Noise <: AbstractAnalysis
    output::String
    source::String
    kind::Symbol
    points::Int
    fstart::Any
    fstop::Any
end
Noise(output, source, fstart, fstop; kind::Symbol = :dec, points::Integer = 10) =
    Noise(probe_text(_as_probe(output)), _source_name(source), kind, Int(points), fstart, fstop)
function directive(a::Noise)
    kw = a.kind === :dec ? "DEC" : a.kind === :oct ? "OCT" : "LIN"
    return _join_card(".NOISE", a.output, a.source, kw, string(a.points),
                      spice(a.fstart), spice(a.fstop))
end
print_tag(::Noise) = "NOISE"

"""
    RawAnalysis(directive, tag)

Escape hatch for an analysis Jyce does not model: `directive` is written as-is
and `tag` is used on the `.PRINT` line.
"""
struct RawAnalysis <: AbstractAnalysis
    text::String
    tag::String
end
directive(a::RawAnalysis) = a.text
print_tag(a::RawAnalysis) = a.tag

"""
    Step(parameter, values)
    Step(parameter, start, stop, step)

A `.STEP` directive: re-run the analysis for each value of a `.PARAM`, with
Xyce looping internally.  For sweeps driven from Julia (arbitrary parameters,
arbitrary post-processing) see [`sweep`](@ref) instead.
"""
struct Step
    parameter::String
    spec::String
end
Step(parameter, values::AbstractVector) =
    Step(String(string(parameter)), "LIST " * join(spice.(values), " "))
Step(parameter, start, stop, step) =
    Step(String(string(parameter)), join(spice.((start, stop, step)), " "))
Step(parameter, r::AbstractRange) = Step(parameter, first(r), last(r), Base.step(r))
directive(s::Step) = _join_card(".STEP", s.parameter, s.spec)

# --- Output probes ---------------------------------------------------------

"""
    Probe(text)

A single column requested on a `.PRINT` line.  Build one with
[`voltage`](@ref), [`current`](@ref), [`power`](@ref), [`vdb`](@ref),
[`vphase`](@ref) or [`vmag`](@ref) rather than by hand.
"""
struct Probe
    text::String
end

probe_text(p::Probe) = p.text
Base.show(io::IO, p::Probe) = print(io, p.text)

"""
    voltage(node) -> Probe
    voltage(node_plus, node_minus) -> Probe

Node voltage `V(node)`, or the differential voltage `V(a,b)`.
"""
voltage(n::NodeLike) = Probe("V(" * node(n) * ")")
voltage(a::NodeLike, b::NodeLike) = Probe("V(" * node(a) * "," * node(b) * ")")

"""
    branch_current(element) -> Probe

Branch current `I(element)`; the element may be named (`:V1`) or passed as the
component itself.

Named `branch_current` rather than `current` because `Plots.current` already
claims that name; `Jyce.current` is available as a synonym when Plots is not
loaded.
"""
branch_current(e::Union{Symbol,AbstractString}) = Probe("I(" * String(string(e)) * ")")
branch_current(c::AbstractComponent) = Probe("I(" * designator(c) * ")")

"""
    current(element) -> Probe

Synonym for [`branch_current`](@ref), not exported to avoid clashing with
`Plots.current`.
"""
const current = branch_current

"""
    power(element) -> Probe

Device power `P(element)`.
"""
power(e::Union{Symbol,AbstractString}) = Probe("P(" * String(string(e)) * ")")
power(c::AbstractComponent) = Probe("P(" * designator(c) * ")")

"""
    vdb(node) -> Probe

Magnitude in decibels, `VDB(node)`; for [`ACSweep`](@ref) results.
"""
vdb(n::NodeLike) = Probe("VDB(" * node(n) * ")")

"""
    vphase(node) -> Probe

Phase in degrees, `VP(node)`; for [`ACSweep`](@ref) results.
"""
vphase(n::NodeLike) = Probe("VP(" * node(n) * ")")

"""
    vmag(node) -> Probe

Magnitude, `VM(node)`; for [`ACSweep`](@ref) results.
"""
vmag(n::NodeLike) = Probe("VM(" * node(n) * ")")

_as_probe(p::Probe) = p
_as_probe(n::Symbol) = voltage(n)
_as_probe(n::Integer) = voltage(n)
_as_probe(s::AbstractString) = Probe(String(s))
_as_probe(c::AbstractComponent) = current(c)
_as_probe(t::Tuple{<:NodeLike,<:NodeLike}) = voltage(t[1], t[2])
_as_probe(x) = throw(ArgumentError("cannot interpret $(repr(x)) as an output probe"))

_as_probes(xs::Union{Tuple,AbstractVector}) = Probe[_as_probe(x) for x in xs]
_as_probes(x) = Probe[_as_probe(x)]

"""
    print_directive(analysis, probes; format = nothing) -> String

Build the `.PRINT` card collecting `probes` for `analysis`.
"""
function print_directive(analysis::AbstractAnalysis, probes; format = nothing)
    ps = _as_probes(probes)
    isempty(ps) && return ""
    fmt = format === nothing ? "" : "FORMAT=" * String(string(format))
    return _join_card(".PRINT", print_tag(analysis), fmt, join(probe_text.(ps), " "))
end
