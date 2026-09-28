# 09 - Memristor as a .SUBCKT: the Biolek HP model and its pinched hysteresis.
#
# The model uses SPICE constructs Jyce does not wrap (`.func`, behavioural
# sources with SDT), so the body is kept as netlist text inside a Julia-defined
# subcircuit. Mixing the two levels is the point: the parts Jyce models become
# Julia values, the rest stays verbatim.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

const BIOLEK_MEMRISTOR = raw"""
.SUBCKT memristor plus minus PARAMS:
+ Ron=100 Roff=16K Rinit=11K D=10N uv=10F p=1
* State: x = w/D, integrated from the current through the device.
Gx 0 x value={I(Emem)*uv*Ron/D**2*f(V(x),p)}
Cx x 0 1 IC={(Roff-Rinit)/(Roff-Ron)}
Raux x 0 1000000
* Resistive port.
Emem plus aux value={-I(Emem)*V(x)*(Roff-Ron)}
Roff aux minus {Roff}
* Joglekar window for nonlinear dopant drift.
.func f(x,p) {1-(2*x-1)**(2*p)}
.ENDS memristor
"""

ckt = Circuit(
    RawCard(BIOLEK_MEMRISTOR),
    VoltageSource(:V1, :n001, :gnd, Sine(0, 1.2, 1.0)),
    SubcircuitCall(:XMemristor, (:n001, :gnd), :memristor);
    title = "Biolek HP memristor",
)

res = simulate(ckt, Transient(2e-3, 3.0); outputs = [:n001, branch_current(:V1)],
               output_file = joinpath(@__DIR__, "plots", "memristor.prn"))

plot_transient_voltages(res; nodes = ["V(N001)"],
                        output_file = joinpath(@__DIR__, "plots", "memristor_transient.png"),
                        title = "Memristor drive voltage")

plot_iv_characteristic(res;
                       voltage_col = "V(N001)", current_col = "I(V1)",
                       output_file = joinpath(@__DIR__, "plots", "memristor_iv.png"),
                       title = "Pinched hysteresis loop", cycle_overlay = true)

# Two numbers that characterise the loop: the peak current, and the area it
# encloses (zero for a plain resistor, positive for a memristive device).
v, i = res["V(N001)"], -res["I(V1)"]
loop_area = abs(sum((v[k+1] - v[k]) * (i[k+1] + i[k]) / 2 for k in 1:(length(v)-1)))
println("peak current: ", round(maximum(abs.(i)) * 1e3; digits = 3), " mA")
println("hysteresis loop area: ", round(loop_area * 1e3; sigdigits = 3), " mW")
println("saved plots/memristor_transient.png and plots/memristor_iv.png")
