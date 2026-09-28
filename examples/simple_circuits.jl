# Legacy-style example, kept working: a netlist string driven through the
# original API.  See 02_rc_lowpass_ac.jl for the same circuit with the current
# interface.
using Jyce

require_native!()

sim = Jyce.XyceSimulator(false)

custom_netlist = """
* RC low-pass frequency response
Vin input 0 AC 1

* RC filter components
R1 input output 1k
C1 output 0 1u

* AC analysis: 10 points per decade, 1Hz to 100kHz
.AC DEC 10 1 100k

* Print frequency response
.PRINT AC VDB(output) VP(output)

.END
"""
Jyce.loadNetlistString(sim, custom_netlist)
result = Jyce.runSimulation(sim)
if Jyce.simulation_success(result)
    println("Simulation succeeded!")
    println("Frequency points: ", Jyce.simulation_prn_file_path(result))
else
    println("Simulation failed: ", Jyce.simulation_error_message(result))
end