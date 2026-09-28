# 03 - Pulse response of the same RC network, in the time domain.
#
# Shows a Pulse source, a transient analysis, and the plot recipe: `plot(res)`
# draws every printed signal against time.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

R, C = 1e3, 100e-9
tau = R * C

rc = @circuit "RC pulse response" begin
    V1 = VoltageSource(:in, :gnd, Pulse(0, 1; delay = 100e-6, rise = 1e-6, fall = 1e-6,
                                        width = 1e-3, period = 2e-3))
    R1 = Resistor(:in, :out, R)
    C1 = Capacitor(:out, :gnd, C)
end

res = simulate(rc, Transient(2e-6, 4e-3); outputs = [:in, :out])

# The time constant read straight off the response.
t, vout = times(res), res[:out]
settled = maximum(vout)
i63 = findfirst(>=(0.632 * settled), vout)
println("tau (analytic) = ", tau, " s")
println("tau (measured) ≈ ", round(t[i63] - 100e-6; sigdigits = 3), " s")

p = plot(res; title = "RC pulse response", ylabel = "Voltage (V)")
savefig(p, joinpath(@__DIR__, "plots", "rc_pulse.png"))
println("saved plots/rc_pulse.png")
