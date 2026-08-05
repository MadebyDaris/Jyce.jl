#!/bin/bash
set -e

echo "=== Jyce & XyceSolver Automated Installer ==="

# 1. Locate workspace directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XYCESOLVER_DIR="${XYCESOLVER_DIR:-$SCRIPT_DIR/../XyceSolver}"
JYCE_DIR="${JYCE_DIR:-$SCRIPT_DIR}"

if [ ! -d "$XYCESOLVER_DIR" ] || [ ! -d "$JYCE_DIR" ]; then
    echo "Error: Could not find XyceSolver and Jyce directories."
    echo "Please place this script in your workspace root containing both folders."
    exit 1
fi

# 2. Configure Xyce and Trilinos paths (adjust if installed elsewhere)
XYCE_ROOT="${XYCE_ROOT:-$HOME/XyceInstall/Serial}"
TRILINOS_ROOT="${TRILINOS_ROOT:-$HOME/XyceLibs/Serial}"

if [ ! -d "$XYCE_ROOT" ]; then
    echo "Warning: Xyce install not found at $XYCE_ROOT."
    echo "Ensure Xyce is built, or export XYCE_ROOT and TRILINOS_ROOT before running."
fi

echo "Using Xyce root: $XYCE_ROOT"
echo "Using Trilinos root: $TRILINOS_ROOT"

# 3. Detect Julia CxxWrap.jl prefix path automatically
echo "Detecting Julia CxxWrap.jl prefix..."
CXXWRAP_PREFIX=$(julia --project="$JYCE_DIR" -e 'using CxxWrap; print(CxxWrap.prefix_path())' 2>/dev/null || julia -e 'using CxxWrap; print(CxxWrap.prefix_path())')

if [ -z "$CXXWRAP_PREFIX" ]; then
    echo "Error: CxxWrap.jl is not installed in Julia."
    echo "Please run: julia -e 'using Pkg; Pkg.add(\"CxxWrap\")'"
    exit 1
fi
echo "Found CxxWrap prefix: $CXXWRAP_PREFIX"

# 4. Build XyceSolver CxxWrap module via CMake
echo "Building XyceSolver CxxWrap module..."
cd "$XYCESOLVER_DIR"
mkdir -p build && cd build

cmake .. \
    -DBUILD_CXXWRAP_MODULE=ON \
    -DXYCE_ROOT="$XYCE_ROOT" \
    -DTRILINOS_ROOT="$TRILINOS_ROOT" \
    -DCMAKE_PREFIX_PATH="$CXXWRAP_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release

make -j$(nproc)

# 5. Populate Jyce/lib for seamless zero-config loading
echo "Linking compiled native module to Jyce..."
mkdir -p "$JYCE_DIR/lib"

# Find the compiled extension (.so on Linux, .dylib on macOS)
EXT_FILE=$(find . -maxdepth 2 \( -name "xycesolver_julia.so" -o -name "xycesolver_julia.dylib" -o -name "xycesolver_julia.dll" \) | head -n 1)

if [ -n "$EXT_FILE" ]; then
    cp "$EXT_FILE" "$JYCE_DIR/lib/"
    echo "Successfully copied $(basename "$EXT_FILE") to $JYCE_DIR/lib/"
else
    echo "Error: xycesolver_julia native library binary not found in build directory!"
    exit 1
fi

# 6. Initialize Julia package environment & run local tests
echo "Instantiating Jyce Julia package environment..."
cd "$JYCE_DIR"
julia --project -e 'using Pkg; Pkg.instantiate()'

echo "=== Installation Complete! ==="
echo "Run the native smoke test to verify everything works:"
echo "cd $JYCE_DIR && julia --project scripts/smoke_native.jl"