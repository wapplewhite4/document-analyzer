.PHONY: all build-rust build-swift clean

RUST_TARGET = aarch64-apple-darwin
RUST_LIB = sanctum-core/target/$(RUST_TARGET)/release/libsanctum_core.a
HEADER = sanctum-bridge/sanctum_core.h

all: build-rust build-swift

build-rust:
	cd sanctum-core && \
	cargo build --release --target $(RUST_TARGET)
	cd sanctum-core && \
	cbindgen --config cbindgen.toml --crate sanctum-core \
	         --output ../$(HEADER)

build-rust-universal:
	cd sanctum-core && \
	cargo build --release --target aarch64-apple-darwin && \
	cargo build --release --target x86_64-apple-darwin
	lipo -create \
	  sanctum-core/target/aarch64-apple-darwin/release/libsanctum_core.a \
	  sanctum-core/target/x86_64-apple-darwin/release/libsanctum_core.a \
	  -output sanctum-bridge/libsanctum_core_universal.a

clean:
	cd sanctum-core && cargo clean
	rm -f $(HEADER)
