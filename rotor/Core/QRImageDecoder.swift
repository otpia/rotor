import AppKit
import CoreImage

enum QRImageDecoder {
    // Read all QR code payload strings from the image; returns an empty array on failure
    static func decode(_ url: URL) -> [String] {
        guard let ciImage = CIImage(contentsOf: url) else { return [] }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        let features = detector?.features(in: ciImage) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
