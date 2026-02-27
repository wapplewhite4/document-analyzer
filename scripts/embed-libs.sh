#!/bin/bash
# Embed ONNX Runtime dynamic library into the app bundle.
# Called as a post-build Xcode run script phase.

set -euo pipefail

RUST_RELEASE="$PROJECT_DIR/../sanctum-core/target/aarch64-apple-darwin/release"
FRAMEWORKS_DIR="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app/Contents/Frameworks"

# Copy ONNX Runtime dylib into app bundle if it exists
ORT_DYLIB="$RUST_RELEASE/libonnxruntime.dylib"
if [ -f "$ORT_DYLIB" ]; then
    mkdir -p "$FRAMEWORKS_DIR"
    cp "$ORT_DYLIB" "$FRAMEWORKS_DIR/"
    # Re-sign with the app's identity
    if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
        codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$FRAMEWORKS_DIR/libonnxruntime.dylib"
    fi
    echo "Embedded libonnxruntime.dylib in app bundle."
fi
