//! LLM inference backend using llama-cpp-2 bindings.
//!
//! Requires the `ml` feature flag and a C++ compiler + cmake.
//! On macOS with Apple Silicon, Metal GPU acceleration is used automatically.

#[cfg(feature = "ml")]
use anyhow::Result;

#[cfg(feature = "ml")]
use llama_cpp_2::{
    context::params::LlamaContextParams,
    llama_backend::LlamaBackend,
    llama_batch::LlamaBatch,
    model::{params::LlamaModelParams, AddBos, LlamaModel},
    sampling::LlamaSampler,
};

#[cfg(feature = "ml")]
use std::num::NonZeroU32;

#[cfg(feature = "ml")]
use crate::inference::engine::InferenceBackend;

#[cfg(feature = "ml")]
pub struct LlamaCppBackend {
    model: LlamaModel,
    backend: LlamaBackend,
    context_size: u32,
}

#[cfg(feature = "ml")]
impl LlamaCppBackend {
    /// Load a GGUF model from disk.
    ///
    /// `model_path` should point to a .gguf file (e.g. Q4_K_M quantized).
    /// On Apple Silicon, all layers are offloaded to Metal GPU automatically.
    pub fn load(model_path: &str) -> Result<Self> {
        let backend = LlamaBackend::init()?;

        let model_params = LlamaModelParams::default()
            .with_n_gpu_layers(1000); // Offload all layers to GPU

        let model = LlamaModel::load_from_file(&backend, model_path, &model_params)?;

        Ok(Self {
            model,
            backend,
            context_size: 8192, // Conservative default; increase if RAM allows
        })
    }

    /// Set the context window size (in tokens).
    pub fn with_context_size(mut self, size: u32) -> Self {
        self.context_size = size;
        self
    }

    pub fn context_window_tokens(&self) -> usize {
        self.context_size as usize
    }
}

#[cfg(feature = "ml")]
impl InferenceBackend for LlamaCppBackend {
    fn generate(
        &self,
        prompt: &str,
        on_token: &dyn Fn(&str),
    ) -> Result<String> {
        let ctx_params = LlamaContextParams::default()
            .with_n_ctx(NonZeroU32::new(self.context_size));

        let mut ctx = self.model.new_context(&self.backend, ctx_params)?;

        // Tokenize prompt
        let tokens_list = self.model.str_to_token(prompt, AddBos::Always)?;

        // Feed all prompt tokens in a batch
        let mut batch = LlamaBatch::new(tokens_list.len().max(512), 1);
        let last_index = (tokens_list.len() - 1) as i32;
        for (i, token) in (0_i32..).zip(tokens_list.into_iter()) {
            batch.add(token, i, &[0], i == last_index)?;
        }
        ctx.decode(&mut batch)?;

        // Set up sampler: low temperature for factual document Q&A
        let mut sampler = LlamaSampler::chain_simple([
            LlamaSampler::top_p(0.9, 1),
            LlamaSampler::temp(0.1),
            LlamaSampler::dist(42),
        ]);

        // Generate tokens
        let mut full_response = String::new();
        let mut n_cur = batch.n_tokens();
        let max_new_tokens: i32 = 1024;
        let mut decoder = encoding_rs::UTF_8.new_decoder();

        while n_cur <= max_new_tokens {
            // Sample the next token
            let new_token = sampler.sample(&ctx, batch.n_tokens() - 1);
            sampler.accept(new_token);

            // Check for end of generation
            if self.model.is_eog_token(new_token) {
                break;
            }

            // Decode token to string and stream
            let token_str = self.model.token_to_piece(new_token, &mut decoder, true, None)?;
            on_token(&token_str);
            full_response.push_str(&token_str);

            // Prepare next batch
            batch.clear();
            batch.add(new_token, n_cur, &[0], true)?;
            ctx.decode(&mut batch)?;

            n_cur += 1;
        }

        Ok(full_response.trim().to_string())
    }
}
