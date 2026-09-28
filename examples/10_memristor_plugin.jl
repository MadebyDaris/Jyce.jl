# 10 - A compiled Verilog-A device: the ADMS memristor plugin.
#
# This example is about the mechanics of using a compiled device from Julia:
# building the plugin, loading the library, writing its .MODEL card, and
# instantiating it with `PluginDevice`. Whether a given parameter set converges
# is a modelling question, not a Jyce one, so the run is made with
# `strict = false` and reported either way.
#
# Build the plugin first (see docs/src/manual/plugins.md):
#
#     buildxyceplugin.sh -o memristor_plugin memristor-model.va Jyce/plugins
#     cmake -S Jyce/plugins -B Jyce/plugins/build \
#           -DXYCE_INSTALL=/usr/local/XyceNF_7.10 -DPLUGIN_NAME=memristor_plugin
#     cmake --build Jyce/plugins/build -j
#
# The generated header tells you what to write in the netlist:
#
#     deviceTypeName() -> "MEMRISTOR level 1"     => .MODEL ... MEMRISTOR level=1
#     numNodes()       -> 3                       => p, n and the state terminal
#     addPar("RON", ...), addPar("ROFF", ...)     => model parameter names

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using Plots

require_native!()

plugin = get(ENV, "JYCE_MEMRISTOR_PLUGIN",
             joinpath(@__DIR__, "..", "plugins", "build", "libmemristor_plugin.so"))

if !isfile(plugin)
    @warn "plugin not built; skipping" plugin
    exit(0)
end

ckt = @circuit "ADMS memristor plugin" begin
    # Model parameters are the addPar() names from the generated .C file;
    # anything left out keeps the model's own default.
    Model(:mem1, :MEMRISTOR; level = 1, RON = 100, ROFF = 16e3, INIT_STATE = 0.5)

    V1 = VoltageSource(:in, :gnd, Sine(0, 1.0, 1.0))
    Rs = Resistor(:in, :mid, 100.0)                      # series limiter
    m1 = PluginDevice(:MEMRISTOR, (:mid, :gnd, :xstate), :mem1)

    Transient(1e-3, 2.0)
    voltage(:in)
    voltage(:mid)
    branch_current(:V1)
end
plugin!(ckt, plugin)

println("netlist sent to Xyce:\n")
println(netlist(ckt))

res = simulate(ckt; output_file = joinpath(@__DIR__, "plots", "memristor_plugin.prn"),
               strict = false)

if !issuccess(res)
    println("""
    The plugin loaded and the device was instantiated, but Xyce did not converge
    with these parameters: $(res.error_message)

    That is a model question rather than a Jyce one. Things to try:
      * the parameter defaults in plugins/N_DEV_ADMSMemristor.C (addPar entries),
        in particular the model selector, window type and time-step parameters;
      * the third terminal - the Verilog-A module declares `electrical p, n, gnd`,
        so check what the state port expects to be connected to;
      * a smaller drive amplitude, or .OPTIONS NONLIN settings.

    For a memristor that runs out of the box, see 09_memristor_subcircuit.jl.
    """)
    exit(0)
end

plot_iv_characteristic(res; voltage_col = "V(MID)", current_col = "I(V1)",
                       output_file = joinpath(@__DIR__, "plots", "memristor_plugin_iv.png"),
                       title = "ADMS memristor plugin I-V")
println("saved plots/memristor_plugin_iv.png")
