//! Sanctum Core — Rust library for local document analysis.
//!
//! Provides document extraction, text chunking, vector embeddings,
//! and LLM inference orchestration via a C-compatible FFI layer
//! for consumption by the Swift/SwiftUI macOS frontend.
//!
//! # Feature Flags
//! - `llm` — Enables LLM inference via llama.cpp. Requires cmake + C++ compiler.
//! - `ml` — Enables `llm` + neural embeddings (fastembed/ONNX Runtime).
//! - `stub` — Uses placeholder backends for testing without ML dependencies.

pub mod chunker;
pub mod document;
pub mod embeddings;
pub mod inference;
pub mod pipeline;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

use crate::embeddings::store::Embedder;
use crate::inference::engine::InferenceEngine;
use crate::pipeline::DocumentPipeline;

#[cfg(not(feature = "llm"))]
use crate::inference::engine::PlaceholderBackend;

// ---------------------------------------------------------------------------
// Global pipeline instance (one active document at a time for MVP)
// ---------------------------------------------------------------------------

static PIPELINE: Mutex<Option<DocumentPipeline>> = Mutex::new(None);

// ---------------------------------------------------------------------------
// Backend construction (feature-gated)
// ---------------------------------------------------------------------------

/// Create a pipeline using llama.cpp + fastembed (full ML).
#[cfg(feature = "ml")]
fn create_pipeline(doc_path: &str, model_path: &str) -> anyhow::Result<DocumentPipeline> {
    use crate::embeddings::fastembed_backend::FastEmbedBackend;
    use crate::inference::llama_backend::LlamaCppBackend;

    let app_support = get_app_support_dir();
    let embed_cache = format!("{}/embed_cache", app_support);

    std::fs::create_dir_all(&embed_cache).ok();

    let llama = LlamaCppBackend::load(model_path)?;
    let context_window = llama.context_window_tokens();

    let engine = InferenceEngine::new(Box::new(llama));
    let embedder: Box<dyn Embedder> = Box::new(FastEmbedBackend::new(&embed_cache)?);

    DocumentPipeline::new(doc_path, engine, embedder, context_window)
}

/// Create a pipeline using llama.cpp + simple embedder (no ONNX Runtime).
#[cfg(all(feature = "llm", not(feature = "ml")))]
fn create_pipeline(doc_path: &str, model_path: &str) -> anyhow::Result<DocumentPipeline> {
    use crate::inference::llama_backend::LlamaCppBackend;

    let llama = LlamaCppBackend::load(model_path)?;
    let context_window = llama.context_window_tokens();

    let engine = InferenceEngine::new(Box::new(llama));
    let embedder: Box<dyn Embedder> = Box::new(SimpleEmbedder);

    DocumentPipeline::new(doc_path, engine, embedder, context_window)
}

/// Create a pipeline using placeholder backends (no ML dependencies).
#[cfg(not(feature = "llm"))]
fn create_pipeline(doc_path: &str, _model_path: &str) -> anyhow::Result<DocumentPipeline> {
    let engine = InferenceEngine::new(Box::new(PlaceholderBackend));
    let embedder: Box<dyn Embedder> = Box::new(SimpleEmbedder);

    // Stub uses same conservative context as the real backend
    DocumentPipeline::new(doc_path, engine, embedder, 2048)
}

/// Get the application support directory path.
fn get_app_support_dir() -> String {
    if cfg!(target_os = "macos") {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        format!("{}/Library/Application Support/Sanctum", home)
    } else {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        format!("{}/.local/share/sanctum", home)
    }
}

// ---------------------------------------------------------------------------
// Simple embedder — used when fastembed/ONNX Runtime is not available.
// Uses character-frequency features. Works well enough for short documents
// where full-context mode skips RAG anyway.
// ---------------------------------------------------------------------------

#[cfg(not(feature = "ml"))]
struct SimpleEmbedder;

#[cfg(not(feature = "ml"))]
impl Embedder for SimpleEmbedder {
    fn embed_texts(&self, texts: &[&str]) -> anyhow::Result<Vec<Vec<f32>>> {
        Ok(texts.iter().map(|t| simple_embed(t)).collect())
    }
}

#[cfg(not(feature = "ml"))]
fn simple_embed(text: &str) -> Vec<f32> {
    let mut features = vec![0.0f32; 128];
    for byte in text.bytes() {
        features[(byte as usize) % 128] += 1.0;
    }
    let norm: f32 = features.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm > 0.0 {
        for f in &mut features {
            *f /= norm;
        }
    }
    features
}

// ---------------------------------------------------------------------------
// FFI exports — C-compatible API for Swift to call into.
//
// All strings passed as null-terminated C strings.
// Caller responsible for freeing returned strings via sanctum_free_string.
// ---------------------------------------------------------------------------

/// Load and index a document. Returns 0 on success, -1 on error.
///
/// # Safety
/// `path` and `model_path` must be valid, null-terminated C strings.
#[no_mangle]
pub unsafe extern "C" fn sanctum_load_document(
    path: *const c_char,
    model_path: *const c_char,
) -> i32 {
    if path.is_null() || model_path.is_null() {
        eprintln!("sanctum_load_document: null pointer argument");
        return -1;
    }

    let path = unsafe { CStr::from_ptr(path).to_string_lossy().into_owned() };
    let model_path = unsafe { CStr::from_ptr(model_path).to_string_lossy().into_owned() };

    // Validate paths before expensive model loading
    if !std::path::Path::new(&path).exists() {
        eprintln!("sanctum_load_document: document not found: {}", path);
        return -1;
    }
    if !std::path::Path::new(&model_path).exists() {
        eprintln!("sanctum_load_document: model not found: {}", model_path);
        return -1;
    }

    eprintln!("sanctum_load_document: loading doc={} model={}", path, model_path);

    match create_pipeline(&path, &model_path) {
        Ok(pipeline) => {
            eprintln!("sanctum_load_document: pipeline created successfully");
            *PIPELINE.lock().unwrap() = Some(pipeline);
            0
        }
        Err(e) => {
            eprintln!("sanctum_load_document: failed: {}", e);
            -1
        }
    }
}

/// Ask a question about the loaded document.
/// Returns a JSON string: `{"answer": "...", "error": null}`
///
/// Caller must free the returned pointer with `sanctum_free_string`.
///
/// # Safety
/// `question` must be a valid, null-terminated C string.
/// `callback` may be null (no streaming) or a valid function pointer.
#[no_mangle]
pub unsafe extern "C" fn sanctum_ask(
    question: *const c_char,
    callback: Option<unsafe extern "C" fn(*const c_char)>,
) -> *mut c_char {
    if question.is_null() {
        return error_json("Null question pointer");
    }

    let question = unsafe { CStr::from_ptr(question).to_string_lossy().into_owned() };

    let result = PIPELINE.lock().unwrap();
    let result = result.as_ref().map(|p| {
        p.ask(&question, |token| {
            if let Some(cb) = callback {
                if let Ok(s) = CString::new(token) {
                    unsafe { cb(s.as_ptr()) };
                }
            }
        })
    });

    let json = match result {
        Some(Ok(answer)) => {
            let escaped_answer = answer
                .replace('\\', "\\\\")
                .replace('"', "\\\"")
                .replace('\n', "\\n");
            format!(r#"{{"answer":"{}","error":null}}"#, escaped_answer)
        }
        Some(Err(e)) => {
            let escaped_error = e.to_string().replace('\\', "\\\\").replace('"', "\\\"");
            format!(r#"{{"answer":null,"error":"{}"}}"#, escaped_error)
        }
        None => r#"{"answer":null,"error":"No document loaded"}"#.to_string(),
    };

    CString::new(json).unwrap().into_raw()
}

/// Free a string returned by sanctum functions.
///
/// # Safety
/// `ptr` must be a pointer previously returned by a sanctum_* function,
/// or null (in which case this is a no-op).
#[no_mangle]
pub unsafe extern "C" fn sanctum_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            drop(CString::from_raw(ptr));
        }
    }
}

/// Check if a document is currently loaded. Returns 1 if yes, 0 if no.
#[no_mangle]
pub extern "C" fn sanctum_has_document() -> i32 {
    if PIPELINE.lock().unwrap().is_some() {
        1
    } else {
        0
    }
}

/// Clear the current document from memory.
/// Call this when a document is closed or the app is backgrounded
/// to free RAM used by the loaded model and vector store.
#[no_mangle]
pub extern "C" fn sanctum_clear_document() {
    *PIPELINE.lock().unwrap() = None;
}

/// Get information about the loaded document as a JSON string.
/// Returns `{"loaded": true, "char_count": N, "chunk_count": N, "full_context": bool}`
/// or `{"loaded": false}` if no document is loaded.
///
/// Caller must free the returned pointer with `sanctum_free_string`.
#[no_mangle]
pub extern "C" fn sanctum_document_info() -> *mut c_char {
    let pipeline = PIPELINE.lock().unwrap();
    let json = match pipeline.as_ref() {
        Some(p) => format!(
            r#"{{"loaded":true,"char_count":{},"chunk_count":{},"full_context":{}}}"#,
            p.document_text().len(),
            p.chunk_count(),
            p.is_using_full_context(),
        ),
        None => r#"{"loaded":false}"#.to_string(),
    };

    CString::new(json).unwrap().into_raw()
}

/// Check if the embedding model is cached and ready.
/// Returns 1 if the model is ready, 0 if it needs to be downloaded.
///
/// On first document load, fastembed downloads nomic-embed-text (~137MB).
/// Swift should check this and show a progress indicator if needed.
#[no_mangle]
pub extern "C" fn sanctum_is_embed_model_ready() -> i32 {
    let app_support = get_app_support_dir();
    let model_dir = std::path::Path::new(&app_support)
        .join("embed_cache")
        .join("Nomic-nomic-embed-text-v1.5");

    if model_dir.exists() && model_dir.is_dir() {
        1
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn error_json(msg: &str) -> *mut c_char {
    let escaped = msg.replace('\\', "\\\\").replace('"', "\\\"");
    let json = format!(r#"{{"answer":null,"error":"{}"}}"#, escaped);
    CString::new(json).unwrap().into_raw()
}
