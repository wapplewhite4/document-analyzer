use anyhow::Result;

pub struct VectorStore {
    entries: Vec<VectorEntry>,
}

pub struct VectorEntry {
    pub chunk_id: usize,
    pub text: String,
    pub embedding: Vec<f32>,
}

/// Trait for embedding text into vectors. Allows swapping embedding backends.
pub trait Embedder: Send + Sync {
    fn embed_texts(&self, texts: &[&str]) -> Result<Vec<Vec<f32>>>;

    fn embed_query(&self, query: &str) -> Result<Vec<f32>> {
        let embeddings = self.embed_texts(&[query])?;
        embeddings
            .into_iter()
            .next()
            .ok_or_else(|| anyhow::anyhow!("No embedding returned for query"))
    }
}

impl VectorStore {
    pub fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    pub fn add_chunks(
        &mut self,
        chunks: &[crate::chunker::splitter::Chunk],
        embedder: &dyn Embedder,
    ) -> Result<()> {
        let texts: Vec<&str> = chunks.iter().map(|c| c.text.as_str()).collect();
        let embeddings = embedder.embed_texts(&texts)?;

        for (chunk, embedding) in chunks.iter().zip(embeddings.into_iter()) {
            self.entries.push(VectorEntry {
                chunk_id: chunk.id,
                text: chunk.text.clone(),
                embedding,
            });
        }
        Ok(())
    }

    pub fn search(&self, query_embedding: &[f32], top_k: usize) -> Vec<&VectorEntry> {
        let mut scored: Vec<(f32, &VectorEntry)> = self
            .entries
            .iter()
            .map(|e| (cosine_similarity(query_embedding, &e.embedding), e))
            .collect();

        scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        scored.into_iter().take(top_k).map(|(_, e)| e).collect()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let dot: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f32 = a.iter().map(|x| x * x).sum::<f32>().sqrt();
    let norm_b: f32 = b.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm_a == 0.0 || norm_b == 0.0 {
        0.0
    } else {
        dot / (norm_a * norm_b)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity_identical() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![1.0, 0.0, 0.0];
        let sim = cosine_similarity(&a, &b);
        assert!((sim - 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_orthogonal() {
        let a = vec![1.0, 0.0, 0.0];
        let b = vec![0.0, 1.0, 0.0];
        let sim = cosine_similarity(&a, &b);
        assert!(sim.abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_opposite() {
        let a = vec![1.0, 0.0];
        let b = vec![-1.0, 0.0];
        let sim = cosine_similarity(&a, &b);
        assert!((sim + 1.0).abs() < 1e-6);
    }

    #[test]
    fn test_cosine_similarity_zero_vector() {
        let a = vec![0.0, 0.0, 0.0];
        let b = vec![1.0, 2.0, 3.0];
        let sim = cosine_similarity(&a, &b);
        assert_eq!(sim, 0.0);
    }

    #[test]
    fn test_vector_store_search() {
        use crate::chunker::splitter::Chunk;

        struct MockEmbedder;
        impl Embedder for MockEmbedder {
            fn embed_texts(&self, texts: &[&str]) -> Result<Vec<Vec<f32>>> {
                // Simple mock: use text length as a feature
                Ok(texts
                    .iter()
                    .map(|t| vec![t.len() as f32, 1.0, 0.0])
                    .collect())
            }
        }

        let chunks = vec![
            Chunk {
                id: 0,
                text: "short".to_string(),
                char_start: 0,
            },
            Chunk {
                id: 1,
                text: "a much longer piece of text".to_string(),
                char_start: 10,
            },
            Chunk {
                id: 2,
                text: "medium text here".to_string(),
                char_start: 50,
            },
        ];

        let mut store = VectorStore::new();
        store.add_chunks(&chunks, &MockEmbedder).unwrap();
        assert_eq!(store.len(), 3);

        // Search for something similar to "medium text here" (length 16)
        let query_emb = vec![16.0, 1.0, 0.0];
        let results = store.search(&query_emb, 2);
        assert_eq!(results.len(), 2);
        // First result should be the one most similar
        assert_eq!(results[0].text, "medium text here");
    }
}
