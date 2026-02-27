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

# Build release static library for Apple Silicon.
# Default feature "llm" enables llama.cpp inference.
# Add --features ml to also enable neural embeddings (requires ONNX Runtime).
cargo build --release --target aarch64-apple-darwin
