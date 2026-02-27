use anyhow::Result;
use lopdf::Document;

pub struct ExtractedDocument {
    pub text: String,
    pub page_count: usize,
    pub title: Option<String>,
}

pub fn extract_pdf(path: &str) -> Result<ExtractedDocument> {
    let doc = Document::load(path)?;
    let mut full_text = String::new();
    let pages = doc.get_pages();
    let page_count = pages.len();

    // Collect and sort page numbers for deterministic ordering
    let mut page_nums: Vec<u32> = pages.keys().copied().collect();
    page_nums.sort();

    for page_num in page_nums {
        match doc.extract_text(&[page_num]) {
            Ok(text) => {
                full_text.push_str(&text);
                full_text.push('\n');
            }
            Err(_) => {
                // Page may be scanned image — flag for OCR in Phase 2
                full_text.push_str(&format!("[Page {} requires OCR]\n", page_num));
            }
        }
    }

    let title = extract_title(&doc);

    Ok(ExtractedDocument {
        text: full_text,
        page_count,
        title,
    })
}

fn extract_title(doc: &Document) -> Option<String> {
    doc.trailer
        .get(b"Info")
        .ok()
        .and_then(|info_ref| {
            if let Ok(info_obj) = doc.get_object(info_ref.as_reference().ok()?) {
                info_obj.as_dict().ok().and_then(|dict| {
                    dict.get(b"Title")
                        .ok()
                        .and_then(|t| t.as_str().ok())
                        .map(|s| String::from_utf8_lossy(s).to_string())
                })
            } else {
                None
            }
        })
}
