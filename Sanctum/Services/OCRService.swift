import Foundation
import Vision
import PDFKit

/// Extracts text from scanned PDFs using Apple's Vision framework.
///
/// Vision's VNRecognizeTextRequest runs entirely on-device (no network),
/// uses the Neural Engine on Apple Silicon, and supports 18+ languages.
@MainActor
class OCRService {

    /// Check whether a PDF's text layer is mostly empty (i.e. scanned/image-based).
    /// Returns true if OCR is needed.
    static func pdfNeedsOCR(url: URL) -> Bool {
        guard let doc = PDFDocument(url: url) else { return false }

        var totalChars = 0
        let pagesToCheck = min(doc.pageCount, 5) // Sample first 5 pages

        for i in 0..<pagesToCheck {
            if let page = doc.page(at: i) {
                totalChars += (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
            }
        }

        // If average chars per page is very low, it's likely scanned
        let avgChars = pagesToCheck > 0 ? totalChars / pagesToCheck : 0
        return avgChars < 50
    }

    /// Extract text from all pages of a PDF using Vision OCR.
    /// Runs on a background thread; returns the full extracted text.
    static func ocrPDF(url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw OCRError.cannotOpenPDF
        }

        let pageCount = doc.pageCount
        var allText = ""

        for i in 0..<pageCount {
            guard let page = doc.page(at: i) else { continue }

            // First try the embedded text layer
            let embeddedText = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            if embeddedText.count > 50 {
                // Page has real text — use it directly (faster than OCR)
                allText += embeddedText + "\n\n"
            } else {
                // Scanned page — render to image and OCR
                let bounds = page.bounds(for: .mediaBox)
                // Render at 2x for better OCR accuracy
                let scale: CGFloat = 2.0
                let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

                guard let pageImage = page.thumbnail(of: size, for: .mediaBox).cgImage(
                    forProposedRect: nil, context: nil, hints: nil
                ) else { continue }

                let pageText = try await recognizeText(in: pageImage)
                if !pageText.isEmpty {
                    allText += pageText + "\n\n"
                }
            }
        }

        if allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OCRError.noTextFound
        }

        return allText
    }

    /// Run Vision text recognition on a single CGImage.
    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    enum OCRError: LocalizedError {
        case cannotOpenPDF
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .cannotOpenPDF:
                return "Cannot open PDF file for OCR."
            case .noTextFound:
                return "OCR could not extract any text from this document."
            }
        }
    }
}
