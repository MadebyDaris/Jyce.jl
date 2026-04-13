using Jyce

# This script is intended for CI/native verification jobs and should fail fast.
using Jyce

function main()
    # This script is intended for CI/native verification jobs and should fail fast.
    Jyce.require_native!()

    sim = Jyce.XyceSimulator(false)

    repo_netlists = [
        joinpath(@__DIR__, "..", "..", "XyceSolver", "assets", "xyce_cir", "voltage_divider.cir"),
        joinpath(@__DIR__, "..", "..", "XyceSolver", "assets", "xyce_cir", "rc_filter_ac.cir"),
        joinpath(@__DIR__, "..", "..", "XyceSolver", "assets", "xyce_cir", "rc_filter_transient.cir"),
    ]

    minimal_netlist = """
* Jyce native smoke test
V1 1 0 DC 1
R1 1 0 1k
.op
.print op V(1)
.end
"""

    loaded = false
    selected_netlist = nothing
    for net in repo_netlists
        if isfile(net)
            loaded = Jyce.loadNetlistFile(sim, net)
            if loaded
                selected_netlist = net
                break
            end
        end
    end

    if !loaded
        loaded = Jyce.loadNetlistString(sim, minimal_netlist)
    end

    if !loaded
        err = try
            Jyce.getLastError(sim)
        catch
            "unknown load error"
        end
        error("netlist load failed: " * String(err))
    end

    if selected_netlist !== nothing
        println("selected_netlist=" * selected_netlist)
    else
        println("selected_netlist=inline_fallback")
    end

    result = Jyce.runSimulation(sim)
    if !Jyce.simulation_success(result)
        error("runSimulation failed: " * Jyce.simulation_error_message(result))
    end

    println("native_smoke_ok=true")
    println("prn_file_path=" * Jyce.simulation_prn_file_path(result))
end

main()
