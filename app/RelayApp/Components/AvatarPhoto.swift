import AppKit
import SwiftUI

/// Decodes once per photo, so redrawing the inbox doesn't redo the work.
struct AvatarPhoto: View {
    let data: Data
    @State private var image: NSImage?

    var body: some View {
        // A real view to hang the task on: a Group with nothing in it would never start it.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            }
            .task(id: data) { image = NSImage(data: data) }
    }
}
