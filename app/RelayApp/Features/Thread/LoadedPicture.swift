import AppKit
import Presentation
import SwiftUI

/// Decodes once per picture, so typing in the composer doesn't redo the work.
struct LoadedPicture: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                let size = PictureLayout.size(fitting: image.size)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                ProgressView().frame(width: 200, height: 140)
            }
        }
        .task(id: data) { image = NSImage(data: data) }
    }
}
