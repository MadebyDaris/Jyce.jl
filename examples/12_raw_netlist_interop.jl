# 12 - Working with existing netlists.
#
# Jyce never gets in the way of plain Xyce input: run a string, run a file, or
# mix generated and handwritten fragments in one circuit.

using Jyce

require_native!()

# 1. A netlist string, straight through.
text = """
* Handwritten netlist
V1 in 0 SIN(0 1 10)
R1 in out 1k
R2 out 0 2k
.TRAN 1ms 300ms
.PRINT TRAN V(in) V(out) I(V1)
.END
"""
res = simulate(text)
println("string netlist: ", length(times(res)), " time points, signals ", signals(res))

# 2. The same netlist from a file.
path = joinpath(mktempdir(), "divider.cir")
write(path, text)
res_file = simulate_file(path)
println("file netlist: ", issuccess(res_file) ? "ok" : res_file.error_message)

# 3. Generated circuit with handwritten fragments mixed in.
mixed = Circuit(
    VoltageSource(:V1, :in, :gnd, Sine(0, 1, 10)),
    RawCard("R1 in out 1k"),          # verbatim card
    Resistor(:R2, :out, :gnd, 2e3);
    title = "Mixed netlist",
)
directive!(mixed, ".OPTIONS TIMEINT RELTOL=1e-4")
println(netlist(mixed; analysis = Transient(1e-3, 0.3), outputs = [:in, :out]))

# 4. Reusable definitions held on the simulator instead of in the circuit.
sim = Simulator()
snippet!(sim, ".PARAM SCALE=1")
register_subcircuit!(sim, Subcircuit(:rdivider, (:in, :out),
    Resistor(:Rtop, :in, :out, expr"SCALE*1k"),
    Resistor(:Rbot, :out, :gnd, expr"SCALE*2k")))
println("simulator prelude:\n", definitions_prelude(sim))

load!(sim, """
V1 vin 0 DC 1
X1 vin vout rdivider
.OP
.PRINT DC V(vin) V(vout)
.END
""")
out = simulate(sim)
println("divider output: ", out[:vout][end], " V")
