//! Quick CLI smoke test for the sanctum-core pipeline.
//!
//! Usage (with ML backends):
//!   cargo run --bin sanctum-test --features ml -- /path/to/doc.pdf /path/to/model.gguf
//!
//! Usage (with stub backends, for testing document extraction only):
//!   cargo run --bin sanctum-test -- /path/to/doc.txt dummy_model_path

use std::io::Write;

use sanctum_core::pipeline::DocumentPipeline;

#[cfg(not(feature = "ml"))]
use sanctum_core::embeddings::store::Embedder;
#[cfg(not(feature = "ml"))]
use sanctum_core::inference::engine::{InferenceEngine, PlaceholderBackend};

/// Simple embedder for stub mode testing.
#[cfg(not(feature = "ml"))]
struct TestEmbedder;
#[cfg(not(feature = "ml"))]
impl Embedder for TestEmbedder {
    fn embed_texts(&self, texts: &[&str]) -> anyhow::Result<Vec<Vec<f32>>> {
        Ok(texts
            .iter()
            .map(|t| {
                let mut features = vec![0.0f32; 128];
                for byte in t.bytes() {
                    features[(byte as usize) % 128] += 1.0;
                }
                let norm: f32 = features.iter().map(|x| x * x).sum::<f32>().sqrt();
                if norm > 0.0 {
                    for f in &mut features {
                        *f /= norm;
                    }
                }
                features
            })
            .collect())
    }
}

#[cfg(feature = "ml")]
fn create_pipeline(doc_path: &str, model_path: &str) -> anyhow::Result<DocumentPipeline> {
    use sanctum_core::embeddings::fastembed_backend::FastEmbedBackend;
    use sanctum_core::embeddings::store::Embedder;
    use sanctum_core::inference::engine::InferenceEngine;
    use sanctum_core::inference::llama_backend::LlamaCppBackend;

    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let embed_cache = format!("{}/.local/share/sanctum/embed_cache", home);
    std::fs::create_dir_all(&embed_cache).ok();

    let llama = LlamaCppBackend::load(model_path)?;
    let context_window = llama.context_window_tokens();
    let engine = InferenceEngine::new(Box::new(llama));
    let embedder: Box<dyn Embedder> = Box::new(FastEmbedBackend::new(&embed_cache)?);

    DocumentPipeline::new(doc_path, engine, embedder, context_window)
}

#[cfg(not(feature = "ml"))]
fn create_pipeline(doc_path: &str, _model_path: &str) -> anyhow::Result<DocumentPipeline> {
    let engine = InferenceEngine::new(Box::new(PlaceholderBackend));
    let embedder: Box<dyn Embedder> = Box::new(TestEmbedder);
    DocumentPipeline::new(doc_path, engine, embedder, 128_000)
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: sanctum-test <doc_path> <model_path>");
        eprintln!();
        eprintln!("Examples:");
        eprintln!("  sanctum-test ./sample.pdf ./model.gguf    # With --features ml");
        eprintln!("  sanctum-test ./sample.txt dummy            # With stub backends");
        std::process::exit(1);
    }

    let doc_path = &args[1];
    let model_path = &args[2];

    println!("=== Sanctum Core Pipeline Test ===");
    #[cfg(feature = "ml")]
    println!("Mode: ML backends (llama.cpp + fastembed)");
    #[cfg(not(feature = "ml"))]
    println!("Mode: Stub backends (placeholder inference)");
    println!();

    // Load document
    println!("Loading document: {}", doc_path);
    let pipeline = create_pipeline(doc_path, model_path)?;
    println!("Document loaded successfully.");
    println!(
        "  Text length: {} chars",
        pipeline.document_text().len()
    );
    println!("  Full context mode: {}", pipeline.is_using_full_context());
    println!("  Chunk count: {}", pipeline.chunk_count());
    println!();

    // Test questions
    let test_questions = [
        "What is this document about?",
        "Who are the main parties involved?",
        "What are the key dates mentioned?",
    ];

    for question in &test_questions {
        println!("Q: {}", question);
        print!("A: ");
        std::io::stdout().flush().ok();

        let answer = pipeline.ask(question, |token| {
            print!("{}", token);
            std::io::stdout().flush().ok();
        })?;

        println!();
        println!("   [Full answer: {} chars]", answer.len());
        println!("---");
    }

    println!();
    println!("Test complete.");

    Ok(())
}
