# 08 - Parameter sweeps: design-space exploration from Julia.
#
# `sweep` re-runs a circuit for every combination of `.PARAM` values. With a
# function it reduces each run on the fly and hands back one tidy DataFrame -
# the shape you want for `groupby`, `plot` or `CSV.write`.

ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")   # save figures without a display

using Jyce
using DataFrames
using Plots

require_native!()

# Parameters are referenced from component values as Symbols.
rc = Circuit(
    VoltageSource(:V1, :in, :gnd, DC(0), AC(1)),
    Resistor(:R1, :in, :out, :rload),
    Capacitor(:C1, :out, :gnd, :cload);
    title = "RC with swept R and C",
)
param!(rc, :rload => 1e3, :cload => 1e-6)

# 1. Sweep one parameter, keep every waveform.
res = sweep(rc, ACSweep(10, 1e6; points = 20), :rload => [1e2, 1e3, 1e4];
            outputs = [vdb(:out)])
println(res)

p = plot(res; signal = "VDB(OUT)", xscale = :log10, xlabel = "Frequency (Hz)",
         ylabel = "|V(out)| (dB)", title = "Cutoff vs. series resistance")
savefig(p, joinpath(@__DIR__, "plots", "sweep_rc.png"))

# 2. Two parameters, reduced to one row per run.
corners = sweep(rc, ACSweep(10, 1e6; points = 20),
                :rload => [1e2, 1e3, 1e4],
                :cload => [1e-7, 1e-6]; outputs = [vdb(:out)]) do out
    mag = out["VDB(OUT)"]
    freq = out["FREQ"]
    (; cutoff_hz = freq[argmin(abs.(mag .- (mag[1] - 3)))])
end

corners.analytic_hz = 1 ./ (2pi .* corners.rload .* corners.cload)
println(corners)

# 3. The tidy long-format table of every waveform, ready for DataFrames work.
long = DataFrame(res)
println("long table: ", nrow(long), " rows x ", ncol(long), " columns")
println("saved plots/sweep_rc.png")
