# 11 - A 4x4 memristive crossbar, generated with a Julia loop.
#
# This is the case where a netlist file stops being convenient: the circuit is
# a function of the array size and of a conductance matrix. Here Jyce is doing
# what a netlist cannot - the circuit is computed, not written.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using DataFrames
using Plots

require_native!()

"""
    crossbar(G; vread = 0.2, row = 1)

Build an `n x m` crossbar of resistors whose conductances are given by `G`,
drive one word line with `vread`, and sense each bit line through a small
transimpedance resistor to ground.
"""
function crossbar(G::AbstractMatrix; vread = 0.2, row = 1, rsense = 100.0)
    n, m = size(G)
    ckt = Circuit(; title = "$(n)x$(m) crossbar, reading row $row")

    for i in 1:n
        # Unselected word lines are grounded.
        add!(ckt, VoltageSource(Symbol("Vw$i"), Symbol("w$i"), :gnd, DC(i == row ? vread : 0.0)))
    end

    for j in 1:m
        add!(ckt, Resistor(Symbol("Rs$j"), Symbol("b$j"), :gnd, rsense))
    end

    for i in 1:n, j in 1:m
        add!(ckt, Resistor(Symbol("R$(i)_$(j)"), Symbol("w$i"), Symbol("b$j"), 1 / G[i, j]))
    end

    output!(ckt, (voltage(Symbol("b$j")) for j in 1:m)...)
    return ckt
end

# A weight matrix: high conductance = "1", low conductance = "0".
bits = Bool[1 0 1 1
            0 1 1 0
            1 1 0 0
            0 0 1 1]
G = map(b -> b ? 1 / 1e3 : 1 / 100e3, bits)

# Read every row in turn; the sensed bit-line voltages recover the stored bits.
readout = zeros(size(G)...)
for row in 1:size(G, 1)
    res = simulate(crossbar(G; row = row), OperatingPoint())
    readout[row, :] = [res[Symbol("b$j")][end] for j in 1:size(G, 2)]
end

println("sensed bit-line voltages (V):")
display(DataFrame(readout, [Symbol("b$j") for j in 1:size(G, 2)]))

recovered = readout .> (maximum(readout) + minimum(readout)) / 2
println("\nrecovered bits match stored bits: ", recovered == bits)

heatmap(readout; title = "Crossbar read-out (V)", xlabel = "bit line", ylabel = "word line",
        yflip = true, color = :viridis)
savefig(joinpath(@__DIR__, "plots", "crossbar_readout.png"))
println("saved plots/crossbar_readout.png")
