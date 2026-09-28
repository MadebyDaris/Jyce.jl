# 06 - NMOS common-source amplifier: transistor models and small-signal gain.
#
# One circuit, three analyses: operating point for the bias, AC for the gain,
# transient for the large-signal waveform.
#
# Bias by hand first: with kp = 120 uA/V^2 and W/L = 100, a gate overdrive of
# ~0.2 V gives I_D ~ 240 uA, so RD = 12k puts the drain near mid-supply.

using Jyce

require_native!()

amp = @circuit "NMOS common-source amplifier" begin
    Model(:NMOS1, :NMOS; level = 1, vto = 0.7, kp = 120e-6, lambda = 0.02)

    VDD = VoltageSource(:vdd, :gnd, DC(5))
    VIN = VoltageSource(:gate, :gnd, DC(0.9), AC(1), Sine(0.9, 0.01, 1e3))

    M1 = MOSFET(:drain, :gate, :gnd, :gnd, :NMOS1; l = 1e-6, w = 100e-6)
    RD = Resistor(:vdd, :drain, 12e3)
    CL = Capacitor(:drain, :gnd, 1e-12)
end

bias = simulate(amp, OperatingPoint(); outputs = [:gate, :drain, branch_current(:VDD)])
println("bias point: V(drain) = ", round(bias[:drain][end]; digits = 3), " V, ",
        "I(VDD) = ", round(bias["I(VDD)"][end] * 1e6; digits = 1), " µA")

gain = simulate(amp, ACSweep(10, 1e8; points = 10); outputs = [vdb(:drain)])
println("midband gain: ", round(maximum(gain["VDB(DRAIN)"]); digits = 2), " dB")

tran = simulate(amp, Transient(2e-6, 4e-3); outputs = [:gate, :drain])
swing = maximum(tran[:drain]) - minimum(tran[:drain])
println("output swing for a 20 mVpp input: ", round(swing * 1e3; digits = 1), " mV")
