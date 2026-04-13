using Test
using DataFrames

ENV["JYCE_ALLOW_MISSING_NATIVE"] = "1"
using Jyce

@testset "Jyce native integration" begin
    @test Jyce.native_available() isa Bool

    if Jyce.native_available()
        sim = Jyce.XyceSimulator()
        @test sim isa Jyce.XyceSimulator

        netlist = """
        * Jyce in-memory simulation data smoke
        V1 in 0 DC 1
        R1 in out 1k
        R2 out 0 2k
        .OP
        .PRINT DC V(in) V(out)
        .END
        """

        Jyce.loadNetlistString(sim, netlist)
        data = Jyce.run_simulation_data(sim)
        @test data.success isa Bool
        @test data.error_message isa String
        @test data.prn_file_path isa String
        @test data.parameter_pairs isa Vector{String}
        @test data.plugin_libraries isa Vector{String}
        @test data.time_points isa Vector{Float64}
        @test data.node_names isa Vector{String}
        @test data.node_voltages isa Vector

        Jyce.add_inline_snippet(sim, ".PARAM SCALE=1")
        Jyce.register_subcircuit(sim, "rdivider", ".SUBCKT rdivider in out\nRtop in out 1k\nRbot out 0 2k\n.ENDS rdivider\n")

        prelude = Jyce.custom_components_prelude(sim)
        @test occursin(".PARAM SCALE=1", prelude)
        @test occursin(".SUBCKT rdivider", prelude)

        custom_netlist = """
        * custom subckt smoke
        V1 vin 0 DC 1
        X1 vin vout rdivider
        .OP
        .PRINT DC V(vin) V(vout)
        .END
        """

        Jyce.loadNetlistString(sim, custom_netlist)
        custom_data = Jyce.run_simulation_data(sim)
        @test custom_data.success == true

        Jyce.clear_custom_components(sim)
        cleared_prelude = Jyce.custom_components_prelude(sim)
        @test isempty(strip(cleared_prelude))
    else
        @test_throws ErrorException Jyce.require_native!()
    end
end

@testset "Jyce utils detection" begin
    df = DataFrame(Symbol("V(N001)") => [0.0, 0.1], Symbol("I(V1)") => [0.0, -1e-6])
    cols = Jyce.detect_iv_columns(df)
    @test cols.voltage_col == "V(N001)"
    @test cols.current_col == "I(V1)"
    @test "V(N001)" in cols.available_columns
    @test "I(V1)" in cols.available_columns
end
