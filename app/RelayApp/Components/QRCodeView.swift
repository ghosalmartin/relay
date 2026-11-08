import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders text as a crisp, scannable QR code.
struct QRCodeView: View {
    static let side: CGFloat = 264
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: Self.side, height: Self.side)
                .padding(12)
                .background(.white, in: .rect(cornerRadius: 12))
                .accessibilityLabel("Pairing QR code")
        }
    }

    private static func render(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: output.extent.size)
    }
}
