//! LLM inference backend using llama-cpp-2 bindings.
//!
//! Requires the `ml` feature flag and a C++ compiler + cmake.
//! On macOS with Apple Silicon, Metal GPU acceleration is used automatically.

#[cfg(feature = "llm")]
use anyhow::Result;

#[cfg(feature = "llm")]
use llama_cpp_2::{
    context::{params::LlamaContextParams, LlamaContext},
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, AddBos, LlamaModel},
    sampling::LlamaSampler,
};

#[cfg(feature = "llm")]
use std::num::NonZeroU32;
#[cfg(feature = "llm")]
use std::sync::Mutex;

#[cfg(feature = "llm")]
use crate::inference::engine::InferenceBackend;

#[cfg(feature = "llm")]
pub struct LlamaCppBackend {
    model: LlamaModel,
    backend: LlamaBackend,
    context: Mutex<Option<LlamaContext<'static>>>,
    context_size: u32,
}

// Safety: LlamaModel and LlamaBackend are thread-safe for read access.
// The mutable LlamaContext is protected by a Mutex.
#[cfg(feature = "llm")]
unsafe impl Send for LlamaCppBackend {}
#[cfg(feature = "llm")]
unsafe impl Sync for LlamaCppBackend {}

#[cfg(feature = "llm")]
impl LlamaCppBackend {
    /// Load a GGUF model from disk.
    ///
    /// `model_path` should point to a .gguf file (e.g. Q4_K_M quantized).
    /// On Apple Silicon, all layers are offloaded to Metal GPU automatically.
    pub fn load(model_path: &str) -> Result<Self> {
        let backend = LlamaBackend::init()?;

        // On Apple Silicon the GPU shares system RAM, so offloading all
        // layers to Metal improves speed without extra memory cost.
        let model_params = LlamaModelParams::default()
            .with_n_gpu_layers(1000);

        let model = LlamaModel::load_from_file(&backend, model_path, &model_params)?;

        // Keep context size conservative to avoid OOM on 8 GB Macs.
        // KV-cache cost is roughly 128–256 KB per token depending on model.
        // 2048 tokens ≈ 256–512 MB KV-cache, safe alongside a 4.7–8.4 GB model.
        let context_size: u32 = 2048;

        let this = Self {
            model,
            backend,
            context: Mutex::new(None),
            context_size,
        };

        // Create the context eagerly so Metal init happens once at load time
        this.ensure_context()?;

        Ok(this)
    }

    /// Set the context window size (in tokens).
    /// Must be called before the first generate() call, or call ensure_context() after.
    pub fn with_context_size(mut self, size: u32) -> Self {
        self.context_size = size;
        // Invalidate existing context so it gets recreated with new size
        *self.context.lock().unwrap() = None;
        self
    }

    pub fn context_window_tokens(&self) -> usize {
        self.context_size as usize
    }

    /// Create the LlamaContext if it doesn't exist yet.
    /// This is where the expensive Metal pipeline compilation happens.
    fn ensure_context(&self) -> Result<()> {
        let mut ctx_guard = self.context.lock().unwrap();
        if ctx_guard.is_none() {
            let ctx_params = LlamaContextParams::default()
                .with_n_ctx(NonZeroU32::new(self.context_size));

            // Safety: We store model and backend in the same struct, so the
            // context's lifetime references are valid for as long as Self lives.
            // The Mutex ensures exclusive access to the context.
            let ctx = unsafe {
                std::mem::transmute::<LlamaContext<'_>, LlamaContext<'static>>(
                    self.model.new_context(&self.backend, ctx_params)?
                )
            };
            *ctx_guard = Some(ctx);
        }
        Ok(())
    }
}

#[cfg(feature = "llm")]
impl InferenceBackend for LlamaCppBackend {
    fn generate(
        &self,
        prompt: &str,
        on_token: &dyn Fn(&str),
    ) -> Result<String> {
        let n_batch: usize = 512;

        self.ensure_context()?;
        let mut ctx_guard = self.context.lock().unwrap();
        let ctx = ctx_guard.as_mut().unwrap();

        // Clear KV cache from previous generation
        ctx.clear_kv_cache();

        // Tokenize prompt
        let tokens_list = self.model.str_to_token(prompt, AddBos::Never)?;
        let n_prompt = tokens_list.len();

        if n_prompt == 0 {
            anyhow::bail!("Prompt tokenized to zero tokens");
        }

        // Feed prompt tokens in chunks of n_batch to avoid exceeding the
        // batch size limit. Only the last token in the final chunk needs
        // logits (is_last = true) for sampling.
        let mut batch = LlamaBatch::new(n_batch, 1);
        let mut n_processed: usize = 0;

        while n_processed < n_prompt {
            batch.clear();
            let chunk_end = (n_processed + n_batch).min(n_prompt);

            for i in n_processed..chunk_end {
                let is_last = i == n_prompt - 1;
                batch.add(tokens_list[i], i as i32, &[0], is_last)?;
            }

            ctx.decode(&mut batch)?;
            n_processed = chunk_end;
        }

        // Set up sampler: low temperature for factual document Q&A
        let mut sampler = LlamaSampler::chain_simple([
            LlamaSampler::top_p(0.9, 1),
            LlamaSampler::temp(0.1),
            LlamaSampler::dist(42),
        ]);

        // Generate tokens
        let mut full_response = String::new();
        let mut n_cur = n_prompt as i32;
        let max_total: i32 = n_cur + 1024; // up to 1024 new tokens
        let mut decoder = encoding_rs::UTF_8.new_decoder();

        while n_cur < max_total {
            // Sample the next token
            let new_token = sampler.sample(ctx, batch.n_tokens() - 1);
            sampler.accept(new_token);

            // Check for end of generation
            if self.model.is_eog_token(new_token) {
                break;
            }

            // Decode token to string and stream
            let token_str = self.model.token_to_piece(new_token, &mut decoder, true, None)?;

            // Stop on end-of-turn markers before appending to response
            if full_response.len() + token_str.len() > 0 {
                let combined = format!("{}{}", full_response, token_str);
                if combined.contains("<|eot_id|>")
                    || combined.contains("<|end_of_text|>")
                    || combined.ends_with("</s>")
                {
                    break;
                }
            }

            on_token(&token_str);
            full_response.push_str(&token_str);

            // Prepare next batch (single token)
            batch.clear();
            batch.add(new_token, n_cur, &[0], true)?;
            ctx.decode(&mut batch)?;

            n_cur += 1;
        }

        Ok(full_response.trim().to_string())
    }
}
