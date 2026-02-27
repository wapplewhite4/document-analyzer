/// Chunk strategy: fixed size with overlap.
/// For document Q&A, 512 tokens per chunk with 64 token overlap is a solid default.
/// Larger chunks = more context per retrieval hit but lower precision.

pub struct ChunkConfig {
    pub chunk_size: usize, // characters, approximate
    pub overlap: usize,    // characters of overlap between chunks
}

impl Default for ChunkConfig {
    fn default() -> Self {
        Self {
            chunk_size: 1500, // ~400 tokens at avg 3.5 chars/token
            overlap: 200,
        }
    }
}

pub struct Chunk {
    pub id: usize,
    pub text: String,
    pub char_start: usize,
}

pub fn chunk_text(text: &str, config: &ChunkConfig) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let chars: Vec<char> = text.chars().collect();
    let total = chars.len();
    let mut start = 0;
    let mut id = 0;

    while start < total {
        let end = (start + config.chunk_size).min(total);

        // Try to break on sentence boundary within last 200 chars of window
        let break_point = find_sentence_break(&chars, start, end);

        let chunk_text: String = chars[start..break_point].iter().collect();

        if !chunk_text.trim().is_empty() {
            chunks.push(Chunk {
                id,
                text: chunk_text.trim().to_string(),
                char_start: start,
            });
            id += 1;
        }

        // Advance with overlap
        let next_start = break_point.saturating_sub(config.overlap);
        if next_start <= start {
            // Prevent infinite loop: force advance
            start = break_point;
        } else {
            start = next_start;
        }
    }

    chunks
}

fn find_sentence_break(chars: &[char], start: usize, end: usize) -> usize {
    // Look backwards from end for '. ', '.\n', '? ', '! '
    let search_start = end.saturating_sub(200).max(start);
    for i in (search_start..end).rev() {
        if i + 1 < chars.len()
            && (chars[i] == '.' || chars[i] == '?' || chars[i] == '!')
            && (chars[i + 1] == ' ' || chars[i + 1] == '\n')
        {
            return i + 2;
        }
    }
    end // No sentence break found, use hard break
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_empty_text() {
        let chunks = chunk_text("", &ChunkConfig::default());
        assert!(chunks.is_empty());
    }

    #[test]
    fn test_chunk_short_text() {
        let text = "This is a short sentence.";
        let chunks = chunk_text(text, &ChunkConfig::default());
        assert_eq!(chunks.len(), 1);
        assert_eq!(chunks[0].text, text);
    }

    #[test]
    fn test_chunk_long_text_with_sentences() {
        // Create text longer than default chunk_size (1500 chars)
        let sentence = "This is a test sentence. ";
        let text: String = sentence.repeat(100); // ~2500 chars
        let config = ChunkConfig {
            chunk_size: 500,
            overlap: 50,
        };
        let chunks = chunk_text(&text, &config);
        assert!(chunks.len() > 1);
        // All chunks should be non-empty
        for chunk in &chunks {
            assert!(!chunk.text.is_empty());
        }
    }

    #[test]
    fn test_chunk_ids_sequential() {
        let text = "A. B. C. D. E. ".repeat(200);
        let config = ChunkConfig {
            chunk_size: 100,
            overlap: 10,
        };
        let chunks = chunk_text(&text, &config);
        for (i, chunk) in chunks.iter().enumerate() {
            assert_eq!(chunk.id, i);
        }
    }

    #[test]
    fn test_no_infinite_loop() {
        // Edge case: very small chunk size
        let text = "Hello world, this is a test.";
        let config = ChunkConfig {
            chunk_size: 5,
            overlap: 2,
        };
        let chunks = chunk_text(text, &config);
        assert!(!chunks.is_empty());
    }
}
