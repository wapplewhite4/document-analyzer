use anyhow::Result;

use crate::chunker::splitter::{chunk_text, ChunkConfig};
use crate::document::{docx, pdf, text as textdoc};
use crate::embeddings::store::{Embedder, VectorStore};
use crate::inference::engine::{should_use_full_context, InferenceEngine};

pub struct DocumentPipeline {
    full_text: String,
    store: VectorStore,
    engine: InferenceEngine,
    embedder: Box<dyn Embedder>,
    use_full_context: bool,
}

impl DocumentPipeline {
    pub fn new(
        doc_path: &str,
        engine: InferenceEngine,
        embedder: Box<dyn Embedder>,
        context_window_tokens: usize,
    ) -> Result<Self> {
        // Extract text based on file extension
        let full_text = if doc_path.ends_with(".pdf") {
            pdf::extract_pdf(doc_path)?.text
        } else if doc_path.ends_with(".docx") {
            docx::extract_docx(doc_path)?
        } else {
            textdoc::extract_text(doc_path)?
        };

        if full_text.trim().is_empty() {
            anyhow::bail!("Document appears to be empty or contains no extractable text.");
        }

        // For shorter documents, skip RAG and use full context.
        // llama 3.1 8B has 128k context window — most documents fit.
        let use_full_context = should_use_full_context(&full_text, context_window_tokens);

        let mut store = VectorStore::new();

        if !use_full_context {
            // Build vector index for large documents
            let chunks = chunk_text(&full_text, &ChunkConfig::default());
            store.add_chunks(&chunks, embedder.as_ref())?;
        }

        Ok(Self {
            full_text,
            store,
            engine,
            embedder,
            use_full_context,
        })
    }

    /// Create a pipeline from pre-extracted text (e.g. from OCR).
    /// Skips file-based extraction entirely.
    pub fn new_from_text(
        text: String,
        engine: InferenceEngine,
        embedder: Box<dyn Embedder>,
        context_window_tokens: usize,
    ) -> Result<Self> {
        if text.trim().is_empty() {
            anyhow::bail!("Document appears to be empty or contains no extractable text.");
        }

        let use_full_context = should_use_full_context(&text, context_window_tokens);
        let mut store = VectorStore::new();

        if !use_full_context {
            let chunks = chunk_text(&text, &ChunkConfig::default());
            store.add_chunks(&chunks, embedder.as_ref())?;
        }

        Ok(Self {
            full_text: text,
            store,
            engine,
            embedder,
            use_full_context,
        })
    }

    pub fn ask(&self, question: &str, on_token: impl Fn(&str)) -> Result<String> {
        let context_chunks: Vec<&str> = if self.use_full_context {
            // Pass entire document text as single context
            vec![&self.full_text]
        } else {
            // RAG: retrieve top 5 most relevant chunks
            let query_embedding = self.embedder.embed_query(question)?;
            self.store
                .search(&query_embedding, 5)
                .into_iter()
                .map(|e| e.text.as_str())
                .collect()
        };

        self.engine.answer(question, &context_chunks, on_token)
    }

    pub fn document_text(&self) -> &str {
        &self.full_text
    }

    pub fn is_using_full_context(&self) -> bool {
        self.use_full_context
    }

    pub fn chunk_count(&self) -> usize {
        self.store.len()
    }
}
