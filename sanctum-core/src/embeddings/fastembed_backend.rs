//! Text embedding backend using fastembed (ONNX-based).
//!
//! Requires the `ml` feature flag. The ONNX runtime binary is bundled
//! automatically by the fastembed crate.
//!
//! Uses nomic-embed-text-v1.5 (137MB) — excellent quality/size tradeoff
//! for local document analysis. Downloaded on first use to cache_dir.

#[cfg(feature = "ml")]
use anyhow::Result;

#[cfg(feature = "ml")]
use fastembed::{EmbeddingModel, InitOptions, TextEmbedding};

#[cfg(feature = "ml")]
use crate::embeddings::store::Embedder;

#[cfg(feature = "ml")]
pub struct FastEmbedBackend {
    model: TextEmbedding,
}

#[cfg(feature = "ml")]
impl FastEmbedBackend {
    /// Create a new FastEmbed backend.
    ///
    /// `cache_dir` is where the ONNX model files are downloaded and cached.
    /// On macOS this should be inside Application Support/Sanctum/embed_cache/.
    pub fn new(cache_dir: &str) -> Result<Self> {
        let model = TextEmbedding::try_new(
            InitOptions::new(EmbeddingModel::NomicEmbedTextV15)
                .with_cache_dir(cache_dir.into())
                .with_show_download_progress(false), // Progress handled by Swift UI
        )?;

        Ok(Self { model })
    }
}

#[cfg(feature = "ml")]
impl Embedder for FastEmbedBackend {
    fn embed_texts(&self, texts: &[&str]) -> Result<Vec<Vec<f32>>> {
        let texts: Vec<String> = texts.iter().map(|s| s.to_string()).collect();
        Ok(self.model.embed(texts, None)?)
    }
}
