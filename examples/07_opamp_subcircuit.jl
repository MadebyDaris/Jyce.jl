# 07 - Reusable blocks: a .SUBCKT built from Julia components.
#
# `Subcircuit` defines a block once; `SubcircuitCall` instantiates it. Both the
# definition and its parameters are ordinary Julia values, so a block can be
# generated, parameterised and reused like any other function result.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

"""A single-pole op-amp macromodel: differential gain, output resistance, one pole."""
function opamp_model(; gain = 1e5, pole = 10.0, rout = 100.0)
    return Subcircuit(:opamp, (:inp, :inn, :out),
        # Differential input -> internal node, with the dominant pole.
        VCVS(:Egain, :a, :gnd, :inp, :inn, gain),
        Resistor(:Rp, :a, :b, 1e3),
        Capacitor(:Cp, :b, :gnd, 1 / (2pi * pole * 1e3)),
        # Output buffer.
        VCVS(:Eout, :c, :gnd, :b, :gnd, 1.0),
        Resistor(:Rout, :c, :out, rout),
    )
end

inverting = Circuit(
    opamp_model(),
    VoltageSource(:V1, :in, :gnd, DC(0), AC(1), Sine(0, 0.1, 1e3)),
    Resistor(:Rin, :in, :minus, 1e3),
    Resistor(:Rf, :minus, :out, 10e3),
    SubcircuitCall(:X1, (:gnd, :minus, :out), :opamp);
    title = "Inverting amplifier, gain -10",
)

tran = simulate(inverting, Transient(10e-6, 3e-3); outputs = [:in, :out])
measured = maximum(tran[:out]) / maximum(tran[:in])
println("closed-loop gain (transient): ", round(measured; digits = 2), " (expected -10)")

ac = simulate(inverting, ACSweep(1, 1e6; points = 20); outputs = [vdb(:out), vphase(:out)])
plot_bode(ac; node = :out, output_file = joinpath(@__DIR__, "plots", "opamp_bode.png"),
          title = "Inverting amplifier response")
savefig(plot(tran; title = "Inverting amplifier, 1 kHz input"),
        joinpath(@__DIR__, "plots", "opamp_tran.png"))
println("saved plots/opamp_bode.png and plots/opamp_tran.png")
