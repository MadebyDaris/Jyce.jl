# Running simulations

## `simulate`

[`simulate`](@ref) accepts a circuit, a netlist string, or a simulator that
already has a netlist loaded:

```julia
simulate(ckt, Transient(1e-6, 1e-3); outputs = [:in, :out])
simulate(netlist_text)
simulate_file("circuits/amp.cir")
```

Useful keywords:

| Keyword | Meaning |
|:--|:--|
| `analysis`, `outputs`, `format` | override what the circuit carries |
| `params` | `.PARAM` overrides applied before the run |
| `plugins` | extra Verilog-A libraries to load |
| `output_file` | where Xyce writes its table (directories are created) |
| `sim` | reuse an existing [`Simulator`](@ref) |
| `strict` | `false` returns failed runs instead of throwing |
| `read_data` | `false` skips parsing the output table |
| `verbose` | pass Xyce's chatter through |

## Netlist errors abort the process

This is the one sharp edge worth knowing about. Xyce reports a netlist error -
an unknown parameter, a malformed card, a missing model - by aborting, and
because Jyce runs Xyce in-process that takes the Julia session with it. There
is no exception to catch.

Jyce therefore checks a generated circuit before handing it over:

```julia
validate(ckt; strict = false)   # list the problems without throwing
```

[`validate`](@ref) catches duplicate instance names, references to parameters,
models and subcircuits that are never defined, and nodes only one device
touches. [`simulate`](@ref) runs it automatically; pass `validate = false` to
skip it.

The checks are conservative - they are skipped where the circuit contains raw
cards or `.INCLUDE`s, and expressions are not analysed - so they reduce the
exposure rather than remove it. When working with handwritten netlist strings,
which Jyce cannot check, it is worth running new netlists in a throwaway
session first.

## Failures

A run that Xyce completes but reports as failed - a convergence failure, say -
throws [`SimulationFailure`](@ref), which carries the whole
[`SimulationOutput`](@ref) - including the exact netlist that was sent:

```julia
try
    simulate(ckt, Transient(1e-9, 1.0))
catch err
    err isa SimulationFailure || rethrow()
    println(err.output.error_message)
    println(err.output.netlist)      # what Xyce actually saw
end
```

For batch work, `strict = false` keeps the failure as data:

```julia
res = simulate(ckt, Transient(1e-6, 1e-3); strict = false)
issuccess(res) || @warn "did not converge" res.error_message
```

## Reusing a simulator

Creating a [`Simulator`](@ref) is not free, and a loaded simulator can be run
repeatedly. Pass one in to keep it alive across runs:

```julia
sim = Simulator()
for c in cload_values
    param!(ckt, :cload => c)
    simulate(ckt, Transient(1e-6, 1e-3); sim = sim)
end
```

This is what [`sweep`](@ref) does internally. Runs are sequential: one native
Xyce instance is driven at a time.

## Driving the simulator directly

The lower-level API is available when you want control over each step:

```julia
sim = Simulator(; verbose = true)
load!(sim, netlist(ckt; analysis = Transient(1e-6, 1e-3)))
set_param!(sim, :rload => 4.7e3)
add_plugin!(sim, "plugins/build/libmemristor_plugin.so")
output_suffix!(sim, "_run1")

res = simulate(sim)

isready(sim)        # netlist loaded and ready
last_error(sim)     # message from the native layer
debug_state(sim)    # internal state, for bug reports
prn_path(sim)       # output file of the last run
```

[`set_param!`](@ref) uses Xyce's own parameter override mechanism; it changes
`.PARAM` values without regenerating the netlist. [`sweep`](@ref) regenerates
the netlist instead, which also covers values that are not parameters.

## Where output files go

With no `output_file`, Jyce writes to a unique file under
[`default_output_dir`](@ref) - a per-process folder in `tempdir()`, overridable
with `JYCE_OUTPUT_DIR` - and reports it as `res.prn_file_path`. Left to itself
Xyce would name the file after the temporary netlist and tag it by analysis
(`....cir.FD.prn` for an `.AC` run), which is why Jyce always asks explicitly.

Pass `output_file` for any run whose raw table you want to keep:

```julia
simulate(ckt, Transient(1e-6, 1e-3); output_file = "results/run1.prn")
```

[`export_csv`](@ref) converts an existing `.prn` with the native exporter, and
`CSV.write("run.csv", res)` writes the parsed table from Julia.
