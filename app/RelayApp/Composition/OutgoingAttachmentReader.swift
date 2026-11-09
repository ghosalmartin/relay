import AppKit
import MessagingDomain
import UniformTypeIdentifiers

/// Turns what the user picked, dropped or pasted into a file ready to send.
enum OutgoingAttachmentReader {
    static func read(_ url: URL) -> OutgoingAttachment? {
        // Reading a web address here would block the app on the network.
        guard url.isFileURL else { return nil }
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return OutgoingAttachment(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
    }

    /// The copied files or picture, or nothing when the paste belongs in the text field. Copying from
    /// a document can put both text and a picture of it on the clipboard, and then text wins.
    static func pasted(from board: NSPasteboard) -> [OutgoingAttachment] {
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty { return files.compactMap(read) }
        guard board.string(forType: .string) == nil, let png = pngData(from: board) else { return [] }
        return [OutgoingAttachment(data: png, fileName: "Pasted Image.png", mimeType: "image/png")]
    }

    private static func pngData(from board: NSPasteboard) -> Data? {
        if let png = board.data(forType: .png) { return png }
        return board.data(forType: .tiff)
            .flatMap(NSBitmapImageRep.init(data:))?
            .representation(using: .png, properties: [:])
    }
}
