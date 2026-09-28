# 02 - RC low-pass: AC sweep and a Bode plot.
#
# One source carries both the DC value and the AC stimulus, so the same circuit
# can be reused for operating point, AC and transient analyses.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce

require_native!()

rc = @circuit "RC low-pass" begin
    V1 = VoltageSource(:in, :gnd, DC(0), AC(1))
    R1 = Resistor(:in, :out, 1e3)
    C1 = Capacitor(:out, :gnd, 1e-6)
end

# f_-3dB = 1 / (2*pi*R*C)
cutoff = 1 / (2pi * 1e3 * 1e-6)
println("expected cutoff: ", round(cutoff; digits = 2), " Hz")

res = simulate(rc, ACSweep(1, 100e3; points = 20); outputs = [vdb(:out), vphase(:out)])

mag = res["VDB(OUT)"]
freq = res["FREQ"]
idx = argmin(abs.(mag .- (mag[1] - 3)))
println("measured -3 dB point: ", round(freq[idx]; digits = 2), " Hz")

plot_bode(res; node = :out, output_file = joinpath(@__DIR__, "plots", "rc_bode.png"),
          title = "RC low-pass frequency response")
println("saved plots/rc_bode.png")
