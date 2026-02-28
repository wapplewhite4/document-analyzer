use anyhow::Result;
use quick_xml::events::Event;
use quick_xml::reader::Reader;
use std::io::Read;
use zip::ZipArchive;

/// Extract text from a DOCX file.
///
/// A .docx file is a ZIP archive containing XML. The main document body
/// lives in `word/document.xml`. Text runs are stored in `<w:t>` elements
/// inside `<w:p>` (paragraph) / `<w:r>` (run) nodes.
pub fn extract_docx(path: &str) -> Result<String> {
    let file = std::fs::File::open(path)?;
    let mut archive = ZipArchive::new(file)?;

    let mut xml_content = String::new();
    {
        let mut doc_xml = archive.by_name("word/document.xml").map_err(|_| {
            anyhow::anyhow!("Not a valid DOCX file: missing word/document.xml")
        })?;
        doc_xml.read_to_string(&mut xml_content)?;
    }

    let text = parse_document_xml(&xml_content);

    if text.trim().is_empty() {
        anyhow::bail!("DOCX file contains no extractable text.");
    }

    Ok(text)
}

/// Parse the document.xml content and extract all text.
fn parse_document_xml(xml: &str) -> String {
    let mut reader = Reader::from_str(xml);
    let mut text = String::new();
    let mut in_text_element = false;
    let mut paragraph_has_text = false;

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) | Ok(Event::Empty(e)) => {
                let local = e.local_name();
                match local.as_ref() {
                    b"t" => in_text_element = true,
                    // <w:br/> → line break within a paragraph
                    b"br" => {
                        text.push('\n');
                    }
                    // <w:tab/> → tab character
                    b"tab" => {
                        text.push('\t');
                    }
                    _ => {}
                }
            }
            Ok(Event::End(e)) => {
                let local = e.local_name();
                match local.as_ref() {
                    b"t" => in_text_element = false,
                    // End of paragraph → newline
                    b"p" => {
                        if paragraph_has_text {
                            text.push('\n');
                        }
                        paragraph_has_text = false;
                    }
                    _ => {}
                }
            }
            Ok(Event::Text(e)) => {
                if in_text_element {
                    if let Ok(decoded) = e.unescape() {
                        text.push_str(&decoded);
                        paragraph_has_text = true;
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => {
                eprintln!("DOCX XML parse warning: {}", e);
                break;
            }
            _ => {}
        }
    }

    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_simple_xml() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Hello </w:t></w:r>
      <w:r><w:t>World</w:t></w:r>
    </w:p>
    <w:p>
      <w:r><w:t>Second paragraph.</w:t></w:r>
    </w:p>
  </w:body>
</w:document>"#;

        let result = parse_document_xml(xml);
        assert!(result.contains("Hello World"));
        assert!(result.contains("Second paragraph."));
    }

    #[test]
    fn test_parse_with_tabs_and_breaks() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:t>Before</w:t></w:r>
      <w:r><w:tab/><w:t>After tab</w:t></w:r>
    </w:p>
  </w:body>
</w:document>"#;

        let result = parse_document_xml(xml);
        assert!(result.contains("Before\tAfter tab"));
    }
}
