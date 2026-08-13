import UIKit
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    static func generate(from string: String, size: CGFloat = 260) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scale = size / outputImage.extent.width
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
