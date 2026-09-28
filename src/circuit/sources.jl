# Independent-source waveforms.
#
# A source card may carry several specifications at once (a DC operating point,
# an AC small-signal magnitude and a transient waveform), so every waveform is
# a value and sources simply hold a list of them.

"""
    AbstractWaveform

Supertype of every independent-source specification ([`DC`](@ref), [`AC`](@ref),
[`Sine`](@ref), [`Pulse`](@ref), [`PWL`](@ref), [`Exponential`](@ref),
[`SFFM`](@ref)).  Subtypes render themselves with [`waveform`](@ref).
"""
abstract type AbstractWaveform end

"""
    waveform(w::AbstractWaveform) -> String

Render a waveform as the text that follows the node names on a source card.
"""
function waveform end

"""
    DC(value)

Constant source value, rendered as `DC <value>`.  Used for operating points and
as the sweep base for [`DCSweep`](@ref).

```jldoctest
julia> Jyce.waveform(DC(5))
"DC 5"
```
"""
struct DC <: AbstractWaveform
    value::Any
end
waveform(w::DC) = "DC " * spice(w.value)

"""
    AC(magnitude = 1.0, phase = 0.0)

Small-signal stimulus for [`ACSweep`](@ref) analyses, rendered as
`AC <magnitude> <phase>`.  The phase is in degrees.
"""
struct AC <: AbstractWaveform
    magnitude::Any
    phase::Any
end
AC(magnitude = 1.0) = AC(magnitude, 0.0)
waveform(w::AC) = "AC " * spice(w.magnitude) * " " * spice(w.phase)

"""
    Sine(offset, amplitude, frequency; delay = 0, damping = 0, phase = 0)

Damped sinusoid, rendered as `SIN(offset amplitude frequency delay damping phase)`.
`phase` is in degrees, `damping` in 1/s.

```jldoctest
julia> Jyce.waveform(Sine(0, 2.0, 1.0))
"SIN(0 2 1 0 0 0)"
```
"""
struct Sine <: AbstractWaveform
    offset::Any
    amplitude::Any
    frequency::Any
    delay::Any
    damping::Any
    phase::Any
end
Sine(offset, amplitude, frequency; delay = 0, damping = 0, phase = 0) =
    Sine(offset, amplitude, frequency, delay, damping, phase)
waveform(w::Sine) = "SIN(" * join(spice.((w.offset, w.amplitude, w.frequency, w.delay, w.damping, w.phase)), " ") * ")"

"""
    Pulse(low, high; delay = 0, rise = 0, fall = 0, width, period)

Rectangular pulse train, rendered as `PULSE(low high delay rise fall width period)`.
`width` defaults to half of `period`; `period` defaults to `width` when only the
width is given, producing a single pulse when neither is supplied.
"""
struct Pulse <: AbstractWaveform
    low::Any
    high::Any
    delay::Any
    rise::Any
    fall::Any
    width::Any
    period::Any
end
function Pulse(low, high; delay = 0, rise = 0, fall = 0, width = nothing, period = nothing)
    if width === nothing && period === nothing
        throw(ArgumentError("Pulse requires at least one of `width` or `period`"))
    end
    w = width === nothing ? period / 2 : width
    p = period === nothing ? w : period
    return Pulse(low, high, delay, rise, fall, w, p)
end
waveform(w::Pulse) = "PULSE(" * join(spice.((w.low, w.high, w.delay, w.rise, w.fall, w.width, w.period)), " ") * ")"

"""
    PWL(points)
    PWL(times, values)

Piecewise-linear source from `(time, value)` pairs, rendered as
`PWL(t1 v1 t2 v2 ...)`.

```jldoctest
julia> Jyce.waveform(PWL([(0.0, 0.0), (1e-3, 5.0)]))
"PWL(0 0 0.001 5)"
```
"""
struct PWL <: AbstractWaveform
    points::Vector{Tuple{Any,Any}}
    PWL(points::Vector{Tuple{Any,Any}}) = new(points)
end
PWL(points::AbstractVector) = PWL(Tuple{Any,Any}[(first(p), last(p)) for p in points])
PWL(times::AbstractVector, values::AbstractVector) =
    (length(times) == length(values) ||
     throw(ArgumentError("PWL: times and values must have equal length"));
     PWL([(t, v) for (t, v) in zip(times, values)]))
waveform(w::PWL) = "PWL(" * join((spice(t) * " " * spice(v) for (t, v) in w.points), " ") * ")"

"""
    Exponential(v1, v2, rise_delay, rise_tau, fall_delay, fall_tau)

Exponential rise/fall source, rendered as `EXP(...)`.
"""
struct Exponential <: AbstractWaveform
    v1::Any
    v2::Any
    rise_delay::Any
    rise_tau::Any
    fall_delay::Any
    fall_tau::Any
end
waveform(w::Exponential) =
    "EXP(" * join(spice.((w.v1, w.v2, w.rise_delay, w.rise_tau, w.fall_delay, w.fall_tau)), " ") * ")"

"""
    SFFM(offset, amplitude, carrier_freq, modulation_index, signal_freq)

Single-frequency FM source, rendered as `SFFM(...)`.
"""
struct SFFM <: AbstractWaveform
    offset::Any
    amplitude::Any
    carrier_freq::Any
    modulation_index::Any
    signal_freq::Any
end
waveform(w::SFFM) =
    "SFFM(" * join(spice.((w.offset, w.amplitude, w.carrier_freq, w.modulation_index, w.signal_freq)), " ") * ")"

"""
    RawWaveform(text)

Escape hatch for a source specification Jyce does not model yet; `text` is
copied verbatim onto the source card.
"""
struct RawWaveform <: AbstractWaveform
    text::String
end
waveform(w::RawWaveform) = w.text

# Bare numbers and strings are accepted wherever a waveform is expected.
_as_waveform(w::AbstractWaveform) = w
_as_waveform(x::Real) = DC(x)
_as_waveform(x::AbstractString) = RawWaveform(String(x))
_as_waveform(x::SpiceExpr) = RawWaveform(spice(x))
_as_waveform(x) = throw(ArgumentError("cannot interpret $(repr(x)) as a source waveform"))

_as_waveforms(x) = AbstractWaveform[_as_waveform(x)]
_as_waveforms(xs::Union{Tuple,AbstractVector}) = AbstractWaveform[_as_waveform(x) for x in xs]
