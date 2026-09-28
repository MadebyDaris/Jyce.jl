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

@testset "Netlist generation" begin
    # These run without the native backend: netlist text is pure Julia.
    @test Jyce.node(:gnd) == "0"
    @test Jyce.node(0) == "0"
    @test Jyce.node(:out) == "out"

    @test card(Resistor(:R1, :in, :out, 1e3)) == "R1 in out 1000"
    @test card(Resistor(:load, :in, :out, "4k7")) == "Rload in out 4k7"
    @test card(Capacitor(:C1, :out, :gnd, 1e-6; ic = 0.5)) == "C1 out 0 1e-06 IC=0.5"
    @test card(VoltageSource(:V1, :in, :gnd, DC(0), AC(1))) == "V1 in 0 DC 0 AC 1 0"
    @test card(Diode(:D1, :a, :b, :D1N4148)) == "D1 a b D1N4148"
    @test card(SubcircuitCall(:X1, (:in, :out), :rdivider; scale = 2)) ==
          "X1 in out rdivider PARAMS: scale=2"
    @test card(PluginDevice(:m1, :MEMRISTOR, (:p, :n, :gnd), :mymem)) ==
          "YMEMRISTOR m1 p n 0 mymem"

    @test Jyce.waveform(Sine(0, 2.0, 1.0)) == "SIN(0 2 1 0 0 0)"
    @test Jyce.waveform(PWL([(0.0, 0.0), (1e-3, 5.0)])) == "PWL(0 0 0.001 5)"

    @test directive(DCSweep(:V1, 0, 5, 0.1)) == ".DC V1 0 5 0.1"
    @test directive(ACSweep(1, 100e3; points = 20)) == ".AC DEC 20 1 100000"
    @test directive(Transient(1e-3, 2.0)) == ".TRAN 0.001 2"

    divider = Circuit(VoltageSource(:V1, :in, :gnd, DC(5)),
                      Resistor(:R1, :in, :out, 1e3),
                      Resistor(:R2, :out, :gnd, 2e3); title = "divider")
    text = netlist(divider; analysis = OperatingPoint(), outputs = [:in, :out])
    @test text == """
    * divider
    V1 in 0 DC 5
    R1 in out 1000
    R2 out 0 2000
    .OP
    .PRINT DC V(in) V(out)
    .END
    """
    @test nodes(divider) == ["0", "in", "out"]
    @test length(components(divider)) == 3

    macro_ckt = @circuit "macro" begin
        V1 = VoltageSource(:in, :gnd, DC(1))
        R1 = Resistor(:in, :gnd, 1e3)
        OperatingPoint()
        voltage(:in)
    end
    @test occursin("V1 in 0 DC 1", netlist(macro_ckt))
    @test occursin(".PRINT DC V(in)", netlist(macro_ckt))
end

@testset "Circuit validation" begin
    bad = Circuit(VoltageSource(:V1, :in, :gnd, DC(1)),
                  Resistor(:R1, :in, :out, :undeclared),
                  Diode(:D1, :out, :gnd, :nosuchmodel))
    issues = validate(bad; strict = false)
    @test any(contains("undeclared"), issues)
    @test any(contains("nosuchmodel"), issues)
    @test_throws Jyce.CircuitValidationError validate(bad)

    good = Circuit(VoltageSource(:V1, :in, :gnd, DC(1)),
                   Resistor(:R1, :in, :out, :rload),
                   Resistor(:R2, :out, :gnd, 1e3))
    param!(good, :rload => 1e3)
    @test isempty(validate(good; strict = false))
end
