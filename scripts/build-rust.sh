#!/bin/bash
# Build sanctum-core Rust library for linking into the Xcode project.
# Called automatically by Xcode's "Build Rust Library" run script phase.

set -euo pipefail

cd "$PROJECT_DIR/../sanctum-core"

# Ensure cargo and Homebrew tools are on PATH
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Check prerequisites
if ! command -v cargo &> /dev/null; then
    echo "error: Rust toolchain not found. Install via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

if ! command -v cmake &> /dev/null; then
    echo "error: cmake is required to build llama.cpp. Install via: brew install cmake"
    exit 1
fi

TARGET="aarch64-apple-darwin"

# Build the static library
cargo build --release --target "$TARGET"

# ---------------------------------------------------------------------------
# Merge native C/C++ static libraries into libsanctum_core.a
#
# Cargo's "staticlib" crate-type bundles all *Rust* code into one .a, but
# native C/C++ libraries produced by build scripts (ort-sys → ONNX Runtime,
# llama-cpp-sys → llama.cpp) are left as separate .a files in the build dir.
# Xcode only links libsanctum_core.a, so we merge everything into it.
# ---------------------------------------------------------------------------
SANCTUM_LIB="target/$TARGET/release/libsanctum_core.a"
BUILD_DIR="target/$TARGET/release/build"

# Collect all native .a files produced by build scripts (in their out/ dirs)
NATIVE_LIBS=$(find "$BUILD_DIR" -name "*.a" -path "*/out/*" 2>/dev/null || true)

if [ -n "$NATIVE_LIBS" ]; then
    echo "Merging native static libraries into libsanctum_core.a:"
    echo "$NATIVE_LIBS" | sed 's/^/  /'
    libtool -static -o "${SANCTUM_LIB}.merged" "$SANCTUM_LIB" $NATIVE_LIBS
    mv "${SANCTUM_LIB}.merged" "$SANCTUM_LIB"
    echo "Merge complete."
fi
