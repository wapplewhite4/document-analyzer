import Foundation

/// Swift types mirroring the C FFI structs and JSON responses from sanctum-core.
///
/// The Rust core communicates via JSON strings over FFI. These types
/// provide Swift-native parsing of those responses.

/// Response from sanctum_ask().
struct AskResponse: Decodable {
    let answer: String?
    let error: String?
}

/// Response from sanctum_document_info().
struct DocumentInfo: Decodable {
    let loaded: Bool
    let charCount: Int?
    let chunkCount: Int?
    let fullContext: Bool?

    enum CodingKeys: String, CodingKey {
        case loaded
        case charCount = "char_count"
        case chunkCount = "chunk_count"
        case fullContext = "full_context"
    }
}

/// Parse a JSON string returned from a sanctum FFI function.
func parseSanctumJSON<T: Decodable>(_ cString: UnsafeMutablePointer<CChar>) -> T? {
    defer { sanctum_free_string(cString) }
    let jsonStr = String(cString: cString)
    guard let data = jsonStr.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}
