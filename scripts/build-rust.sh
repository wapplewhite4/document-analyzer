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
# Find and stage the ONNX Runtime library for Xcode.
#
# ort-sys downloads a pre-built ONNX Runtime (usually a .dylib on macOS).
# Cargo doesn't bundle dynamic libraries into our staticlib, so Xcode
# needs to link and embed it separately.
# ---------------------------------------------------------------------------
echo "Searching for ONNX Runtime library in build output..."
find "$BUILD_DIR" -name "*onnxruntime*" \( -name "*.a" -o -name "*.dylib" \) 2>/dev/null | while read f; do
    echo "  Found: $f"
done

# Prefer static, fall back to dynamic
ORT_LIB=$(find "$BUILD_DIR" -name "libonnxruntime.a" -path "*/out/*" 2>/dev/null | head -1)
if [ -z "$ORT_LIB" ]; then
    ORT_LIB=$(find "$BUILD_DIR" -name "libonnxruntime.dylib" -path "*/out/*" 2>/dev/null | head -1)
fi
if [ -z "$ORT_LIB" ]; then
    # Broadest search: any onnxruntime library
    ORT_LIB=$(find "$BUILD_DIR" -name "*onnxruntime*" \( -name "*.a" -o -name "*.dylib" \) 2>/dev/null | head -1)
fi

if [ -n "$ORT_LIB" ]; then
    BASENAME=$(basename "$ORT_LIB")
    echo "Staging ONNX Runtime library: $ORT_LIB -> $RELEASE_DIR/$BASENAME"
    cp "$ORT_LIB" "$RELEASE_DIR/$BASENAME"

    # Fix install name so the app finds it at @rpath
    if [[ "$BASENAME" == *.dylib ]]; then
        install_name_tool -id "@rpath/$BASENAME" "$RELEASE_DIR/$BASENAME" 2>/dev/null || true
    fi
else
    echo "warning: No ONNX Runtime library found in build output."
    echo "  The build may fail with undefined httplib/onnxruntime symbols."
    echo "  Build dir searched: $BUILD_DIR"
fi
