using Jyce

Jyce.print_native_diagnostics()

if !Jyce.native_available()
    println("\nTip: build the CxxWrap module and set JYCE_XYCESOLVER_ROOT or JYCE_XYCESOLVER_JULIA_LIB.")
end
