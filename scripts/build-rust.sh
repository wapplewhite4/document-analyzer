#!/bin/bash
# Build sanctum-core Rust library for linking into the Xcode project.
# Called automatically by Xcode's "Build Rust Library" run script phase.

set -euo pipefail

cd "$PROJECT_DIR/../sanctum-core"

# Ensure cargo is on PATH (rustup default install location)
export PATH="$HOME/.cargo/bin:$PATH"

# Build release static library for Apple Silicon
cargo build --release --target aarch64-apple-darwin
