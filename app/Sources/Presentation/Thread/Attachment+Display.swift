import Foundation
import MessagingDomain

public extension Attachment {
    var displayName: String {
        fileName.isEmpty ? (isImage ? "Photo" : "Attachment") : fileName
    }

    var sizeText: String? {
        byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    var symbolName: String {
        if isImage { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        return mimeType == "application/pdf" ? "doc.richtext" : "doc"
    }

    /// Pictures run to the bubble's edges. A failed one is only a line of text, so it's inset like text.
    func fillsBubble(showing content: AttachmentContent?) -> Bool {
        isImage && content != .failed
    }

    /// The file's icon, or a warning once fetching it has failed.
    func symbolName(showing content: AttachmentContent?) -> String {
        content == .failed ? "exclamationmark.triangle" : symbolName
    }

    /// Files come from whoever texted you, so only kinds that can't run anything get opened.
    /// SVG is left out because it can carry scripts.
    var canOpen: Bool {
        guard mimeType != "image/svg+xml" else { return false }
        return isImage || mimeType.hasPrefix("video/") || mimeType.hasPrefix("audio/") || mimeType == "application/pdf"
    }
}
