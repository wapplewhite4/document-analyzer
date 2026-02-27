use anyhow::Result;

/// Extract text from a DOCX file.
///
/// DOCX support is planned for a future phase. Currently returns an error
/// directing users to use PDF or plain text files instead.
pub fn extract_docx(_path: &str) -> Result<String> {
    anyhow::bail!(
        "Word document (.docx) support is not yet available. \
         Please convert to PDF or plain text first."
    )
}
