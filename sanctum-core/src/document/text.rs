use anyhow::Result;
use std::fs;

pub fn extract_text(path: &str) -> Result<String> {
    let content = fs::read_to_string(path)?;
    Ok(content)
}
