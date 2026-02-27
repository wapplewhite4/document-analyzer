/// Minimal Swift CLI to validate FFI bridging before building the full app.
///
/// Build and run this as a standalone command-line tool target in Xcode
/// to verify that the Rust library links correctly and all FFI functions work.
///
/// Usage: SanctumFFITest <doc_path> <model_path>

import Foundation

guard CommandLine.arguments.count >= 3 else {
    print("Usage: SanctumFFITest <doc_path> <model_path>")
    exit(1)
}

let docPath = CommandLine.arguments[1]
let modelPath = CommandLine.arguments[2]

print("=== Sanctum FFI Validation ===")
print()

// Test 1: Check initial state
let hasDocBefore = sanctum_has_document()
print("Has document (before load): \(hasDocBefore == 1 ? "yes" : "no")")
assert(hasDocBefore == 0, "Should not have a document loaded initially")

// Test 2: Load document
print("Loading document via FFI: \(docPath)")
let loadResult = sanctum_load_document(docPath, modelPath)
guard loadResult == 0 else {
    print("FAIL: Load returned \(loadResult)")
    exit(1)
}
print("OK: Document loaded")

// Test 3: Verify document state
let hasDocAfter = sanctum_has_document()
assert(hasDocAfter == 1, "Document should be loaded")
print("OK: sanctum_has_document() = 1")

// Test 4: Get document info
if let infoPtr = sanctum_document_info() {
    let info = String(cString: infoPtr)
    print("OK: Document info: \(info)")
    sanctum_free_string(infoPtr)
}

// Test 5: Ask a question with streaming
print()
print("Asking question with streaming...")
let question = "What is this document about?"

let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { ptr in
    guard let ptr else { return }
    print(String(cString: ptr), terminator: "")
}

if let resultPtr = sanctum_ask(question, callback) {
    print() // newline after streamed tokens
    let json = String(cString: resultPtr)
    print("OK: JSON result: \(json)")
    sanctum_free_string(resultPtr)
}

// Test 6: Clear document
sanctum_clear_document()
let hasDocCleared = sanctum_has_document()
assert(hasDocCleared == 0, "Document should be cleared")
print("OK: Document cleared")

// Test 7: Embedding model readiness
let embedReady = sanctum_is_embed_model_ready()
print("Embed model ready: \(embedReady == 1 ? "yes" : "no")")

print()
print("=== All FFI tests passed ===")
