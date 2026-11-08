import AppKit
import Foundation
import UniformTypeIdentifiers

/// Hands an attachment to the app that handles its type.
enum AttachmentFileOpener {
    /// The name and extension come from the MIME type, never the sender's file name, so a file
    /// can't pose as something else or write outside its folder.
    @MainActor
    static func open(_ data: Data, mimeType: String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileName = "Attachment." + (UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "bin")
        let file = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            NSWorkspace.shared.open(file)
        } catch {
            NSSound.beep()
        }
    }
}
