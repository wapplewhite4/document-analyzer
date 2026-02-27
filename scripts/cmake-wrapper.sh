#!/bin/bash
# Wrapper around cmake that injects -DLLAMA_HTTPLIB=OFF.
#
# llama-cpp-sys-2's build.rs sets LLAMA_CURL=OFF but not LLAMA_HTTPLIB=OFF.
# Without this, llama.cpp's common library compiles with LLAMA_USE_HTTPLIB,
# pulling in cpp-httplib symbols that produce "undefined symbol" linker
# errors when building the final macOS binary.
#
# The cmake-rs crate finds the cmake binary via the CMAKE env var,
# so setting CMAKE=<this script> lets us intercept the invocation.

# Find the real cmake binary (skip ourselves)
REAL_CMAKE=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for dir in /opt/homebrew/bin /usr/local/bin /usr/bin; do
    if [ -x "$dir/cmake" ] && [ "$dir/cmake" != "$SCRIPT_DIR/cmake-wrapper.sh" ]; then
        REAL_CMAKE="$dir/cmake"
        break
    fi
done

if [ -z "$REAL_CMAKE" ]; then
    REAL_CMAKE=$(which -a cmake 2>/dev/null | grep -v "$SCRIPT_DIR" | head -1)
fi

if [ -z "$REAL_CMAKE" ] || [ ! -x "$REAL_CMAKE" ]; then
    echo "error: cmake-wrapper.sh: could not find real cmake binary" >&2
    exit 1
fi

# Only inject -DLLAMA_HTTPLIB=OFF during the configure step.
# The --build step doesn't accept -D flags.
IS_BUILD_STEP=false
for arg in "$@"; do
    if [ "$arg" = "--build" ]; then
        IS_BUILD_STEP=true
        break
    fi
done

if [ "$IS_BUILD_STEP" = true ]; then
    exec "$REAL_CMAKE" "$@"
else
    exec "$REAL_CMAKE" -DLLAMA_HTTPLIB=OFF "$@"
fi
