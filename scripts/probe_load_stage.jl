using Jyce

# Allow import even when native backend is unavailable.
# This script only probes load-stage behavior.
if !Jyce.native_available()
    Jyce.require_native!()
end

sim = Jyce.XyceSimulator(false)

repo_netlist = joinpath(@__DIR__, "..", "..", "XyceSolver", "assets", "xyce_cir", "cs_amplifier.cir")

inline_netlist = """
* Jyce load-stage probe
V1 1 0 DC 1
R1 1 0 1k
.op
.print op V(1)
.end
"""

println("probe: netlist_file_exists=" * string(isfile(repo_netlist)))
println("probe: netlist_file_path=" * repo_netlist)

file_loaded = isfile(repo_netlist) ? Jyce.loadNetlistFile(sim, repo_netlist) : false
println("probe: loadNetlistFile_success=" * string(file_loaded))
println("probe: isReady_after_file=" * string(Jyce.isReady(sim)))

string_loaded = Jyce.loadNetlistString(sim, inline_netlist)
println("probe: loadNetlistString_success=" * string(string_loaded))
println("probe: isReady_after_string=" * string(Jyce.isReady(sim)))

last_error = try
    Jyce.getLastError(sim)
catch
    ""
end
println("probe: last_error=" * String(last_error))

println("probe: load_stage_ok=true")
println("probe: note=No simulation was executed in this script.")
