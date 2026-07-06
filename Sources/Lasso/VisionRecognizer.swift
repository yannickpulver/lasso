import CoreGraphics
import Foundation
import Vision

/// Instant on-device recognition (OCR + barcodes) via Apple's Vision
/// framework. Runs in a few hundred ms with no network, so the card can show
/// a useful "first read" immediately while the Gemini answer streams in behind
/// it. Text-heavy crops (menus, signs, foreign text, errors, code) are the
/// common case and are fully answered here.
enum VisionRecognizer {
    struct QuickRead {
        /// OCR'd text, top-to-bottom, one line per recognized region.
        let text: String
        /// Decoded barcode/QR payloads.
        let barcodes: [String]

        /// Whether there is anything worth showing before the model answers.
        var isUseful: Bool { !text.isEmpty || !barcodes.isEmpty }

        /// Lines to render in the instant card (text first, then codes).
        var lines: [String] {
            var result = text.isEmpty ? [] : [text]
            result.append(contentsOf: barcodes.map { "⧉ \($0)" })
            return result
        }
    }

    /// Loads the text-recognition model on a blank image so the first real
    /// capture is instant instead of paying the one-time cold-start cost.
    static func warmUp() {
        guard let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let image = context.makeImage() else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: image).perform([request])
    }

    static func recognize(imageData: Data) -> QuickRead {
        let handler = VNImageRequestHandler(data: imageData, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.automaticallyDetectsLanguage = true

        let barcodeRequest = VNDetectBarcodesRequest()

        try? handler.perform([textRequest, barcodeRequest])

        let text = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // De-duplicate: a QR code's URL is often also OCR'd as text.
        let barcodes = (barcodeRequest.results ?? [])
            .compactMap { $0.payloadStringValue }
            .filter { !$0.isEmpty && !text.contains($0) }

        return QuickRead(text: text, barcodes: barcodes)
    }
}
