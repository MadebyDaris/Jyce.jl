# Verilog-A plugins

Xyce compiles Verilog-A models into shared libraries through ADMS; Jyce loads
them into the simulator and instantiates their devices with
[`PluginDevice`](@ref).

## Building a plugin

For the ADMS memristor model in this repository:

```bash
# 1. Verilog-A -> generated plugin project
buildxyceplugin.sh -o memristor_plugin memristor-model.va Jyce/plugins

# 2. Build the generated project
cmake -S Jyce/plugins -B Jyce/plugins/build \
      -DXYCE_INSTALL=/usr/local/XyceNF_7.10 \
      -DPLUGIN_NAME=memristor_plugin
cmake --build Jyce/plugins/build -j
```

The result is `Jyce/plugins/build/libmemristor_plugin.so`.

## Finding the device name

A compiled plugin declares its device type in the generated header. For the
memristor:

```cpp
static const char *name() {return "ADMS Memristor";}
static const char *deviceTypeName() {return "MEMRISTOR level 1";}
static int numNodes() {return 3;}
```

So the device is `MEMRISTOR`, level 1, with three terminals - in this model
`p`, `n` and `gnd`, taken from the Verilog-A `electrical p, n, gnd;`
declaration. Instance and model parameters are the `addPar` entries in the
generated `.C` file (`RON`, `ROFF`, `INIT_STATE`, `V_ON`, `V_OFF`, `K_ON`,
`K_OFF`, `ALPHA_ON`, `ALPHA_OFF`, ...).

## Using it from Jyce

```julia
ckt = @circuit "VTEAM memristor" begin
    Model(:mem1, :MEMRISTOR; level = 1, RON = 100, ROFF = 16e3, INIT_STATE = 0.1,
          V_ON = -0.5, V_OFF = 0.5, K_ON = -10, K_OFF = 10,
          ALPHA_ON = 1, ALPHA_OFF = 1)

    V1 = VoltageSource(:in, :gnd, Sine(0, 2.0, 1.0))
    M1 = PluginDevice(:MEMRISTOR, (:in, :gnd, :gnd), :mem1)

    Transient(1e-3, 2.0)
    voltage(:in)
    branch_current(:V1)
end

plugin!(ckt, "plugins/build/libmemristor_plugin.so")
res = simulate(ckt)
```

Inside `@circuit`, `M1 = PluginDevice(:MEMRISTOR, ...)` becomes
`PluginDevice(:M1, :MEMRISTOR, (:in, :gnd, :gnd), :mem1)` and emits
`YMEMRISTOR M1 in 0 0 mem1`: the device type joins the `Y`, the instance name
follows it, then the terminals and the model name, as Xyce expects.

The library can also be attached to the simulator rather than the circuit:

```julia
sim = Simulator()
add_plugin!(sim, "plugins/build/libmemristor_plugin.so")
res = simulate(ckt; sim = sim)
```

[`clear_plugins!`](@ref) unregisters them.

## Troubleshooting

- *Device type not recognised* - the `.MODEL` type must match
  `deviceTypeName()`, and `level` must match the level in that string.
- *Wrong number of nodes* - `numNodes()` in the generated header is
  authoritative, including internal ground terminals.
- *Library not found* - [`add_plugin!`](@ref) checks the path exists before
  handing it to Xyce; pass an absolute path when in doubt.
- *Parameter ignored* - parameter names are the `addPar` strings, upper case,
  and model parameters belong on the `.MODEL` card rather than the instance.

## Alternative: a SPICE subcircuit

Many device models do not need a compiled plugin. The Biolek HP memristor, for
instance, is a `.SUBCKT` built from behavioural sources, which needs no build
step at all - see
[`examples/09_memristor_subcircuit.jl`](https://github.com/MadebyDaris/Jyce/blob/master/examples/09_memristor_subcircuit.jl).
Plugins pay off when the model is large, performance-critical, or already
written in Verilog-A.
