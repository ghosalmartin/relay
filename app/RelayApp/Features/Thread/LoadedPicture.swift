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
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 320)
                    .clipShape(.rect(cornerRadius: 10))
            } else {
                ProgressView().frame(width: 200, height: 140)
            }
        }
        .task(id: data) { image = NSImage(data: data) }
    }
}
