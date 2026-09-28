# 05 - Half-wave rectifier: .MODEL cards and a DC sweep.
#
# Shows `Model`, a diode instance, a DC sweep of the source, and a transient run
# of the smoothing capacitor.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

rectifier = @circuit "Half-wave rectifier" begin
    Model(:D1N4148, :D; is = 2.52e-9, rs = 0.568, n = 1.752, cjo = 4e-12, bv = 100.0)

    V1 = VoltageSource(:in, :gnd, DC(0), Sine(0, 5.0, 50.0))
    D1 = Diode(:in, :out, :D1N4148)
    C1 = Capacitor(:out, :gnd, 100e-6)
    R1 = Resistor(:out, :gnd, 1e3)
end

# I-V curve of the diode alone: sweep the source and look at the current.
curve = Circuit(
    VoltageSource(:V1, :in, :gnd, DC(0)),
    Diode(:D1, :in, :gnd, :D1N4148),
    Model(:D1N4148, :D; is = 2.52e-9, rs = 0.568, n = 1.752);
    title = "Diode I-V",
)
iv = simulate(curve, DCSweep(:V1, -1.0, 0.9, 0.01); outputs = [branch_current(:V1)])
savefig(plot(iv["V1"], -iv["I(V1)"]; xlabel = "V (V)", ylabel = "I (A)", yscale = :identity,
             label = "1N4148", linewidth = 2, title = "Diode forward characteristic", grid = true),
        joinpath(@__DIR__, "plots", "diode_iv.png"))

# Rectified output over five mains cycles.
res = simulate(rectifier, Transient(100e-6, 100e-3); outputs = [:in, :out])
savefig(plot(res; title = "Half-wave rectifier with smoothing"),
        joinpath(@__DIR__, "plots", "rectifier.png"))

ripple = maximum(res[:out][end÷2:end]) - minimum(res[:out][end÷2:end])
println("output ripple: ", round(ripple * 1e3; digits = 1), " mV")
println("saved plots/diode_iv.png and plots/rectifier.png")
