# 01 - Voltage divider: the smallest complete Jyce program.
#
# Build a circuit from typed components, solve its DC operating point, and read
# the answer back as a DataFrame.
#
#     julia --project examples/01_voltage_divider.jl

using Jyce
using DataFrames

require_native!()

divider = Circuit(
    VoltageSource(:V1, :in, :gnd, DC(5)),
    Resistor(:R1, :in, :out, 1e3),
    Resistor(:R2, :out, :gnd, 2e3);
    title = "Resistive divider",
)

# Inspect what will be sent to Xyce before running anything.
println(netlist(divider; analysis = OperatingPoint(), outputs = [:in, :out, branch_current(:V1)]))

res = simulate(divider, OperatingPoint(); outputs = [:in, :out, branch_current(:V1)])

println(res)
println("V(out)  = ", res[:out][end], " V   (expected ", 5 * 2e3 / 3e3, ")")
println("I(V1)   = ", res["I(V1)"][end], " A")
println("\nFull table:")
println(DataFrame(res))
