import AppKit
import CoreImage

enum QRImageDecoder {
    // 读取图片中的所有二维码 payload 字符串；失败返回空数组
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
