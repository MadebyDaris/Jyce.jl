# 04 - Series RLC: damping, initial conditions and a resonance sweep.
#
# Demonstrates `ic!` + `uic = true` (start from stored energy instead of the DC
# operating point) and a frequency sweep of the same network.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

L, C = 10e-3, 100e-9
f0 = 1 / (2pi * sqrt(L * C))
println("resonance: ", round(f0; digits = 1), " Hz")

function rlc(R)
    ckt = @circuit "Series RLC" begin
        V1 = VoltageSource(:in, :gnd, DC(0), AC(1))
        R1 = Resistor(:in, :a, R)
        L1 = Inductor(:a, :out, L)
        C1 = Capacitor(:out, :gnd, C)
    end
    return ckt
end

# Frequency response for three damping factors.
p = plot(; xscale = :log10, xlabel = "Frequency (Hz)", ylabel = "|V(out)| (dB)",
         title = "Series RLC resonance", grid = true)
for R in (10.0, 100.0, 1000.0)
    res = simulate(rlc(R), ACSweep(100, 1e6; points = 50); outputs = [vdb(:out)])
    plot!(p, res["FREQ"], res["VDB(OUT)"]; label = "R = $(Int(R)) Ω", linewidth = 2)
end
savefig(p, joinpath(@__DIR__, "plots", "rlc_resonance.png"))

# Ringing from a charged capacitor, with no source driving it.
ringing = @circuit "RLC ringing" begin
    R1 = Resistor(:out, :a, 10.0)
    L1 = Inductor(:a, :gnd, L)
    C1 = Capacitor(:out, :gnd, C; ic = 1.0)
end
ic!(ringing, :out => 1.0)

res = simulate(ringing, Transient(1e-6, 2e-3; uic = true); outputs = [:out])
savefig(plot(res; title = "RLC ringing from V(out) = 1 V"),
        joinpath(@__DIR__, "plots", "rlc_ringing.png"))
println("saved plots/rlc_resonance.png and plots/rlc_ringing.png")
