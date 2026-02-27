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
RELEASE_DIR="target/$TARGET/release"
BUILD_DIR="$RELEASE_DIR/build"

# Build the static library
cargo build --release --target "$TARGET"

# ---------------------------------------------------------------------------
# Copy ONNX Runtime static library to a stable path for Xcode linking.
#
# Cargo's staticlib bundles Rust code and llama.cpp (compiled by
# llama-cpp-sys's build script). But ONNX Runtime (downloaded by ort-sys)
# is a separate pre-built .a that cargo doesn't merge into our staticlib.
# We copy it to a predictable path so Xcode can link it alongside ours.
# ---------------------------------------------------------------------------
ORT_LIB=$(find "$BUILD_DIR" -name "libonnxruntime.a" -path "*/out/*" 2>/dev/null | head -1)

if [ -n "$ORT_LIB" ]; then
    echo "Copying ONNX Runtime library for Xcode: $ORT_LIB"
    cp "$ORT_LIB" "$RELEASE_DIR/libonnxruntime.a"
else
    echo "warning: libonnxruntime.a not found in build output"
fi
